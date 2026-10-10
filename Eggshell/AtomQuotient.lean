module
public import Eggshell.PartitionIndex
@[expose] public section
namespace Eggshell.QuotientBuilder.AtomQuotient
open Partition

def isAtom : Value → Bool
  | .atom _ => true
  | .apply _ _ => false

/-- Every equivalence class has one constructor kind. This is required:
an explicit Atom/application Union can otherwise expose new Atom aliases
through application congruence. -/
def Homogeneous (partition : RawPartition) : Prop :=
  ∀ query, ∀ member ∈ lookup partition query, isAtom member = isAtom query

theorem empty_homogeneous : Homogeneous [] := by
  intro query member present
  exact congrArg isAtom (by simpa [lookup, takeClass] using present)

theorem initial_homogeneous (values : List Value) : Homogeneous (initial values) := by
  intro query member present
  rw [initial_equivalent_empty values query] at present
  exact empty_homogeneous query member present

theorem merge_homogeneous {partition : RawPartition} (valid : Valid partition)
    (homogeneous : Homogeneous partition) (left right : Value)
    (kinds : isAtom left = isAtom right) : Homogeneous (merge partition left right) := by
  intro query member present
  rw [merge_lookup valid] at present
  split at present
  · exact homogeneous query member present
  · split at present
    · rename_i _ inside
      have queryKind : isAtom query = isAtom left := by
        rcases List.mem_append.mp inside with first | second
        · exact homogeneous left query first
        · exact (homogeneous right query second).trans kinds.symm
      apply Eq.trans _ queryKind.symm
      rcases List.mem_append.mp present with first | second
      · exact homogeneous left member first
      · exact (homogeneous right member second).trans kinds.symm
    · exact homogeneous query member present

theorem merge_applications {partition : RawPartition} (valid : Valid partition)
    (homogeneous : Homogeneous partition) (left right : Value)
    (leftApp : isAtom left = false) (rightApp : isAtom right = false) (bytes : ByteArray) :
    lookup (merge partition left right) (.atom bytes) = lookup partition (.atom bytes) := by
  have outside : Value.atom bytes ∉ lookup partition left ++ lookup partition right := by
    intro member
    rcases List.mem_append.mp member with first | second
    · have impossible := (homogeneous left _ first).trans leftApp
      cases impossible
    · have impossible := (homogeneous right _ second).trans rightApp
      cases impossible
  rw [merge_lookup valid, if_neg outside]
  exact ite_self _

def HomogeneousEdges (edges : List UnionEdge) : Prop :=
  ∀ edge ∈ edges, isAtom edge.left = isAtom edge.right

theorem explicit_homogeneous {partition : RawPartition} (valid : Valid partition)
    (homogeneous : Homogeneous partition) (edges : List UnionEdge) (kinds : HomogeneousEdges edges) :
    Homogeneous (mergeExplicit partition edges) := by
  induction edges generalizing partition with
  | nil => exact homogeneous
  | cons edge rest ih =>
    have sameKind := kinds edge (by simp)
    exact ih (merge_valid valid edge.left edge.right)
      (merge_homogeneous valid homogeneous edge.left edge.right sameKind)
      (fun next member => kinds next (by simp [member]))

theorem signature_kind (index : Representatives) (value : Value) :
    isAtom (signature index value) = isAtom value := by cases value <;> rfl

