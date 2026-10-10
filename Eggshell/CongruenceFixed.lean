module

public import Eggshell.QuotientAuthority

@[expose] public section
namespace Eggshell.QuotientBuilder.CongruenceFixed
open Partition

/-- Removing a present class only moves that class to the front. -/
theorem take_perm (partition : RawPartition) (value : Value)
    (present : value ∈ partition.flatten) :
    partition.Perm (lookup partition value :: (takeClass value partition).2) := by
  induction partition with
  | nil => simp at present
  | cons head tail ih =>
    by_cases here : value ∈ head
    · simp [lookup, takeClass, here]
    · have there : value ∈ tail.flatten := by simpa [List.flatten_cons, here] using present
      simpa [lookup, takeClass, here] using
        (List.Perm.cons head (ih there)).trans (List.Perm.swap _ _ _)

theorem merge_progress {partition : RawPartition} (valid : Valid partition)
    (left right : Value) (leftIn : left ∈ partition.flatten) (rightIn : right ∈ partition.flatten) :
    Valid (merge partition left right) ∧
      (∀ value, value ∈ (merge partition left right).flatten ↔ value ∈ partition.flatten) ∧
      (merge partition left right).length ≤ partition.length ∧
      ((merge partition left right).length = partition.length → merge partition left right = partition) := by
  refine ⟨merge_valid valid left right, ?_⟩
  cases matched : same partition left right with
  | true => simp [merge, matched]
  | false =>
    have outside : right ∉ lookup partition left := by
      rw [same_lookup valid] at matched
      simpa using matched
    have first := take_perm partition left leftIn
    have rightRemaining : right ∈ (takeClass left partition).2.flatten := by
      have member := first.flatten.mem_iff.mp rightIn
      simpa [List.flatten_cons, outside] using member
    have second := take_perm (takeClass left partition).2 right rightRemaining
    have ordered := first.trans (List.Perm.cons _ second)
    rw [merge_eq valid left right matched]
    refine ⟨?_, ?_, ?_⟩
    · intro value
      simpa [List.flatten_cons, List.append_assoc] using (ordered.flatten.mem_iff (a := value)).symm
    · have count := ordered.length_eq
      simp only [List.length_cons] at count ⊢
      omega
    · have count := ordered.length_eq
      simp only [List.length_cons] at count ⊢
      omega

def SeenInside (partition : RawPartition) (seen : Representatives) : Prop :=
  ∀ (key value : Value), seen[key]? = some value → value ∈ partition.flatten

theorem seen_insert (partition : RawPartition) (seen : Representatives)
    (inside : SeenInside partition seen) (key value : Value) (present : value ∈ partition.flatten) :
    SeenInside partition (seen.insert key value) := by
  intro query found stored
  rw [Std.HashMap.getElem?_insert] at stored
  split at stored
  · have equal := Option.some.inj stored
    simpa [← equal] using present
  · exact inside query found stored

theorem step_progress (index : Representatives) (state : Representatives × RawPartition)
    (valid : Valid state.2) (inside : SeenInside state.2 state.1)
    (value : Value) (present : value ∈ state.2.flatten) :
    Valid (applicationStep index state value).2 ∧
      SeenInside (applicationStep index state value).2 (applicationStep index state value).1 ∧
      (∀ query, query ∈ (applicationStep index state value).2.flatten ↔ query ∈ state.2.flatten) ∧
      (applicationStep index state value).2.length ≤ state.2.length ∧
      ((applicationStep index state value).2.length = state.2.length →
        (applicationStep index state value).2 = state.2) := by
  rcases state with ⟨seen, partition⟩
  cases value with
  | atom bytes => exact ⟨valid, inside, fun _ => Iff.rfl, Nat.le_refl _, fun _ => rfl⟩
  | apply operator arguments =>
    cases found : seen[signature index (.apply operator arguments)]? with
    | none =>
      simpa only [applicationStep, congruenceStep, found] using
        (show Valid partition ∧
          SeenInside partition (seen.insert (signature index (.apply operator arguments)) (.apply operator arguments)) ∧
          (∀ query, query ∈ partition.flatten ↔ query ∈ partition.flatten) ∧
          partition.length ≤ partition.length ∧ (partition.length = partition.length → partition = partition) from
          ⟨valid, seen_insert partition seen inside _ _ present,
            fun _ => Iff.rfl, Nat.le_refl _, fun _ => rfl⟩)
    | some prior =>
      have next := merge_progress valid prior _ (inside _ _ found) present
      simpa only [applicationStep, congruenceStep, found] using
        (show Valid (merge partition prior (.apply operator arguments)) ∧
          SeenInside (merge partition prior (.apply operator arguments)) seen ∧
          (∀ query, query ∈ (merge partition prior (.apply operator arguments)).flatten ↔ query ∈ partition.flatten) ∧
          (merge partition prior (.apply operator arguments)).length ≤ partition.length ∧
          ((merge partition prior (.apply operator arguments)).length = partition.length →
            merge partition prior (.apply operator arguments) = partition) from
          ⟨next.1, fun key value stored => (next.2.1 value).mpr (inside key value stored), next.2⟩)

