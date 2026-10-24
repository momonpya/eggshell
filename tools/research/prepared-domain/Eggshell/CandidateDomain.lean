module

public import Eggshell.GraphStore
public import Eggshell.Receipt

@[expose] public section

namespace Eggshell.CandidateDomain
open Lean DB Persistence.Store

/-- Nomination metadata only. Original owners must still be read and checked
before Match can receive their original Work, Outcome and occurrence authority. -/
structure Row where
  owner : Nat
  ordinal : Nat
  work : Nat
  text : String
  native : Bool
  windows : List String
  deriving BEq, ToJson, FromJson

def boolCodec : Wire.Codec Bool := Wire.natural.iso
  (fun value => if value then 1 else 0) (· != 0) (by intro value; cases value <;> rfl)

def rowCodec : Wire.Codec Row :=
  (Wire.natural.product (Wire.natural.product (Wire.natural.product
    (Wire.text.product (boolCodec.product (Wire.list Wire.text)))))).iso
    (fun row => (row.owner,row.ordinal,row.work,row.text,row.native,row.windows))
    (fun (owner,ordinal,work,text,native,windows) => ⟨owner,ordinal,work,text,native,windows⟩)
    (by intro row; cases row; rfl)

structure Data where
  rows : List Row
  links : List (Nat × List Nat)
  deriving BEq

def dataCodec : Wire.Codec Data :=
  ((Wire.list rowCodec).product (Wire.list (Wire.natural.product (Wire.list Wire.natural)))).iso
    (fun data => (data.rows,data.links)) (fun (rows,links) => ⟨rows,links⟩)
    (by intro data; cases data; rfl)

theorem packed_roundtrip (data : Data) (tail : List UInt8) :
    dataCodec.decode (dataCodec.encode data ++ tail) = .ok (data,tail) :=
  dataCodec.roundtrip data tail

structure Stamp where
  database : String
  authority : String
  change : Nat
  roots : Nat
  candidates : Nat
  deriving BEq, ToJson, FromJson

def stamp (source : Snapshot) : IO Stamp := do
  return ⟨source.head.identity,Sha256.hex source.head.authority.toUTF8,
    ← getNat source.get "sourceChange",← getNat source.get "roots",← getNat source.get "candidates"⟩

def implementation : String := Sha256.hex (
  (include_str "CandidateDomain.lean").toUTF8 ++
  (include_str "GraphStore.lean").toUTF8 ++
  (include_str "SearchRank.lean").toUTF8)

structure Manifest where
  source : PageMap.Head
  stamp : Stamp
  implementation : String
  digest : String
  bytes : Nat
  windows : Nat
  deriving ToJson, FromJson

def maxBytes : Nat := 64*1024*1024

def directory (source : Snapshot) (storage : Sidecar.Storage) : IO System.FilePath := do
  return (← Sidecar.locate source storage).directory / "candidate-domain"

def manifest? (source : Snapshot) (storage : Sidecar.Storage) : IO (Option Manifest) := do
  let path ← directory source storage
  let bytes ← FileSystem.boundedBytes (path / "ready.json") 65536
  let some text := String.fromUTF8? bytes | throw (IO.userError "invalid candidate readiness UTF-8")
  let record ← IO.ofExcept (Json.parse text >>= fromJson? (α := Manifest))
  unless record.stamp == (← stamp source) && record.implementation == implementation &&
      record.bytes ≤ maxBytes && record.source.identity == source.head.identity &&
      record.source.authority == source.head.authority do return none
  return some record

def Row.document (row : Row) (source : Snapshot) : SearchDocument :=
  ⟨row.owner,row.work,row.windows,some (Sidecar.Owner.ofSnapshot source)⟩

def Row.origin (row : Row) : WorkOrigin := ⟨.text row.text,row.native⟩

structure Ready where
  metadata : Manifest
  data : Data
  owners : Std.HashMap Nat Row
  documents : List SearchDocument
  workIds : Std.HashSet Nat

/-- Stable directory order, unique owner/ordinal identities and all window
keys are checked once. Cached native flags remain nomination hints. -/
def prepare (source : Snapshot) (metadata : Manifest) (data : Data) : Except String Ready := do
  unless data.rows.length == metadata.stamp.candidates do throw "candidate count disagrees"
  let mut previous : Option Nat := none
  let mut owners : Std.HashMap Nat Row := {}
  let mut windows := 0
  let mut workIds : Std.HashSet Nat := {}
  for row in data.rows do
    if owners.contains row.owner || previous.any (· ≥ row.ordinal) then throw "candidate order is not unique"
    unless !row.windows.isEmpty && row.windows.all (fun value =>
        value.length == 64 && value.toList.all (fun c =>
          ('0' ≤ c && c ≤ '9') || ('a' ≤ c && c ≤ 'f'))) do throw "invalid candidate window key"
    windows := windows+row.windows.length
    previous := some row.ordinal
    owners := owners.insert row.owner row
    workIds := workIds.insert row.work
  unless windows == metadata.windows do throw "candidate window count disagrees"
  return ⟨metadata,data,owners,data.rows.map (·.document source),workIds⟩

