module
public import Eggshell.SynapticRoutingStore

@[expose] public section
namespace Eggshell.Research.PreparedRoutingLeaf
open Lean Eggshell DB Synapses
open Synapses.Routing.Store

/-- A cached value carries the original bytes and semantic acceptance facts.
An advisory integer or a digest cannot supply these proofs. -/
structure Value (payload : ByteArray) where
  arc : Arc
  bounded : payload.size ≤ Index.payloadLimit
  canonical : encode arc = payload
  valid : (digest arc.evidence && arc.kind < 7 &&
    (arc.kind == 0 || arc.kind == 2) == arc.group.isSome) = true

theorem Value.unique {payload : ByteArray} (left right : Value payload) : left.arc = right.arc := by
  have same := left.canonical.trans right.canonical.symm
  apply arcCodec.encode_injective
  exact List.toByteArray_inj.mp same

/-- Preparation uses the actual product decoder. Invalid rows are left cold;
they fail in the original decoder only if the query selects them. -/
def Value.capture (payload : ByteArray) : IO (Option (Value payload)) := do
  try
    let arc ← decode payload
    if bounded : payload.size ≤ Index.payloadLimit then
      if canonical : encode arc = payload then
        if valid : (digest arc.evidence && arc.kind < 7 &&
            (arc.kind == 0 || arc.kind == 2) == arc.group.isSome) = true then
          return some ⟨arc,bounded,canonical,valid⟩
    return none
  catch _ => return none

structure Cell where
  name : String
  payload : Option ByteArray
  value : match payload with
    | none => PUnit
    | some bytes => Option (Value bytes)

def Cell.original (cell : Cell) : PageMap.Row := (cell.name,cell.payload)

def Cell.capture (row : PageMap.Row) : IO Cell := do
  match row with
  | (name,none) => return ⟨name,none,⟨⟩⟩
  | (name,some bytes) =>
    let value ← if name.startsWith "route:arc:" then Value.capture bytes else pure none
    return ⟨name,some bytes,value⟩

def Cell.read (cell : Cell) : IO (Option Arc) := do
  match cell with
  | ⟨_,none,_⟩ => return none
  | ⟨_,some bytes,none⟩ => some <$> decode bytes
  | ⟨_,some _,some value⟩ => return some value.arc

def select (range : PageMap.KeyRange) (cells : List Cell) : List Cell :=
  cells.filter (fun cell => range.contains cell.name)

theorem select_original (range : PageMap.KeyRange) (cells : List Cell) :
    (select range cells).map Cell.original = range.select (cells.map Cell.original) := by
  induction cells with
  | nil => rfl
  | cons cell rest ih =>
    simp only [select,PageMap.KeyRange.select,List.filter_cons,List.map_cons]
    by_cases hit : range.contains cell.name <;> simp_all [Cell.original,select,PageMap.KeyRange.select]

/-- The exact leaf, including row order and tombstones, remains the witness.
A cache entry cannot splice data from another page into this descriptor. -/
structure Leaf (ref : PageMap.Ref) where
  loaded : PageMap.Loaded ref
  cells : List Cell
  original : loaded.page = .leaf (cells.map Cell.original)

def Leaf.capture {ref : PageMap.Ref} (loaded : PageMap.Loaded ref) : IO (Option (Leaf ref)) := do
  match loaded.page with
  | .branch _ => return none
  | .leaf rows =>
    let cells ← rows.mapM Cell.capture
    if same : loaded.page = .leaf (cells.map Cell.original) then
      return some ⟨loaded,cells,same⟩
    throw (IO.userError "prepared routing leaf changed its original rows")

theorem Leaf.selected_original {ref : PageMap.Ref} (leaf : Leaf ref) (range : PageMap.KeyRange) :
    leaf.loaded.page = .leaf (leaf.cells.map Cell.original) ∧
    (select range leaf.cells).map Cell.original = range.select (leaf.cells.map Cell.original) :=
  ⟨leaf.original,select_original range leaf.cells⟩

structure PackedLeaf where
  ref : PageMap.Ref
  value : Leaf ref

def PackedLeaf.charge (leaf : PackedLeaf) : Nat :=
  leaf.ref.bytes+512+leaf.value.cells.length*64

def allowance : Nat := 8*1024*1024

abbrev Cache := Eggshell.Research.WeighedCache.Cache Nat PackedLeaf (allowance/2)
  (fun _ leaf => leaf.charge)

/-- One borrowed immutable image; the native probe alone owns its successor.
This is not a service-wide lifecycle or whole-heap bound. -/
structure Image where
  directory : String
  identity : String
  authority : String
  scope : String
  entries : Cache := {}

def Image.charged (image : Image) : Nat :=
  Eggshell.Research.WeighedCache.weightOf (fun _ leaf => leaf.charge) image.entries.state.recent.slots+
    Eggshell.Research.WeighedCache.weightOf (fun _ leaf => leaf.charge) image.entries.state.previous.slots

def Image.empty (snapshot : PageMap.Snapshot) (scope : String) : Image :=
  ⟨snapshot.directory.toString,snapshot.head.identity,snapshot.head.authority,scope,{}⟩

def Image.find (image : Image) (snapshot : PageMap.Snapshot) (scope : String)
    (ref : PageMap.Ref) : Option (Leaf ref) := do
  if snapshot.directory.toString != image.directory || snapshot.head.identity != image.identity ||
      snapshot.head.authority != image.authority || scope != image.scope then none else do
    let entry ← image.entries.find? ref.offset
    if same : entry.ref = ref then some (same ▸ entry.value) else none

def Image.admit (image : Image) (entry : PackedLeaf) : Image :=
  {image with entries := image.entries.insert entry.ref.offset entry}

theorem Image.charge_bounded (image : Image) : image.charged ≤ 8*1024*1024 :=
  image.entries.retained_bounded

theorem Image.foreign_scope (image : Image) (snapshot : PageMap.Snapshot) (scope : String)
    (ref : PageMap.Ref) (foreign : scope ≠ image.scope) : image.find snapshot scope ref = none := by
  simp [find,foreign]

end Eggshell.Research.PreparedRoutingLeaf
