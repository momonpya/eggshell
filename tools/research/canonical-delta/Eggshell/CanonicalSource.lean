module
public import Eggshell.SynapseBuild
public import Eggshell.SourceDelta
@[expose] public section

namespace Eggshell.Synapses.CanonicalSource
open Lean _root_.Eggshell.Synapses.Extraction DB
variable {database : String} {document : Document}

/-- The payload identity contains no owner, session or occurrence. Original
observations remain separate origins and cannot acquire Union authority. -/
structure Key where
  file : File
  line : Nat
  deriving Repr, DecidableEq, BEq, ReflBEq, LawfulBEq, Hashable, ToJson, FromJson

structure Origin where
  occurrence : Occurrence
  binding : Binding
  deriving Repr, DecidableEq, BEq, ReflBEq, LawfulBEq, Hashable, ToJson, FromJson

structure Prepared (database : String) (document : Document) where
  raw : Array Char
  rawExact : raw = (document.source.getD "").toList.toArray
  rows : Array Read
  rowsExact : recordedRows database document = .ok rows
  native : document.native = true

def prepare (database : String) (document : Document) : Except String (Prepared database document) := do
  if native : document.native = true then
    match rowsExact : recordedRows database document with
    | .error error => throw error
    | .ok rows => return ⟨(document.source.getD "").toList.toArray,rfl,rows,rowsExact,native⟩
  else throw "not an original native source observation"

def escaped (text : String) : String :=
  String.ofList ((toJson text).compress.toList.drop 1 |>.dropLast)

def literal (raw : Array Char) (first limit : Nat) (line : String) : Bool :=
  let text := String.ofList (raw.extract first limit).toList
  first < limit && limit ≤ raw.size &&
    (text == line || text == escaped line)

/-- The row is checked against a member of the pinned original projection
and its actual scalar bytes. Code is transient here; origins store no copy. -/
structure Observation (prepared : Prepared database document) where
  index : Fin prepared.rows.size
  file : File
  typed : prepared.rows[index].source.subject = .file file
  code : String
  line : String
  single : prepared.rows[index].source.first = prepared.rows[index].source.last
  valid : prepared.rows[index].valid = true
  decoded : numbered line = some (prepared.rows[index].source.first,code)
  original : literal prepared.raw prepared.rows[index].binding.first prepared.rows[index].binding.limit
    line = true ∨
    literal prepared.raw prepared.rows[index].binding.first prepared.rows[index].binding.limit (line ++ "\n") = true

variable {prepared : Prepared database document}

def Observation.key (row : Observation prepared) : Key :=
  ⟨row.file,prepared.rows[row.index].source.first⟩

def Observation.origin (row : Observation prepared) : Origin :=
  ⟨prepared.rows[row.index].occurrence,prepared.rows[row.index].binding⟩

/-- Several native execution witnesses may belong to one saved owner. The
payload is shared, but no real session/turn/use identity is discarded. -/
def Observation.origins (row : Observation prepared) : Std.HashSet Origin :=
  document.occurrences.foldl (fun found occurrence =>
    if occurrence.valid then found.insert ⟨occurrence,prepared.rows[row.index].binding⟩ else found)
    (({} : Std.HashSet Origin).insert row.origin)

def observe? (prepared : Prepared database document) (index : Fin prepared.rows.size)
    (line : String) : Option (Observation prepared) := do
  match typed : prepared.rows[index].source.subject with
  | .original _ => none
  | .file file => do
    let (_,code) ← numbered line
    if single : prepared.rows[index].source.first = prepared.rows[index].source.last then
      if valid : prepared.rows[index].valid = true then
        if decoded : numbered line = some (prepared.rows[index].source.first,code) then
          if original : literal prepared.raw prepared.rows[index].binding.first prepared.rows[index].binding.limit line = true ∨
              literal prepared.raw prepared.rows[index].binding.first prepared.rows[index].binding.limit (line ++ "\n") = true then
            some ⟨index,file,typed,code,line,single,valid,decoded,original⟩
          else none
        else none
      else none
    else none

structure Atom where
  code : String
  origins : Std.HashSet Origin

structure Registry where
  atoms : Std.HashMap Key Atom := {}

def Atom.withoutOwners (atom : Atom) (owners : Std.HashSet String) : Atom :=
  {atom with origins := atom.origins.filter fun origin => !owners.contains origin.binding.owner}

theorem Atom.remaining_origin (atom : Atom) (owners : Std.HashSet String) (origin : Origin)
    (retained : origin ∈ (atom.withoutOwners owners).origins) :
    origin ∈ atom.origins ∧ owners.contains origin.binding.owner = false := by
  simpa [Atom.withoutOwners] using retained

theorem Atom.remaining_code (atom : Atom) (owners : Std.HashSet String) :
    (atom.withoutOwners owners).code = atom.code := rfl