theorem application_step (index : Representatives) (state : Representatives × RawPartition)
    (valid : Valid state.2) (homogeneous : Homogeneous state.2)
    (sound : ApplicationScan.Sound index state.1) (value : Value) :
    Valid (applicationStep index state value).2 ∧
    Homogeneous (applicationStep index state value).2 ∧
    ApplicationScan.Sound index (applicationStep index state value).1 ∧
    ∀ bytes, lookup (applicationStep index state value).2 (.atom bytes) = lookup state.2 (.atom bytes) := by
  rcases state with ⟨seen, partition⟩
  cases value with
  | atom bytes => exact ⟨valid, homogeneous, sound, fun _ => rfl⟩
  | apply operator arguments =>
    cases found : seen[signature index (.apply operator arguments)]? with
    | none =>
      simp only [applicationStep, congruenceStep, found]
      exact ⟨valid, homogeneous, ApplicationScan.sound_insert index seen sound _, fun _ => True.intro⟩
    | some prior =>
      have priorApp : isAtom prior = false := by
        rw [← signature_kind index prior, sound _ _ found]
        rfl
      simp only [applicationStep, congruenceStep, found]
      exact ⟨merge_valid valid prior _, merge_homogeneous valid homogeneous prior _ priorApp,
        sound, merge_applications valid homogeneous prior _ priorApp rfl⟩

theorem application_fold (index : Representatives) (values : List Value)
    (state : Representatives × RawPartition) (valid : Valid state.2)
    (homogeneous : Homogeneous state.2) (sound : ApplicationScan.Sound index state.1) :
    Valid (values.foldl (applicationStep index) state).2 ∧
    Homogeneous (values.foldl (applicationStep index) state).2 ∧
    ∀ bytes, lookup (values.foldl (applicationStep index) state).2 (.atom bytes) = lookup state.2 (.atom bytes) := by
  induction values generalizing state with
  | nil => exact ⟨valid, homogeneous, fun _ => rfl⟩
  | cons value rest ih =>
    have next := application_step index state valid homogeneous sound value
    have result := ih _ next.1 next.2.1 next.2.2.1
    exact ⟨result.1, result.2.1, fun bytes => (result.2.2 bytes).trans (next.2.2.2 bytes)⟩

theorem congruence_atoms (values : List Value) {partition : RawPartition}
    (valid : Valid partition) (homogeneous : Homogeneous partition) :
    Valid (congruencePass values partition) ∧ Homogeneous (congruencePass values partition) ∧
    ∀ bytes, lookup (congruencePass values partition) (.atom bytes) = lookup partition (.atom bytes) :=
  application_fold (representatives partition) values ({}, partition) valid homogeneous
    (by simp [ApplicationScan.Sound])

theorem saturation_atoms (values : List Value) (fuel : Nat) {partition : RawPartition}
    (valid : Valid partition) (homogeneous : Homogeneous partition) :
    Valid (saturateCongruence values fuel partition) ∧
    Homogeneous (saturateCongruence values fuel partition) ∧
    ∀ bytes, lookup (saturateCongruence values fuel partition) (.atom bytes) = lookup partition (.atom bytes) := by
  induction fuel generalizing partition with
  | zero => exact ⟨valid, homogeneous, fun _ => rfl⟩
  | succ fuel ih =>
    simp only [saturateCongruence_step]
    split
    · exact ⟨valid, homogeneous, fun _ => rfl⟩
    · have next := congruence_atoms values valid homogeneous
      have result := ih next.1 next.2.1
      exact ⟨result.1, result.2.1, fun bytes => (result.2.2 bytes).trans (next.2.2 bytes)⟩

/-- Full runtime saturation, for any corpus and fuel, has exactly the same
ordered Atom classes as the explicit constructor-preserving Union fold.
Application/application unions and congruence cannot create Atom aliases.
Atom/application unions are deliberately outside this certified domain. -/
theorem independent (values : List Value) (fuel : Nat) (edges : List UnionEdge)
    (kinds : HomogeneousEdges edges) (bytes : ByteArray) :
    lookup (saturateCongruence values fuel (mergeExplicit (initial values) edges)) (.atom bytes) =
      lookup (mergeExplicit [] edges) (.atom bytes) :=
  ((saturation_atoms values fuel (explicit_valid (initial_valid values) edges)
    (explicit_homogeneous (initial_valid values) (initial_homogeneous values) edges kinds)).2.2 bytes).trans
    (explicit_independent values edges (.atom bytes))

