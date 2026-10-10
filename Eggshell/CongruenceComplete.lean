module

public import Eggshell.CongruenceFixed

@[expose] public section
namespace Eggshell.QuotientBuilder.CongruenceComplete
open Partition

def canonical (partition : RawPartition) (value : Value) : Value :=
  (lookup partition value).headD value

def Mono (before after : RawPartition) : Prop :=
  ∀ left right, canonical before left = canonical before right →
    canonical after left = canonical after right

theorem merge_mono (partition : RawPartition) (valid : Valid partition) (left right : Value) :
    Mono partition (merge partition left right) := by
  intro first second equal
  have present := (heads_equal valid first second).mp equal
  apply (heads_equal (merge_valid valid left right) first second).mpr
  rw [merge_lookup valid]
  split
  · exact present
  · split
    · rename_i _ joined
      rcases List.mem_append.mp joined with inLeft | inRight
      · have sameClass := lookup_related valid left first inLeft
        exact List.mem_append_left _ (sameClass ▸ present)
      · have sameClass := lookup_related valid right first inRight
        exact List.mem_append_right _ (sameClass ▸ present)
    · exact present

theorem merge_join (partition : RawPartition) (valid : Valid partition) (left right : Value) :
    canonical (merge partition left right) left = canonical (merge partition left right) right := by
  apply (heads_equal (merge_valid valid left right) left right).mpr
  rw [merge_lookup valid]
  split
  · assumption
  · have first : left ∈ lookup partition left ++ lookup partition right :=
      List.mem_append_left _ (lookup_contains partition left)
    simp only [first, ↓reduceIte]
    exact List.mem_append_right _ (lookup_contains partition right)

theorem step_valid (index : Representatives) (state : Representatives × RawPartition)
    (valid : Valid state.2) (value : Value) : Valid (applicationStep index state value).2 := by
  cases value with
  | atom _ => exact valid
  | apply operator arguments =>
    cases found : state.1[signature index (.apply operator arguments)]? with
    | none => simpa only [applicationStep, congruenceStep, found] using valid
    | some prior => simpa only [applicationStep, congruenceStep, found] using merge_valid valid prior (.apply operator arguments)

theorem step_mono (index : Representatives) (state : Representatives × RawPartition)
    (valid : Valid state.2) (value : Value) : Mono state.2 (applicationStep index state value).2 := by
  cases value with
  | atom _ => exact fun _ _ same => same
  | apply operator arguments =>
    cases found : state.1[signature index (.apply operator arguments)]? with
    | none => exact fun _ _ same => by simpa only [applicationStep, congruenceStep, found] using same
    | some prior => simpa only [applicationStep, congruenceStep, found] using merge_mono state.2 valid prior (.apply operator arguments)

theorem fold_mono (index : Representatives) (values : List Value) (state : Representatives × RawPartition)
    (valid : Valid state.2) : Valid (values.foldl (applicationStep index) state).2 ∧
    Mono state.2 (values.foldl (applicationStep index) state).2 := by
  induction values generalizing state with
  | nil => exact ⟨valid, fun _ _ equal => equal⟩
  | cons value rest ih =>
    have next := ih _ (step_valid index state valid value)
    exact ⟨next.1, fun left right equal => next.2 left right (step_mono index state valid value left right equal)⟩

theorem step_preserves (index : Representatives) (state : Representatives × RawPartition) (value key prior : Value)
    (stored : state.1[key]? = some prior) : (applicationStep index state value).1[key]? = some prior := by
  cases value with
  | atom _ => exact stored
  | apply operator arguments =>
    cases found : state.1[signature index (.apply operator arguments)]? with
    | some _ => simpa only [applicationStep, congruenceStep, found] using stored
    | none =>
      simp only [applicationStep, congruenceStep, found, Std.HashMap.getElem?_insert]
      split
      · rename_i equal
        have same : signature index (.apply operator arguments) = key := beq_iff_eq.mp equal
        rw [same, stored] at found
        contradiction
      · exact stored

