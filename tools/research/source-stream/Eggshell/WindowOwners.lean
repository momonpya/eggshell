module
public import Eggshell.SourceDelta
public import SourceCatalogue
public import Eggshell.VectorMatrix

@[expose] public section
namespace Eggshell.WindowOwners
open Lean DB Persistence.Store

/-- A nomination retains the original DB-local identity and window position.
It carries neither equality nor permission to reuse an observation. -/
structure Occurrence where
  owner : Nat
  work : Nat
  ordinal : Nat
  position : Nat
  deriving BEq, Repr, ToJson, FromJson

def occurrenceCodec : Wire.Codec Occurrence :=
  (Wire.natural.product (Wire.natural.product (Wire.natural.product Wire.natural))).iso
    (fun row => (row.owner,row.work,row.ordinal,row.position))
    (fun (owner,work,ordinal,position) => ⟨owner,work,ordinal,position⟩)
    (by intro row; cases row; rfl)

theorem occurrence_roundtrip (row : Occurrence) (tail : List UInt8) :
    occurrenceCodec.decode (occurrenceCodec.encode row ++ tail) = .ok (row,tail) :=
  occurrenceCodec.roundtrip row tail

def entries (document : SearchDocument) (ordinal : Nat) : List (String × Occurrence) :=
  document.windows.zipIdx.map fun (key,position) =>
    (key,⟨document.owner,document.work,ordinal,position⟩)

theorem entries_original (document : SearchDocument) (ordinal : Nat)
    (key : String) (row : Occurrence) (member : (key,row) ∈ entries document ordinal) :
    row.owner = document.owner ∧ row.work = document.work ∧ row.ordinal = ordinal ∧
      document.windows[row.position]? = some key := by
  simp only [entries, List.mem_map] at member
  obtain ⟨⟨value,position⟩,present,same⟩ := member
  cases same
  exact ⟨rfl,rfl,rfl,List.mk_mem_zipIdx_iff_getElem?.mp present⟩

def postingKey (window : String) (row : Occurrence) : String :=
  "w:" ++ window ++ ":" ++ toString row.owner ++ ":" ++ toString row.position

def postingRange (window : String) : PageMap.KeyRange :=
  ⟨"w:" ++ window ++ ":", "w:" ++ window ++ ";"⟩

def implementation : String := Sha256.hex (
  (include_str "WindowOwners.lean").toUTF8 ++
  (include_str "SourceDelta.lean").toUTF8 ++
  (include_str "GraphStore.lean").toUTF8 ++
  (include_str "SearchRank.lean").toUTF8)

def authority (database : String) := "eggshell.window-owners:" ++ database ++ ":" ++ implementation

structure Manifest where
  source : PageMap.Head
  stamp : SourceCatalogue.Stamp
  occurrences : Nat
  deriving ToJson, FromJson

structure Ready where
  snapshot : PageMap.Snapshot
  manifest : Manifest

def folder (source : Snapshot) (storage : Sidecar.Storage) : IO System.FilePath := do
  return (← Sidecar.locate source storage).indexes / "window-owners" / implementation

def load? (source : Snapshot) (storage : Sidecar.Storage) : IO (Option Ready) := do
  let some index ← PageMap.open? (← folder source storage) | return none
  unless index.head.authority == authority source.head.identity do
    throw (IO.userError "foreign window-owner index authority")
  let some bytes ← index.get "manifest" | return none
  unless bytes.size ≤ 16384 do throw (IO.userError "oversized window-owner manifest")
  let some text := String.fromUTF8? bytes | throw (IO.userError "invalid window-owner manifest UTF-8")
  let manifest ← IO.ofExcept (Json.parse text >>= fromJson? (α := Manifest))
  unless manifest.source.identity == source.head.identity &&
      manifest.source.authority == source.head.authority &&
      manifest.stamp.database == source.head.identity do
    throw (IO.userError "foreign window-owner source")
  return some ⟨index,manifest⟩

/-- A cold, divergent or changed source is unavailable, never a successful
empty search. Neutral publications are checked against their real parent chain.
No original candidate directory is opened by this foreground operation. -/
def open? (source : Snapshot) (storage : Sidecar.Storage) : IO (Option Ready) := do
  let some ready ← load? source storage | return none
  unless ready.manifest.stamp == (← SourceCatalogue.stamp source) do return none
  if ready.manifest.source != source.head then
    let some delta ← SourceDelta.read? source ready.manifest.source | return none
    unless delta.owners.isEmpty do return none
  return some ready

