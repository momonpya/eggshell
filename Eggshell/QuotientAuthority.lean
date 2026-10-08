module
public import Eggshell.PartitionIndex
@[expose] public section
namespace Eggshell.QuotientBuilder.Authority
open Partition

def Safe (partition : RawPartition) : Prop :=
  ∀ query, ∀ member ∈ lookup partition query, Value.SameExactFootprint member query

theorem empty_safe : Safe [] := by
  intro query member present
  have equal : member = query := by simpa [lookup, takeClass] using present
  subst member
  exact Value.sameExactFootprint_refl query

theorem initial_safe (values : List Value) : Safe (initial values) := by
  intro query member present
  rw [initial_equivalent_empty values query] at present
  exact empty_safe query member present

theorem merge_safe {partition : RawPartition} (valid : Valid partition) (safe : Safe partition)
    (left right : Value) (authority : Value.SameExactFootprint left right) :
    Safe (merge partition left right) := by
  intro query member present
  rw [merge_lookup valid] at present
  split at present
  · exact safe query member present
  · split at present
    · rename_i _ inside
      have querySafe : Value.SameExactFootprint query left := by
        rcases List.mem_append.mp inside with first | second
        · exact safe left query first
        · exact Value.sameExactFootprint_trans (safe right query second)
            (Value.sameExactFootprint_symm authority)
      apply Value.sameExactFootprint_trans _ (Value.sameExactFootprint_symm querySafe)
      rcases List.mem_append.mp present with first | second
      · exact safe left member first
      · exact Value.sameExactFootprint_trans (safe right member second)
          (Value.sameExactFootprint_symm authority)
    · exact safe query member present

theorem explicit_safe {partition : RawPartition} (valid : Valid partition) (safe : Safe partition)
    (edges : List UnionEdge) : Safe (mergeExplicit partition edges) := by
  induction edges generalizing partition with
  | nil => exact safe
  | cons edge rest ih =>
    exact ih (merge_valid valid edge.left edge.right)
      (merge_safe valid safe edge.left edge.right edge.exactAuthority)

theorem fold_members (members : List Value) (index : Representatives) (representative : Value) :
    members.foldl (fun current member => current.insert member representative) index =
      RepresentativeIndex.insertMembers representative index members := by
  induction members generalizing index with
  | nil => rfl
  | cons head tail ih => exact ih _

theorem raw_lookup (partition : RawPartition) (valid : Valid partition)
    (index : Representatives) (query : Value) :
    (partition.foldl (fun current members => match members with
      | [] => current
      | head :: _ => members.foldl (fun next member => next.insert member head) current) index).getD query query =
      if query ∈ partition.flatten then (lookup partition query).headD query else index.getD query query := by
  induction partition generalizing index with
  | nil => rfl
  | cons members tail ih =>
    obtain ⟨_, tailValid, nonempty, apart⟩ := valid_cons.mp valid
    cases members with
    | nil => exact False.elim (nonempty rfl)
    | cons head rest =>
      simp only [List.foldl_cons, ih tailValid, List.flatten_cons, List.mem_append, lookup_cons]
      by_cases inTail : query ∈ tail.flatten
      · have outside : query ∉ head :: rest := fun inside => apart query inside inTail
        simp only [inTail, outside, false_or, ↓reduceIte]
      · have joined := insertMembers_lookup index head query (head :: rest)
        rw [← fold_members] at joined
        simp only [List.foldl_cons] at joined
        rw [joined]
        by_cases inHead : query ∈ head :: rest
        · simp only [inTail, inHead, true_or, ↓reduceIte, List.headD_cons]
        · simp only [inTail, inHead, or_self, ↓reduceIte]

theorem representatives_safe {partition : RawPartition} (valid : Valid partition) (safe : Safe partition) :
    RepresentativeIndex.Sound (representatives partition) := by
  intro query
  have equation := raw_lookup partition valid ({} : Representatives) query
  change (representatives partition).getD query query = _ at equation
  rw [equation]
  split
  · apply Value.sameExactFootprint_symm
    apply safe query
    have present := lookup_contains partition query
    cases found : lookup partition query with
    | nil => simp [found] at present
    | cons head rest => simp
  · simpa using Value.sameExactFootprint_refl query

theorem normalize_authority (index : Representatives) (safe : RepresentativeIndex.Sound index)
    (arguments : Refs) (exact : Value) :
    exact ∈ Value.refsExactFootprint (normalizeRefs index arguments) ↔
      exact ∈ Value.refsExactFootprint arguments := by
  cases arguments with
  | nil => rfl
  | semantic value rest =>
    simp only [normalizeRefs, Value.refsExactFootprint, List.mem_append,
      normalize_authority index safe rest exact, ← safe value exact]
  | exact value rest =>
    simp only [normalizeRefs, Value.refsExactFootprint, List.mem_append, List.mem_cons,
      normalize_authority index safe rest exact]
termination_by sizeOf arguments

theorem signature_authority (index : Representatives) (safe : RepresentativeIndex.Sound index)
    (value : Value) : Value.SameExactFootprint value (signature index value) := by
  cases value with
  | atom bytes => exact Value.sameExactFootprint_refl _
  | apply operator arguments =>
    intro exact
    exact (normalize_authority index safe arguments exact).symm