theorem fold_preserves (index : Representatives) (values : List Value)
    (state : Representatives × RawPartition) (key prior : Value) (stored : state.1[key]? = some prior) :
    (values.foldl (applicationStep index) state).1[key]? = some prior := by
  induction values generalizing state with
  | nil => exact stored
  | cons value rest ih => exact ih _ (step_preserves index state value key prior stored)

/-- Every scanned application has a signature witness in the actual final
table and is joined to that witness in the actual final partition. -/
theorem fold_covers (index : Representatives) (values : List Value)
    (state : Representatives × RawPartition) (valid : Valid state.2)
    (operator : Operator) (arguments : Refs) (present : Value.apply operator arguments ∈ values) :
    ∃ prior, (values.foldl (applicationStep index) state).1[signature index (.apply operator arguments)]? = some prior ∧
      canonical (values.foldl (applicationStep index) state).2 (.apply operator arguments) =
        canonical (values.foldl (applicationStep index) state).2 prior := by
  induction values generalizing state with
  | nil => simp at present
  | cons value rest ih =>
    rcases List.mem_cons.mp present with same | later
    · subst value
      let next := applicationStep index state (.apply operator arguments)
      have recorded : ∃ prior, next.1[signature index (.apply operator arguments)]? = some prior ∧
          canonical next.2 (.apply operator arguments) = canonical next.2 prior := by
        cases found : state.1[signature index (.apply operator arguments)]? with
        | none => exact ⟨.apply operator arguments, by simp [next, applicationStep, congruenceStep, found], rfl⟩
        | some prior =>
          exact ⟨prior, by simp [next, applicationStep, congruenceStep, found],
            by simpa only [next, applicationStep, congruenceStep, found] using (merge_join state.2 valid prior (.apply operator arguments)).symm⟩
      obtain ⟨prior, stored, equal⟩ := recorded
      exact ⟨prior, fold_preserves index rest next _ prior stored,
        (fold_mono index rest next (step_valid index state valid _)).2 _ _ equal⟩
    · exact ih _ (step_valid index state valid value) later

/-- A fixed production pass is closed under every same-signature pair in
its input domain; this follows from the executed scan, not a new pair scan. -/
theorem pass_closed (values : List Value) (partition : RawPartition) (valid : Valid partition)
    (fixed : congruencePass values partition = partition) (left right : Value)
    (leftIn : left ∈ values) (rightIn : right ∈ values)
    (equal : signature (representatives partition) left = signature (representatives partition) right) :
    canonical partition left = canonical partition right := by
  cases left with
  | atom bytes =>
    have literal := ApplicationScan.signature_atom (representatives partition) right bytes equal.symm
    subst right
    rfl
  | apply operator arguments =>
    cases right with
    | atom bytes => simp [signature] at equal
    | apply other references =>
      obtain ⟨first, firstStored, firstEqual⟩ := fold_covers (representatives partition) values ({}, partition) valid operator arguments leftIn
      obtain ⟨second, secondStored, secondEqual⟩ := fold_covers (representatives partition) values ({}, partition) valid other references rightIn
      rw [equal, secondStored] at firstStored
      have same := Option.some.inj firstStored
      subst first
      change canonical (congruencePass values partition) _ = canonical (congruencePass values partition) _ at firstEqual secondEqual
      rw [fixed] at firstEqual secondEqual
      exact firstEqual.trans secondEqual.symm

theorem saturation_mono (values : List Value) (fuel : Nat) (partition : RawPartition)
    (valid : Valid partition) : Valid (saturateCongruence values fuel partition) ∧
    Mono partition (saturateCongruence values fuel partition) := by
  induction fuel generalizing partition with
  | zero => exact ⟨valid, fun _ _ equal => equal⟩
  | succ fuel ih =>
    simp only [saturateCongruence_step]
    split
    · exact ⟨valid, fun _ _ equal => equal⟩
    · have next := fold_mono (representatives partition) values ({}, partition) valid
      have rest := ih _ next.1
      exact ⟨rest.1, fun left right equal => rest.2 left right (next.2 left right equal)⟩

