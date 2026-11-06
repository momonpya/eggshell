module
public import tools.research.SourceProjectionDictionary
@[expose] public section
namespace Eggshell.Research.CompactProvenance
open Lean Synapses CanonicalSource SourceProjectionWire

/-- One response owns these immutable dictionaries. No source, occurrence,
scope, offset, quotation or ordering is approximated or discarded. -/
structure Tables where
  subjects : Array Subject
  occurrences : Array Occurrence
  scopes : Array Scope
  deriving ToJson,FromJson

structure Builder where
  subjects : Directory Subject
  occurrences : Directory Occurrence
  scopes : Directory Scope

def Builder.tables (builder : Builder) : Tables :=
  ⟨builder.subjects.values.toArray,builder.occurrences.values.toArray,builder.scopes.values.toArray⟩

structure Input where
  rows : Array StoredRow
  reads : Array Read

def Input.subjects (input : Input) : List Subject :=
  input.reads.toList.map (·.source.subject) ++ input.rows.toList.map (fun row => .file row.key.file)
def Input.occurrences (input : Input) : List Occurrence :=
  input.reads.toList.map (·.occurrence) ++
    input.rows.toList.flatMap (fun row => row.origins.toList.map (·.occurrence))
def Input.scopes (input : Input) : List Scope :=
  input.reads.toList.map (fun read => scope read.binding) ++
    input.rows.toList.flatMap (fun row => row.origins.toList.map (fun origin => scope origin.binding))
def Input.builder (input : Input) : Builder :=
  ⟨directory input.subjects,directory input.occurrences,directory input.scopes⟩

structure EncodedRead where
  subject : Nat
  occurrence : Nat
  scope : Nat
  first : Nat
  last : Nat
  bindingFirst : Nat
  bindingLimit : Nat
  quotations : Array String
  deriving ToJson,FromJson

def encodeRead (builder : Builder) (read : Read) : EncodedRead := {
  subject := builder.subjects.index read.source.subject
  occurrence := builder.occurrences.index read.occurrence
  scope := builder.scopes.index (scope read.binding)
  first := read.source.first,last := read.source.last
  bindingFirst := read.binding.first,bindingLimit := read.binding.limit,quotations := read.quotations }

def decodeRead (tables : Tables) (read : EncodedRead) : Option Read := do
  let subject ← tables.subjects[read.subject]?
  let occurrence ← tables.occurrences[read.occurrence]?
  let fields ← tables.scopes[read.scope]?
  return ⟨occurrence,⟨subject,read.first,read.last⟩,
    ⟨fields.database,fields.owner,fields.work,read.bindingFirst,read.bindingLimit⟩,read.quotations⟩

theorem read_roundtrip (builder : Builder) (read : Read)
    (subject : read.source.subject ∈ builder.subjects.values)
    (occurrence : read.occurrence ∈ builder.occurrences.values)
    (fields : scope read.binding ∈ builder.scopes.values) :
    decodeRead builder.tables (encodeRead builder read) = some read := by
  simp only [decodeRead,encodeRead,Builder.tables]
  rw [builder.subjects.resolves _ subject,builder.occurrences.resolves _ occurrence,
    builder.scopes.resolves _ fields]
  cases read with
  | mk occurrence source binding quotations => cases source; cases binding; rfl

def encodeOrigin (builder : Builder) (origin : Origin) : EncodedOrigin :=
  ⟨builder.occurrences.index origin.occurrence,builder.scopes.index (scope origin.binding),
    origin.binding.first,origin.binding.limit⟩

def decodeOrigin (tables : Tables) : EncodedOrigin → Option Origin :=
  readOriginUsing tables.occurrences tables.scopes

theorem origin_roundtrip (builder : Builder) (origin : Origin)
    (occurrence : origin.occurrence ∈ builder.occurrences.values)
    (fields : scope origin.binding ∈ builder.scopes.values) :
    decodeOrigin builder.tables (encodeOrigin builder origin) = some origin := by
  simp only [decodeOrigin,readOriginUsing,encodeOrigin,Builder.tables]
  rw [builder.occurrences.resolves _ occurrence,builder.scopes.resolves _ fields]
  rfl

def restoreList (decode : β → Option α) : List β → Option (List α)
  | [] => some []
  | first::rest => do return (← decode first)::(← restoreList decode rest)

theorem restoreList_map (encode : α → β) (decode : β → Option α) (values : List α)
    (exact : ∀ value ∈ values,decode (encode value) = some value) :
    restoreList decode (values.map encode) = some values := by
  induction values with
  | nil => rfl
  | cons first rest ih =>
    simp only [List.map_cons,restoreList,exact first (by simp)]
    rw [ih (fun value present => exact value (by simp [present]))]
    rfl

def restoreArray (decode : β → Option α) (values : Array β) : Option (Array α) :=
  (restoreList decode values.toList).map List.toArray