/-- Retire only bindings from the changed original owners. A shared payload
remains while any other owner still witnesses it; empty classes disappear. -/
def Registry.withoutOwners (registry : Registry) (owners : Std.HashSet String) : Registry :=
  ⟨registry.atoms.filterMap fun _ atom =>
    let kept := atom.withoutOwners owners
    if kept.origins.isEmpty then none else some kept⟩

/-- Full key equality chooses a class; full text equality permits joining
origins. A hash alone never merges payloads or resolves contradictory text. -/
def Registry.insert (registry : Registry) (row : Observation prepared) : Except String Registry :=
  match registry.atoms[row.key]? with
  | none => .ok ⟨registry.atoms.insert row.key ⟨row.code,row.origins⟩⟩
  | some prior =>
    if prior.code = row.code then
      let origins := row.origins.fold (fun found origin => found.insert origin) prior.origins
      .ok ⟨registry.atoms.insert row.key {prior with origins}⟩
    else .error s!"conflicting canonical source row: {row.key.file.relative}:{row.key.line}"

theorem existing_payload_kept (registry : Registry) (row : Observation prepared) (prior : Atom)
    (existing : registry.atoms[row.key]? = some prior) (next : Registry)
    (inserted : registry.insert row = .ok next) :
    (next.atoms[row.key]?).map (·.code) = some prior.code := by
  simp only [Registry.insert,existing] at inserted
  split at inserted
  · cases inserted
    simp
  · contradiction

theorem changed_fingerprint_separates (left right : Key)
    (changed : left.file.fingerprint ≠ right.file.fingerprint) : left ≠ right := by
  intro same
  exact changed (congrArg (fun key => key.file.fingerprint) same)

theorem replay_does_not_add_origin (origins : Std.HashSet Origin) (origin query : Origin) :
    ((origins.insert origin).insert origin).contains query = (origins.insert origin).contains query := by
  simp

structure Statistics where
  nativeOwners : Nat := 0
  originalRows : Nat := 0
  rejectedRows : Nat := 0
  unsupportedOwners : Nat := 0
  deriving BEq, ToJson, FromJson

def Statistics.subtract (total removed : Statistics) : Except String Statistics := do
  unless removed.nativeOwners ≤ total.nativeOwners && removed.originalRows ≤ total.originalRows &&
      removed.rejectedRows ≤ total.rejectedRows && removed.unsupportedOwners ≤ total.unsupportedOwners do
    throw "canonical source statistics underflow"
  return ⟨total.nativeOwners-removed.nativeOwners,total.originalRows-removed.originalRows,
    total.rejectedRows-removed.rejectedRows,total.unsupportedOwners-removed.unsupportedOwners⟩

structure StoredRow where
  key : Key
  code : String
  origins : Array Origin
  deriving BEq, ToJson, FromJson

def Registry.store (registry : Registry) : Array StoredRow :=
  (registry.atoms.toArray.map fun (key,atom) =>
    {key,code := atom.code,origins := atom.origins.toArray.qsort fun a b =>
      (toJson a).compress < (toJson b).compress}).qsort fun a b =>
        (toJson a.key).compress < (toJson b.key).compress

/-- Loading cannot merge contradictory payloads, accept dangling origins,
or move an origin across its source DB. The content digest is checked by the
storage adapter before this structural check. -/
def load (database : String) (rows : Array StoredRow) : Except String Registry := do
  let mut registry : Registry := {}
  for row in rows do
    unless row.key.file.valid && 0 < row.key.line && !row.origins.isEmpty &&
        row.origins.all (fun origin => origin.occurrence.valid && origin.binding.valid &&
          origin.binding.database == database) do throw "invalid canonical source row or origin"
    if registry.atoms.contains row.key then throw "duplicate canonical source row"
    let origins := row.origins.foldl (fun found origin => found.insert origin) ({} : Std.HashSet Origin)
    unless origins.size == row.origins.size do throw "duplicate canonical origin"
    registry := ⟨registry.atoms.insert row.key ⟨row.code,origins⟩⟩
  return registry

structure Resolved (registry : Registry) (source : Range) where
  rows : Array StoredRow
  complete : rows.map (·.key.line) = (Array.range (source.last+1-source.first)).map (source.first+·)
  original : rows.all (fun row => Subject.file row.key.file == source.subject &&
    (registry.atoms[row.key]?).any (fun atom => atom.code == row.code)) = true

def Registry.resolve? (registry : Registry) (source : Range) : Option (Resolved registry source) := do
  let .file file := source.subject | none
  if !source.valid || registry.atoms.size < source.last+1-source.first then none else do
    let numbers := (Array.range (source.last+1-source.first)).map (source.first+·)
    let rows ← numbers.mapM fun number => do
      let key := Key.mk file number
      let atom ← registry.atoms[key]?
      return {key,code := atom.code,origins := atom.origins.toArray : StoredRow}
    if complete : rows.map (·.key.line) = numbers then
      if original : rows.all (fun row => Subject.file row.key.file == source.subject &&
          (registry.atoms[row.key]?).any (fun atom => atom.code == row.code)) = true then
        some ⟨rows,complete,original⟩
      else none
    else none

