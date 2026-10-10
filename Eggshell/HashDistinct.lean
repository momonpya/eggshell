module
public import Eggshell.Value
public import Std.Data.HashMap.Lemmas
@[expose] public section
namespace Eggshell.HashDistinct

def step [BEq α] [Hashable α] (state : Std.HashMap α Unit × List α) (value : α) :
    Std.HashMap α Unit × List α :=
  if state.1.contains value then state else (state.1.insert value (), value :: state.2)

def Seen [BEq α] [Hashable α] (index : Std.HashMap α Unit) (items : List α) : Prop :=
  ∀ value, index.contains value = items.contains value

theorem seen_insert [BEq α] [LawfulBEq α] [Hashable α]
    (index : Std.HashMap α Unit) (items : List α) (known : Seen index items) (value : α) :
    Seen (index.insert value ()) (value :: items) := by
  intro query
  simp only [Std.HashMap.contains_insert, List.contains_cons, known query]
  simp [BEq.comm]

/-- A streaming membership fold records every encountered value, including
duplicates, with the same complete membership as the list specification. -/
theorem fold_contains [BEq α] [LawfulBEq α] [Hashable α]
    (input : List α) (index : Std.HashMap α Unit) (query : α) :
    (input.foldl (fun known value => known.insert value ()) index).contains query =
      (index.contains query || input.contains query) := by
  induction input generalizing index with
  | nil => simp
  | cons head tail ih =>
      simp only [List.foldl_cons, ih, Std.HashMap.contains_insert, List.contains_cons]
      simp only [BEq.comm, Bool.or_assoc, Bool.or_left_comm]

theorem loop_reference [BEq α] [LawfulBEq α] [Hashable α]
    (input : List α) (index : Std.HashMap α Unit) (result : List α) (known : Seen index result) :
    (input.foldl step (index, result)).2.reverse = List.eraseDupsBy.loop (· == ·) input result := by
  induction input generalizing index result with
  | nil => rfl
  | cons head tail ih =>
    simp only [List.foldl_cons, step, List.eraseDupsBy.loop, ← List.contains_eq_any_beq, ← known head]
    cases found : index.contains head with
    | false => exact ih _ _ (seen_insert index result known head)
    | true => exact ih _ _ known

theorem reference [BEq α] [LawfulBEq α] [Hashable α] (input : List α) :
    hashDistinct input = input.eraseDups :=
  loop_reference input {} [] (by intro value; simp)

theorem mem [BEq α] [LawfulBEq α] [Hashable α] (value : α) (input : List α) :
    value ∈ hashDistinct input ↔ value ∈ input := by
  rw [reference, List.mem_eraseDups]

theorem loop_nodup [BEq α] [LawfulBEq α] (input result : List α) (valid : result.Nodup) :
    (List.eraseDupsBy.loop (· == ·) input result).Nodup := by
  induction input generalizing result with
  | nil => simpa [List.eraseDupsBy.loop, List.Nodup, List.pairwise_reverse, ne_comm] using valid
  | cons head tail ih =>
    simp only [List.eraseDupsBy.loop, ← List.contains_eq_any_beq]
    cases found : result.contains head with
    | true => exact ih result valid
    | false =>
      apply ih
      exact List.nodup_cons.mpr ⟨by simpa using found, valid⟩

theorem nodup [BEq α] [LawfulBEq α] [Hashable α] (input : List α) :
    (hashDistinct input).Nodup := by
  rw [reference]
  exact loop_nodup input [] (by simp)

theorem length_le [BEq α] [LawfulBEq α] [Hashable α] (input : List α) :
    (hashDistinct input).length ≤ input.length := by
  exact (nodup input).length_le_of_subset (fun value member => (mem value input).mp member)

theorem erase_nodup [BEq α] [LawfulBEq α] (input : List α) (valid : input.Nodup) :
    input.eraseDups = input := by
  induction input with
  | nil => rfl
  | cons head tail ih =>
    have valid := List.nodup_cons.mp valid
    rw [List.eraseDups_cons]
    have filtered : tail.filter (fun value => !value == head) = tail := by
      apply List.filter_eq_self.mpr
      intro value member
      have different : value ≠ head := by intro equal; subst value; exact valid.1 member
      simpa using different
    rw [filtered, ih valid.2]

theorem unchanged [BEq α] [LawfulBEq α] [Hashable α] (input : List α) (valid : input.Nodup) :
    hashDistinct input = input := (reference input).trans (erase_nodup input valid)

/-- Validate uniqueness without constructing a second list or comparing every
pair. A hash nominates a bucket; the full value still decides identity. -/
def uniqueLoop [BEq α] [Hashable α] (seen : Std.HashMap α Unit) : List α → Bool
  | [] => true
  | value :: rest => !seen.contains value && uniqueLoop (seen.insert value ()) rest

private theorem negated_true (value : Bool) : (!value) = true ↔ value = false := by
  cases value <;> decide

theorem uniqueLoop_exact [BEq α] [LawfulBEq α] [Hashable α]
    (input : List α) (seen : Std.HashMap α Unit) :
    uniqueLoop seen input = true ↔
      input.Nodup ∧ ∀ value ∈ input, seen.contains value = false := by
  induction input generalizing seen with
  | nil => simp [uniqueLoop]
  | cons head tail ih =>
    simp only [uniqueLoop, Bool.and_eq_true, negated_true, ih,
      List.nodup_cons, List.mem_cons, Std.HashMap.contains_insert,
      Bool.or_eq_false_iff, beq_eq_false_iff_ne]
    constructor
    · rintro ⟨absent, unique, observations⟩
      refine ⟨⟨?_, unique⟩, ?_⟩
      · intro member
        exact (observations head member).1 rfl
      · intro value member
        rcases member with rfl | member
        · exact absent
        · exact (observations value member).2
    · rintro ⟨⟨separated, unique⟩, observations⟩
      refine ⟨observations head (Or.inl rfl), unique, ?_⟩
      intro value member
      exact ⟨by intro same; subst value; exact separated member,
        observations value (Or.inr member)⟩

def unique [BEq α] [Hashable α] (input : List α) : Bool := uniqueLoop {} input

theorem unique_exact [BEq α] [LawfulBEq α] [Hashable α] (input : List α) :
    unique input = true ↔ input.Nodup := by
  simp [unique, uniqueLoop_exact]

end Eggshell.HashDistinct
