import Eggshell.Handoff
namespace Eggshell.Plugin

/-- Every successful result and every rejected input has the same denotation
as the former Option boundary. Error detail cannot create a fitting packet. -/
theorem PendingRendering.materializeReport_exact (pending : PendingRendering)
    (choice : SharedRangeAdapter.ServiceChoice) (generic : Array SharedRangeAdapter.UnitPlan)
    (rows : Array Synapses.CanonicalSource.StoredRow) :
    (pending.materializeReport choice generic rows).toOption = pending.materialize? choice generic rows := by
  cases decoded : SharedRangeAdapter.materialize generic choice.generic.toList rows with
  | none =>
    simp [PendingRendering.materializeReport,PendingRendering.materialize?,decoded]
    rfl
  | some slices =>
    by_cases chars : (pending.cost (pending.mandatory ++ slices)).1 ≤ pending.ceiling.1
    <;> by_cases bytes : (pending.cost (pending.mandatory ++ slices)).2 ≤ pending.ceiling.2
    <;> simp [PendingRendering.materializeReport,PendingRendering.materialize?,decoded,chars,bytes]
    <;> rfl

#print axioms PendingRendering.materializeReport_exact
end Eggshell.Plugin
