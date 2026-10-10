module
public import Eggshell.Partition
@[expose] public section
namespace Eggshell.QuotientBuilder.Partition

theorem insertMembers_lookup (index : RepresentativeIndex.T) (representative query : Value)
    (members : List Value) :
    (RepresentativeIndex.insertMembers representative index members).getD query query =
      if query ∈ members then representative else index.getD query query := by
  induction members generalizing index with
  | nil => rfl
  | cons head tail ih =>
    rw [RepresentativeIndex.insertMembers, ih, Std.HashMap.getD_insert]
    by_cases present : query ∈ tail
    · simp only [List.mem_cons, present, or_true, ↓reduceIte]
    · by_cases equal : head = query
      · subst head; simp [present]
      · simp only [List.mem_cons, present, Ne.symm equal, or_false,
          show (head == query) = false from by simpa using equal, Bool.false_eq_true, ↓reduceIte]

def Heads (classes : List EquivalenceClass) : Prop :=
  ∀ item ∈ classes, ∀ fallback, item.members.headD fallback = item.representative

theorem build_lookup (index : RepresentativeIndex.T) (classes : List EquivalenceClass)
    (valid : Valid (classes.map (·.members))) (heads : Heads classes) (query : Value) :
    (RepresentativeIndex.build index classes).getD query query =
      if query ∈ (classes.map (·.members)).flatten then
        (lookup (classes.map (·.members)) query).headD query
      else index.getD query query := by
  induction classes generalizing index with
  | nil => rfl
  | cons head tail ih =>
    obtain ⟨_, tailValid, _, apart⟩ := valid_cons.mp valid
    have tailHeads : Heads tail := fun item member => heads item (by simp [member])
    simp only [RepresentativeIndex.build, ih _ tailValid tailHeads, List.map_cons,
      List.flatten_cons, List.mem_append, lookup_cons]
    by_cases inTail : query ∈ (tail.map (·.members)).flatten
    · have outside : query ∉ head.members := fun inside => apart query inside inTail
      simp only [inTail, outside, false_or, ↓reduceIte]
    · rw [insertMembers_lookup]
      by_cases inHead : query ∈ head.members
      · simp only [inTail, inHead, true_or, ↓reduceIte, heads head (by simp) query]
      · simp only [inTail, inHead, or_self, ↓reduceIte]

theorem class_certificate {members : RawClass} {item : EquivalenceClass}
    (certified : EquivalenceClass.certify? members = some item) :
    item.members = members ∧ ∀ fallback, members.headD fallback = item.representative := by
  cases members with
  | nil => simp [EquivalenceClass.certify?] at certified
  | cons head tail =>
    simp only [EquivalenceClass.certify?] at certified
    split at certified
    · cases Option.some.inj certified
      exact ⟨rfl, fun _ => rfl⟩
    · contradiction

theorem classes_certificate {partition : RawPartition} {classes : List EquivalenceClass}
    (certified : partition.mapM EquivalenceClass.certify? = some classes) :
    classes.map (·.members) = partition ∧ Heads classes := by
  induction partition generalizing classes with
  | nil =>
    have empty : classes = [] := by simpa using certified.symm
    subst classes
    exact ⟨rfl, by simp [Heads]⟩
  | cons head tail ih =>
    cases first : EquivalenceClass.certify? head with
    | none => simp [List.mapM_cons, first] at certified
    | some item =>
      cases rest : tail.mapM EquivalenceClass.certify? with
      | none => simp [List.mapM_cons, first, rest] at certified
      | some items =>
        have joined : classes = item :: items := by simpa [List.mapM_cons, first, rest] using certified.symm
        subst classes
        have one := class_certificate first
        have others := ih rest
        refine ⟨by simp only [List.map_cons, one.1, others.1], ?_⟩
        intro next member fallback
        rcases List.mem_cons.mp member with same | later
        · subst next; rw [one.1]; exact one.2 fallback
        · exact others.2 next later fallback

/-- The certified runtime HashMap chooses the head of exactly the raw
partition class. Class disjointness rules out later insertions overwriting it. -/
theorem certify_lookup {partition : RawPartition} (valid : Valid partition) {quotient : Quotient}
    (certified : certify partition = some quotient) (query : Value) :
    quotient.canonical query = (lookup partition query).headD query := by
  cases classes : partition.mapM EquivalenceClass.certify? with
  | none => simp [certify, classes] at certified
  | some items =>
    simp [certify, classes] at certified
    subst quotient
    have accepted := classes_certificate classes
    have result := build_lookup {} items (accepted.1 ▸ valid) accepted.2 query
    simp only [Quotient.canonical] at ⊢
    rw [accepted.1] at result
    rw [result]
    split
    · rfl
    · rename_i missing
      simp [lookup_missing partition query missing]

theorem lookup_related {partition : RawPartition} (valid : Valid partition) (left right : Value)
    (member : right ∈ lookup partition left) : lookup partition right = lookup partition left := by
  rcases lookup_origin partition left with stored | singleton
  · exact lookup_member valid stored member
  · rw [singleton] at member
    have equal := List.mem_singleton.mp member
    subst right
    rfl

theorem lookup_head {partition : RawPartition} (valid : Valid partition) (query : Value) :
    lookup partition ((lookup partition query).headD query) = lookup partition query := by
  apply lookup_related valid
  have contains := lookup_contains partition query
  cases found : lookup partition query with
  | nil => simp [found] at contains
  | cons head tail => simp

theorem heads_equal {partition : RawPartition} (valid : Valid partition) (left right : Value) :
    (lookup partition left).headD left = (lookup partition right).headD right ↔
      right ∈ lookup partition left := by
  constructor
  · intro heads
    have classes : lookup partition left = lookup partition right := by
      rw [← lookup_head valid left, heads, lookup_head valid right]
    rw [classes]
    exact lookup_contains partition right
  · intro member
    rw [lookup_related valid left right member]
    have contains := lookup_contains partition left
    cases found : lookup partition left with
    | nil => simp [found] at contains
    | cons head tail => rfl

end Eggshell.QuotientBuilder.Partition
