module

public import Std.Data.DHashMap

@[expose] public section
namespace Eggshell.ExactMemo

variable {α β : Type} [BEq α] [LawfulBEq α] [Hashable α]

/-- Every value carries equality with this function at its actual lookup key.
The dependent table cannot contain an unchecked or foreign-key result. -/
abbrev Table (f : α → β) := Std.DHashMap α (fun key => {value : β // value = f key})

def read (f : α → β) (table : Table f) (key : α) : β × Table f :=
  match table.get? key with
  | some checked => (checked.val, table)
  | none =>
      let value := f key
      (value, table.insert key ⟨value, rfl⟩)

theorem read_exact (f : α → β) (table : Table f) (key : α) :
    (read f table key).1 = f key := by
  unfold read
  cases found : table.get? key with
  | none => rfl
  | some checked => exact checked.property

def loop (f : α → β) (table : Table f) (items : List α) (kept : List β) : List β :=
  match items with
  | [] => kept.reverse
  | item :: rest =>
      let next := read f table item
      loop f next.2 rest (next.1 :: kept)

theorem loop_exact (f : α → β) (table : Table f) (items : List α) (kept : List β) :
    loop f table items kept = kept.reverse ++ items.map f := by
  induction items generalizing table kept with
  | nil => simp [loop]
  | cons item rest ih => simp [loop, ih, read_exact, List.reverse_cons, List.append_assoc]

def map (f : α → β) (items : List α) : List β := loop f {} items []

theorem map_exact (f : α → β) (items : List α) : map f items = items.map f := by
  simp [map, loop_exact]

/-- Preserve order, multiplicity and absent results. Only evaluation is shared. -/
def filterMap (f : α → Option β) (items : List α) : List β :=
  (map f items).filterMap id

theorem filterMap_exact (f : α → Option β) (items : List α) :
    filterMap f items = items.filterMap f := by
  simp [filterMap, map_exact, List.filterMap_map]

end Eggshell.ExactMemo
