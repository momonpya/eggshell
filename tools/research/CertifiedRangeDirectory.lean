module
public import Std
@[expose] public section

namespace Eggshell.Research.CertifiedRangeDirectory

variable {α : Type} (lower upper : α → String)

def contains (first limit key : String) : Bool := decide (first ≤ key ∧ key < limit)
def overlaps (first limit lo hi : String) : Bool := decide (lo ≤ limit ∧ first < hi)

/-- A branch carries the bounds of every original entry below it. The proof
is erased; a skipped branch cannot hide an entry matching the request. -/
inductive Tree : List α → Type where
  | empty : Tree []
  | leaf (value : α) : Tree [value]
  | branch {leftRows rightRows : List α} (first limit : String)
      (left : Tree leftRows) (right : Tree rightRows)
      (bounds : ∀ value ∈ leftRows ++ rightRows,
        first ≤ lower value ∧ upper value ≤ limit) : Tree (leftRows ++ rightRows)

def Tree.find? {rows : List α} (tree : Tree lower upper rows) (key : String) : Option α :=
  match tree with
  | .empty => none
  | .leaf value => if contains (lower value) (upper value) key then some value else none
  | .branch first limit left right _ =>
    if contains first limit key then (left.find? key).orElse (fun _ => right.find? key) else none

def Tree.anyOverlap {rows : List α} (tree : Tree lower upper rows) (first last : String) : Bool :=
  match tree with
  | .empty => false
  | .leaf value => overlaps first last (lower value) (upper value)
  | .branch lo hi left right _ =>
    overlaps first last lo hi && (left.anyOverlap first last || right.anyOverlap first last)

theorem contains_pruned (first limit key : String) (rows : List α)
    (bounds : ∀ value ∈ rows, first ≤ lower value ∧ upper value ≤ limit)
    (outside : contains first limit key = false) :
    ∀ value ∈ rows, contains (lower value) (upper value) key = false := by
  intro value member
  apply Bool.eq_false_iff.mpr
  intro matching
  have hit := of_decide_eq_true matching
  obtain ⟨lo,hi⟩ := bounds value member
  have inside : contains first limit key = true := by
    simp only [contains,decide_eq_true_eq]
    exact ⟨String.le_trans lo hit.1,Std.lt_of_lt_of_le hit.2 hi⟩
  simp [outside] at inside

theorem overlaps_pruned (first last lo hi : String) (rows : List α)
    (bounds : ∀ value ∈ rows, lo ≤ lower value ∧ upper value ≤ hi)
    (outside : overlaps first last lo hi = false) :
    ∀ value ∈ rows, overlaps first last (lower value) (upper value) = false := by
  intro value member
  apply Bool.eq_false_iff.mpr
  intro matching
  have hit := of_decide_eq_true matching
  obtain ⟨lowerBound,upperBound⟩ := bounds value member
  have inside : overlaps first last lo hi = true := by
    simp only [overlaps,decide_eq_true_eq]
    exact ⟨String.le_trans lowerBound hit.1,Std.lt_of_lt_of_le hit.2 upperBound⟩
  simp [outside] at inside

/-- Exact first-match refinement, including duplicate/overlapping inputs and
input order. No sorted-input assumption is smuggled into the reader. -/
theorem Tree.find_exact {rows : List α} (tree : Tree lower upper rows) (key : String) :
    Tree.find? lower upper tree key = rows.find? (fun value => contains (lower value) (upper value) key) := by
  induction tree with
  | empty => rfl
  | leaf value =>
    cases found : contains (lower value) (upper value) key <;> simp [Tree.find?,List.find?,found]
  | branch first limit left right bounds leftExact rightExact =>
    simp only [Tree.find?]
    split
    · rw [leftExact,rightExact,List.find?_append]
      cases List.find? (fun value => contains (lower value) (upper value) key) _ <;> rfl
    · have outside : contains first limit key = false := Bool.eq_false_iff.mpr ‹_›
      symm
      exact List.find?_eq_none.mpr (by simpa only [Bool.not_eq_true] using contains_pruned lower upper first limit key _ bounds outside)

theorem Tree.overlap_exact {rows : List α} (tree : Tree lower upper rows) (first last : String) :
    Tree.anyOverlap lower upper tree first last = rows.any (fun value => overlaps first last (lower value) (upper value)) := by
  induction tree with
  | empty => rfl
  | leaf value => simp [Tree.anyOverlap]
  | @branch leftRows rightRows lo hi left right bounds leftExact rightExact =>
    simp only [Tree.anyOverlap,leftExact,rightExact,List.any_append]
    by_cases inside : overlaps first last lo hi = true
    · simp [inside]
    · have outside := Bool.eq_false_iff.mpr inside
      have none := overlaps_pruned lower upper first last lo hi _ bounds outside
      have noHits : (List.any (leftRows ++ rightRows) fun value => overlaps first last (lower value) (upper value)) = false := by
        apply Bool.eq_false_iff.mpr
        intro found
        obtain ⟨value,member,matching⟩ := List.any_eq_true.mp found
        simp [none value member] at matching
      simpa [outside,List.any_append] using noHits.symm

structure Prepared (rows : List α) where
  first : String
  limit : String
  bounds : ∀ value ∈ rows, first ≤ lower value ∧ upper value ≤ limit
  tree : Tree lower upper rows

def empty : Prepared lower upper [] := ⟨"","",by simp,Tree.empty⟩
def singleton (value : α) : Prepared lower upper [value] :=
  ⟨lower value,upper value,by intro item present; obtain rfl := List.mem_singleton.mp present; exact ⟨String.le_refl _,String.le_refl _⟩,Tree.leaf value⟩

def Prepared.append {xs ys : List α} (left : Prepared lower upper xs) (right : Prepared lower upper ys) :
    Prepared lower upper (xs ++ ys) := by
  let first := if left.first ≤ right.first then left.first else right.first
  let limit := if left.limit ≤ right.limit then right.limit else left.limit
  have beforeLeft : first ≤ left.first := by dsimp [first]; split <;> grind
  have beforeRight : first ≤ right.first := by dsimp [first]; split <;> grind
  have afterLeft : left.limit ≤ limit := by dsimp [limit]; split <;> grind
  have afterRight : right.limit ≤ limit := by dsimp [limit]; split <;> grind
  have bounds : ∀ value ∈ xs ++ ys, first ≤ lower value ∧ upper value ≤ limit := by
    intro value member
    rcases List.mem_append.mp member with member | member
    · obtain ⟨lo,hi⟩ := left.bounds value member
      exact ⟨String.le_trans beforeLeft lo,String.le_trans hi afterLeft⟩
    · obtain ⟨lo,hi⟩ := right.bounds value member
      exact ⟨String.le_trans beforeRight lo,String.le_trans hi afterRight⟩
  exact ⟨first,limit,bounds,Tree.branch first limit left.tree right.tree bounds⟩

/-- The balanced directory is built once for a request, then shared by all
physical page visits. Existing immutable source pages remain the authority. -/
def prepare (rows : List α) : Prepared lower upper rows :=
  match rows with
  | [] => empty lower upper
  | [value] => singleton lower upper value
  | first :: second :: rest =>
    let values := first :: second :: rest
    let split := values.length/2
    let joined := Prepared.append lower upper (prepare (values.take split)) (prepare (values.drop split))
    Eq.mp (congrArg (Prepared lower upper) (List.take_append_drop split values)) joined
termination_by rows.length
decreasing_by all_goals simp only [List.length_take,List.length_drop,List.length_cons]; omega

end Eggshell.Research.CertifiedRangeDirectory