def openShared? (source : Snapshot) : IO (Option Ready) := do
  for storage in [.database,.user] do
    if let some ready ← try open? source storage catch _ => pure none then return some ready
  return none

structure Slice where
  rows : List PageMap.Row := []
  remaining : Nat
  incomplete : Bool := false

def Slice.consume (state : Slice) (selected : List PageMap.Row) : Slice :=
  let taken := selected.take state.remaining
  ⟨taken.reverse ++ state.rows,state.remaining-taken.length,
    state.incomplete || selected.length > state.remaining⟩

/-- The exact leaf operation spends one physical slot for every retained row;
neither tombstones nor oversized fanout can create an uncharged nomination. -/
theorem Slice.consume_conserves (state : Slice) (selected : List PageMap.Row) :
    (state.consume selected).rows.length + (state.consume selected).remaining =
      state.rows.length + state.remaining := by
  simp only [consume,List.length_append,List.length_reverse,List.length_take]
  omega

/-- Stop traversal, rather than merely ignoring rows after exhausting a quota.
Tombstones spend the same physical-row budget as live entries. Checked parent
fences prune children, while the root itself is authenticated even on a miss. -/
def scanAt (snapshot : PageMap.Snapshot) (ref : PageMap.Ref) (range : PageMap.KeyRange)
    (state : Slice) : IO Slice := do
  let loaded ← snapshot.load ref
  unless range.overlaps ref do return state
  match loaded.page with
  | .leaf rows =>
    return state.consume (range.select rows)
  | .branch children =>
    let mut state := state
    for child in children do
      if range.overlaps child then
        if state.remaining == 0 then return {state with incomplete := true}
        if _smaller : child.height < ref.height then
          state ← scanAt snapshot child range state
        else throw (IO.userError "window-owner index height did not decrease")
        if state.incomplete then return state
    return state
termination_by ref.height

structure Lookup where
  occurrences : List (String × Occurrence)
  physicalRows : Nat
  requestedKeys : Nat
  visitedKeys : Nat
  partialKeys : List String
  deriving ToJson

