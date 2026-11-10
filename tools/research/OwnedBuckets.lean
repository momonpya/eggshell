module
public import Std.Data.HashMap.Lemmas
@[expose] public section
namespace Eggshell.Research.OwnedBuckets
universe u v

def appendSlow {κ : Type u} {ν : Type v} [BEq κ] [Hashable κ]
    (state : Std.HashMap κ (Array ν)) (entry : κ × ν) : Std.HashMap κ (Array ν) :=
  state.insert entry.1 ((state[entry.1]?.getD #[]).push entry.2)

def appendFast {κ : Type u} {ν : Type v} [BEq κ] [Hashable κ]
    (state : Std.HashMap κ (Array ν)) (entry : κ × ν) : Std.HashMap κ (Array ν) :=
  state.alter entry.1 (fun previous => some ((previous.getD #[]).push entry.2))

theorem append_observes {κ : Type u} {ν : Type v} [BEq κ] [Hashable κ]
    [LawfulBEq κ] [LawfulHashable κ]
    (left right : Std.HashMap κ (Array ν))
    (same : ∀ key : κ, left[key]? = right[key]?) (entry : κ × ν) (probe : κ) :
    (appendFast left entry)[probe]? = (appendSlow right entry)[probe]? := by
  simp only [appendFast,appendSlow,Std.HashMap.getElem?_alter,Std.HashMap.getElem?_insert]
  rw [same entry.1,same probe]

def reference {κ : Type u} {ν : Type v} [BEq κ] [Hashable κ]
    (rows : List (κ × ν)) (initial : Std.HashMap κ (Array ν) := {}) : Std.HashMap κ (Array ν) :=
  rows.foldl appendSlow initial

def exclusive {κ : Type u} {ν : Type v} [BEq κ] [Hashable κ]
    (rows : List (κ × ν)) (initial : Std.HashMap κ (Array ν) := {}) : Std.HashMap κ (Array ν) :=
  rows.foldl appendFast initial

theorem fold_observes {κ : Type u} {ν : Type v} [BEq κ] [Hashable κ]
    [LawfulBEq κ] [LawfulHashable κ] (rows : List (κ × ν))
    (left right : Std.HashMap κ (Array ν)) (same : ∀ key : κ, left[key]? = right[key]?) :
    ∀ key : κ, (exclusive rows left)[key]? = (reference rows right)[key]? := by
  induction rows generalizing left right with
  | nil => exact same
  | cons entry rest ih =>
    exact ih (appendFast left entry) (appendSlow right entry) (append_observes left right same entry)

/-- The observable result is the complete ordered bucket, including absent
keys and duplicates. No equality of internal hash-table layout is claimed. -/
def referenceLookup {κ : Type u} {ν : Type v} [BEq κ] [Hashable κ]
    [LawfulBEq κ] [LawfulHashable κ] (rows : List (κ × ν)) : κ → Option (Array ν) :=
  let ready := reference rows
  fun key => ready[key]?

def exclusiveLookup {κ : Type u} {ν : Type v} [BEq κ] [Hashable κ]
    [LawfulBEq κ] [LawfulHashable κ] (rows : List (κ × ν)) : κ → Option (Array ν) :=
  let ready := exclusive rows
  fun key => ready[key]?

theorem lookup_exact : @referenceLookup.{u,v} = @exclusiveLookup.{u,v} := by
  funext κ ν equality hashing lawful lawfulHash rows probe
  exact (fold_observes rows {} {} (fun _ => rfl) probe).symm

#print axioms append_observes
#print axioms fold_observes
#print axioms lookup_exact
end Eggshell.Research.OwnedBuckets
