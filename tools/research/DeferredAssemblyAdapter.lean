module
public import Eggshell.Handoff
public import tools.research.DeferredAssembly
@[expose] public section

namespace Eggshell.Plugin.SharedRangeAdapter

def contextAssemblyAlgebra : Research.DeferredAssembly.Algebra TransportSlice ContextDelivery where
  view := (·.context)
  replace := fun slice context => {slice with context := some context,keys := context.keys,text := context.render}
  replace_view := by intros; rfl
  replace_replace := by intros; rfl
  sameAtomic := fun prior next => prior.text == next.text
  merge := fun prior next => (checkedPricedContextAssembly prior next).map Subtype.val

theorem context_assembly_eager_exact (prior next : TransportSlice) :
    contextAssemblyAlgebra.eager prior next = join prior next := by
  cases left : prior.context with
  | none =>
    cases right : next.context <;>
      simp [Research.DeferredAssembly.Algebra.eager,contextAssemblyAlgebra,join,left,right] <;> rfl
  | some context =>
    cases right : next.context with
    | none => simp [Research.DeferredAssembly.Algebra.eager,contextAssemblyAlgebra,join,left,right]
    | some incoming =>
      cases merged : checkedPricedContextAssembly context incoming <;>
        simp [Research.DeferredAssembly.Algebra.eager,contextAssemblyAlgebra,join,left,right,merged]

def joinContextsDeferred (prior : TransportSlice) (following : List TransportSlice) : Option TransportSlice :=
  (Research.DeferredAssembly.fold contextAssemblyAlgebra (.ready prior) following).map
    (Research.DeferredAssembly.finish contextAssemblyAlgebra)

theorem join_contexts_deferred_exact (prior : TransportSlice) (following : List TransportSlice) :
    joinContextsDeferred prior following = following.foldlM (fun accumulated next => join accumulated next) prior := by
  unfold joinContextsDeferred
  rw [Research.DeferredAssembly.fold_exact]
  unfold Research.DeferredAssembly.reference
  have same : contextAssemblyAlgebra.eager = join := by
    funext left right
    exact context_assembly_eager_exact left right
  rw [same]
  rfl

abbrev PendingContexts := List (Nat × Research.DeferredAssembly.Pending TransportSlice ContextDelivery)
abbrev OriginalRows := Array Synapses.CanonicalSource.StoredRow

def projectContexts (state : PendingContexts × OriginalRows) : List (Nat × TransportSlice) × OriginalRows :=
  (Research.DeferredAssembly.finishRows contextAssemblyAlgebra state.1,state.2)

def advanceContexts (units : Array UnitPlan) (index : Nat)
    (state : PendingContexts × OriginalRows) : Option (ForInStep (PendingContexts × OriginalRows)) := do
  let unit ← units[index]?
  if let some shared := unit.slice.shared then
    return .yield (state.1,state.2 ++ shared.rows)
  let rows ← Research.DeferredAssembly.addRow contextAssemblyAlgebra state.1 unit.family unit.slice
  return .yield (rows,state.2)

def referenceContexts (units : Array UnitPlan) (index : Nat)
    (state : List (Nat × TransportSlice) × OriginalRows) :
    Option (ForInStep (List (Nat × TransportSlice) × OriginalRows)) := do
  let unit ← units[index]?
  if let some shared := unit.slice.shared then
    return .yield (state.1,state.2 ++ shared.rows)
  match state.1.find? (·.1 == unit.family) with
  | none => return .yield (state.1 ++ [(unit.family,unit.slice)],state.2)
  | some (_,prior) =>
    let merged ← join prior unit.slice
    return .yield (state.1.map (fun row => if row.1 == unit.family then (row.1,merged) else row),state.2)

def finishMaterialized (state : List (Nat × TransportSlice) × OriginalRows) : Option (List TransportSlice) := do
  let legacy := (state.1.mergeSort fun a b => a.1 ≤ b.1).map Prod.snd
  if state.2.isEmpty then return legacy
  let mergedRows ← (Synapses.CanonicalSource.Delivery.merge state.2).toOption
  let shared ← Synapses.CanonicalSource.Delivery.Part.check? mergedRows
  return legacy ++ [{owner := none,keys := shared.keys,text := shared.render,shared := some shared,members := [],visibleKeys := []}]

