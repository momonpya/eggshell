module
public import tools.research.ReferenceRequirements
@[expose] public section

/- Original payload coordinates and exact wire costs only. Heuristic call
resolution is a recommendation; it is not a required original dependency. -/
namespace Eggshell.Research.OriginalPayloadBasis
open Lean Eggshell.Synapses Eggshell.Synapses.CanonicalSource

def rows (familyCount : Nat) (originals : Array StoredRow) (p : SharedCoverage.Problem) :
    Option (Array (StoredRow × Fin p.costs.size)) := do
  let mut files : Std.HashSet File := {}
  let mut result := #[]
  let mut cursor := familyCount
  let checkedAtom (index : Nat) (text : String) : Option (Fin p.costs.size) := do
    unless p.costs[index]? == some (text.length,text.utf8ByteSize) do none
    if h : index < p.costs.size then some ⟨index,h⟩ else none
  for row in originals do
    unless files.contains row.key.file do
      let frame := Packet.fileFrame row.key.file (originals.filter (·.key.file == row.key.file))
      let _ ← checkedAtom cursor (frame.leading ++ frame.trailing)
      files := files.insert row.key.file
      cursor := cursor+1
    let payload ← checkedAtom cursor (Packet.rowText row)
    result := result.push (row,payload)
    cursor := cursor+1
  return result

def prepare (familyCount : Nat) (originals : Array StoredRow) (p : SharedCoverage.Problem) :
    Option (ReferenceRequirements.Prepared p) :=
  (rows familyCount originals p).map fun sourceRows => ⟨sourceRows,{},0,0⟩

theorem no_inferred_dependencies (familyCount : Nat) (originals : Array StoredRow)
    (prepared : ReferenceRequirements.Prepared p)
    (found : prepare familyCount originals p = some prepared) :
    prepared.dependencies = {} := by
  unfold prepare at found
  cases source : rows familyCount originals p with
  | none => simp [source] at found
  | some values =>
    simp only [source,Option.map_some,Option.some.injEq] at found
    subst prepared
    rfl
end Eggshell.Research.OriginalPayloadBasis
