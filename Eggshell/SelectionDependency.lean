module

public import Eggshell.EqualityDependency

@[expose] public section

namespace Eggshell.SelectionDependency

inductive Role where
  | decomposition
  | deduplicatedChild
  | completedOutcome
  | advisoryOutcome
  deriving BEq, DecidableEq, Repr

structure Comparison where
  role : Role
  left : Value
  right : Value

def Comparison.holds (equality : Equality) (comparison : Comparison) : Bool :=
  equality.same comparison.left comparison.right

/-- Replay only the selected All's quotient deduplication. The first retained
witness is the one tested by the production `any` predicate. -/
def dedupFrom (equality : Equality) (kept : List Value) :
    List Value → List Value × List Comparison
  | [] => (kept, [])
  | value :: tail =>
      match kept.find? (equality.same value) with
      | none => dedupFrom equality (value :: kept) tail
      | some prior =>
          let next := dedupFrom equality kept tail
          (next.1, ⟨.deduplicatedChild, value, prior⟩ :: next.2)

theorem dedupFrom_output (equality : Equality) (values kept : List Value) :
    (dedupFrom equality kept values).1 =
      values.foldl (fun current value =>
        if current.any (equality.same value) then current else value :: current) kept := by
  induction values generalizing kept with
  | nil => rfl
  | cons value tail ih =>
    have predicate := List.isSome_find? (xs := kept) (f := equality.same value)
    cases found : kept.find? (equality.same value) with
    | none =>
      have absent : kept.any (equality.same value) = false := by simpa [found] using predicate.symm
      simp only [dedupFrom, found, List.foldl_cons, absent, Bool.false_eq_true, ↓reduceIte]
      exact ih _
    | some prior =>
      have present : kept.any (equality.same value) = true := by simpa [found] using predicate.symm
      simp only [dedupFrom, found, List.foldl_cons, present, ↓reduceIte]
      exact ih _

theorem dedupFrom_positive (equality : Equality) (values kept : List Value)
    (comparison : Comparison) (member : comparison ∈ (dedupFrom equality kept values).2) :
    comparison.holds equality = true := by
  induction values generalizing kept with
  | nil => simp [dedupFrom] at member
  | cons value tail ih =>
    cases found : kept.find? (equality.same value) with
    | none => exact ih _ (by simpa [dedupFrom, found] using member)
    | some prior =>
      simp only [dedupFrom, found, List.mem_cons] at member
      rcases member with same | later
      · subst comparison
        simpa only [Comparison.holds] using (List.find?_some found)
      · exact ih _ later

def dedup (equality : Equality) (values : List Value) : List Value × List Comparison :=
  let result := dedupFrom equality [] values
  (result.1.reverse, result.2)

theorem dedup_output (equality : Equality) (values : List Value) :
    (dedup equality values).1 = WorkGraph.distinct equality values := by
  simp only [dedup, dedupFrom_output, WorkGraph.distinct]

mutual

def structural (equality : Equality) (work : Value) : Selection → List Comparison
  | .residual _ _ | .outcomes _ _ _ => []
  | .handoff _ prior => structural equality work prior
  | .decomposed _ edge _ _ children =>
      let dropped := dedup equality edge.children
      ⟨.decomposition, edge.parent, work⟩ :: dropped.2 ++
        structuralChildren equality dropped.1 children

def structuralChildren (equality : Equality) : List Value → List Selection → List Comparison
  | work :: works, child :: children =>
      structural equality work child ++ structuralChildren equality works children
  | _, _ => []

end

mutual

theorem structural_positive (graph : WorkGraph) (equality : Equality) (work : Value)
    (selection : Selection) (valid : selection.structurallyValidAt graph equality work = true)
    (comparison : Comparison) (member : comparison ∈ structural equality work selection) :
    comparison.holds equality = true := by
  cases selection with
  | residual _ _ | outcomes _ _ _ => simp [structural] at member
  | handoff selected prior =>
      have next := (Bool.and_eq_true_iff.mp valid).2
      exact structural_positive graph equality work prior next comparison member
  | decomposed selected edge completed advisory children =>
      have parts := Bool.and_eq_true_iff.mp valid
      have before := Bool.and_eq_true_iff.mp parts.1
      simp only [structural, List.mem_cons, List.mem_append] at member
      rcases member with (same | dropped) | child
      · subst comparison
        exact before.2
      · exact dedupFrom_positive equality edge.children [] comparison dropped
      · apply structuralChildren_positive graph equality _ children _ comparison child
        simpa only [WorkGraph.childrenFor, dedup_output] using parts.2

