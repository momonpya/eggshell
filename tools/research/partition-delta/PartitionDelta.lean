module
public import Eggshell.WindowOwners

@[expose] public section
namespace Eggshell.PartitionDelta

structure Change where
  key : String
  removed : Nat
  added : Nat

/-- Refcounts belong to original window occurrences, not to a similarity score. -/
structure Transition (before : Nat) (change : Change) where
  after : Nat
  exact : after + change.removed = before + change.added
  retained : change.removed ≤ before

def checked (before : Nat) (change : Change) : Except String (Transition before change) := do
  if retained : change.removed ≤ before then
    return ⟨before-change.removed+change.added,by omega,retained⟩
  else throw "partition retraction exceeds saved original references"

theorem Transition.positive_iff (transition : Transition before change) :
    0 < transition.after ↔ change.removed < before+change.added := by
  have := transition.exact
  omega

theorem Transition.shared_reference_survives (transition : Transition before change)
    (shared : change.removed < before) : 0 < transition.after := by
  have := transition.exact
  omega

theorem Transition.last_reference_removed (transition : Transition before change)
    (last : change.removed = before) (noNew : change.added = 0) : transition.after = 0 := by
  have := transition.exact
  omega

def counts (keys : List String) : Std.HashMap String Nat :=
  keys.foldl (fun table key => table.insert key (table[key]?.getD 0+1)) {}

def changes (removed added : List String) : List Change :=
  let old := counts removed
  let current := counts added
  ((Eggshell.hashDistinct (old.toList.map Prod.fst ++ current.toList.map Prod.fst)).mergeSort (· ≤ ·)).map
    fun key => ⟨key,old[key]?.getD 0,current[key]?.getD 0⟩

end Eggshell.PartitionDelta