theorem explicit_mono (partition : RawPartition) (valid : Valid partition) (edges : List UnionEdge) :
    Valid (mergeExplicit partition edges) ∧ Mono partition (mergeExplicit partition edges) := by
  induction edges generalizing partition with
  | nil => exact ⟨valid, fun _ _ equal => equal⟩
  | cons edge rest ih =>
    have next := ih _ (merge_valid valid edge.left edge.right)
    exact ⟨next.1, fun left right equal => next.2 left right (merge_mono partition valid edge.left edge.right left right equal)⟩

theorem explicit_connected (partition : RawPartition) (valid : Valid partition) (edges : List UnionEdge) :
    ∀ edge ∈ edges, canonical (mergeExplicit partition edges) edge.left = canonical (mergeExplicit partition edges) edge.right := by
  induction edges generalizing partition with
  | nil => simp
  | cons edge rest ih =>
    intro selected member
    rcases List.mem_cons.mp member with same | later
    · subst selected
      exact (explicit_mono _ (merge_valid valid edge.left edge.right) rest).2 _ _ (merge_join partition valid edge.left edge.right)
    · exact ih _ (merge_valid valid edge.left edge.right) selected later

theorem saturation_domain (values : List Value) (fuel : Nat) (partition : RawPartition)
    (valid : Valid partition) (covered : values ⊆ partition.flatten) :
    Valid (saturateCongruence values fuel partition) ∧
      (∀ value, value ∈ (saturateCongruence values fuel partition).flatten ↔ value ∈ partition.flatten) := by
  induction fuel generalizing partition with
  | zero => exact ⟨valid, fun _ => Iff.rfl⟩
  | succ fuel ih =>
    simp only [saturateCongruence_step]
    split
    · exact ⟨valid, fun _ => Iff.rfl⟩
    · have next := CongruenceFixed.pass_progress values partition valid covered
      have rest := ih _ next.1 (fun value present => (next.2.1 value).mpr (covered present))
      exact ⟨rest.1, fun value => (rest.2 value).trans (next.2.1 value)⟩

theorem kernel_domain (roots : List Value) (edges : List UnionEdge) :
    Valid (kernelPartition roots edges) ∧
      (∀ value, value ∈ (kernelPartition roots edges).flatten ↔ value ∈ kernelValues roots edges) := by
  let values := kernelValues roots edges
  have initialDomain (value : Value) : value ∈ (initial values).flatten ↔ value ∈ values := by
    rw [CongruenceFixed.initial_flatten, HashDistinct.mem]
  have prepared := CongruenceFixed.explicit_progress (initial values) (initial_valid values) edges (fun edge member =>
    let endpoints := CongruenceFixed.kernel_endpoints roots edges edge member
    ⟨(initialDomain edge.left).mpr endpoints.1, (initialDomain edge.right).mpr endpoints.2⟩)
  have result := saturation_domain values values.length _ prepared.1
    (fun value present => (prepared.2.1 value).mpr ((initialDomain value).mpr present))
  exact ⟨result.1, fun value => (result.2 value).trans ((prepared.2.1 value).trans (initialDomain value))⟩

theorem kernel_connected (roots : List Value) (edges : List UnionEdge) :
    ∀ edge ∈ edges, canonical (kernelPartition roots edges) edge.left = canonical (kernelPartition roots edges) edge.right := by
  intro edge member
  let values := kernelValues roots edges
  exact (saturation_mono values values.length _ (explicit_valid (initial_valid values) edges)).2 _ _
    (explicit_connected (initial values) (initial_valid values) edges edge member)

theorem kernel_closed_signatures (roots : List Value) (edges : List UnionEdge) (left right : Value)
    (leftIn : left ∈ kernelValues roots edges) (rightIn : right ∈ kernelValues roots edges)
    (same : signature (representatives (kernelPartition roots edges)) left =
      signature (representatives (kernelPartition roots edges)) right) :
    canonical (kernelPartition roots edges) left = canonical (kernelPartition roots edges) right :=
  pass_closed _ _ (kernel_domain roots edges).1 (CongruenceFixed.kernel_fixed roots edges) _ _ leftIn rightIn same

