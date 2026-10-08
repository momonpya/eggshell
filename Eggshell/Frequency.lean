module

public import Std.Data.HashMap.Lemmas

@[expose] public section
namespace Eggshell.Frequency

/-- The reference counts every occurrence in an already deduplicated document
row. Empty rows represent owners that do not compile to searchable text. -/
def count (rows : List (List String)) (unit : String) : Nat :=
  (rows.map (List.count unit)).sum

@[simp] theorem count_nil (unit : String) : count [] unit = 0 := rfl

@[simp] theorem count_cons (row : List String) (rows : List (List String)) (unit : String) :
    count (row :: rows) unit = row.count unit + count rows unit := by
  simp [count]

theorem count_append (left right : List (List String)) (unit : String) :
    count (left ++ right) unit = count left unit + count right unit := by
  simp [count, List.sum_append]

/-- Full Nat-map computation retained as the search semantics oracle. -/
def fullUnits (counts : Std.HashMap String Nat) (units : List String) : Std.HashMap String Nat :=
  units.foldl (fun counts unit => counts.insert unit (counts.getD unit 0 + 1)) counts

def full (rows : List (List String)) : Std.HashMap String Nat :=
  rows.foldl fullUnits {}

theorem fullUnits_exact (counts : Std.HashMap String Nat) (units : List String) (unit : String) :
    (fullUnits counts units).getD unit 0 = counts.getD unit 0 + units.count unit := by
  induction units generalizing counts with
  | nil => simp [fullUnits]
  | cons head tail ih =>
      simp only [fullUnits, List.foldl_cons]
      rw [← fullUnits, ih, Std.HashMap.getD_insert]
      by_cases same : head = unit
      · subst head; simp [Nat.add_assoc, Nat.add_comm]
      · simp [same, beq_iff_eq]

theorem full_rows_exact (rows : List (List String)) (counts : Std.HashMap String Nat)
    (unit : String) :
    (rows.foldl fullUnits counts).getD unit 0 = counts.getD unit 0 + count rows unit := by
  induction rows generalizing counts with
  | nil => simp
  | cons row rest ih =>
      simp only [List.foldl_cons]
      rw [ih, fullUnits_exact, count_cons]
      omega

theorem full_exact (rows : List (List String)) (unit : String) :
    (full rows).getD unit 0 = count rows unit := by
  simp [full, full_rows_exact]

/-- Signed intermediate counts permit exact subtraction without silently
clamping an invalid intermediate state to zero. Final nonnegativity follows
from the certified current owner sequence. -/
def change (counts : Std.HashMap String Int) (delta : Int) (unit : String) :
    Std.HashMap String Int :=
  let next := counts.getD unit 0 + delta
  if next = 0 then counts.erase unit else counts.insert unit next

theorem change_exact (counts : Std.HashMap String Int) (delta : Int) (key unit : String) :
    (change counts delta key).getD unit 0 =
      if key == unit then counts.getD unit 0 + delta else counts.getD unit 0 := by
  by_cases zero : counts.getD key 0 + delta = 0
  · have update : change counts delta key = counts.erase key := if_pos zero
    rw [update, Std.HashMap.getD_erase]
    by_cases same : key = unit
    · subst key; simp [zero]
    · simp [same]
  · have update : change counts delta key = counts.insert key (counts.getD key 0 + delta) :=
      if_neg zero
    rw [update, Std.HashMap.getD_insert]
    by_cases same : key = unit
    · subst key; simp
    · simp [same]

def NoZeros (counts : Std.HashMap String Int) : Prop :=
  ∀ (unit : String) (value : Int), counts[unit]? = some value → value ≠ 0

theorem change_no_zeros (counts : Std.HashMap String Int) (valid : NoZeros counts)
    (delta : Int) (key : String) : NoZeros (change counts delta key) := by
  intro unit value found
  dsimp [change] at found
  split at found <;> rename_i zero
  · rw [Std.HashMap.getElem?_erase] at found
    by_cases same : key = unit
    · subst key; simp at found
    · simp [same] at found
      exact valid unit value found
  · rw [Std.HashMap.getElem?_insert] at found
    by_cases same : key = unit
    · subst key; simp at found
      simpa [← found] using zero
    · simp [same] at found
      exact valid unit value found

def adjustUnits (counts : Std.HashMap String Int) (delta : Int) (units : List String) :
    Std.HashMap String Int := units.foldl (fun counts unit => change counts delta unit) counts

def adjust (counts : Std.HashMap String Int) (delta : Int) (rows : List (List String)) :
    Std.HashMap String Int := rows.foldl (fun counts row => adjustUnits counts delta row) counts

theorem adjustUnits_exact (counts : Std.HashMap String Int) (delta : Int)
    (units : List String) (unit : String) :
    (adjustUnits counts delta units).getD unit 0 =
      counts.getD unit 0 + delta * (units.count unit : Int) := by
  induction units generalizing counts with
  | nil => simp [adjustUnits]
  | cons head tail ih =>
      simp only [adjustUnits, List.foldl_cons]
      rw [← adjustUnits, ih, change_exact]
      by_cases same : head = unit
      · subst head
        simp [Int.mul_add, Int.add_assoc, Int.add_comm, Int.add_left_comm]
      · simp [same, beq_iff_eq]

