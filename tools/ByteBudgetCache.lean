module
public import Std.Data.HashMap.Lemmas
@[expose] public section

namespace Eggshell.ByteBudgetCache

/-- The append-only slot array owns every retained allocation, including a
replaced value. Budgeting this array needs no table-wide sum on a hot lookup. -/
structure Slot (κ α : Type) where
  key : κ
  value : α
  charge : Nat

def allocated (slots : Array (Slot κ α)) : Nat :=
  slots.foldl (fun total slot => total+slot.charge) 0

structure Generation (κ α : Type) [BEq κ] [Hashable κ] (capacity : Nat) where
  slots : Array (Slot κ α) := #[]
  index : Std.HashMap κ Nat := {}
  bytes : Nat := 0
  exact : bytes = allocated slots := by rfl
  bounded : bytes ≤ capacity := by omega
  indexed : index.size ≤ slots.size := by simp

def Generation.find? [BEq κ] [Hashable κ] (generation : Generation κ α capacity)
    (key : κ) : Option α := do
  let position ← generation.index[key]?
  let slot ← generation.slots[position]?
  if slot.key == key then some slot.value else none

def Generation.insert? [BEq κ] [Hashable κ] [LawfulBEq κ] (generation : Generation κ α capacity)
    (slot : Slot κ α) : Option (Generation κ α capacity) :=
  if fits : generation.bytes+slot.charge ≤ capacity then
    some {
      slots := generation.slots.push slot
      index := generation.index.insert slot.key generation.slots.size
      bytes := generation.bytes+slot.charge
      exact := by
        rw [allocated,Array.foldl_push]
        exact congrArg (· + slot.charge) generation.exact
      bounded := fits
      indexed := by
        have growth : (generation.index.insert slot.key generation.slots.size).size ≤ generation.index.size+1 :=
          Std.HashMap.size_insert_le
        have prior := generation.indexed
        simp only [Array.size_push]
        omega }
  else none

theorem Generation.allocated_bounded [BEq κ] [Hashable κ]
    (generation : Generation κ α capacity) : allocated generation.slots ≤ capacity := by
  rw [← generation.exact]
  exact generation.bounded

theorem Generation.insert_find [BEq κ] [Hashable κ] [LawfulBEq κ]
    (generation : Generation κ α capacity) (slot : Slot κ α)
    (next : Generation κ α capacity) (inserted : generation.insert? slot = some next) :
    next.find? slot.key = some slot.value := by
  unfold insert? at inserted
  split at inserted
  · cases inserted
    simp [find?,Array.getElem?_push]
  · contradiction

/-- Two generations rotate as whole immutable ownership units. A caller can
read `recent` without changing either table; only a promotion or miss writes. -/
structure Cache (κ α : Type) [BEq κ] [Hashable κ] (generationCapacity : Nat) where
  recent : Generation κ α generationCapacity := {}
  previous : Generation κ α generationCapacity := {}

def Cache.find? [BEq κ] [Hashable κ] (cache : Cache κ α capacity) (key : κ) : Option α :=
  (cache.recent.find? key).orElse fun _ => cache.previous.find? key

def Cache.touch [BEq κ] [Hashable κ] [LawfulBEq κ] (cache : Cache κ α capacity)
    (slot : Slot κ α) : Cache κ α capacity :=
  match cache.recent.insert? slot with
  | some next => {cache with recent := next}
  | none => match ({} : Generation κ α capacity).insert? slot with
    | some next => ⟨next,cache.recent⟩
    | none => cache

theorem Cache.allocated_bounded [BEq κ] [Hashable κ] (cache : Cache κ α capacity) :
    allocated cache.recent.slots + allocated cache.previous.slots ≤ 2*capacity := by
  have := cache.recent.allocated_bounded
  have := cache.previous.allocated_bounded
  omega

theorem Cache.touch_recent [BEq κ] [Hashable κ] [LawfulBEq κ]
    (cache : Cache κ α capacity) (slot : Slot κ α) (fits : slot.charge ≤ capacity) :
    (cache.touch slot).recent.find? slot.key = some slot.value := by
  unfold touch
  split
  · rename_i next inserted
    exact Generation.insert_find _ _ _ inserted
  · split
    · rename_i next inserted
      exact Generation.insert_find _ _ _ inserted
    · rename_i rejected
      simp [Generation.insert?,fits] at rejected

end Eggshell.ByteBudgetCache
