module
public import Eggshell.HashDistinct

@[expose] public section
namespace Eggshell

universe u
variable {α : Type u}

/-- The first full-key match wins, including duplicate keys. Nat keys remain
sparse; an untrusted large locator cannot request a proportional allocation. -/
def firstTable (key : α → Nat) (rows : List α) : Std.HashMap Nat α :=
  rows.foldr (fun row table => table.insert (key row) row) {}

theorem firstTable_exact (key : α → Nat) (rows : List α) (query : Nat) :
    (firstTable key rows)[query]? = rows.find? (fun row => key row == query) := by
  induction rows with
  | nil => simp [firstTable]
  | cons row tail ih =>
      change ((firstTable key tail).insert (key row) row)[query]? =
        (row :: tail).find? (fun row => key row == query)
      rw [Std.HashMap.getElem?_insert, List.find?_cons, ih]
      cases key row == query <;> rfl

structure FirstIndex (key : α → Nat) (rows : List α) where
  table : Std.HashMap Nat α
  exact : ∀ query, table[query]? = rows.find? (fun row => key row == query)

def FirstIndex.make (key : α → Nat) (rows : List α) : FirstIndex key rows :=
  ⟨firstTable key rows, firstTable_exact key rows⟩

variable {key : α → Nat} {rows : List α}

def FirstIndex.read (index : FirstIndex key rows) (query : Nat) : Option α :=
  index.table[query]?

theorem FirstIndex.read_exact (index : FirstIndex key rows) (query : Nat) :
    index.read query = rows.find? (fun row => key row == query) := index.exact query

end Eggshell
