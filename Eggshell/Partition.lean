module
public import Eggshell.Quotient
public import Eggshell.HashDistinct
@[expose] public section
namespace Eggshell.QuotientBuilder.Partition

/-- Every Value occurs in at most one class and no class is empty. -/
def Valid (partition : RawPartition) : Prop :=
  partition.flatten.Nodup ∧ ∀ members ∈ partition, members ≠ []

def lookup (partition : RawPartition) (value : Value) : RawClass :=
  (takeClass value partition).1

theorem lookup_cons (head : RawClass) (tail : RawPartition) (query : Value) :
    lookup (head :: tail) query = if query ∈ head then head else lookup tail query := by
  by_cases present : query ∈ head <;> simp [lookup, takeClass, present]

theorem valid_nil : Valid [] := by simp [Valid]

theorem valid_cons {head : RawClass} {tail : RawPartition} :
    Valid (head :: tail) ↔ head.Nodup ∧ Valid tail ∧ head ≠ [] ∧
      ∀ value ∈ head, value ∉ tail.flatten := by
  simp only [Valid, List.flatten_cons, List.nodup_append, List.mem_cons, forall_eq_or_imp]
  constructor
  · rintro ⟨⟨hn, tn, apart⟩, nonempty, rest⟩
    exact ⟨hn, ⟨tn, rest⟩, nonempty, fun value member present => apart value member value present rfl⟩
  · rintro ⟨hn, ⟨tn, rest⟩, nonempty, apart⟩
    exact ⟨⟨hn, tn, fun a ha b hb same => apart a ha (same ▸ hb)⟩, nonempty, rest⟩

theorem lookup_contains (partition : RawPartition) (value : Value) : value ∈ lookup partition value := by
  induction partition with
  | nil => simp [lookup, takeClass]
  | cons head tail ih =>
    by_cases present : value ∈ head
    · simp [lookup, takeClass, present]
    · simpa [lookup, takeClass, present] using ih

theorem lookup_origin (partition : RawPartition) (value : Value) :
    lookup partition value ∈ partition ∨ lookup partition value = [value] := by
  induction partition with
  | nil => exact Or.inr rfl
  | cons head tail ih =>
    by_cases present : value ∈ head
    · exact Or.inl (by simp [lookup, takeClass, present])
    · simpa [lookup, takeClass, present] using ih.imp (fun member => List.mem_cons_of_mem _ member) id

theorem lookup_missing (partition : RawPartition) (value : Value) (absent : value ∉ partition.flatten) :
    lookup partition value = [value] := by
  induction partition with
  | nil => rfl
  | cons head tail ih =>
    simp only [List.flatten_cons, List.mem_append, not_or] at absent
    simpa [lookup, takeClass, absent.1] using ih absent.2

theorem lookup_member {partition : RawPartition} (valid : Valid partition)
    {members : RawClass} (stored : members ∈ partition) {value : Value} (present : value ∈ members) :
    lookup partition value = members := by
  induction partition with
  | nil => simp at stored
  | cons head tail ih =>
    obtain ⟨_, tailValid, _, apart⟩ := valid_cons.mp valid
    rcases List.mem_cons.mp stored with same | stored
    · subst members
      simp [lookup, takeClass, present]
    · have outside : value ∉ head := fun member => apart value member (List.mem_flatten.mpr ⟨members, stored, present⟩)
      simpa [lookup, takeClass, outside] using ih tailValid stored

theorem lookup_nodup {partition : RawPartition} (valid : Valid partition) (value : Value) :
    (lookup partition value).Nodup := by
  rcases lookup_origin partition value with stored | singleton
  · have subset : List.Sublist (lookup partition value) partition.flatten :=
      List.sublist_flatten_of_mem stored
    exact subset.nodup valid.1
  · simp [singleton]

theorem take_subset (partition : RawPartition) (value : Value) :
    (takeClass value partition).2 ⊆ partition := by
  induction partition with
  | nil => simp [takeClass]
  | cons head tail ih =>
    by_cases present : value ∈ head
    · simp [takeClass, present]
    · intro members stored
      simp only [takeClass, show head.contains value = false from by simpa using present,
        Bool.false_eq_true, ↓reduceIte] at stored
      rcases List.mem_cons.mp stored with same | stored
      · exact List.mem_cons.mpr (Or.inl same)
      · exact List.mem_cons_of_mem head (ih stored)

theorem take_valid {partition : RawPartition} (valid : Valid partition) (value : Value) :
    Valid (takeClass value partition).2 := by
  induction partition with
  | nil => exact valid_nil
  | cons head tail ih =>
    obtain ⟨hn, tv, nonempty, apart⟩ := valid_cons.mp valid
    by_cases present : value ∈ head
    · simpa [takeClass, present] using tv
    · simp only [takeClass, show head.contains value = false from by simpa using present,
        Bool.false_eq_true, ↓reduceIte]
      apply valid_cons.mpr
      refine ⟨hn, ih tv, nonempty, ?_⟩
      intro query member included
      obtain ⟨members, stored, found⟩ := List.mem_flatten.mp included
      exact apart query member (List.mem_flatten.mpr ⟨members, take_subset tail value stored, found⟩)