mutual
theorem semantic_nested (root member : Value) (present : member ∈ root.semanticNodes) :
    member.semanticNodes ⊆ root.semanticNodes := by
  cases root with
  | atom bytes =>
    have same : member = .atom bytes := by simpa [Value.semanticNodes] using present
    subst member
    exact fun _ member => member
  | apply operator arguments =>
    simp only [Value.semanticNodes, List.mem_cons] at present ⊢
    rcases present with same | nested
    · subst member
      exact fun _ member => member
    · exact fun value member => List.mem_cons_of_mem _ (references_nested arguments _ nested member)

theorem references_nested (arguments : Refs) (member : Value)
    (present : member ∈ Value.refsSemanticNodes arguments) :
    member.semanticNodes ⊆ Value.refsSemanticNodes arguments := by
  cases arguments with
  | nil => simp [Value.refsSemanticNodes] at present
  | exact _ rest => exact references_nested rest member present
  | semantic value rest =>
    rcases List.mem_append.mp present with here | there
    · exact fun query nested => List.mem_append_left _ (semantic_nested value member here nested)
    · exact fun query nested => List.mem_append_right _ (references_nested rest member there nested)
end

theorem kernel_semantic_closed (roots : List Value) (edges : List UnionEdge) (value : Value)
    (present : value ∈ kernelValues roots edges) : value.semanticNodes ⊆ kernelValues roots edges := by
  obtain ⟨root, rootIn, nested⟩ := List.mem_flatMap.mp ((HashDistinct.mem _ _).mp present)
  intro query member
  exact (HashDistinct.mem _ _).mpr (List.mem_flatMap.mpr ⟨root, rootIn, semantic_nested root value nested member⟩)

theorem representative_canonical (partition : RawPartition) (valid : Valid partition) (value : Value) :
    (representatives partition).getD value value = canonical partition value := by
  have equation := Authority.raw_lookup partition valid ({} : Representatives) value
  change (representatives partition).getD value value = _ at equation
  rw [equation]
  split
  · rfl
  · rename_i absent
    simp [canonical, lookup_missing partition value absent]

/-- A finite completed ground domain. The model below extends it to every
finite Value, including terms absent from the stored or demanded corpus. -/
structure Algebra where
  values : List Value
  partition : RawPartition
  valid : Valid partition
  closed : ∀ value ∈ values, value.semanticNodes ⊆ values
  signatures : ∀ left ∈ values, ∀ right ∈ values,
    signature (representatives partition) left = signature (representatives partition) right →
      canonical partition left = canonical partition right

def kernelAlgebra (roots : List Value) (edges : List UnionEdge) : Algebra :=
  ⟨kernelValues roots edges, kernelPartition roots edges, (kernel_domain roots edges).1,
    kernel_semantic_closed roots edges,
    fun left leftIn right rightIn => kernel_closed_signatures roots edges left right leftIn rightIn⟩

mutual
inductive ModelValue where
  | identified (representative : Value)
  | atom (bytes : ByteArray)
  | apply (operator : Operator) (arguments : ModelRefs)
inductive ModelRefs where
  | nil
  | semantic (value : ModelValue) (tail : ModelRefs)
  | exact (value : Value) (tail : ModelRefs)
end

deriving instance DecidableEq for ModelValue, ModelRefs

mutual
def decode : ModelValue → Value
  | .identified value => value
  | .atom bytes => .atom bytes
  | .apply operator arguments => .apply operator (decodeRefs arguments)
def decodeRefs : ModelRefs → Refs
  | .nil => .nil
  | .semantic value tail => .semantic (decode value) (decodeRefs tail)
  | .exact value tail => .exact value (decodeRefs tail)
end

def shallowRefs : Refs → ModelRefs
  | .nil => .nil
  | .semantic value tail => .semantic (.identified value) (shallowRefs tail)
  | .exact value tail => .exact value (shallowRefs tail)

