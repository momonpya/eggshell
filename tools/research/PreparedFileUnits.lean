module
public import Eggshell.CanonicalSourceRecipe
@[expose] public section

namespace Eggshell.Synapses.PreparedFileUnits
open CanonicalSource

def bindings (owner : String) (rows : Array StoredRow) : List (Nat × Nat) :=
  hashDistinct (rows.toList.flatMap fun row => row.origins.toList.filterMap fun origin =>
    if origin.binding.owner == owner then some (origin.binding.first,origin.binding.limit) else none)

structure Unit (rows : Array StoredRow) where
  indices : List (Fin rows.size)
  ranges : List (Nat × Nat)

def Unit.rows {sourceRows : Array StoredRow} (unit : Unit sourceRows) : Array StoredRow :=
  unit.indices.toArray.map fun index => sourceRows[index]

theorem Unit.original {sourceRows : Array StoredRow} (unit : Unit sourceRows) (row : StoredRow)
    (present : row ∈ unit.rows) : row ∈ sourceRows := by
  change row ∈ unit.indices.toArray.map (fun index => sourceRows[index]) at present
  obtain ⟨index,_,same⟩ := Array.mem_map.mp present
  rw [← same]
  exact Array.getElem_mem index.isLt

/-- Published record boundaries are complete. Query groups can combine them;
they cannot erase unhinted records or require reparsing original code. -/
def base (owner : String) (rows : Array StoredRow) (layout : Recipe.Checked rows) : Array (Unit rows) := Id.run do
  let mut seen : Std.HashSet (List (Nat × Nat)) := {}
  let mut units := #[]
  for indices in layout.catalogue do
    if indices.isEmpty then continue
    let ranges := bindings owner ((indices.map fun index => rows[index]).toArray)
    if seen.contains ranges then continue
    seen := seen.insert ranges
    units := units.push ⟨indices,ranges⟩
  return units

structure Ready (owner : String) (rows : Array StoredRow) (layout : Recipe.Checked rows) where
  units : Array (Unit rows)
  exact : units = base owner rows layout

def prepare (owner : String) (rows : Array StoredRow) (layout : Recipe.Checked rows) : Ready owner rows layout :=
  ⟨base owner rows layout,rfl⟩

def combine (owner : String) (rows : Array StoredRow) (layout : Recipe.Checked rows)
    (prepared : Ready owner rows layout) (groups : List (List (Nat × Nat))) : Array (Unit rows) := Id.run do
  let mut units := prepared.units
  let mut seen := Std.HashSet.ofArray (prepared.units.map (·.ranges))
  for spans in groups do
    let requested := (List.finRange rows.size).filter fun index =>
      rows[index].origins.any fun origin => origin.binding.owner == owner && spans.any fun (first,limit) =>
        first < origin.binding.limit && origin.binding.first < limit
    let indices := CanonicalSource.Records.closeIndices layout.records requested
    if indices.isEmpty then continue
    let ranges := bindings owner ((indices.map fun index => rows[index]).toArray)
    if seen.contains ranges then continue
    seen := seen.insert ranges
    units := units.push ⟨indices,ranges⟩
  return units

end Eggshell.Synapses.PreparedFileUnits