theorem take_separates {partition : RawPartition} (valid : Valid partition) (value : Value) :
    ∀ query ∈ lookup partition value, query ∉ (takeClass value partition).2.flatten := by
  induction partition with
  | nil => simp [lookup, takeClass]
  | cons head tail ih =>
    obtain ⟨_, tv, _, apart⟩ := valid_cons.mp valid
    by_cases present : value ∈ head
    · simpa [lookup, takeClass, present] using apart
    · simp only [lookup, takeClass, show head.contains value = false from by simpa using present,
        Bool.false_eq_true, ↓reduceIte, List.flatten_cons, List.mem_append, not_or]
      intro query member
      refine ⟨?_, ih tv query member⟩
      intro inHead
      rcases lookup_origin tail value with stored | singleton
      · exact apart query inHead (List.mem_flatten.mpr ⟨lookup tail value, stored, member⟩)
      · have same : query = value := by
          change query ∈ lookup tail value at member
          simpa [singleton] using member
        exact present (same ▸ inHead)

theorem take_lookup_other (partition : RawPartition) (value query : Value)
    (outside : query ∉ lookup partition value) :
    lookup (takeClass value partition).2 query = lookup partition query := by
  induction partition with
  | nil => rfl
  | cons head tail ih =>
    by_cases present : value ∈ head
    · have absent : query ∉ head := by simpa [lookup, takeClass, present] using outside
      simp [lookup, takeClass, present, absent]
    · have outsideTail : query ∉ lookup tail value := by simpa [lookup, takeClass, present] using outside
      by_cases here : query ∈ head
      · simp [lookup, takeClass, present, here]
      · simpa [lookup, takeClass, present, here] using ih outsideTail

theorem take_lookup {partition : RawPartition} (valid : Valid partition) (value query : Value) :
    lookup (takeClass value partition).2 query =
      if query ∈ lookup partition value then [query] else lookup partition query := by
  split
  · rename_i member
    exact lookup_missing _ _ (take_separates valid value query member)
  · rename_i outside
    exact take_lookup_other partition value query outside

theorem same_lookup {partition : RawPartition} (valid : Valid partition) (left right : Value) :
    same partition left right = (lookup partition left).contains right := by
  apply Bool.eq_iff_iff.mpr
  simp only [same, Bool.or_eq_true, beq_iff_eq, List.any_eq_true, Bool.and_eq_true, List.contains_iff_mem]
  constructor
  · rintro (equal | ⟨members, stored, leftIn, rightIn⟩)
    · subst right; exact lookup_contains partition left
    · simpa [lookup_member valid stored leftIn] using rightIn
  · intro rightIn
    rcases lookup_origin partition left with stored | singleton
    · exact Or.inr ⟨lookup partition left, stored, lookup_contains partition left, rightIn⟩
    · have equal : right = left := by simpa [singleton] using rightIn
      exact Or.inl equal.symm

theorem lookup_member_origin (partition : RawPartition) (value query : Value)
    (present : query ∈ lookup partition value) : query = value ∨ query ∈ partition.flatten := by
  rcases lookup_origin partition value with stored | singleton
  · exact Or.inr (List.mem_flatten.mpr ⟨lookup partition value, stored, present⟩)
  · exact Or.inl (by simpa [singleton] using present)

theorem take_flatten_subset (partition : RawPartition) (value : Value) :
    (takeClass value partition).2.flatten ⊆ partition.flatten := by
  intro query present
  obtain ⟨members, stored, member⟩ := List.mem_flatten.mp present
  exact List.mem_flatten.mpr ⟨members, take_subset partition value stored, member⟩

theorem merge_parts {partition : RawPartition} (valid : Valid partition) (left right : Value)
    (separate : same partition left right = false) :
    let first := lookup partition left
    let remaining := (takeClass left partition).2
    let second := lookup remaining right
    let rest := (takeClass right remaining).2
    (first ++ second).Nodup ∧ Valid rest ∧ (first ++ second) ≠ [] ∧
      (∀ value ∈ first ++ second, value ∉ rest.flatten) ∧
      second = lookup partition right := by
  dsimp only
  have outside : right ∉ lookup partition left := by
    rw [same_lookup valid] at separate
    simpa using separate
  have rv := take_valid valid left
  have noFirst := take_separates valid left
  have noSecond := take_separates rv right
  refine ⟨List.nodup_append.mpr ⟨lookup_nodup valid left, lookup_nodup rv right, ?_⟩,
    take_valid rv right, ?_, ?_, take_lookup_other partition left right outside⟩
  · intro a first b second equal
    subst b
    rcases lookup_member_origin _ right a second with same | stored
    · exact outside (same ▸ first)
    · exact noFirst a first stored
  · intro empty
    have included : left ∈ lookup partition left ++ lookup (takeClass left partition).2 right :=
      List.mem_append_left _ (lookup_contains partition left)
    simp [empty] at included
  · intro value member
    rcases List.mem_append.mp member with first | second
    · intro stored
      exact noFirst value first (take_flatten_subset _ right stored)
    · exact noSecond value second