theorem application_step (index : Representatives) (indexSafe : RepresentativeIndex.Sound index)
    (state : Representatives × RawPartition) (valid : Valid state.2) (safe : Safe state.2)
    (seen : ApplicationScan.Sound index state.1) (value : Value) :
    Valid (applicationStep index state value).2 ∧ Safe (applicationStep index state value).2 ∧
      ApplicationScan.Sound index (applicationStep index state value).1 := by
  rcases state with ⟨known, partition⟩
  cases value with
  | atom bytes => exact ⟨valid, safe, seen⟩
  | apply operator arguments =>
    cases found : known[signature index (.apply operator arguments)]? with
    | none =>
      simp only [applicationStep, congruenceStep, found]
      exact ⟨valid, safe, ApplicationScan.sound_insert index known seen _⟩
    | some prior =>
      have authority := signature_authority index indexSafe prior
      rw [seen _ _ found] at authority
      have same := Value.sameExactFootprint_trans authority
        (Value.sameExactFootprint_symm (signature_authority index indexSafe (.apply operator arguments)))
      simp only [applicationStep, congruenceStep, found]
      exact ⟨merge_valid valid prior _, merge_safe valid safe prior _ same, seen⟩

theorem application_fold (index : Representatives) (indexSafe : RepresentativeIndex.Sound index)
    (values : List Value) (state : Representatives × RawPartition) (valid : Valid state.2)
    (safe : Safe state.2) (seen : ApplicationScan.Sound index state.1) :
    Valid (values.foldl (applicationStep index) state).2 ∧
      Safe (values.foldl (applicationStep index) state).2 := by
  induction values generalizing state with
  | nil => exact ⟨valid, safe⟩
  | cons value rest ih =>
    have next := application_step index indexSafe state valid safe seen value
    exact ih _ next.1 next.2.1 next.2.2

theorem congruence_safe (values : List Value) {partition : RawPartition}
    (valid : Valid partition) (safe : Safe partition) :
    Valid (congruencePass values partition) ∧ Safe (congruencePass values partition) :=
  application_fold (representatives partition) (representatives_safe valid safe) values
    ({}, partition) valid safe (by simp [ApplicationScan.Sound])

theorem saturation_safe (values : List Value) (fuel : Nat) {partition : RawPartition}
    (valid : Valid partition) (safe : Safe partition) :
    Valid (saturateCongruence values fuel partition) ∧ Safe (saturateCongruence values fuel partition) := by
  induction fuel generalizing partition with
  | zero => exact ⟨valid, safe⟩
  | succ fuel ih =>
    simp only [saturateCongruence_step]
    split
    · exact ⟨valid, safe⟩
    · have next := congruence_safe values valid safe
      exact ih next.1 next.2

theorem footprint_complete {left right : Value} (safe : Value.SameExactFootprint left right) :
    Value.sameExactFootprint left right = true := by
  simp only [Value.sameExactFootprint, Bool.and_eq_true, List.all_eq_true]
  exact ⟨fun value present => List.contains_iff_mem.mpr ((safe value).mp present),
    fun value present => List.contains_iff_mem.mpr ((safe value).mpr present)⟩

theorem class_exists {partition : RawPartition} (valid : Valid partition) (safe : Safe partition)
    (members : RawClass) (stored : members ∈ partition) :
    ∃ item, EquivalenceClass.certify? members = some item := by
  cases members with
  | nil => exact False.elim (valid.2 [] stored rfl)
  | cons head tail =>
    have selected := lookup_member valid stored (List.mem_cons_self (a := head) (l := tail))
    have allSafe : (head :: tail).all (fun member => Value.sameExactFootprint member head) = true := by
      apply List.all_eq_true.mpr
      intro member present
      apply footprint_complete
      exact safe head member (selected ▸ present)
    simp only [EquivalenceClass.certify?, allSafe, ↓reduceDIte]
    exact ⟨_, rfl⟩

/-- Every valid authority-safe partition passes the existing executable
certificate. This proves success; it does not assume the old builder returned
a successful quotient before comparing two results. -/
theorem certify_exists {partition : RawPartition} (valid : Valid partition) (safe : Safe partition) :
    ∃ quotient, certify partition = some quotient := by
  have each := class_exists valid safe
  have mapped (items : RawPartition)
      (accepted : ∀ members ∈ items, ∃ item, EquivalenceClass.certify? members = some item) :
      ∃ classes, items.mapM EquivalenceClass.certify? = some classes := by
    induction items with
    | nil => exact ⟨[], rfl⟩
    | cons head tail ih =>
      obtain ⟨item, first⟩ := accepted head (by simp)
      obtain ⟨items, rest⟩ := ih (fun members member => accepted members (by simp [member]))
      exact ⟨item :: items, by simp [List.mapM_cons, first, rest]⟩
  obtain ⟨classes, found⟩ := mapped partition each
  simp [certify, found]

theorem reference_exists (roots : List Value) (persistent runLocal : List UnionEdge) :
    ∃ quotient, referenceBuild? roots persistent runLocal = some quotient := by
  dsimp only [referenceBuild?]
  rw [← saturateCongruence_reference]
  apply certify_exists
  · exact (saturation_safe _ _ (explicit_valid (initial_valid _) _)
      (explicit_safe (initial_valid _) (initial_safe _) _)).1
  · exact (saturation_safe _ _ (explicit_valid (initial_valid _) _)
      (explicit_safe (initial_valid _) (initial_safe _) _)).2

end Eggshell.QuotientBuilder.Authority
