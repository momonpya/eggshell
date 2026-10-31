module
public import Eggshell.CanonicalSourceRecipe
public import tools.research.SourceProjectionDictionary
@[expose] public section

namespace Eggshell.Synapses.OwnerPalette
open Lean CanonicalSource
open _root_.Eggshell.Research.SourceProjectionWire

/-- A candidate carries original coordinates and exact presentation costs.
No code body, question, score, usage label or completion authority is sent. -/
structure Row where
  file : Nat
  line : Nat
  origins : Array EncodedOrigin
  cost : Nat × Nat
  deriving BEq

abbrev RowWire := Nat × Nat × Array (Nat × Nat × Nat × Nat) × (Nat × Nat)

instance : ToJson Row := ⟨fun row => toJson ((row.file,row.line,row.origins.map (fun origin =>
  (origin.occurrence,origin.scope,origin.first,origin.limit)),row.cost) : RowWire)⟩

instance : FromJson Row where
  fromJson? value := do
    let (file,line,origins,cost) : RowWire ← fromJson? value
    return ⟨file,line,origins.map (fun (occurrence,scope,first,limit) => ⟨occurrence,scope,first,limit⟩),cost⟩

structure Descriptor where
  files : Array File
  occurrences : Array Occurrence
  scopes : Array Scope
  rows : Array Row
  catalogue : List (List Nat)
  deriving BEq,ToJson,FromJson

def Descriptor.origin? (descriptor : Descriptor) (origin : EncodedOrigin) : Option Origin :=
  readOriginUsing descriptor.occurrences descriptor.scopes origin

def Descriptor.inScope (descriptor : Descriptor) (database owner : String) : Bool :=
  descriptor.files.all File.valid && descriptor.occurrences.all (·.valid) &&
    descriptor.scopes.all (fun fields => fields.database == database && fields.owner == owner) &&
    descriptor.rows.all (fun row => row.file < descriptor.files.size && 0 < row.line &&
      !row.origins.isEmpty && row.origins.all (fun origin =>
        (descriptor.origin? origin).any (fun origin => origin.occurrence.valid && origin.binding.valid)) &&
      0 < row.cost.1 && row.cost.1 ≤ row.cost.2) &&
    descriptor.catalogue.all (fun unit => !unit.isEmpty && unit.all (· < descriptor.rows.size))

structure Projection where
  identity : Json
  lease : String
  owners : Array (String × Descriptor)
  deriving ToJson,FromJson

structure Fetch where
  owner : String
  indices : Array Nat
  deriving BEq,ToJson,FromJson

structure Fetched where
  owner : String
  indices : Array Nat
  rows : Array StoredRow
  deriving ToJson,FromJson

structure Reply where
  identity : Json
  parts : Array Fetched
  deriving ToJson,FromJson

def rowCost (row : StoredRow) : Nat × Nat :=
  let text := Packet.rowText row
  (text.length,text.utf8ByteSize)

def Descriptor.matches (descriptor : Descriptor) (index : Nat) (row : StoredRow) : Bool :=
  ((descriptor.rows[index]?).any fun expected =>
    descriptor.files[expected.file]? == some row.key.file && expected.line == row.key.line &&
    expected.cost == rowCost row &&
    expected.origins.mapM descriptor.origin? == some row.origins)

/-- Interning uses content equality. File names and full provenance records
occur once per immutable owner rather than once per row in its reply. -/
def describe (stored : Recipe.Stored) (layout : Recipe.Checked stored.rows) : Descriptor :=
  let tables := Tables.fromRows stored.rows
  let rows := stored.rows.map fun row =>
    ⟨tables.files.index row.key.file,row.key.line,row.origins.map (encodeOrigin tables),rowCost row⟩
  ⟨tables.files.values.toArray,tables.occurrences.values.toArray,tables.scopes.values.toArray,
    rows,layout.catalogue.map (·.map Fin.val)⟩

structure Ready (stored : Recipe.Stored) (layout : Recipe.Checked stored.rows) where
  descriptor : Descriptor
  exact : descriptor = describe stored layout
  json : Json
  jsonExact : json = toJson descriptor
  bytes : Nat
  bytesExact : bytes = json.compress.utf8ByteSize

def prepare (stored : Recipe.Stored) (layout : Recipe.Checked stored.rows) : Ready stored layout :=
  let descriptor := describe stored layout
  let json := toJson descriptor
  ⟨descriptor,rfl,json,rfl,json.compress.utf8ByteSize,rfl⟩

theorem prepared_exact (stored : Recipe.Stored) (layout : Recipe.Checked stored.rows) :
    (prepare stored layout).descriptor = describe stored layout := rfl

/-- Fetch accepts row identities from this pinned palette. It never
re-ranks them, repairs the source, or expands to all rows of an owner. -/
structure Selection (stored : Recipe.Stored) where
  indices : Array (Fin stored.rows.size)

def Selection.rows (selected : Selection stored) : Array StoredRow :=
  selected.indices.map fun index => stored.rows[index]

def select (stored : Recipe.Stored) (indices : Array Nat) : Except String (Selection stored) := do
  let indices ← indices.mapM fun index =>
    if bound : index < stored.rows.size then pure (⟨index,bound⟩ : Fin stored.rows.size)
    else throw "palette row is outside its immutable owner"
  return ⟨indices⟩

theorem selected_original (selected : Selection stored) :
    ∀ row ∈ selected.rows, row ∈ stored.rows := by
  intro row present
  obtain ⟨index,_,equal⟩ := Array.mem_map.mp present
  rw [← equal]
  exact Array.getElem_mem index.isLt

end Eggshell.Synapses.OwnerPalette
