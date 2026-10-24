module
public import tools.RetrievalIndex
public import Std.Data.HashMap.Lemmas

@[expose] public section

namespace Eggshell.LexicalReads
open Lean DB Persistence.Store

def firstTable (rows : List PageMap.Row) : Std.HashMap String (Option ByteArray) :=
  rows.foldr (fun row table => table.insert row.1 row.2) {}

theorem firstTable_exact (rows : List PageMap.Row) (name : String) :
    (firstTable rows)[name]? = (rows.find? (fun row => row.1 == name)).map Prod.snd := by
  induction rows with
  | nil => simp [firstTable]
  | cons row rest ih =>
      change ((firstTable rest).insert row.1 row.2)[name]? = _
      rw [Std.HashMap.getElem?_insert, List.find?_cons, ih]
      cases row.1 == name <;> rfl

/-- The sparse table retains the first original full-key value, including
tombstones. Hashes do not replace key equality or original source values. -/
structure View (rows : List PageMap.Row) where
  table : Std.HashMap String (Option ByteArray)
  exact : ∀ name, table[name]? = (rows.find? (fun row => row.1 == name)).map Prod.snd

def View.make (rows : List PageMap.Row) : View rows := ⟨firstTable rows,firstTable_exact rows⟩

def View.value (view : View rows) (name : String) : Option ByteArray := view.table[name]?.join

theorem View.value_exact (view : View rows) (name : String) :
    view.value name = (rows.find? (fun row => row.1 == name)).bind Prod.snd := by
  unfold View.value
  rw [view.exact]
  cases rows.find? (fun row => row.1 == name) <;> rfl

abbrev Captured := Std.HashMap String (Except IO.Error (Option ByteArray))

def failed (names : List String) (error : IO.Error) : Captured :=
  names.foldl (fun values name => values.insert name (.error error)) {}

/-- Visit only the original point paths, sharing their checked page loads.
As in getAt, load before testing fences, and use route even for gaps. Errors
belong to individual keys: speculative IO must not change the first logical
failure or bypass an earlier membership check. No source body is decoded. -/
def getManyAt (snapshot : PageMap.Snapshot) (ref : PageMap.Ref)
    (names : List String) : IO Captured := do
  let loaded : Except IO.Error (PageMap.Loaded ref) ←
    try pure (.ok (← snapshot.load ref)) catch error => pure (.error error)
  match loaded with
  | .error error => return failed names error
  | .ok loaded =>
      let (outside,inside) := names.partition fun name => name < ref.first || ref.last < name
      let mut values : Captured := outside.foldl (fun values name => values.insert name (.ok none)) {}
      match loaded.page with
      | .leaf rows =>
          let view := View.make rows
          for name in inside do values := values.insert name (.ok (view.value name))
      | .branch children =>
          let mut groups : Std.HashMap Nat (PageMap.Ref × List String) := {}
          for name in inside do
            match PageMap.route children name with
            | none => values := values.insert name (.error (IO.userError "empty branch"))
            | some (ordinal,child) =>
                let before := (groups[ordinal]?.map Prod.snd).getD []
                groups := groups.insert ordinal (child,name :: before)
          for (_,child,requested) in groups.toList do
            if _smaller : child.height < ref.height then
              let next ← getManyAt snapshot child requested
              for (name,value) in next.toList do values := values.insert name value
            else
              for name in requested do
                values := values.insert name (.error (IO.userError "index height did not decrease"))
      return values
termination_by ref.height

def batchLimit : Nat := 1024

structure Batch where
  snapshot : PageMap.Snapshot
  names : List String
  bounded : names.length ≤ batchLimit
  values : Captured

/-- A batch is bounded independently of total DB size. It shares the immutable
root, original page authentication and physical counters, without recording
speculative reads as logical memo dependencies. No whole namespace is loaded. -/
def load (snapshot : PageMap.Snapshot) (names : List String) : IO Batch := do
  if bounded : names.length ≤ batchLimit then
    let quiet ← PageMap.QuietReader.make snapshot
    let values ← match snapshot.head.root with
      | none => pure (names.foldl (fun values name => values.insert name (.ok none)) {})
      | some root => getManyAt quiet.snapshot root names
    return ⟨snapshot,names,bounded,values⟩
  else throw (IO.userError "lexical point batch exceeds its key bound")