def shallow : Value → ModelValue
  | .atom bytes => .atom bytes
  | .apply operator arguments => .apply operator (shallowRefs arguments)

theorem decode_shallow_refs (arguments : Refs) : decodeRefs (shallowRefs arguments) = arguments := by
  cases arguments with
  | nil => rfl
  | semantic _ tail | exact _ tail => simp [shallowRefs, decodeRefs, decode, decode_shallow_refs tail]

theorem shallow_injective {left right : Value} (equal : shallow left = shallow right) : left = right := by
  have restored (value : Value) : decode (shallow value) = value := by
    cases value <;> simp [shallow, decode, decode_shallow_refs]
  simpa only [restored] using congrArg decode equal

def domainKey (algebra : Algebra) (value : Value) : ModelValue :=
  shallow (signature (representatives algebra.partition) value)

/-- This is a proof model, not a second search engine. Known ground
signatures evaluate to their class; an unknown structure remains distinct.
It does not enumerate the unbounded universe of terms. -/
def Algebra.lookup (algebra : Algebra) (key : ModelValue) : ModelValue :=
  match algebra.values.find? (fun value => decide (domainKey algebra value = key)) with
  | some value => .identified (canonical algebra.partition value)
  | none => key

theorem lookup_known (algebra : Algebra) (value : Value) (present : value ∈ algebra.values) :
    algebra.lookup (domainKey algebra value) = .identified (canonical algebra.partition value) := by
  unfold Algebra.lookup
  cases found : algebra.values.find? (fun prior => decide (domainKey algebra prior = domainKey algebra value)) with
  | none =>
    have absent := (List.find?_eq_none.mp found) value present
    simp at absent
  | some prior =>
    have source := List.mem_of_find?_eq_some found
    have same : domainKey algebra prior = domainKey algebra value := by
      simpa using List.find?_some found
    have signatures := shallow_injective same
    exact congrArg ModelValue.identified (algebra.signatures prior source value present signatures)

mutual
def evaluate (algebra : Algebra) : Value → ModelValue
  | .atom bytes => algebra.lookup (.atom bytes)
  | .apply operator arguments => algebra.lookup (.apply operator (evaluateRefs algebra arguments))
def evaluateRefs (algebra : Algebra) : Refs → ModelRefs
  | .nil => .nil
  | .semantic value tail => .semantic (evaluate algebra value) (evaluateRefs algebra tail)
  | .exact value tail => .exact value (evaluateRefs algebra tail)
end

mutual
theorem evaluate_domain (algebra : Algebra) (value : Value) (present : value ∈ algebra.values) :
    evaluate algebra value = .identified (canonical algebra.partition value) := by
  cases value with
  | atom bytes => exact lookup_known algebra (.atom bytes) present
  | apply operator arguments =>
    have covered : Value.refsSemanticNodes arguments ⊆ algebra.values :=
      fun query member => algebra.closed (.apply operator arguments) present (List.mem_cons_of_mem _ member)
    change algebra.lookup (.apply operator (evaluateRefs algebra arguments)) = _
    rw [evaluate_refs_domain algebra arguments covered]
    exact lookup_known algebra (.apply operator arguments) present

theorem evaluate_refs_domain (algebra : Algebra) (arguments : Refs)
    (covered : Value.refsSemanticNodes arguments ⊆ algebra.values) :
    evaluateRefs algebra arguments = shallowRefs (normalizeRefs (representatives algebra.partition) arguments) := by
  cases arguments with
  | nil => rfl
  | exact value rest =>
    change ModelRefs.exact value (evaluateRefs algebra rest) = .exact value (shallowRefs (normalizeRefs _ rest))
    rw [evaluate_refs_domain algebra rest covered]
  | semantic value rest =>
    have present := covered (List.mem_append_left _ (CongruenceFixed.semantic_self value))
    have tail : Value.refsSemanticNodes rest ⊆ algebra.values := fun query member => covered (List.mem_append_right _ member)
    simp only [evaluateRefs, normalizeRefs, shallowRefs]
    rw [evaluate_domain algebra value present, evaluate_refs_domain algebra rest tail,
      representative_canonical algebra.partition algebra.valid value]
