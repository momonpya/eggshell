import Eggshell.SynapseBundles
open Lean Eggshell Eggshell.Synapses

theorem prepared_bindings_exact (plan : Transport.Plan) (source : Range) :
    ((KeyPostings.prepare Routed.Located.source (plan.owners.flatMap (·.located))).lookup source).map (·.row.binding) =
      plan.owners.flatMap (fun owner => owner.located.filterMap fun located =>
        if located.source == source then some located.row.binding else none) := by
  rw [KeyPostings.Index.lookup_exact,Array.map_filterMap,Array.filterMap_flatMap]
  have transform (located : Routed.Located) :
      (if located.source == source then some located else none).map (·.row.binding) =
        (if located.source == source then some located.row.binding else none) := by
    split <;> rfl
  simp only [transform]

#print axioms prepared_bindings_exact
#print axioms Eggshell.KeyPostings.directory_exact
#print axioms Eggshell.HashDistinct.reference
