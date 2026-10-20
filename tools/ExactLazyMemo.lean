module

public import Std

@[expose] public section
namespace Eggshell.ExactLazyMemo

universe u
variable {α : Type u}

/-- A finite address tree with lazy branches and certified leaf values.
Only paths actually read are constructed; repeated reads share Lean's Thunks.
Getter fields keep the indexed recursive type strictly positive. Construction
uses Thunk.fn, whose standard compiler equality preserves cached access. -/
inductive Tree (f : Nat → α) : Nat → Nat → Type u where
  | leaf (saved : Unit → {value : α // value = f first}) : Tree f first 0
  | branch (left : Unit → Tree f first depth)
      (right : Unit → Tree f (first + 2 ^ depth) depth) : Tree f first (depth + 1)

def make (f : Nat → α) (first : Nat) : (depth : Nat) → Tree f first depth
  | 0 => .leaf (Thunk.mk fun _ => ⟨f first, rfl⟩).fn
  | depth + 1 => .branch (Thunk.mk fun _ => make f first depth).fn
      (Thunk.mk fun _ => make f (first + 2 ^ depth) depth).fn

/-- Out-of-domain addresses retain the exact result; they do not alias a leaf. -/
def read (f : Nat → α) {first depth : Nat} (tree : Tree f first depth) (key : Nat) : α :=
  match tree with
  | .leaf saved => if key = first then (saved ()).val else f key
  | .branch left right =>
      if key < first + 2 ^ (depth - 1) then read f (left ()) key else read f (right ()) key
termination_by depth

theorem read_exact (f : Nat → α) {first depth : Nat} (tree : Tree f first depth) (key : Nat) :
    read f tree key = f key := by
  induction depth generalizing first with
  | zero =>
      cases tree with
      | leaf saved =>
          simp only [read]
          split
          next same => rw [same]; exact (saved ()).property
          next => rfl
  | succ depth ih =>
      cases tree with
      | branch left right =>
          simp only [read]
          split <;> apply ih

end Eggshell.ExactLazyMemo
