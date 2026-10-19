module

public import Eggshell.Persistence
public import Eggshell.DB.Sidecar
public import Eggshell.Receipt
public import tools.RetrievalGrams

@[expose] public section

namespace Eggshell.RetrievalResearch.Index
open Lean
open Persistence Store

def contract : String := Sha256.hex (
  (include_str "RetrievalGrams.lean").toUTF8 ++
  (include_str "RetrievalCategories.lean").toUTF8 ++
  (include_str "../Eggshell/SearchUnicode.lean").toUTF8 ++
  (include_str "../Eggshell/SearchRank.lean").toUTF8 ++
  (include_str "RetrievalIndex.lean").toUTF8)

/-- Source roots are append ordinals; candidate deletion changes population.
Both remain stable across derived query/matcher memo publications. -/
structure Stamp where
  database : String
  authority : String
  roots : Nat
  candidates : Nat
  contract : String
  deriving ToJson, FromJson, BEq, DecidableEq

def stamp (source : Snapshot) : IO Stamp := do
  pure {
    database := source.head.identity, authority := Sha256.hex source.head.authority.toUTF8
    roots := ← getNat source.get "roots", candidates := ← getNat source.get "candidates", contract}

def authority (source : Snapshot) : String :=
  "eggshell.lexical:" ++ source.head.identity ++ ":" ++
    Sha256.hex source.head.authority.toUTF8 ++ ":" ++ contract

def path (source : Snapshot) (storage : DB.Sidecar.Storage) : IO System.FilePath := do
  pure ((← DB.Sidecar.locate source storage).directory / "lexical" / contract / "tree")

def readStamp (index : Snapshot) : IO (Option Stamp) := do
  let some bytes ← index.get "ready" | return none
  let some text := String.fromUTF8? bytes | throw (IO.userError "invalid lexical readiness record")
  some <$> IO.ofExcept (fromJson? (← IO.ofExcept (Json.parse text)))

structure Reader (source : Snapshot) where
  index : Snapshot
  expected : Stamp

def open? (source : Snapshot) : IO (Option (Reader source)) := do
  DB.Sidecar.observe source
  let expected ← stamp source
  for storage in [.database, .user] do
    try
      let index ← DB.PageMap.pin (← path source storage)
      unless index.head.authority == authority source do continue
      unless (← readStamp index) == some expected &&
          (← getNat index.get "documents") == expected.candidates do continue
      return some ⟨index, expected⟩
    catch _ => pure ()
  pure none

def Reader.posting (reader : Reader source) (unit : String) : IO (List Nat × Nat) := do
  let some term ← findTerm? reader.index reader.index.get unit | return ([], 0)
  let rows ← directory reader.index (key "posting" term.id)
  let count ← getNat reader.index.get (key "frequency" term.id)
  unless rows.length == count do throw (IO.userError "lexical posting frequency disagrees")
  for (ordinal, owner) in rows do
    let indexed ← IO.ofExcept (payloadSize (← reader.index.get (key "owner" owner)))
    let live ← IO.ofExcept (payloadSize (← source.get (key "member" owner)))
    unless indexed == ordinal && live == ordinal &&
        (← getNat source.get (key "candidate" owner)) == 1 do
      throw (IO.userError "lexical posting names a different live source owner")
  pure (rows.map Prod.snd, count)

def ready (source : Snapshot) : IO Bool := do
  if (← getNat source.get "candidates") == 0 then return true
  pure (← open? source).isSome

def status (source : Snapshot) : IO Json := do
  let expected ← stamp source
  pure (Json.mkObj [("contract", toJson contract), ("stamp", toJson expected),
    ("ready", toJson (← ready source))])

/-- Hybrid nominations require complete lexical as well as numerical input.
A missing/partial index is pending, never a completed empty ranking. -/
def strictLookup (source : Snapshot) : IO (String → IO (List Nat × Nat)) := do
  if (← getNat source.get "candidates") == 0 then return fun _ => pure ([], 0)
  let some reader ← open? source |
    throw (IO.userError "dictionary-free lexical index is pending explicit/background warm")
  pure reader.posting

def strictPosting (source : Snapshot) (unit : String) : IO (List Nat × Nat) := do
  (← strictLookup source) unit

/-- Cold-index delivery uses existing original-unit postings as coarse advice.
It does not repair the index or claim the new normalized ranking is complete.
Normal operation requires warm; width/case aliases are guaranteed by that
complete index, not by this degraded original-unit path. -/
def originalPosting (source : Snapshot) (unit : String) : IO (List Nat × Nat) := do
  let text := String.ofList (unit.toList.drop 1)
  let units := (LogicalText.logical text).units.map (·.text)
  let mut matched : Option (Std.HashSet Nat) := none
  for part in units do
    let ids := Std.HashSet.ofList (← Store.postings source part)
    matched := some (match matched with | none => ids | some before => before.filter ids.contains)
  let ids ← (matched.getD {}).toList.filterM fun id => do
    pure ((← source.get (key "member" id)).isSome &&
      (← getNat source.get (key "candidate" id)) == 1)
  pure (ids, ids.length)

def coarseLookup (source : Snapshot) (receipt : Option String := none) :
    IO (String → IO (List Nat × Nat)) := do
  if (← getNat source.get "candidates") == 0 then return fun _ => pure ([], 0)
  if let some reader ← open? source then return reader.posting
  Receipt.observe receipt ("lexical-index-" ++ source.head.identity) (Json.mkObj [
    ("status", toJson "pending"), ("route", toJson "original-unit-postings"),
    ("database", toJson source.head.identity), ("contract", toJson contract)])
  pure (originalPosting source)