theorem certified_aliases (values : List Value) (fuel : Nat) (edges : List UnionEdge)
    (kinds : HomogeneousEdges edges) (quotient : Quotient)
    (built : certify (saturateCongruence values fuel (mergeExplicit (initial values) edges)) = some quotient)
    (bytes : ByteArray) (value : Value) :
    quotient.toEquality.same (.atom bytes) value = true ↔
      value ∈ lookup (mergeExplicit [] edges) (.atom bytes) := by
  have valid := (saturation_atoms values fuel (explicit_valid (initial_valid values) edges)
    (explicit_homogeneous (initial_valid values) (initial_homogeneous values) edges kinds)).1
  rw [Quotient.same_iff_canonical_eq, certify_lookup valid built, certify_lookup valid built,
    heads_equal valid, independent values fuel edges kinds bytes]

theorem reference_aliases (roots : List Value) (edges : List UnionEdge)
    (kinds : HomogeneousEdges edges) (quotient : Quotient)
    (built : referenceBuild? roots [] edges = some quotient) (bytes : ByteArray) (value : Value) :
    quotient.toEquality.same (.atom bytes) value = true ↔
      value ∈ lookup (mergeExplicit [] edges) (.atom bytes) := by
  simp only [referenceBuild?, List.nil_append, ← saturateCongruence_reference] at built
  exact certified_aliases _ _ edges kinds quotient built bytes value

theorem build_aliases (roots : List Value) (edges : List UnionEdge)
    (kinds : HomogeneousEdges edges) (quotient : Quotient)
    (built : build? roots [] edges = some quotient) (bytes : ByteArray) (value : Value) :
    quotient.toEquality.same (.atom bytes) value = true ↔
      value ∈ lookup (mergeExplicit [] edges) (.atom bytes) := by
  by_cases empty : edges = []
  · subst edges
    have literal := Option.some.inj built
    subst quotient
    simp [Quotient.toEquality, Quotient.literal_canonical, mergeExplicit, lookup, takeClass, eq_comm]
  · rw [build_with_unions roots [] edges (Or.inr empty)] at built
    exact reference_aliases roots edges kinds quotient built bytes value

/-- A query-local Work class index. Its size depends on explicit Union
endpoints, never on the stored corpus, Outcome payloads or root inventory. -/
structure Index (edges : List UnionEdge) where
  partition : RawPartition
  exact : partition = mergeExplicit [] edges
  homogeneous : HomogeneousEdges edges

def Index.empty : Index [] := ⟨[], rfl, by simp [HomogeneousEdges]⟩

/-- Extend the existing classes with new edges only. The ordered class
representation equals a fresh fold over the complete edge sequence. -/
def Index.append (index : Index edges) (added : List UnionEdge)
    (kinds : HomogeneousEdges added) : Index (edges ++ added) where
  partition := mergeExplicit index.partition added
  exact := by simp only [index.exact, mergeExplicit, List.foldl_append]
  homogeneous := by
    intro edge member
    rcases List.mem_append.mp member with old | new
    · exact index.homogeneous edge old
    · exact kinds edge new

def Index.append? (index : Index edges) (added : List UnionEdge) :
    Option (Index (edges ++ added)) :=
  if checked : added.all (fun edge => isAtom edge.left == isAtom edge.right) then
    some (index.append added (by
      intro edge member
      exact beq_iff_eq.mp ((List.all_eq_true.mp checked) edge member)))
  else none

/-- Begin a run with an empty local delta, preserving the certified ordered
partition explicitly rather than transporting an executable Option through
a proposition about list append. -/
def Index.beginRun (index : Index edges) : Index (edges ++ []) := {
  partition := index.partition
  exact := by simpa only [List.append_nil] using index.exact
  homogeneous := by simpa only [List.append_nil] using index.homogeneous }

theorem Index.beginRun_partition (index : Index edges) :
    index.beginRun.partition = index.partition := rfl

theorem Index.append_partition (index : Index edges) (added : List UnionEdge)
    (kinds : HomogeneousEdges added) :
    (index.append added kinds).partition = mergeExplicit [] (edges ++ added) :=
  (index.append added kinds).exact