/-- One bounded payload read, checksum and decode. No source body or owner
membership is scanned here, and a cold/invalid domain is never repaired. -/
def open? (source : Snapshot) (storage : Sidecar.Storage) : IO (Option Ready) := do
  let some metadata ← manifest? source storage | return none
  let bytes ← FileSystem.boundedBytes ((← directory source storage) / "domain") maxBytes
  unless bytes.size == metadata.bytes && Sha256.hex bytes == metadata.digest do
    throw (IO.userError "candidate domain digest disagrees")
  let (data,tail) ← IO.ofExcept (dataCodec.decode bytes.toList)
  unless tail.isEmpty do throw (IO.userError "trailing candidate domain bytes")
  some <$> IO.ofExcept (prepare source metadata data)

def openShared? (source : Snapshot) (receipt : Option String := none) : IO (Option Ready) := do
  let started ← IO.monoMsNow
  for storage in [.database,.user] do
    try
      if let some ready ← open? source storage then
        Receipt.observe receipt ("candidate-domain-" ++ source.head.identity) (Json.mkObj [
          ("status",toJson "ready"),("storage",toJson storage),
          ("rows",toJson ready.data.rows.length),("windows",toJson ready.metadata.windows),
          ("bytes",toJson ready.metadata.bytes),("digest",toJson ready.metadata.digest),
          ("elapsedMs",toJson ((← IO.monoMsNow)-started))])
        return some ready
    catch error =>
      Receipt.observe receipt ("candidate-domain-" ++ source.head.identity) (Json.mkObj [
        ("status",toJson "unavailable"),("storage",toJson storage),("error",toJson error.toString)])
  return none

/-- Maintenance hint only. Actual hook reads always verify the packed payload. -/
def ready (source : Snapshot) : IO Bool := do
  for storage in [.database,.user] do
    try
      if let some _ ← manifest? source storage then return true
    catch _ => pure ()
  return false

/-- The same parent membership rule as the complete original-header path.
Staged Work may extend the parent domain without reopening saved All frames. -/
def Ready.children (ready : Ready) (parents : Std.HashSet Nat) : Std.HashSet Nat :=
  ready.data.links.foldl (fun children (parent,values) =>
    if parents.contains parent then values.foldl (·.insert ·) children else children) {}

structure Result where
  mode : String
  metadata : Manifest
  elapsedMs : Nat
  deriving ToJson

/-- Explicit/background maintenance only. Original catalogue and Work reads
happen here once, outside the hook. Two atomically replaced files keep storage
bounded across source changes; a racing reader can miss but cannot accept a
mismatching payload. Original graph membership is never written. -/
def refresh (source : Snapshot) (storage : Sidecar.Storage) : IO Result := do
  let started ← IO.monoMsNow
  if let some known ← try open? source storage catch _ => pure none then
    return ⟨"warm",known.metadata,(← IO.monoMsNow)-started⟩
  let expected ← stamp source
  Sidecar.withIndexClaim (Sidecar.Owner.ofSnapshot source) (fun sidecar => do
    unless (← stamp (← (Sidecar.Owner.ofSnapshot source).pin)) == expected do
      throw (IO.userError "source changed before candidate preparation")
    let reader ← NodeReader.new source
    let mut rows := []
    let mut windows := 0
    for document in ← searchDocuments source do
      let origin ← reader.workOrigin (← reader.locateOutcome document.owner)
      let some text := text? origin.work | throw (IO.userError "candidate Work is not textual")
      let ordinal ← getNat source.get (key "member" document.owner)
      let row : Row := {
        owner := document.owner
        ordinal := ordinal
        work := document.work
        text := text
        native := origin.native
        windows := document.windows }
      rows := row :: rows
      windows := windows+document.windows.length
    let mut links := []
    for entry in ← allHeaders source do
      let some located := entry.2.atHead? source.head | throw (IO.userError "foreign candidate topology")
      links := (located.val.header.parent,located.val.header.children) :: links
    let data : Data := ⟨rows.reverse,links.reverse⟩
    let bytes := (dataCodec.encode data).toByteArray
    unless bytes.size ≤ maxBytes do throw (IO.userError "candidate domain exceeds byte budget")
    let metadata : Manifest := ⟨source.head,expected,implementation,Sha256.hex bytes,bytes.size,windows⟩
    let _ ← IO.ofExcept (prepare source metadata data)
    unless (← stamp (← (Sidecar.Owner.ofSnapshot source).pin)) == expected do
      throw (IO.userError "source changed during candidate preparation")
    let path ← Sidecar.childDirectory sidecar.directory "candidate-domain"
    if let some previous ← try manifest? source storage catch _ => pure none then
      if previous.source.revision > source.head.revision then throw (IO.userError "newer candidate domain already exists")
    FileSystem.atomicExistingBytes (path / "domain") bytes
    FileSystem.atomicExistingBytes (path / "ready.json") (toJson metadata).compress.toUTF8
    return ⟨"prepared",metadata,(← IO.monoMsNow)-started⟩) storage

end Eggshell.CandidateDomain