def reverseTerms (writer : DB.PageMap.Writer) (owner : Nat) : IO (List Nat) := do
  let bytes ← readChunks (← writer.snapshot) writer.get "ownerTerms" owner
  let (terms, tail) ← IO.ofExcept ((DB.Wire.list DB.Wire.natural).decode bytes.toList)
  unless tail.isEmpty && hashDistinct terms == terms do throw (IO.userError "invalid lexical reverse index")
  pure terms

def retract (writer : DB.PageMap.Writer) (owner ordinal : Nat) : IO Unit := do
  for (term, index) in (← reverseTerms writer owner).zipIdx do
    let count ← getNat writer.get (key "frequency" term)
    if count == 0 then throw (IO.userError "lexical frequency underflow")
    putNat writer (key "frequency" term) (count - 1)
    writer.put (key (key "posting" term) ordinal) none
    if index % 256 == 255 then writer.flush
  writer.put (key "owner" owner) none

def add (writer : DB.PageMap.Writer) (source : Snapshot) (document : SearchDocument)
    (ordinal : Nat) : IO Bool := do
  let retained ← writer.get (key "ownerTerms" document.owner)
  let terms ← if retained.isSome then reverseTerms writer document.owner else do
    let reader ← NodeReader.new source
    let owner ← reader.outcome (← reader.locateOutcome document.owner)
    let intern : Intern := ⟨writer, ← IO.mkRef {}⟩
    let mut result : Array Nat := #[]
    for (unit, index) in (tokens (searchText owner)).zipIdx do
      result := result.push (← intern.term unit)
      if index % 256 == 255 then writer.flush
    pure result.toList
  for (term, index) in terms.zipIdx do
    putNat writer (key "frequency" term) ((← getNat writer.get (key "frequency" term)) + 1)
    putNat writer (key (key "posting" term) ordinal) document.owner
    if index % 256 == 255 then writer.flush
  putChunks writer "ownerTerms" document.owner ((DB.Wire.list DB.Wire.natural).encode terms).toByteArray
  putNat writer (key "owner" document.owner) ordinal
  pure retained.isNone

structure Result where
  stamp : Stamp
  added : Nat := 0
  removed : Nat := 0
  hydrated : Nat := 0
  batches : Nat := 0
  deriving ToJson

/-- Explicit maintenance only. Read hooks never create or repair an index.
Removing readiness precedes every delta, so a crash cannot certify a partial
tree. Pinned older readers retain their complete immutable page root. -/
def warm (source : Snapshot) (storage : DB.Sidecar.Storage) : IO Result := do
  let expected ← stamp source
  if expected.candidates == 0 then return {stamp := expected}
  if let some known ← open? source then
    return {stamp := known.expected}
  DB.Sidecar.withIndexClaim (DB.Sidecar.Owner.ofSnapshot source) (fun sidecar => do
    let current ← (DB.Sidecar.Owner.ofSnapshot source).pin
    unless (← stamp current) == expected do throw (IO.userError "source changed before lexical warm")
    let folder ← DB.Sidecar.childDirectory sidecar.directory "lexical"
    let folder ← DB.Sidecar.childDirectory folder contract
    let target := folder / "tree"
    let initial ← if ← target.pathExists then DB.PageMap.pin target
      else DB.PageMap.create target (authority source)
    unless initial.head.authority == authority source do throw (IO.userError "foreign lexical index")
    let documents ← searchDocuments source
    let wanted ← documents.mapM fun document => do
      pure (document, ← getNat source.get (key "member" document.owner))
    let live := Std.HashMap.ofList (wanted.map fun (document, ordinal) => (document.owner, ordinal))
    let previous ← directory initial "owner"
    let known := Std.HashMap.ofList previous
    let removed := previous.filter fun (owner, ordinal) => live[owner]? != some ordinal
    let added := wanted.filter fun (document, ordinal) => known[document.owner]? != some ordinal
    let _ ← DB.PageMap.withWriter initial fun writer => writer.put "ready" none
    let mut index ← DB.PageMap.pin target
    let mut batches := 0
    let mut hydrated := 0
    let mut remainingRemoved := removed
    while !remainingRemoved.isEmpty do
      let batch := remainingRemoved.take 32
      let _ ← DB.PageMap.withWriter index fun writer =>
        for (owner, ordinal) in batch do retract writer owner ordinal
      remainingRemoved := remainingRemoved.drop 32
      index ← DB.PageMap.pin target
      batches := batches + 1
    let mut remainingAdded := added
    while !remainingAdded.isEmpty do
      let batch := remainingAdded.take 32
      let (read, _, _) ← DB.PageMap.withWriter index fun writer => do
        let mut read := 0
        for (document, ordinal) in batch do
          if ← add writer source document ordinal then read := read + 1
        pure read
      hydrated := hydrated + read
      remainingAdded := remainingAdded.drop 32
      index ← DB.PageMap.pin target
      batches := batches + 1
    let current ← (DB.Sidecar.Owner.ofSnapshot source).pin
    unless (← stamp current) == expected do throw (IO.userError "source changed during lexical warm")
    let observed ← directory index "owner"
    unless observed.length == expected.candidates &&
        observed.all (fun (owner, ordinal) => live[owner]? == some ordinal) do
      throw (IO.userError "lexical index does not cover the complete source catalogue")
    let _ ← DB.PageMap.withWriter index fun writer => do
      putNat writer "documents" expected.candidates
      writer.put "ready" (some (toJson expected).compress.toUTF8)
    pure {stamp := expected, added := added.length, removed := removed.length, hydrated, batches}) storage

end Eggshell.RetrievalResearch.Index
