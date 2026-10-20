module
public import tools.FirstIndex

@[expose] public section
namespace Eggshell

universe u
variable {α : Type u}

/-- One prepared positional directory, tied to the complete original list. -/
structure OwnedRows (rows : List α) where
  values : Array α
  lookup : ∀ index : Nat, values[index]? = rows[index]?

def OwnedRows.make (rows : List α) : OwnedRows rows :=
  ⟨rows.toArray, fun _ => List.getElem?_toArray⟩

def OwnedRows.reference (rows : List α) (index : Nat) : Option {row // row ∈ rows} :=
  match present : rows[index]? with
  | none => none
  | some row => some ⟨row, List.mem_of_getElem? present⟩

theorem OwnedRows.reference_value (rows : List α) (index : Nat) :
    (OwnedRows.reference rows index).map Subtype.val = rows[index]? := by
  unfold OwnedRows.reference
  split
  · rename_i missing
    exact missing.symm
  · rename_i row present
    change some row = rows[index]?
    exact present.symm

variable {rows : List α}

def OwnedRows.get (directory : OwnedRows rows) (index : Nat) : Option {row // row ∈ rows} :=
  match present : directory.values[index]? with
  | none => none
  | some row => some ⟨row, List.mem_of_getElem? ((directory.lookup index).symm.trans present)⟩

theorem OwnedRows.get_exact (directory : OwnedRows rows) (index : Nat) :
    directory.get index = OwnedRows.reference rows index := by
  unfold OwnedRows.get OwnedRows.reference
  split
  · rename_i missing
    have original := (directory.lookup index).symm.trans missing
    split
    · rfl
    · rename_i row present
      rw [original] at present
      contradiction
  · rename_i row indexed
    have original := (directory.lookup index).symm.trans indexed
    split
    · rename_i missing
      rw [original] at missing
      contradiction
    · rename_i other present
      have same := Option.some.inj (original.symm.trans present)
      cases same
      rfl

/-- Preserve left-to-right effects and the first error while avoiding repeated
copying of the already accepted prefix. filterMapM uses its standard tail loop. -/
theorem append_fold_filterMapM (read : α → Except ε (Option β)) (items : List α)
    (initial : List β) :
    items.foldlM (fun values item => do
      match ← read item with
      | none => pure values
      | some value => pure (values ++ [value])) initial =
    (do let values ← items.filterMapM read; pure (initial ++ values)) := by
  induction items generalizing initial with
  | nil => simp
  | cons head tail ih =>
      rw [List.foldlM_cons, List.filterMapM_cons]
      cases effect : read head with
      | error message => rfl
      | ok value =>
          cases value with
          | none =>
              change tail.foldlM _ initial = _
              rw [ih]
              rfl
          | some value =>
              change tail.foldlM _ (initial ++ [value]) = _
              rw [ih]
              cases result : tail.filterMapM read with
              | error message => rfl
              | ok values =>
                  simp only [List.append_assoc, List.singleton_append]
                  rfl

end Eggshell
