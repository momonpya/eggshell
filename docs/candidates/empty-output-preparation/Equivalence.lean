import Eggshell.Handoff
open Lean Eggshell
namespace Eggshell.Synapses.Transport
def originalTarget (located : Routed.Located) : Bool :=
  match located.source.subject with
  | .original _ => true
  | _ => false
def LocatedOwner.originalRangesSparse (owner : LocatedOwner) : Array (Range × OutputRange) := Id.run do
  if !(owner.located.any originalTarget) then return #[]
  let raw := owner.document.source.getD ""
  let json := JsonScalars.prepare? raw
  return owner.located.filterMap fun located => do
    let .original _ := located.source.subject | none
    some (located.source,{
      priority := located.offer.priority
      first := located.row.binding.first
      limit := located.row.binding.limit
      path := (json.bind (·.cover? located.row.binding.first located.row.binding.limit)).map (·.path)})
theorem LocatedOwner.originalRanges_sparse_exact (owner : LocatedOwner) :
    owner.originalRangesSparse = owner.originalRanges := by
  cases available : owner.located.any originalTarget with
  | true => simp [LocatedOwner.originalRangesSparse,LocatedOwner.originalRanges,available] <;> rfl
  | false =>
    have empty : owner.originalRanges = #[] := by
      unfold LocatedOwner.originalRanges
      apply Array.filterMap_eq_empty_iff.mpr
      intro located present
      have absent := Array.any_eq_false'.mp available located present
      cases subject : located.source.subject with
      | file file => rfl
      | original identity => simp [originalTarget,subject] at absent
    simp [LocatedOwner.originalRangesSparse,available,empty]
@[csimp] theorem LocatedOwner.original_ranges_sparse_compiled :
    @LocatedOwner.originalRanges = @LocatedOwner.originalRangesSparse := by
  funext owner
  exact (LocatedOwner.originalRanges_sparse_exact owner).symm
end Eggshell.Synapses.Transport
namespace Eggshell.Plugin.SharedRangeAdapter
def prepareOutputsWithSparse {Output : Type}
    (emit : Nat → TransportSlice → ContextDelivery → List (Nat × Nat) → Output)
    (familyIndex : Nat) (family : Family) : List Output × List (Nat × Nat) := Id.run do
  if family.outputRanges.isEmpty then return ([],[])
  if !Matcher.nativeOutcome family.owner then return ([],[])
  let some source := Matcher.atomText? family.owner.outcome | return ([],[])
  let some envelope := family.template.context | return ([],[])
  let original := IndexedCharacters.make source
  let state ← forIn family.outputRanges ([],[]) (outputStepWith emit familyIndex family.template source envelope original)
  return state
theorem prepare_outputs_with_sparse_exact : @prepareOutputsWithSparse = @prepareOutputsWith := by
  funext Output emit familyIndex family
  cases ranges : family.outputRanges with
  | cons first rest => simp [prepareOutputsWithSparse,prepareOutputsWith,ranges] <;> rfl
  | nil =>
    simp only [prepareOutputsWithSparse,ranges,List.isEmpty_nil,↓reduceIte,Id.run_pure]
    unfold prepareOutputsWith
    split <;> try rfl
    split <;> try rfl
    split <;> simp [ranges]
@[csimp] theorem prepare_outputs_with_sparse_compiled :
    @prepareOutputsWith = @prepareOutputsWithSparse := prepare_outputs_with_sparse_exact.symm
end Eggshell.Plugin.SharedRangeAdapter
#print axioms Eggshell.Synapses.Transport.LocatedOwner.originalRanges_sparse_exact
#print axioms Eggshell.Plugin.SharedRangeAdapter.prepare_outputs_with_sparse_exact