end

/-- Semantic congruence is preserved even through arbitrary intermediate
terms absent from the finite domain. Exact arguments stay literally equal. -/
theorem evaluate_equivalent (algebra : Algebra) (edges : List UnionEdge)
    (joined : ∀ edge ∈ edges, evaluate algebra edge.left = evaluate algebra edge.right)
    {left right : Value} (equivalent : Eggshell.Equivalent edges left right) :
    evaluate algebra left = evaluate algebra right :=
  Eggshell.Equivalent.rec
    (motive_1 := fun left right _ => evaluate algebra left = evaluate algebra right)
    (motive_2 := fun left right _ => evaluateRefs algebra left = evaluateRefs algebra right)
    (fun _ => rfl)
    (fun edge member => joined edge member)
    (fun _ equal => equal.symm)
    (fun _ _ first second => first.trans second)
    (fun operator _ same => congrArg (fun arguments => algebra.lookup (.apply operator arguments)) same)
    rfl
    (fun _ _ head tail =>
      (congrArg (fun value => ModelRefs.semantic value _) head).trans
        (congrArg (ModelRefs.semantic _) tail))
    (fun _ tail => congrArg (ModelRefs.exact _) tail)
    equivalent

theorem kernel_complete (roots : List Value) (edges : List UnionEdge) (left right : Value)
    (leftIn : left ∈ kernelValues roots edges) (rightIn : right ∈ kernelValues roots edges)
    (equivalent : Eggshell.Equivalent edges left right) :
    canonical (kernelPartition roots edges) left = canonical (kernelPartition roots edges) right := by
  let algebra := kernelAlgebra roots edges
  have joined : ∀ edge ∈ edges, evaluate algebra edge.left = evaluate algebra edge.right := by
    intro edge member
    have endpoints := CongruenceFixed.kernel_endpoints roots edges edge member
    rw [evaluate_domain algebra edge.left endpoints.1, evaluate_domain algebra edge.right endpoints.2]
    exact congrArg ModelValue.identified (kernel_connected roots edges edge member)
  have equal := evaluate_equivalent algebra edges joined equivalent
  rw [evaluate_domain algebra left leftIn, evaluate_domain algebra right rightIn] at equal
  exact ModelValue.identified.inj equal

theorem evaluate_atom_missing (algebra : Algebra) (bytes : ByteArray)
    (missing : Value.atom bytes ∉ algebra.values) : evaluate algebra (.atom bytes) = .atom bytes := by
  have absent : algebra.values.find? (fun value => decide (domainKey algebra value = .atom bytes)) = none := by
    apply List.find?_eq_none.mpr
    intro value present accepted
    have key : domainKey algebra value = .atom bytes := by simpa using accepted
    have same : signature (representatives algebra.partition) value = .atom bytes :=
      shallow_injective key
    exact missing ((ApplicationScan.signature_atom _ value bytes same) ▸ present)
  simp [evaluate, Algebra.lookup, absent]

theorem evaluate_atom_origin (algebra : Algebra) (value : Value) (bytes : ByteArray)
    (equal : evaluate algebra value = .atom bytes) : value = .atom bytes := by
  cases value with
  | atom other =>
    unfold evaluate Algebra.lookup at equal
    cases found : algebra.values.find? (fun value => decide (domainKey algebra value = .atom other)) with
    | none =>
      have same : other = bytes := by simpa only [found, ModelValue.atom.injEq] using equal
      exact congrArg Value.atom same
    | some prior => simp [found] at equal
  | apply operator arguments =>
    unfold evaluate Algebra.lookup at equal
    cases found : algebra.values.find? (fun value => decide (domainKey algebra value =
        .apply operator (evaluateRefs algebra arguments))) <;> simp [found] at equal