theorem fold_progress (index : Representatives) (values : List Value)
    (state : Representatives × RawPartition) (valid : Valid state.2)
    (inside : SeenInside state.2 state.1) (covered : values ⊆ state.2.flatten) :
    Valid (values.foldl (applicationStep index) state).2 ∧
      (∀ value, value ∈ (values.foldl (applicationStep index) state).2.flatten ↔ value ∈ state.2.flatten) ∧
      (values.foldl (applicationStep index) state).2.length ≤ state.2.length ∧
      ((values.foldl (applicationStep index) state).2.length = state.2.length →
        (values.foldl (applicationStep index) state).2 = state.2) := by
  induction values generalizing state with
  | nil => exact ⟨valid, fun _ => Iff.rfl, Nat.le_refl _, fun _ => rfl⟩
  | cons value rest ih =>
    have next := step_progress index state valid inside value (covered (by simp))
    have later := ih _ next.1 next.2.1 (fun v member =>
      (next.2.2.1 v).mpr (covered (by simp [member])))
    simp only [List.foldl_cons]
    refine ⟨later.1, fun v => (later.2.1 v).trans (next.2.2.1 v),
      Nat.le_trans later.2.2.1 next.2.2.2.1, ?_⟩
    intro count
    have firstCount : (applicationStep index state value).2.length = state.2.length := by omega
    have lastCount : (rest.foldl (applicationStep index) (applicationStep index state value)).2.length =
        (applicationStep index state value).2.length := by omega
    exact (later.2.2.2 lastCount).trans (next.2.2.2.2 firstCount)

/-- A changed pass strictly removes a class. Reordering or a cached script
cannot consume fuel without semantic progress. All values are already in the
closed input domain, so the pass cannot introduce a new class. -/
theorem pass_progress (values : List Value) (partition : RawPartition)
    (valid : Valid partition) (covered : values ⊆ partition.flatten) :
    Valid (congruencePass values partition) ∧
      (∀ value, value ∈ (congruencePass values partition).flatten ↔ value ∈ partition.flatten) ∧
      (congruencePass values partition).length ≤ partition.length ∧
      ((congruencePass values partition).length = partition.length →
        congruencePass values partition = partition) :=
  fold_progress (representatives partition) values ({}, partition) valid
    (by simp [SeenInside]) covered

/-- The actual interpreter reaches a fixed point within the number of
remaining classes, independently of payload sizes, mixed/cyclic unions or
the contents of an old join plan. This is a step bound, not a wall-clock SLO. -/
theorem saturation_fixed (values : List Value) (fuel : Nat) (partition : RawPartition)
    (valid : Valid partition) (covered : values ⊆ partition.flatten)
    (enough : partition.length ≤ fuel) :
    congruencePass values (saturateCongruence values fuel partition) =
      saturateCongruence values fuel partition := by
  induction fuel generalizing partition with
  | zero =>
    have empty : partition = [] := List.eq_nil_of_length_eq_zero (by omega)
    subst partition
    have noValues : values = [] := List.eq_nil_iff_forall_not_mem.mpr (by
      intro value member
      have impossible := covered member
      simp at impossible)
    subst values
    rfl
  | succ fuel ih =>
    simp only [saturateCongruence_step]
    by_cases changed : congruencePass values partition = partition
    · simp only [changed, ↓reduceIte]
    · simp only [changed, ↓reduceIte]
      have next := pass_progress values partition valid covered
      have strict : (congruencePass values partition).length < partition.length := by
        have unequal : (congruencePass values partition).length ≠ partition.length :=
          fun count => changed (next.2.2.2 count)
        omega
      exact ih _ next.1 (fun value present => (next.2.1 value).mpr (covered present)) (by omega)