/-- The result exposes lost coverage from a common key or an exhausted global
budget. Its subtype bounds actual physical rows, including deleted postings. -/
def lookup (ready : Ready) (keys : List String) (budget : Nat) :
    IO {result : Lookup // result.physicalRows ≤ budget ∧ result.occurrences.length ≤ result.physicalRows} := do
  unless keys.length ≤ 4096 && budget ≤ 8192 &&
      keys.all PageMap.validIdentity && (Std.HashSet.ofList keys).size == keys.length do
    throw (IO.userError "invalid window-owner lookup allowance or keys")
  let mut remaining := budget
  let mut found := []
  let mut visited := 0
  let mut partialKeys := []
  for key in keys do
    if remaining == 0 then
      partialKeys := key :: partialKeys
      continue
    let state ← match ready.snapshot.head.root with
      | none => pure (Slice.mk [] remaining false)
      | some root => scanAt ready.snapshot root (postingRange key) ⟨[],remaining,false⟩
    let rows := state.rows.reverse
    unless rows.length ≤ remaining && state.remaining == remaining-rows.length do
      throw (IO.userError "window-owner physical allowance disagrees")
    remaining := state.remaining
    visited := visited+1
    if state.incomplete then
      partialKeys := key :: partialKeys
      ready.snapshot.trace.modify (·.map fun _ => {complete := false})
    else ready.snapshot.observe (.range (postingRange key).lower (postingRange key).upper rows)
    for (stored,encoded) in rows do
      let some encoded := encoded | continue
      let (row,tail) ← IO.ofExcept (occurrenceCodec.decode encoded.toList)
      unless tail.isEmpty && (occurrenceCodec.encode row).toByteArray == encoded &&
          stored == postingKey key row do
        throw (IO.userError "window-owner posting disagrees with original identity")
      found := (key,row) :: found
  let result : Lookup := ⟨found.reverse,budget-remaining,keys.length,visited,partialKeys.reverse⟩
  if bounded : result.physicalRows ≤ budget ∧ result.occurrences.length ≤ result.physicalRows then
    return ⟨result,bounded⟩
  throw (IO.userError "window-owner lookup exceeded its checked allowance")

theorem lookup_rows_bounded (result : {result : Lookup //
    result.physicalRows ≤ budget ∧ result.occurrences.length ≤ result.physicalRows}) :
    result.val.occurrences.length ≤ budget := Nat.le_trans result.property.2 result.property.1

/-- Cache rows are hints. Validate each nominated owner and each original
position against the pinned source, never against a fabricated compact ordinal.
Original text and freshness remain the delivery producer's responsibility. -/
def resolve (source : Snapshot) (result : Lookup) : IO (List SearchDocument) := do
  let owners := hashDistinct (result.occurrences.map (·.2.owner))
  let documents ← SourceDelta.documents source owners
  let table := documents.foldl (fun table doc => table.insert doc.owner doc)
    ({} : Std.HashMap Nat SearchDocument)
  for (key,row) in result.occurrences do
    let some document := table[row.owner]? | throw (IO.userError "nominated window owner is no longer live")
    unless document.work == row.work && document.windows[row.position]? == some key &&
        (← getNat source.get (Persistence.Store.key "member" row.owner)) == row.ordinal do
      throw (IO.userError "nominated window disagrees with original source")
  return documents

structure Result where
  mode : String
  changedOwners : Nat
  removed : Nat
  added : Nat
  occurrences : Nat
  writtenBytes : Nat
  elapsedMs : Nat
  deriving ToJson

def documentEntries (source : Snapshot) (documents : List SearchDocument) :
    IO (List (String × Occurrence)) := do
  let mut rows := []
  for document in documents do
    let ordinal ← getNat source.get (Persistence.Store.key "member" document.owner)
    rows := (entries document ordinal).reverse ++ rows
  return rows.reverse

/-- Warm-only maintenance. Existing publication journals provide both the old
and new original windows of changed owners. Retraction needs no second reverse
directory. Data and coverage basis switch in one atomic PageMap head. -/
def refresh (source : Snapshot) (storage : Sidecar.Storage) : IO Result := do
  let started ← IO.monoMsNow
  Sidecar.withIndexClaim (Sidecar.Owner.ofSnapshot source) (fun sidecar => do
    unless (← (Sidecar.Owner.ofSnapshot source).pin).head == source.head do
      throw (IO.userError "source changed before window-owner preparation")
    let previous ← load? source storage
    if let some previous := previous then
      if previous.manifest.source == source.head then
        return ⟨"warm",0,0,0,previous.manifest.occurrences,0,(← IO.monoMsNow)-started⟩
    let delta : Option (List Nat) ← match previous with
      | none => pure none
      | some previous => do pure ((← SourceDelta.read? source previous.manifest.source).map (·.owners))
    let (mode,changed,removed,added,occurrences) ← match previous,delta with
      | some previous,some delta => do
        let before := {source with head := previous.manifest.source}
        let removed ← documentEntries before (← SourceDelta.documents before delta)
        let added ← documentEntries source (← SourceDelta.documents source delta)
        unless removed.length ≤ previous.manifest.occurrences do
          throw (IO.userError "window-owner retraction exceeds saved coverage")
        pure ("publication-delta",delta.length,removed,added,
          previous.manifest.occurrences-removed.length+added.length)
      | _,_ => do
        let documents ← searchDocuments source
        let added ← documentEntries source documents
        pure ("full-source",documents.length,[],added,added.length)
    let parent ← Sidecar.childDirectory sidecar.indexes "window-owners"
    let directory := parent / implementation
    let index ← match previous with
      | some previous => pure previous.snapshot
      | none => PageMap.create directory (authority source.head.identity)
    let metadata : Manifest := ⟨source.head,← SourceCatalogue.stamp source,occurrences⟩
    let (_,_,written) ← PageMap.withWriter index fun writer => do
      if mode == "full-source" then
        let rows := List.mergeSort (("manifest",some (toJson metadata).compress.toUTF8) ::
          added.map (fun (key,row) => (postingKey key row,some (occurrenceCodec.encode row).toByteArray)))
          (fun a b => a.1 ≤ b.1)
        unless PageMap.ordered rows do throw (IO.userError "duplicate original window occurrence")
        let mut levels := []
        let mut buffered := []
        for row in rows do
          buffered := row :: buffered
          if buffered.length == 64 then
            levels ← VectorMatrix.flushLeaves writer buffered levels
            buffered := []
        levels ← VectorMatrix.flushLeaves writer buffered levels
        writer.root.set (some (← VectorMatrix.finish writer levels))
      else
        for (key,row) in removed do writer.put (postingKey key row) none
        for (key,row) in added do
          writer.put (postingKey key row) (some (occurrenceCodec.encode row).toByteArray)
        writer.put "manifest" (some (toJson metadata).compress.toUTF8)
      unless (← (Sidecar.Owner.ofSnapshot source).pin).head == source.head do
        throw (IO.userError "source changed during window-owner preparation")
    return ⟨mode,changed,removed.length,added.length,occurrences,written,(← IO.monoMsNow)-started⟩) storage

end Eggshell.WindowOwners
