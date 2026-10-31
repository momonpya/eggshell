module
public import tools.research.ReferenceRequirements
@[expose] public section

namespace Eggshell.Research.PreparedSourceCosts
open Lean Eggshell.Synapses Eggshell.Synapses.CanonicalSource

/-- A source domain has one row order and one cost coordinate system.
The prefix is the query's owner frames. Source text and file frames are
rendered once here; consumers retain the resulting coordinates and costs.
This is recommendation data and grants no Match or completion authority. -/
structure Data where
  rows : Array StoredRow
  costs : Array (Nat × Nat)
  fileIds : Std.HashMap File Nat
  rowIds : Std.HashMap Key Nat
  payloads : Array Nat

def buildTables (rows : Array StoredRow) (prefixCosts : Array (Nat × Nat)) :
    Array (Nat × Nat) × Std.HashMap File Nat × Std.HashMap Key Nat × Array Nat := Id.run do
  let mut costs := prefixCosts
  let mut fileIds : Std.HashMap File Nat := {}
  let mut rowIds : Std.HashMap Key Nat := {}
  let mut payloads := #[]
  for row in rows do
    unless fileIds.contains row.key.file do
      let frame := Packet.fileFrame row.key.file (rows.filter (·.key.file == row.key.file))
      let text := frame.leading ++ frame.trailing
      fileIds := fileIds.insert row.key.file costs.size
      costs := costs.push (text.length,text.utf8ByteSize)
    let text := Packet.rowText row
    rowIds := rowIds.insert row.key costs.size
    payloads := payloads.push costs.size
    costs := costs.push (text.length,text.utf8ByteSize)
  return (costs,fileIds,rowIds,payloads)

def build (rows : Array StoredRow) (prefixCosts : Array (Nat × Nat)) : Data :=
  let (costs,fileIds,rowIds,payloads) := buildTables rows prefixCosts
  ⟨rows,costs,fileIds,rowIds,payloads⟩

structure Ready (rows : Array StoredRow) (prefixCosts : Array (Nat × Nat)) where
  data : Data
  exact : data = build rows prefixCosts

def prepare (rows : Array StoredRow) (prefixCosts : Array (Nat × Nat)) : Ready rows prefixCosts :=
  ⟨build rows prefixCosts,rfl⟩

theorem Ready.original_rows (ready : Ready rows prefixCosts) : ready.data.rows = rows := by
  rw [ready.exact]
  simp [build]

/-- The cost domain may be extended by general output records. Binding only
checks ordinal/cost correspondence; it never renders source text again. -/
structure Bound (p : SharedCoverage.Problem) where
  sourceRows : Array (StoredRow × Fin p.costs.size)
  frames : Std.HashMap File (Fin p.costs.size)

def bind (data : Data) (p : SharedCoverage.Problem) : Option (Bound p) := do
  unless data.rows.size == data.payloads.size do none
  let checked := fun index => do
    let expected ← data.costs[index]?
    unless p.costs[index]? == some expected do none
    if bound : index < p.costs.size then some (⟨index,bound⟩ : Fin p.costs.size) else none
  let sourceRows ← data.rows.zip data.payloads |>.mapM fun (row,index) => do
    return (row,← checked index)
  let mut frames := {}
  for (file,index) in data.fileIds.toArray do
    frames := frames.insert file (← checked index)
  return ⟨sourceRows,frames⟩

def Bound.requirements (bound : Bound p) : ReferenceRequirements.Prepared p :=
  ⟨bound.sourceRows,{},0,0⟩

theorem Bound.no_inferred_dependencies (bound : Bound p) : bound.requirements.dependencies = {} := rfl

end Eggshell.Research.PreparedSourceCosts