/-- A completely unmentioned Atom cannot acquire an alias through unseen
intermediate applications. This also covers mixed and recursive edges. -/
theorem outside_atom_literal (roots : List Value) (edges : List UnionEdge) (bytes : ByteArray)
    (missing : Value.atom bytes ∉ kernelValues roots edges) (value : Value)
    (equivalent : Eggshell.Equivalent edges (.atom bytes) value) : Value.atom bytes = value := by
  let algebra := kernelAlgebra roots edges
  have joined : ∀ edge ∈ edges, evaluate algebra edge.left = evaluate algebra edge.right := by
    intro edge member
    have endpoints := CongruenceFixed.kernel_endpoints roots edges edge member
    rw [evaluate_domain algebra edge.left endpoints.1, evaluate_domain algebra edge.right endpoints.2]
    exact congrArg ModelValue.identified (kernel_connected roots edges edge member)
  have equal := evaluate_equivalent algebra edges joined equivalent
  rw [evaluate_atom_missing algebra bytes missing] at equal
  exact (evaluate_atom_origin algebra value bytes equal.symm).symm

/-- Completeness of the actual producer on its demanded semantic domain.
The derivation may use arbitrary outside terms; it is not restricted to
proofs whose intermediate Values were read from the corpus. -/
theorem build_complete (roots : List Value) (persistent runLocal : List UnionEdge)
    (quotient : Quotient) (built : build? roots persistent runLocal = some quotient)
    (left right : Value) (leftIn : left ∈ kernelValues roots (persistent ++ runLocal))
    (rightIn : right ∈ kernelValues roots (persistent ++ runLocal))
    (equivalent : Eggshell.Equivalent (persistent ++ runLocal) left right) :
    quotient.toEquality.same left right = true := by
  unfold build? at built
  split at built
  · rename_i empty
    have noEdges : persistent = [] ∧ runLocal = [] := by simpa using empty
    obtain ⟨rfl, rfl⟩ := noEdges
    have literal := Eggshell.Equivalent.without_edges equivalent
    subst right
    exact quotient.toEquality.reflexive left
  · unfold congruenceBuild? at built
    apply (Quotient.same_iff_canonical_eq quotient).mpr
    rw [certify_lookup (kernel_domain roots (persistent ++ runLocal)).1 built,
      certify_lookup (kernel_domain roots (persistent ++ runLocal)).1 built]
    exact kernel_complete roots (persistent ++ runLocal) left right leftIn rightIn equivalent

/-- Text Work and newly produced text fragments need no corpus-membership
assumption. If an Atom is not in the closed edge domain, only literal equality
is possible. No old complete root/body catalogue is required. -/
theorem build_complete_atoms (roots : List Value) (persistent runLocal : List UnionEdge)
    (quotient : Quotient) (built : build? roots persistent runLocal = some quotient)
    (left right : ByteArray) (equivalent : Eggshell.Equivalent (persistent ++ runLocal) (.atom left) (.atom right)) :
    quotient.toEquality.same (.atom left) (.atom right) = true := by
  by_cases leftIn : Value.atom left ∈ kernelValues roots (persistent ++ runLocal)
  · by_cases rightIn : Value.atom right ∈ kernelValues roots (persistent ++ runLocal)
    · exact build_complete roots persistent runLocal quotient built _ _ leftIn rightIn equivalent
    · have literal := outside_atom_literal roots (persistent ++ runLocal) right rightIn (.atom left) (.symm equivalent)
      rw [literal]
      exact quotient.toEquality.reflexive _
  · have literal := outside_atom_literal roots (persistent ++ runLocal) left leftIn (.atom right) equivalent
    rw [literal]
    exact quotient.toEquality.reflexive _

theorem kernel_root (roots : List Value) (edges : List UnionEdge) (value : Value)
    (present : value ∈ roots) : value ∈ kernelValues roots edges :=
  (HashDistinct.mem _ _).mpr (List.mem_flatMap.mpr
    ⟨value, List.mem_append_left _ present, CongruenceFixed.semantic_self value⟩)

end Eggshell.QuotientBuilder.CongruenceComplete