def Batch.read (batch : Batch) (name : String) : IO (Option ByteArray) := do
  let some captured := batch.values[name]? |
    throw (IO.userError "lexical lookup escaped its requested point batch")
  let value ← match captured with
    | .error error => throw error
    | .ok value => pure value
  batch.snapshot.observe (.point name value)
  return value

theorem Batch.keys_bounded (batch : Batch) : batch.names.length ≤ batchLimit := batch.bounded

structure Metrics where
  preparationMs : Nat := 0
  batches : Nat := 0
  requestedKeys : Nat := 0
  largestBatch : Nat := 0
  postingCalls : Nat := 0
  postingRows : Nat := 0
  postingMs : Nat := 0
  deriving ToJson

def observe (source : PageMap.Snapshot) (receipt : Option String) (metrics : Metrics) : IO Unit :=
  Receipt.observe receipt ("lexical-reads-" ++ source.head.identity) (toJson metrics)

/-- Every check from Reader.posting remains, on original pinned values. Only
requested posting owners are batched; results are consumed in original order.
This creates no Work, Match, Union or completed authority. -/
def posting (reader : RetrievalResearch.Index.Reader source)
    (metrics : IO.Ref Metrics)
    (receipt : Option String) (unit : String) : IO (List Nat × Nat) := do
  let started ← IO.monoMsNow
  let some term ← findTerm? reader.index reader.index.get unit | return ([],0)
  let rows ← directory reader.index (key "posting" term.id)
  let count ← getNat reader.index.get (key "frequency" term.id)
  unless rows.length == count do throw (IO.userError "lexical posting frequency disagrees")
  let mut remaining := rows
  while !remaining.isEmpty do
    let selected := remaining.take (batchLimit / 2)
    remaining := remaining.drop (batchLimit / 2)
    let begin ← IO.monoMsNow
    let indexed ← load reader.index (selected.map fun (_,owner) => key "owner" owner)
    let live ← load source (selected.flatMap fun (_,owner) => [key "member" owner,key "candidate" owner])
    let elapsed := (← IO.monoMsNow)-begin
    metrics.modify fun before => {before with
      preparationMs := before.preparationMs+elapsed
      batches := before.batches+2
      requestedKeys := before.requestedKeys+indexed.names.length+live.names.length
      largestBatch := max before.largestBatch (max indexed.names.length live.names.length)}
    for (ordinal,owner) in selected do
      let indexed ← IO.ofExcept (payloadSize (← indexed.read (key "owner" owner)))
      let member ← IO.ofExcept (payloadSize (← live.read (key "member" owner)))
      unless indexed == ordinal && member == ordinal &&
          (← getNat live.read (key "candidate" owner)) == 1 do
        throw (IO.userError "lexical posting names a different live source owner")
  let elapsed := (← IO.monoMsNow)-started
  metrics.modify fun before => {before with
    postingCalls := before.postingCalls+1
    postingRows := before.postingRows+rows.length
    postingMs := before.postingMs+elapsed}
  observe source receipt (← metrics.get)
  return (rows.map Prod.snd,count)

def make (reader : RetrievalResearch.Index.Reader source) (receipt : Option String := none) :
    IO (String → IO (List Nat × Nat)) := do
  return posting reader (← IO.mkRef {}) receipt

def strictLookup (source : PageMap.Snapshot) (receipt : Option String := none) :
    IO (String → IO (List Nat × Nat)) := do
  if (← getNat source.get "candidates") == 0 then return fun _ => pure ([],0)
  let some reader ← RetrievalResearch.Index.open? source |
    throw (IO.userError "dictionary-free lexical index is pending explicit/background warm")
  make reader receipt

def coarseLookup (source : PageMap.Snapshot) (receipt : Option String := none) :
    IO (String → IO (List Nat × Nat)) := do
  if (← getNat source.get "candidates") == 0 then return fun _ => pure ([],0)
  if let some reader ← RetrievalResearch.Index.open? source then return ← make reader receipt
  RetrievalResearch.Index.coarseLookup source receipt

end Eggshell.LexicalReads
