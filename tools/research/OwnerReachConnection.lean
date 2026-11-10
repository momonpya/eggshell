module
public import Eggshell.Handoff
public import tools.research.BucketView
@[expose] public section
namespace Eggshell.Plugin.SharedRangeAdapter.ReachBuilder
open Eggshell.Research

abbrev Rows (units : Array UnitShape) := Std.HashMap String (Array (RangeReach.Entry (Fin units.size)))

def collectWith (keys : Array String) (units : Array UnitShape)
    (update : Rows units → String × RangeReach.Entry (Fin units.size) → Rows units) : Rows units := Id.run do
  let mut rows := {}
  for index in List.finRange units.size do
    let some owner := keys[units[index].family]? | continue
    for (first,limit) in units[index].ranges do
      rows := update rows (owner,⟨first,limit,index⟩)
  return rows

theorem original_is_finished (keys : Array String) (units : Array UnitShape) :
    ownerReach keys units = BucketView.finish (collectWith keys units OwnedBuckets.appendSlow) RangeReach.prepare := by
  rfl

def step (keys : Array String) (units : Array UnitShape)
    (update : Rows units → String × RangeReach.Entry (Fin units.size) → Rows units)
    (state : Rows units) (index : Fin units.size) : Rows units :=
  match keys[units[index].family]? with
  | none => state
  | some owner => units[index].ranges.foldl
      (fun state span => update state (owner,⟨span.1,span.2,index⟩)) state

theorem collect_is_fold (keys : Array String) (units : Array UnitShape)
    (update : Rows units → String × RangeReach.Entry (Fin units.size) → Rows units) :
    collectWith keys units update = (List.finRange units.size).foldl (step keys units update) {} := by
  have wrapped (index : Fin units.size) (state : Rows units) :
      (match keys[units[index].family]? with
      | some owner => pure (ForInStep.yield (units[index].ranges.foldl
          (fun rows span => update rows (owner,⟨span.1,span.2,index⟩)) state))
      | _ => pure (ForInStep.yield state) : Id (ForInStep (Rows units))) =
        pure (ForInStep.yield (step keys units update state index)) := by
    cases captured : keys[units[index].family]? <;> simp only [step,captured]
  simp only [collectWith,List.forIn_pure_yield_eq_foldl,pure_bind,bind_pure]
  calc
    _ = (forIn (List.finRange units.size) ({} : Rows units)
        (fun index state => pure (ForInStep.yield (step keys units update state index))) : Id (Rows units)).run :=
      congrArg (fun body => (forIn (List.finRange units.size) ({} : Rows units) body : Id (Rows units)).run)
        (funext fun index => funext fun state => wrapped index state)
    _ = _ := List.forIn_pure_yield_eq_foldl _ _

theorem step_observes (keys : Array String) (units : Array UnitShape)
    (left right : Rows units) (same : ∀ key : String, left[key]? = right[key]?) (index : Fin units.size) :
    ∀ key : String, (step keys units OwnedBuckets.appendFast left index)[key]? =
      (step keys units OwnedBuckets.appendSlow right index)[key]? := by
  cases captured : keys[units[index].family]? with
  | none => simpa only [step,captured] using same
  | some owner =>
    have result := OwnedBuckets.fold_observes
      (units[index].ranges.map fun span => (owner,({ first := span.1, limit := span.2, value := index } : RangeReach.Entry (Fin units.size))))
      left right same
    simpa only [OwnedBuckets.exclusive,OwnedBuckets.reference,List.foldl_map,step,captured] using result

theorem collect_observes (keys : Array String) (units : Array UnitShape) :
    ∀ key : String, (collectWith keys units OwnedBuckets.appendFast)[key]? =
      (collectWith keys units OwnedBuckets.appendSlow)[key]? := by
  have loop (indices : List (Fin units.size)) (left right : Rows units)
      (same : ∀ key : String, left[key]? = right[key]?) :
      ∀ key : String, (indices.foldl (step keys units OwnedBuckets.appendFast) left)[key]? =
        (indices.foldl (step keys units OwnedBuckets.appendSlow) right)[key]? := by
    induction indices generalizing left right with
    | nil => exact same
    | cons index rest ih => exact ih _ _ (step_observes keys units left right same index)
  simpa only [collect_is_fold] using loop (List.finRange units.size) {} {} (fun _ => rfl)

def referenceLookup (keys : Array String) (units : Array UnitShape) :
    String → Option (RangeReach.Prepared (Fin units.size)) :=
  let ready := ownerReach keys units
  fun key => ready[key]?

def exclusiveLookup (keys : Array String) (units : Array UnitShape) :
    String → Option (RangeReach.Prepared (Fin units.size)) :=
  let ready := (collectWith keys units OwnedBuckets.appendFast).map (fun _ rows => RangeReach.prepare rows)
  fun key => ready[key]?

theorem lookup_exact : @referenceLookup = @exclusiveLookup := by
  funext keys units probe
  simp only [referenceLookup,exclusiveLookup,original_is_finished,BucketView.finish_lookup,Std.HashMap.getElem?_map]
  exact congrArg (Option.map RangeReach.prepare) (collect_observes keys units probe).symm

def fromLookup (keys : Array String) (units : Array UnitShape)
    (lookup : String → Option (RangeReach.Prepared (Fin units.size)))
    (member : Synapses.AdvisoryBundles.Member) : List (List (Fin units.size)) :=
  member.choices.toList.filterMap fun bound => do
    let index ← lookup bound.owner
    let parts ← bound.spans.mapM fun (first,last) => index.cover? first last
    let parts := parts.flatten.eraseDups
    if memberCovered keys units parts member then some parts else none

structure Index (units : Array UnitShape) where
  atOwner : String → Option (RangeReach.Prepared (Fin units.size))

/-- Returning data keeps index construction outside the later member loop.
A function result alone can be eta-expanded into each individual lookup. -/
def referenceIndex (keys : Array String) (units : Array UnitShape) : Index units :=
  let ready := ownerReach keys units
  ⟨fun key => ready[key]?⟩

def exclusiveIndex (keys : Array String) (units : Array UnitShape) : Index units :=
  let ready := (collectWith keys units OwnedBuckets.appendFast).map (fun _ rows => RangeReach.prepare rows)
  ⟨fun key => ready[key]?⟩

theorem index_exact : @referenceIndex = @exclusiveIndex := by
  funext keys units
  change Index.mk (referenceLookup keys units) = Index.mk (exclusiveLookup keys units)
  rw [lookup_exact]

def fromIndex (keys : Array String) (units : Array UnitShape) (index : Index units)
    (member : Synapses.AdvisoryBundles.Member) : List (List (Fin units.size)) :=
  fromLookup keys units index.atOwner member

theorem reference_member_exact (keys : Array String) (units : Array UnitShape)
    (member : Synapses.AdvisoryBundles.Member) :
    fromIndex keys units (referenceIndex keys units) member = memberChoices keys units (ownerReach keys units) member := by
  rfl

#print axioms original_is_finished
#print axioms collect_observes
#print axioms lookup_exact
#print axioms index_exact
#print axioms reference_member_exact
end Eggshell.Plugin.SharedRangeAdapter.ReachBuilder