theorem restoreArray_map (encode : α → β) (decode : β → Option α) (values : Array α)
    (exact : ∀ value ∈ values,decode (encode value) = some value) :
    restoreArray decode (values.map encode) = some values := by
  unfold restoreArray
  rw [Array.toList_map,restoreList_map encode decode values.toList (by simpa using exact)]
  simp

structure EncodedRow where
  subject : Nat
  line : Nat
  code : String
  origins : Array EncodedOrigin
  deriving ToJson,FromJson

def encodeRow (builder : Builder) (row : StoredRow) : EncodedRow :=
  ⟨builder.subjects.index (.file row.key.file),row.key.line,row.code,row.origins.map (encodeOrigin builder)⟩

def decodeRow (tables : Tables) (row : EncodedRow) : Option StoredRow := do
  let .file file ← tables.subjects[row.subject]? | none
  let origins ← restoreArray (decodeOrigin tables) row.origins
  return ⟨⟨file,row.line⟩,row.code,origins⟩

theorem row_roundtrip (builder : Builder) (row : StoredRow)
    (subject : Subject.file row.key.file ∈ builder.subjects.values)
    (occurrence : ∀ origin ∈ row.origins,origin.occurrence ∈ builder.occurrences.values)
    (fields : ∀ origin ∈ row.origins,scope origin.binding ∈ builder.scopes.values) :
    decodeRow builder.tables (encodeRow builder row) = some row := by
  simp only [decodeRow,encodeRow,Builder.tables]
  rw [builder.subjects.resolves _ subject]
  change (do
    let origins ← restoreArray (decodeOrigin builder.tables) (row.origins.map (encodeOrigin builder))
    pure (⟨⟨row.key.file,row.key.line⟩,row.code,origins⟩ : StoredRow)) = some row
  rw [restoreArray_map (encodeOrigin builder) (decodeOrigin builder.tables) row.origins
    (fun origin member => origin_roundtrip builder origin (occurrence origin member) (fields origin member))]
  cases row with
  | mk key code origins => cases key; rfl

theorem Input.read_subject (input : Input) (read : Read) (present : read ∈ input.reads) :
    read.source.subject ∈ input.builder.subjects.values := by
  simp only [Input.builder,Input.subjects,directory_member,List.mem_append]
  exact Or.inl (List.mem_map.mpr ⟨read,by simpa using present,rfl⟩)

theorem Input.read_occurrence (input : Input) (read : Read) (present : read ∈ input.reads) :
    read.occurrence ∈ input.builder.occurrences.values := by
  simp only [Input.builder,Input.occurrences,directory_member,List.mem_append]
  exact Or.inl (List.mem_map.mpr ⟨read,by simpa using present,rfl⟩)

theorem Input.read_scope (input : Input) (read : Read) (present : read ∈ input.reads) :
    scope read.binding ∈ input.builder.scopes.values := by
  simp only [Input.builder,Input.scopes,directory_member,List.mem_append]
  exact Or.inl (List.mem_map.mpr ⟨read,by simpa using present,rfl⟩)

theorem Input.row_subject (input : Input) (row : StoredRow) (present : row ∈ input.rows) :
    Subject.file row.key.file ∈ input.builder.subjects.values := by
  simp only [Input.builder,Input.subjects,directory_member,List.mem_append]
  exact Or.inr (List.mem_map.mpr ⟨row,by simpa using present,rfl⟩)

theorem Input.origin_occurrence (input : Input) (row : StoredRow) (present : row ∈ input.rows)
    (origin : Origin) (member : origin ∈ row.origins) :
    origin.occurrence ∈ input.builder.occurrences.values := by
  simp only [Input.builder,Input.occurrences,directory_member,List.mem_append]
  exact Or.inr (List.mem_flatMap.mpr ⟨row,by simpa using present,
    List.mem_map.mpr ⟨origin,by simpa using member,rfl⟩⟩)

theorem Input.origin_scope (input : Input) (row : StoredRow) (present : row ∈ input.rows)
    (origin : Origin) (member : origin ∈ row.origins) :
    scope origin.binding ∈ input.builder.scopes.values := by
  simp only [Input.builder,Input.scopes,directory_member,List.mem_append]
  exact Or.inr (List.mem_flatMap.mpr ⟨row,by simpa using present,
    List.mem_map.mpr ⟨origin,by simpa using member,rfl⟩⟩)

theorem Input.restore_read (input : Input) (read : Read) (present : read ∈ input.reads) :
    decodeRead input.builder.tables (encodeRead input.builder read) = some read :=
  read_roundtrip _ _ (input.read_subject read present) (input.read_occurrence read present) (input.read_scope read present)

theorem Input.restore_row (input : Input) (row : StoredRow) (present : row ∈ input.rows) :
    decodeRow input.builder.tables (encodeRow input.builder row) = some row :=
  row_roundtrip _ _ (input.row_subject row present)
    (input.origin_occurrence row present) (input.origin_scope row present)

end Eggshell.Research.CompactProvenance