theorem structuralChildren_positive (graph : WorkGraph) (equality : Equality)
    (works : List Value) (children : List Selection)
    (valid : Selection.structurallyValidChildren graph equality works children = true)
    (comparison : Comparison) (member : comparison ∈ structuralChildren equality works children) :
    comparison.holds equality = true := by
  cases works with
  | nil => simp [structuralChildren] at member
  | cons work works =>
      cases children with
      | nil => simp [structuralChildren] at member
      | cons child children =>
          have parts := Bool.and_eq_true_iff.mp valid
          simp only [structuralChildren, List.mem_append] at member
          rcases member with first | later
          · exact structural_positive graph equality work child parts.1 comparison first
          · exact structuralChildren_positive graph equality works children parts.2 comparison later

end

def outcomeComparisons (role : Role) (uses : List (Value × OutcomeEdge)) : List Comparison :=
  uses.map fun (work, edge) => ⟨role, edge.work, work⟩

def comparisons (equality : Equality) (work : Value) (selection : Selection) : List Comparison :=
  structural equality work selection ++
    outcomeComparisons .completedOutcome selection.completedUses ++
    outcomeComparisons .advisoryOutcome selection.advisoryUses

theorem comparisons_positive (graph : WorkGraph) (equality : Equality) (policy : OutcomePolicy)
    (work : Value) (selection : Selection) (valid : selection.validFor graph equality policy work = true)
    (comparison : Comparison) (member : comparison ∈ comparisons equality work selection) :
    comparison.holds equality = true := by
  have outer := Bool.and_eq_true_iff.mp valid
  have middle := Bool.and_eq_true_iff.mp outer.1
  have first := Bool.and_eq_true_iff.mp middle.1
  simp only [comparisons, List.mem_append] at member
  rcases member with (tree | completed) | advisory
  · exact structural_positive graph equality work selection first.1 comparison tree
  · obtain ⟨⟨demand, edge⟩, present, same⟩ := List.mem_map.mp completed
    subst comparison
    exact (Bool.and_eq_true_iff.mp ((Bool.and_eq_true_iff.mp
      ((List.all_eq_true.mp middle.2) _ present)).1)).2
  · obtain ⟨⟨demand, edge⟩, present, same⟩ := List.mem_map.mp advisory
    subst comparison
    exact (Bool.and_eq_true_iff.mp ((Bool.and_eq_true_iff.mp
      ((List.all_eq_true.mp outer.2) _ present)).1)).2

/-- A component of a delivery explanation. This validates the chosen
selection's equality premises; matcher admission, original child-role evidence
and causal ancestry of local generators are separate required components. -/
structure Report (graph : WorkGraph) (equality : Equality) (policy : OutcomePolicy)
    (work : Value) (selection : Selection) : Type where
  valid : selection.validFor graph equality policy work = true
  premises : List Comparison
  exact : premises = comparisons equality work selection
  positive : ∀ premise ∈ premises, premise.holds equality = true

def Report.ofValid {graph : WorkGraph} {equality : Equality} {policy : OutcomePolicy}
    {work : Value} {selection : Selection}
    (valid : selection.validFor graph equality policy work = true) :
    Report graph equality policy work selection :=
  ⟨valid, comparisons equality work selection, rfl,
    comparisons_positive graph equality policy work selection valid⟩

def report? (graph : WorkGraph) (equality : Equality) (policy : OutcomePolicy)
    (work : Value) (selection : Selection) : Option (Report graph equality policy work selection) :=
  if valid : selection.validFor graph equality policy work = true then
    some (Report.ofValid valid)
  else none

end Eggshell.SelectionDependency