theorem resolved_original (resolved : Resolved registry source) (row : StoredRow)
    (member : row ∈ resolved.rows) : Subject.file row.key.file = source.subject ∧
      ∃ atom, registry.atoms[row.key]? = some atom ∧ atom.code = row.code := by
  have original := (Array.all_eq_true'.mp resolved.original) row member
  simpa only [Bool.and_eq_true,beq_iff_eq,Option.any_eq_true] using original

def addDocument (registry : Registry) (statistics : Statistics) (database : String) (document : Document) :
    Except String (Registry × Statistics) := do
  let statistics := {statistics with nativeOwners := statistics.nativeOwners+1}
  let .ok prepared := prepare database document |
    return (registry,{statistics with unsupportedOwners := statistics.unsupportedOwners+1})
  let decoded ← layout (document.source.getD "")
  let mut coordinates : Std.HashMap (Nat × Nat) (Fin prepared.rows.size) := {}
  for index in List.finRange prepared.rows.size do
    let row := prepared.rows[index]
    if coordinates.contains (row.binding.first,row.binding.limit) then throw "duplicate original scalar row position"
    coordinates := coordinates.insert (row.binding.first,row.binding.limit) index
  let mut registry := registry
  let mut statistics := statistics
  for line in textLines decoded.text do
    let some first := decoded.offsets[line.first]? | continue
    let some limit := decoded.offsets[line.limit]? | continue
    let some index := coordinates[(first,limit)]? | continue
    let some row := observe? prepared index line.text |
      statistics := {statistics with rejectedRows := statistics.rejectedRows+1}; continue
    registry ← registry.insert row
    statistics := {statistics with originalRows := statistics.originalRows+1}
  return (registry,statistics)

def build (source : PageMap.Snapshot) : IO (Registry × Statistics) := do
  let reader ← Persistence.Store.NodeReader.new source
  let mut registry : Registry := {}
  let mut statistics : Statistics := {}
  for entry in ← Build.entries source do
    let document ← Build.document reader entry.id
    if document.native then
      let next ← IO.ofExcept (addDocument registry statistics source.head.identity document)
      registry := next.1
      statistics := next.2
  return (registry,statistics)

structure Rebased where
  registry : Registry
  statistics : Statistics
  owners : Nat
  hydrated : Nat

/-- Exact publication history determines candidate changes and source-receipt
owners. Old contributions are removed against the old pinned original, then
current originals are reinserted by the same checked row extractor as build.
Provenance timing/usage metadata is not an input to original source rows. -/
def rebase (source : PageMap.Snapshot) (before : PageMap.Head) (registry : Registry)
    (statistics : Statistics) : IO (Option Rebased) := do
  let some _ ← SourceDelta.read? source before | return none
  let some history ← PageMap.HistoryReader.make? source before | return none
  let some changes ← Build.changes source before | return none
  if changes.owners.size > 4096 then return none
  let ids := changes.owners.toList
  let previous ← SourceDelta.documents history.snapshot ids
  let current ← SourceDelta.documents source ids
  let oldReader ← Persistence.Store.NodeReader.new history.snapshot
  let newReader ← Persistence.Store.NodeReader.new source
  let mut owners : Std.HashSet String := {}
  let mut statistics := statistics
  for entry in previous do
    let document ← Build.document oldReader entry.owner
    owners := owners.insert document.owner
    if document.native then
      let (_,contribution) ← IO.ofExcept (addDocument {} {} source.head.identity document)
      statistics ← IO.ofExcept (statistics.subtract contribution)
  let documents ← current.mapM fun entry => Build.document newReader entry.owner
  for document in documents do owners := owners.insert document.owner
  let mut registry := registry.withoutOwners owners
  for document in documents do
    if document.native then
      let next ← IO.ofExcept (addDocument registry statistics source.head.identity document)
      registry := next.1
      statistics := next.2
  return some ⟨registry,statistics,ids.length,previous.length+current.length⟩

def Registry.summary (registry : Registry) (statistics : Statistics) : Json :=
  let aliases := registry.atoms.fold (fun count _ atom => count+atom.origins.size) 0
  let payload := registry.atoms.fold (fun count _ atom => count+atom.code.utf8ByteSize) 0
  Json.mkObj [("source",toJson statistics),("canonicalRows",toJson registry.atoms.size),
    ("originBindings",toJson aliases),("codePayloadBytes",toJson payload),
    ("multiplyObservedRows",toJson (registry.atoms.fold (fun count _ atom =>
      if atom.origins.size > 1 then count+1 else count) 0))]

end Eggshell.Synapses.CanonicalSource