theorem initial_flatten (values : List Value) : (initial values).flatten = hashDistinct values := by
  have singletons (items : List Value) : (items.map (fun value => [value])).flatten = items := by
    induction items <;> simp_all
  exact singletons _

theorem explicit_progress (partition : RawPartition) (valid : Valid partition) (edges : List UnionEdge)
    (endpoints : ∀ edge ∈ edges, edge.left ∈ partition.flatten ∧ edge.right ∈ partition.flatten) :
    Valid (mergeExplicit partition edges) ∧
      (∀ value, value ∈ (mergeExplicit partition edges).flatten ↔ value ∈ partition.flatten) ∧
      (mergeExplicit partition edges).length ≤ partition.length := by
  induction edges generalizing partition with
  | nil => exact ⟨valid, fun _ => Iff.rfl, Nat.le_refl _⟩
  | cons edge rest ih =>
    have present := endpoints edge (by simp)
    have next := merge_progress valid edge.left edge.right present.1 present.2
    have later := ih _ next.1 (fun other member =>
      let before := endpoints other (by simp [member])
      ⟨(next.2.1 other.left).mpr before.1, (next.2.1 other.right).mpr before.2⟩)
    exact ⟨later.1, fun value => (later.2.1 value).trans (next.2.1 value),
      Nat.le_trans later.2.2 next.2.2.1⟩

theorem semantic_self (value : Value) : value ∈ value.semanticNodes := by
  cases value <;> simp [Value.semanticNodes]

theorem kernel_endpoints (roots : List Value) (edges : List UnionEdge) :
    ∀ edge ∈ edges, edge.left ∈ kernelValues roots edges ∧ edge.right ∈ kernelValues roots edges := by
  intro edge present
  have containsEndpoint (value : Value) (endpoint : value = edge.left ∨ value = edge.right) :
      value ∈ kernelValues roots edges := by
    apply (HashDistinct.mem _ _).mpr
    apply List.mem_flatMap.mpr
    refine ⟨value, List.mem_append_right _ (List.mem_flatMap.mpr ⟨edge, present, ?_⟩), semantic_self value⟩
    rcases endpoint with left | right
    · exact List.mem_append_left _ (left ▸ semantic_self edge.left)
    · exact List.mem_append_right _ (right ▸ semantic_self edge.right)
  exact ⟨containsEndpoint edge.left (Or.inl rfl), containsEndpoint edge.right (Or.inr rfl)⟩

/-- The production builder's chosen fuel is sufficient, not a heuristic
iteration cap. No old result or assumed completed-output equality is used. -/
theorem kernel_fixed (roots : List Value) (edges : List UnionEdge) :
    congruencePass (kernelValues roots edges) (kernelPartition roots edges) = kernelPartition roots edges := by
  let values := kernelValues roots edges
  have domain (value : Value) : value ∈ (initial values).flatten ↔ value ∈ values := by
    rw [initial_flatten, HashDistinct.mem]
  have prepared := explicit_progress (initial values) (initial_valid values) edges (fun edge member =>
    let endpoints := kernel_endpoints roots edges edge member
    ⟨(domain edge.left).mpr endpoints.1, (domain edge.right).mpr endpoints.2⟩)
  apply saturation_fixed values values.length _ prepared.1
  · exact fun value present => (prepared.2.1 value).mpr ((domain value).mpr present)
  · have count : (initial values).length ≤ values.length := by
      simpa only [initial, List.length_map] using HashDistinct.length_le values
    exact Nat.le_trans prepared.2.2 count

end Eggshell.QuotientBuilder.CongruenceFixed
