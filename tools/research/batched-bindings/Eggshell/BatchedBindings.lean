module
public import Eggshell.SynapticBindings
@[expose] public section

namespace Eggshell.Synapses.BatchedBindings
open Lean DB

structure Request where
  ordinal : Nat
  source : Range
  key : Index.Key
  range : PageMap.KeyRange

def requests (wanted : Array Range) : Array Request :=
  wanted.mapIdx (fun ordinal source =>
    let key := Index.Key.source source
    let digest := Index.contentKey key
    {ordinal,source,key,range := ⟨"lookup:" ++ digest ++ ":","lookup:" ++ digest ++ ";"⟩})
  |>.qsort (fun left right => left.range.lower < right.range.lower)

/-- Each child receives only the requests which can have a row there. The
existing checked page fences justify discarding a child for each request
independently, including negative lookups. -/
theorem pruned_request_exact (request : Request) (ref : PageMap.Ref) (rows : List PageMap.Row)
    (bounded : ∀ row ∈ rows, ref.first ≤ row.1 ∧ row.1 ≤ ref.last) :
    (if request.range.overlaps ref then request.range.select rows else []) = request.range.select rows := by
  by_cases found : request.range.overlaps ref = true
  · simp [found]
  · have absent : request.range.overlaps ref = false := Bool.eq_false_iff.mpr found
    rw [if_neg found,request.range.prune_exact ref rows bounded absent]

structure Column where
  postings : Array Index.Posting := #[]
  complete : Bool := true
  visits : Nat := 0

structure Scanned where
  columns : Array Column
  pages : Nat := 0
  postingDecodes : Nat := 0
  postingBytes : Nat := 0
  complete : Bool := true

structure Statistics where
  pageVisits : Nat := 0
  postingDecodes : Nat := 0
  postingBytes : Nat := 0
  factDecodes : Nat := 0
  factCacheHits : Nat := 0
  physicalReads : Nat := 0
  physicalBytes : Nat := 0
  deriving ToJson

structure Result where
  resolved : IndexedBindings.Resolved := {}
  statistics : Statistics := {}

/-- A page is loaded once for the whole batch. This is not a scan from the
smallest requested hash to the largest: unrelated children are never opened.
Metadata staging is bounded independently of original Fact payloads. -/
def scanAt (snapshot : PageMap.Snapshot) (ref : PageMap.Ref) (queries : Array Request)
    (limit deadline byteLimit : Nat) (initial : Scanned) : IO Scanned := do
  if !initial.complete then return initial
  if (← IO.monoMsNow) ≥ deadline then return {initial with complete := false}
  let mut state := initial
  let mut active := #[]
  for query in queries do
    let some column := state.columns[query.ordinal]? | throw (IO.userError "batch request has no result column")
    if !column.complete then continue
    if column.postings.size ≥ limit then
      state := {state with columns := state.columns.modify query.ordinal fun column => {column with complete := false}}
    else active := active.push query
  if active.isEmpty then return state
  let loaded ← snapshot.load ref
  state := {state with pages := state.pages+1}
  for query in active do
    state := {state with columns := state.columns.modify query.ordinal fun column => {column with visits := column.visits+1}}
  match loaded.page with
  | .branch children =>
    for child in children do
      let narrowed := active.filter fun query => query.range.overlaps child
      if narrowed.isEmpty then continue
      if _smaller : child.height < ref.height then
        state ← scanAt snapshot child narrowed limit deadline byteLimit state
      else throw (IO.userError "batched synaptic page height did not decrease")
      if !state.complete then return state
    return state
  | .leaf rows =>
    for query in active do
      for (name,payload) in query.range.select rows do
        let some column := state.columns[query.ordinal]? | throw (IO.userError "batch lost a result column")
        if !column.complete then break
        if column.postings.size ≥ limit then
          state := {state with columns := state.columns.modify query.ordinal fun column => {column with complete := false}}
          break
        if (← IO.monoMsNow) ≥ deadline then return {state with complete := false}
        let some bytes := payload | continue
        if state.postingBytes+bytes.size > byteLimit then return {state with complete := false}
        let posting ← Index.decode (α := Index.Posting) bytes
        unless name == Index.postingPrefix posting.key ++ posting.fact && posting.key == query.key do
          throw (IO.userError "batched synaptic posting differs from its complete requested key")
        state := {state with
          columns := state.columns.modify query.ordinal fun column => {column with postings := column.postings.push posting}
          postingDecodes := state.postingDecodes+1,postingBytes := state.postingBytes+bytes.size}
    return state
termination_by ref.height

structure CachedFact where
  fact : Fact
  bytes : Nat