theorem adjust_exact (counts : Std.HashMap String Int) (delta : Int)
    (rows : List (List String)) (unit : String) :
    (adjust counts delta rows).getD unit 0 =
      counts.getD unit 0 + delta * (count rows unit : Int) := by
  induction rows generalizing counts with
  | nil => simp [adjust]
  | cons row rest ih =>
      simp only [adjust, List.foldl_cons]
      rw [← adjust, ih, adjustUnits_exact, count_cons]
      simp [Int.mul_add, Int.add_assoc]

theorem adjustUnits_no_zeros (counts : Std.HashMap String Int) (valid : NoZeros counts)
    (delta : Int) (units : List String) : NoZeros (adjustUnits counts delta units) := by
  induction units generalizing counts with
  | nil => exact valid
  | cons head tail ih =>
      exact ih _ (change_no_zeros counts valid delta head)

theorem adjust_no_zeros (counts : Std.HashMap String Int) (valid : NoZeros counts)
    (delta : Int) (rows : List (List String)) : NoZeros (adjust counts delta rows) := by
  induction rows generalizing counts with
  | nil => exact valid
  | cons head tail ih =>
      exact ih _ (adjustUnits_no_zeros counts valid delta head)

structure Index (rows : List (List String)) where
  counts : Std.HashMap String Int
  exact : ∀ unit, counts.getD unit 0 = (count rows unit : Int)
  noZeros : NoZeros counts

def Index.empty : Index [] := ⟨{}, by intro unit; simp, by intro unit value found; simp at found⟩

/-- A frequency update requires an exact multiset difference, rather than
depending on a hash-table traversal order or a monotone-only insertion API. -/
def Index.replace {before : List (List String)} (previous : Index before)
    (after removed added : List (List String))
    (difference : ∀ unit, count before unit + count added unit =
      count after unit + count removed unit) : Index after where
  counts := adjust (adjust previous.counts (-1) removed) 1 added
  exact := by
    intro unit
    rw [adjust_exact, adjust_exact, previous.exact]
    have equation := difference unit
    simp
    omega
  noZeros := adjust_no_zeros _ (adjust_no_zeros _ previous.noZeros _ _) _ _

structure CommonPrefix (before after : List α) where
  retained : List α
  removed : List α
  added : List α
  old : before = retained ++ removed
  current : after = retained ++ added

def commonPrefix [DecidableEq α] : (before after : List α) → CommonPrefix before after
  | [], after => ⟨[], [], after, rfl, rfl⟩
  | head :: tail, [] => ⟨[], head :: tail, [], rfl, rfl⟩
  | head :: tail, next :: rest =>
      if same : head = next then
        let continued := commonPrefix tail rest
        ⟨head :: continued.retained, continued.removed, continued.added,
          congrArg (List.cons head) continued.old,
          by simpa only [same, List.cons_append] using congrArg (List.cons head) continued.current⟩
      else ⟨[], head :: tail, next :: rest, rfl, rfl⟩
termination_by before _ => before.length

/-- Unchanged prefix and suffix never have their terms rescanned. The affected
middle may be larger than the minimal edit set, but retains exact semantics for
arbitrary reorderings, duplicates, insertions, removals and corrections. -/
structure Region (before after : List α) where
  left : List α
  removed : List α
  added : List α
  right : List α
  old : before = left ++ removed ++ right
  current : after = left ++ added ++ right

def affectedRegion [DecidableEq α] (before after : List α) : Region before after :=
  let start := commonPrefix before after
  let ending := commonPrefix start.removed.reverse start.added.reverse
  { left := start.retained
    removed := ending.removed.reverse
    added := ending.added.reverse
    right := ending.retained.reverse
    old := by
      have rest := congrArg List.reverse ending.old
      simp only [List.reverse_reverse, List.reverse_append] at rest
      exact start.old.trans ((congrArg (start.retained ++ ·) rest).trans
        (List.append_assoc _ _ _).symm)
    current := by
      have rest := congrArg List.reverse ending.current
      simp only [List.reverse_reverse, List.reverse_append] at rest
      exact start.current.trans ((congrArg (start.retained ++ ·) rest).trans
        (List.append_assoc _ _ _).symm) }

/-- Reuse a certified prefix, subtract the old suffix and add the new suffix.
No prefix terms are traversed. This also handles duplicate owners and arbitrary
reordering; reordering can repair a larger suffix, but never changes semantics. -/
def Index.revise {before : List (List String)} (previous : Index before)
    (retained removed added : List (List String)) (same : before = retained ++ removed) :
    Index (retained ++ added) :=
  { counts := adjust (adjust previous.counts (-1) removed) 1 added
    exact := by
      intro unit
      rw [adjust_exact, adjust_exact, previous.exact, same, count_append, count_append]
      simp
      omega
    noZeros := adjust_no_zeros _ (adjust_no_zeros _ previous.noZeros _ _) _ _ }

theorem Index.read_exact (rows : List (List String)) (index : Index rows) (unit : String) :
    (index.counts.getD unit 0).toNat = (full rows).getD unit 0 := by
  rw [index.exact, full_exact]; simp

end Eggshell.Frequency
