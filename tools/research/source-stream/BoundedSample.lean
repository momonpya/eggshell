module
public import Std.Data.TreeMap.Lemmas

@[expose] public section
namespace Eggshell.BoundedSample

/-- Keep the least ranking keys, using a balanced tree whose resident size
is independent of the source population. The rank includes the original key
after the hash, so collisions still have a deterministic total order. -/
structure State (α : Type) (capacity : Nat) where
  entries : Std.TreeMap String α := ∅
  bounded : entries.size ≤ capacity

def empty : State α capacity := ⟨∅,by simp⟩

def State.insert (state : State α capacity) (key : String) (value : α) : State α capacity :=
  let next := state.entries.insert key value
  if bounded : next.size ≤ capacity then ⟨next,bounded⟩
  else
    have nonempty : next.isEmpty = false := by
      rw [Std.TreeMap.isEmpty_eq_size_eq_zero]
      simp only [beq_eq_false_iff_ne]
      omega
    let last := next.maxKey nonempty
    ⟨next.erase last,by
      have previous := state.bounded
      have grown := Std.TreeMap.size_insert_le (t := state.entries) (k := key) (v := value)
      have retained := Std.TreeMap.contains_maxKey (t := next) (he := nonempty)
      rw [Std.TreeMap.size_erase]
      simp only [last,retained,↓reduceIte]
      dsimp [next] at *
      omega⟩

theorem resident_bounded (state : State α capacity) : state.entries.size ≤ capacity := state.bounded

theorem insert_bounded (state : State α capacity) (key : String) (value : α) :
    (state.insert key value).entries.size ≤ capacity := (state.insert key value).bounded

end Eggshell.BoundedSample