/-- Valid classes are already disjoint, so joining them needs no second
payload hash/deduplication scan. This is the executed merge's exact equation. -/
theorem merge_eq {partition : RawPartition} (valid : Valid partition) (left right : Value)
    (separate : same partition left right = false) :
    merge partition left right =
      (lookup partition left ++ lookup (takeClass left partition).2 right) ::
        (takeClass right (takeClass left partition).2).2 := by
  simp only [merge, separate, Bool.false_eq_true, ↓reduceIte]
  exact congrArg (· :: (takeClass right (takeClass left partition).2).2)
    (HashDistinct.unchanged _ (merge_parts valid left right separate).1)

theorem merge_valid {partition : RawPartition} (valid : Valid partition) (left right : Value) :
    Valid (merge partition left right) := by
  cases matched : same partition left right with
  | true => simpa [merge, matched] using valid
  | false =>
    rw [merge_eq valid left right matched]
    have parts := merge_parts valid left right matched
    exact valid_cons.mpr ⟨parts.1, parts.2.1, parts.2.2.1, parts.2.2.2.1⟩

theorem merge_lookup {partition : RawPartition} (valid : Valid partition) (left right query : Value) :
    lookup (merge partition left right) query =
      if right ∈ lookup partition left then lookup partition query
      else if query ∈ lookup partition left ++ lookup partition right then
        lookup partition left ++ lookup partition right
      else lookup partition query := by
  by_cases sameClass : right ∈ lookup partition left
  · have same : same partition left right = true := by rw [same_lookup valid]; simpa using sameClass
    simp [merge, same, sameClass]
  · have different : same partition left right = false := by rw [same_lookup valid]; simpa using sameClass
    have parts := merge_parts valid left right different
    rw [merge_eq valid left right different]
    by_cases member : query ∈ lookup partition left ++ lookup partition right
    · simp only [lookup_cons, sameClass, member, ↓reduceIte, parts.2.2.2.2]
    · have absent : query ∉ lookup partition left ++ lookup (takeClass left partition).2 right := by
        simpa only [parts.2.2.2.2] using member
      have outside := not_or.mp (fun either => member (List.mem_append.mpr either))
      have secondOutside : query ∉ lookup (takeClass left partition).2 right := by
        simpa only [parts.2.2.2.2] using outside.2
      have afterRight := take_lookup_other (takeClass left partition).2 right query secondOutside
      have afterLeft := take_lookup_other partition left query outside.1
      simpa only [lookup_cons, absent, sameClass, member, ↓reduceIte] using afterRight.trans afterLeft

def Equivalent (first second : RawPartition) : Prop := ∀ value, lookup first value = lookup second value

theorem merge_equivalent {first second : RawPartition} (fv : Valid first) (sv : Valid second)
    (equivalent : Equivalent first second) (left right : Value) :
    Equivalent (merge first left right) (merge second left right) := by
  intro query
  simp only [merge_lookup fv, merge_lookup sv, equivalent left, equivalent right, equivalent query]

theorem initial_valid (values : List Value) : Valid (initial values) := by
  constructor
  · have singletons (items : List Value) : (items.map (fun value => [value])).flatten = items := by
      induction items <;> simp_all
    simpa only [initial, singletons] using HashDistinct.nodup values
  · intro members present
    obtain ⟨value, _, rfl⟩ := List.mem_map.mp present
    simp

theorem singleton_lookup (values : List Value) (query : Value) :
    lookup (values.map (fun value => [value])) query = [query] := by
  induction values with
  | nil => rfl
  | cons head tail ih =>
    by_cases same : head = query
    · subst head; simp [lookup, takeClass]
    · simpa [lookup, takeClass, same, Ne.symm same] using ih

theorem initial_equivalent_empty (values : List Value) : Equivalent (initial values) [] := by
  intro query
  exact singleton_lookup _ query

theorem explicit_valid {partition : RawPartition} (valid : Valid partition) (edges : List UnionEdge) :
    Valid (mergeExplicit partition edges) := by
  induction edges generalizing partition with
  | nil => exact valid
  | cons edge rest ih => exact ih (merge_valid valid edge.left edge.right)

theorem explicit_equivalent {first second : RawPartition} (fv : Valid first) (sv : Valid second)
    (equivalent : Equivalent first second) (edges : List UnionEdge) :
    Equivalent (mergeExplicit first edges) (mergeExplicit second edges) := by
  induction edges generalizing first second with
  | nil => exact equivalent
  | cons edge rest ih =>
    exact ih (merge_valid fv edge.left edge.right) (merge_valid sv edge.left edge.right)
      (merge_equivalent fv sv equivalent edge.left edge.right)

/-- Explicit Union classes do not depend on enumerating any stored roots.
Singleton lookup fallback provides exactly the missing initial classes. -/
theorem explicit_independent (values : List Value) (edges : List UnionEdge) :
    Equivalent (mergeExplicit (initial values) edges) (mergeExplicit [] edges) :=
  explicit_equivalent (initial_valid values) valid_nil (initial_equivalent_empty values) edges

end Eggshell.QuotientBuilder.Partition