/-- The original scope, digest and key-membership checks remain at the data
boundary. Sharing a decoded Fact never grants another query its membership. -/
def checkedFact (reader : Index.Reader) (query : Request) (posting : Index.Posting)
    (cache : Std.HashMap String CachedFact) : IO (Fact × Nat × Bool × Std.HashMap String CachedFact) := do
  unless posting.key == query.key do throw (IO.userError "batched posting crossed its query")
  let (cached,hit) ← match cache[posting.fact]? with
    | some cached => pure (cached,true)
    | none => do
      let some bytes ← reader.index.get ("fact:" ++ posting.fact) |
        throw (IO.userError "dangling batched synaptic posting")
      let fact ← Index.decode (α := Fact) bytes
      pure (⟨fact,bytes.size⟩,false)
  unless cached.fact.valid && reader.manifest.scope.accepts cached.fact &&
      Index.belongs reader.manifest.source.identity cached.fact && Index.contentKey cached.fact == posting.fact do
    throw (IO.userError "batched source Fact has a foreign scope or digest")
  unless (Index.addresses cached.fact).contains query.key do
    throw (IO.userError "batched source Fact does not address this query")
  return (cached.fact,cached.bytes,hit,if hit then cache else cache.insert posting.fact cached)

/-- Result columns return in the first-occurrence input order, with the same
stable posting order and checked original bindings as the point reader.
This function creates no Work, Match, Union or completion authority. -/
def resolve (reader : Index.Reader) (wanted : Array Range) (allowed : Std.HashSet String)
    (deadline : Nat) (perKeyLimit : Nat := 32768) (byteLimit : Nat := 32*1024*1024) : IO Result := do
  let wanted := (hashDistinct wanted.toList).toArray
  if wanted.isEmpty then return {}
  if (← IO.monoMsNow) ≥ deadline || byteLimit == 0 then
    return {resolved := {complete := false}}
  let ordered := requests wanted
  let byOrdinal := ordered.qsort (fun left right => left.ordinal < right.ordinal)
  let initialReads ← reader.index.reads.get
  let initialBytes ← reader.index.readBytes.get
  let initial : Scanned := {columns := Array.replicate wanted.size {}}
  let scanned ← match reader.index.head.root with
    | none => pure initial
    | some ref => scanAt reader.index ref ordered perKeyLimit deadline byteLimit initial
  let mut result : Result := {
    resolved := {complete := scanned.complete}
    statistics := {pageVisits := scanned.pages,postingDecodes := scanned.postingDecodes,postingBytes := scanned.postingBytes}}
  let mut facts : Std.HashMap String CachedFact := {}
  for query in byOrdinal do
    if (← IO.monoMsNow) ≥ deadline || result.resolved.bytes ≥ byteLimit then
      result := {result with resolved := {result.resolved with complete := false}}
      break
    let some column := scanned.columns[query.ordinal]? | throw (IO.userError "missing batched source result")
    let mut rows := #[]
    let mut seen : Std.HashSet Read := {}
    let mut inspected := 0
    let mut complete := scanned.complete && column.complete
    let mut bytes := 0
    let mut unusable := 0
    for posting in column.postings do
      if (← IO.monoMsNow) ≥ deadline then complete := false; break
      let (fact,size,hit,updated) ← checkedFact reader query posting facts
      if result.resolved.bytes+bytes+size > byteLimit then complete := false; break
      facts := updated
      result := {result with statistics := {result.statistics with
        factDecodes := result.statistics.factDecodes + if hit then 0 else 1
        factCacheHits := result.statistics.factCacheHits + if hit then 1 else 0}}
      inspected := inspected+1
      bytes := bytes+size
      if (IndexedBindings.candidate? fact).any (fun read => !read.valid) then unusable := unusable+1
      let some origin := IndexedBindings.check? reader.manifest.source.identity allowed query.source fact | continue
      if seen.contains origin.read then continue
      seen := seen.insert origin.read
      rows := rows.push origin.read
    result := {result with resolved := {
      rows := result.resolved.rows.insert query.source rows
      complete := result.resolved.complete && complete && unusable == 0
      requests := result.resolved.requests+1,inspected := result.resolved.inspected+inspected
      bytes := result.resolved.bytes+bytes,unusable := result.resolved.unusable+unusable
      unresolved := result.resolved.unresolved + if rows.isEmpty then 1 else 0}}
  return {result with statistics := {result.statistics with
    physicalReads := (← reader.index.reads.get)-initialReads
    physicalBytes := (← reader.index.readBytes.get)-initialBytes}}

end Eggshell.Synapses.BatchedBindings
