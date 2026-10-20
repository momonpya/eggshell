module

public import Eggshell.HashDistinct
public import Std.Data.HashSet.Lemmas

@[expose] public section
namespace Eggshell.KeyedOverride

variable {α β : Type} [BEq β] [LawfulBEq β] [Hashable β]

def put (key : α → β) (previous : List α) (item : α) : List α :=
  item :: previous.filter (fun old => !(key item == key old))

def reference (key : α → β) (previous added : List α) : List α :=
  added.foldl (put key) previous

/-- Right-to-left specification: new keys keep their latest complete payload;
untouched prior entries, including duplicates, remain in their original order. -/
def collect (key : α → β) (seen : Std.HashSet β) (items previous : List α) : List α :=
  match items with
  | [] => previous.filter (fun item => !seen.contains (key item))
  | item :: rest =>
      if seen.contains (key item) then collect key seen rest previous
      else item :: collect key (seen.insert (key item)) rest previous

private theorem insert_filter (key : α → β) (seen : Std.HashSet β) (value : β)
    (rows : List α) :
    rows.filter (fun item => !(seen.insert value).contains (key item)) =
      (rows.filter (fun item => !(value == key item))).filter
        (fun item => !seen.contains (key item)) := by
  rw [List.filter_filter]
  apply List.filter_congr
  intro item _
  simp [Std.HashSet.contains_insert, Bool.not_or, Bool.and_comm]

private theorem seen_filter (key : α → β) (seen : Std.HashSet β) (value : β)
    (present : seen.contains value = true) (rows : List α) :
    (rows.filter (fun item => !(value == key item))).filter
        (fun item => !seen.contains (key item)) =
      rows.filter (fun item => !seen.contains (key item)) := by
  rw [List.filter_filter]
  apply List.filter_congr
  intro item _
  by_cases same : value = key item
  · have present : seen.contains (key item) = true := same ▸ present
    simp [present]
  · simp [beq_eq_false_iff_ne.mpr same]

private theorem filter_put (key : α → β) (seen : Std.HashSet β)
    (rows : List α) (item : α) :
    (put key rows item).filter (fun old => !seen.contains (key old)) =
      if seen.contains (key item) then rows.filter (fun old => !seen.contains (key old))
      else item :: rows.filter (fun old => !(seen.insert (key item)).contains (key old)) := by
  unfold put
  rw [List.filter_cons]
  cases present : seen.contains (key item) with
  | false =>
      simp only [Bool.not_false, Bool.false_eq_true, ↓reduceIte]
      exact congrArg (List.cons item) (insert_filter key seen (key item) rows).symm
  | true => simp [seen_filter key seen (key item) present rows]

theorem collect_exact (key : α → β) (seen : Std.HashSet β) (items previous : List α) :
    collect key seen items previous =
      (items.foldr (fun item rows => put key rows item) previous).filter
        (fun item => !seen.contains (key item)) := by
  induction items generalizing seen with
  | nil => rfl
  | cons item rest ih =>
      rw [List.foldr_cons, filter_put]
      unfold collect
      cases present : seen.contains (key item) <;> simp [ih]

private theorem collect_insert_seen (key : α → β) (seen : Std.HashSet β) (value : β)
    (present : seen.contains value = true) (items previous : List α) :
    collect key (seen.insert value) items previous = collect key seen items previous := by
  rw [collect_exact, collect_exact, insert_filter, seen_filter key seen value present]

/-- Tail-recursive implementation. The set is only an exact membership index;
the retained list carries every chosen original payload and its final order. -/
def loop (key : α → β) (seen : Std.HashSet β) (items kept : List α) :
    Std.HashSet β × List α :=
  match items with
  | [] => (seen, kept)
  | item :: rest =>
      let checked := seen.containsThenInsert (key item)
      if checked.1 then loop key checked.2 rest kept
      else loop key checked.2 rest (item :: kept)

theorem loop_exact (key : α → β) (seen : Std.HashSet β) (items kept previous : List α) :
    let result := loop key seen items kept
    result.2.reverse ++ previous.filter (fun item => !result.1.contains (key item)) =
      kept.reverse ++ collect key seen items previous := by
  induction items generalizing seen kept with
  | nil => rfl
  | cons item rest ih =>
      simp only [loop, collect, Std.HashSet.containsThenInsert_fst, Std.HashSet.containsThenInsert_snd]
      cases present : seen.contains (key item) with
      | true =>
          simp only [↓reduceIte]
          rw [ih, collect_insert_seen key seen (key item) present]
      | false =>
          simp only [Bool.false_eq_true, ↓reduceIte]
          rw [ih]
          simp [List.reverse_cons, List.append_assoc]

def merge (key : α → β) (previous added : List α) : List α :=
  let result := loop key {} added.reverse []
  result.2.reverse ++ previous.filter (fun item => !result.1.contains (key item))

theorem merge_exact (key : α → β) (previous added : List α) :
    merge key previous added = reference key previous added := by
  unfold merge
  rw [loop_exact, collect_exact]
  simp [reference]

end Eggshell.KeyedOverride