theorem Index.append_no_replay (index : Index edges) (added : List UnionEdge)
    (kinds : HomogeneousEdges added) :
    (index.append added kinds).partition = mergeExplicit index.partition added := rfl

def Index.values (index : Index edges) (work : Value) : List Value :=
  lookup index.partition work

theorem Index.values_fresh (index fresh : Index edges) (work : Value) :
    index.values work = fresh.values work := by
  simp only [Index.values, index.exact, fresh.exact]

theorem Index.values_exact (index : Index edges) (quotient : Quotient)
    (certified : certify index.partition = some quotient) (work value : Value) :
    value ∈ index.values work ↔ quotient.toEquality.same work value = true := by
  have valid : Valid index.partition := index.exact ▸ explicit_valid valid_nil edges
  rw [Quotient.same_iff_canonical_eq, certify_lookup valid certified,
    certify_lookup valid certified, heads_equal valid]
  rfl

def prepare (edges : List UnionEdge) : Option (Index edges) :=
  if checked : edges.all (fun edge => isAtom edge.left == isAtom edge.right) then
    some ⟨mergeExplicit [] edges, rfl, by
      intro edge member
      exact beq_iff_eq.mp ((List.all_eq_true.mp checked) edge member)⟩
  else none

def Index.aliases (index : Index edges) (bytes : ByteArray) : List Value :=
  lookup index.partition (.atom bytes)

theorem Index.aliases_are_atoms (index : Index edges) (bytes : ByteArray) (value : Value)
    (present : value ∈ index.aliases bytes) : isAtom value = true := by
  have homogeneous : Homogeneous index.partition := by
    rw [index.exact]
    exact explicit_homogeneous valid_nil empty_homogeneous edges index.homogeneous
  exact homogeneous (.atom bytes) value present

theorem Index.aliases_exact (index : Index edges) (roots : List Value) (quotient : Quotient)
    (built : build? roots [] edges = some quotient) (bytes : ByteArray) (value : Value) :
    value ∈ index.aliases bytes ↔ quotient.toEquality.same (.atom bytes) value = true := by
  rw [Index.aliases, index.exact]
  exact (build_aliases roots edges index.homogeneous quotient built bytes value).symm

/-- Checking literal child postings for every Atom alias is exactly the
full quotient's subwork membership, including children outside the demand
closure. A structured sibling cannot create an Atom alias. -/
theorem Index.subwork_exact (index : Index edges) (roots : List Value) (quotient : Quotient)
    (built : build? roots [] edges = some quotient) (bytes : ByteArray) (children : List Value) :
    (index.aliases bytes).any (fun alias => children.contains alias) =
      children.any (quotient.toEquality.same (.atom bytes)) := by
  apply Bool.eq_iff_iff.mpr
  simp only [List.any_eq_true, List.contains_iff_mem, index.aliases_exact roots quotient built]
  constructor
  · rintro ⟨value, same, member⟩
    exact ⟨value, member, same⟩
  · rintro ⟨value, member, same⟩
    exact ⟨value, same, member⟩

theorem prepare_complete (edges : List UnionEdge) (kinds : HomogeneousEdges edges) :
    (prepare edges).isSome = true := by
  have accepted : edges.all (fun edge => isAtom edge.left == isAtom edge.right) = true := by
    apply List.all_eq_true.mpr
    intro edge member
    exact beq_iff_eq.mpr (kinds edge member)
  simp [prepare, accepted]

theorem prepare_mixed_rejected (edges : List UnionEdge) (edge : UnionEdge)
    (present : edge ∈ edges) (mixed : isAtom edge.left ≠ isAtom edge.right) :
    prepare edges = none := by
  have rejected : edges.all (fun item => isAtom item.left == isAtom item.right) = false := by
    cases checked : edges.all (fun item => isAtom item.left == isAtom item.right) with
    | false => rfl
    | true => exact False.elim (mixed (beq_iff_eq.mp ((List.all_eq_true.mp checked) edge present)))
  simp [prepare, rejected]

end Eggshell.QuotientBuilder.AtomQuotient