theorem materialize_reference_definition (units : Array UnitPlan) (indices : List Nat) (requiredRows : OriginalRows) :
    materialize units indices requiredRows = (do
      let state ← forIn indices ([],requiredRows) (referenceContexts units)
      finishMaterialized state) := by rfl

theorem advance_contexts_exact (units : Array UnitPlan) (index : Nat) (state : PendingContexts × OriginalRows) :
    (advanceContexts units index state).map (Research.DeferredAssembly.projectStep projectContexts) =
      referenceContexts units index (projectContexts state) := by
  cases present : units[index]? with
  | none => simp [advanceContexts,referenceContexts,present]
  | some unit =>
    cases shared : unit.slice.shared with
    | some part => simp [advanceContexts,referenceContexts,present,shared,Research.DeferredAssembly.projectStep,projectContexts]
    | none =>
      have packed : referenceContexts units index (projectContexts state) =
          (Research.DeferredAssembly.referenceRow contextAssemblyAlgebra
            (Research.DeferredAssembly.finishRows contextAssemblyAlgebra state.1) unit.family unit.slice).map
            (fun rows => ForInStep.yield (rows,state.2)) := by
        simp only [referenceContexts,projectContexts,Bind.bind,Option.bind,present,shared,
          Research.DeferredAssembly.referenceRow,context_assembly_eager_exact]
        cases found : (Research.DeferredAssembly.finishRows contextAssemblyAlgebra state.1).find?
            (fun row => row.1 == unit.family) with
        | none => rfl
        | some prior =>
          rcases prior with ⟨family,current⟩
          cases joined : join current unit.slice <;>
            simp only [joined,Option.map] <;> rfl
      rw [packed,← Research.DeferredAssembly.addRow_exact]
      cases updated : Research.DeferredAssembly.addRow contextAssemblyAlgebra state.1 unit.family unit.slice <;>
        simp [advanceContexts,present,shared,updated,projectContexts,Research.DeferredAssembly.projectStep]

def materializeDeferred (units : Array UnitPlan) (indices : List Nat)
    (requiredRows : OriginalRows := #[]) : Option (List TransportSlice) := do
  let state ← forIn indices ([],requiredRows) (advanceContexts units)
  finishMaterialized (projectContexts state)

theorem materialize_deferred_exact (units : Array UnitPlan) (indices : List Nat) (requiredRows : OriginalRows) :
    materializeDeferred units indices requiredRows = materialize units indices requiredRows := by
  rw [materialize_reference_definition]
  have loop := Research.DeferredAssembly.forIn_project projectContexts (advanceContexts units)
    (referenceContexts units) (advance_contexts_exact units) indices ([],requiredRows)
  simpa only [materializeDeferred,Bind.bind,Option.bind_map,Function.comp_def,projectContexts,
    Research.DeferredAssembly.finishRows,List.map_nil] using
    congrArg (fun value => value.bind finishMaterialized) loop

@[csimp] theorem materialize_eq_deferred : @materialize = @materializeDeferred := by
  funext units indices requiredRows
  exact (materialize_deferred_exact units indices requiredRows).symm

end Eggshell.Plugin.SharedRangeAdapter

#print axioms Eggshell.Plugin.SharedRangeAdapter.context_assembly_eager_exact
#print axioms Eggshell.Plugin.SharedRangeAdapter.join_contexts_deferred_exact
#print axioms Eggshell.Plugin.SharedRangeAdapter.materialize_reference_definition
#print axioms Eggshell.Plugin.SharedRangeAdapter.advance_contexts_exact
#print axioms Eggshell.Plugin.SharedRangeAdapter.materialize_deferred_exact
#print axioms Eggshell.Plugin.SharedRangeAdapter.materialize_eq_deferred
