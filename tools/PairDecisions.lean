module

public import tools.ExactLazyMemo

@[expose] public section
namespace Eggshell

def pairDecisionValue (predicate : Nat → Nat → Prop) [DecidableRel predicate]
    (width key : Nat) : Bool := decide (predicate (key / width) (key % width))

/-- The two coordinates belong to this predicate, width and lazy tree.
The canonical witness also preserves equality of enclosing source layouts. -/
structure PairDecisions (predicate : Nat → Nat → Prop) [DecidableRel predicate]
    (width depth : Nat) where
  tree : ExactLazyMemo.Tree (pairDecisionValue predicate width) 0 depth
  canonical : tree = ExactLazyMemo.make (pairDecisionValue predicate width) 0 depth

@[noinline] def PairDecisions.make (predicate : Nat → Nat → Prop) [DecidableRel predicate]
    (width depth : Nat) : PairDecisions predicate width depth :=
  ⟨ExactLazyMemo.make (pairDecisionValue predicate width) 0 depth, rfl⟩

theorem PairDecisions.is_canonical [DecidableRel predicate] (memo : PairDecisions predicate width depth) :
    memo = make predicate width depth := by
  cases memo with
  | mk tree canonical => subst tree; rfl

theorem PairDecisions.read_eq [DecidableRel predicate]
    (memo : PairDecisions predicate width depth) (first second : Nat) (bounded : second < width) :
    ExactLazyMemo.read (pairDecisionValue predicate width) memo.tree (second + width * first) =
      decide (predicate first second) := by
  rw [ExactLazyMemo.read_exact]
  have positive : 0 < width := Nat.lt_of_le_of_lt (Nat.zero_le second) bounded
  unfold pairDecisionValue
  rw [Nat.add_mul_div_left second first positive, Nat.div_eq_of_lt bounded, Nat.zero_add,
    Nat.add_mul_mod_self_left, Nat.mod_eq_of_lt bounded]

/-- Positions outside the stride retain the original decision rather than
aliasing another coordinate. Stored decisions certify the actual proposition. -/
def PairDecisions.decision [DecidableRel predicate]
    (memo : PairDecisions predicate width depth) (first second : Nat) : Decidable (predicate first second) :=
  if bounded : second < width then
    if accepted : ExactLazyMemo.read (pairDecisionValue predicate width) memo.tree
        (second + width * first) = true then
      isTrue (of_decide_eq_true (by rwa [memo.read_eq first second bounded] at accepted))
    else
      isFalse (of_decide_eq_false (by
        have rejected : ExactLazyMemo.read (pairDecisionValue predicate width) memo.tree
            (second + width * first) = false := Bool.eq_false_iff.mpr accepted
        rwa [memo.read_eq first second bounded] at rejected))
  else inferInstance

theorem PairDecisions.decision_eq [DecidableRel predicate]
    (memo : PairDecisions predicate width depth) (first second : Nat) :
    memo.decision first second = (inferInstance : Decidable (predicate first second)) :=
  Subsingleton.elim _ _

def PairDecisions.branch [DecidableRel predicate]
    (memo : PairDecisions predicate width depth) (first second : Nat)
    (yes : predicate first second → α) (no : ¬predicate first second → α) : α :=
  @dite α _ (memo.decision first second) yes no

theorem PairDecisions.branch_exact [DecidableRel predicate]
    (memo : PairDecisions predicate width depth) (first second : Nat)
    (yes : predicate first second → α) (no : ¬predicate first second → α) :
    memo.branch first second yes no = dite (predicate first second) yes no := by
  unfold branch
  rw [decision_eq]

theorem PairDecisions.branch_function_eq [DecidableRel predicate]
    (memo : PairDecisions predicate width depth) :
    @PairDecisions.branch predicate width depth α _ memo =
      fun first second yes no => dite (predicate first second) yes no := by
  funext first second yes no
  exact branch_exact memo first second yes no

end Eggshell
