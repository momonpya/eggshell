module
public import Std.Data.HashMap.Lemmas

@[expose] public section
namespace PreparedPagePoints

/-- A decoded immutable leaf can prepare its point lookups once. Inserting
from the right preserves List.find?'s first occurrence, including tombstones.
This is a research component; it does not change the persistent page format. -/
def compile (rows : List (String × α)) : Std.HashMap String α :=
  rows.foldr (fun row table => table.insert row.1 row.2) {}

theorem lookup_exact (rows : List (String × α)) (key : String) :
    (compile rows)[key]? = (rows.find? (fun row => row.1 == key)).map Prod.snd := by
  induction rows with
  | nil => simp [compile]
  | cons row rest ih =>
    change ((compile rest).insert row.1 row.2)[key]? = _
    simp only [Std.HashMap.getElem?_insert]
    by_cases same : row.1 = key
    · simp [same]
    · simp [same,ih]

theorem entries_bounded (rows : List (String × α)) :
    (compile rows).size ≤ rows.length := by
  induction rows with
  | nil => simp [compile]
  | cons row rest ih =>
    change ((compile rest).insert row.1 row.2).size ≤ rest.length+1
    have bound : ((compile rest).insert row.1 row.2).size ≤ (compile rest).size+1 :=
      Std.HashMap.size_insert_le
    omega

def read (table : Std.HashMap String (Option α)) (key : String) : Option α :=
  table[key]?.join

theorem read_exact (rows : List (String × Option α)) (key : String) :
    read (compile rows) key = (rows.find? (fun row => row.1 == key)).bind Prod.snd := by
  rw [read,lookup_exact]
  cases rows.find? (fun row => row.1 == key) <;> rfl

end PreparedPagePoints
