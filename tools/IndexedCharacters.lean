module

public import Std

@[expose] public section
namespace Eggshell

/-- An immutable character array bound to the exact original String. Substring
reads traverse only the selected characters, preserving character coordinates. -/
structure IndexedCharacters (source : String) where
  chars : Array Char
  exact : chars = source.toList.toArray

@[noinline] def IndexedCharacters.make (source : String) : IndexedCharacters source :=
  ⟨source.toList.toArray, rfl⟩

theorem IndexedCharacters.is_canonical (indexed : IndexedCharacters source) :
    indexed = make source := by
  cases indexed with
  | mk chars exact => subst chars; rfl

def IndexedCharacters.slice (indexed : IndexedCharacters source) (first count : Nat) : String :=
  String.ofList (indexed.chars.extract first (first + count)).toList

theorem IndexedCharacters.slice_exact (indexed : IndexedCharacters source) (first count : Nat) :
    indexed.slice first count = ((source.drop first).take count).copy := by
  apply String.ext
  simp [slice, indexed.exact]

/-- A decision over indexed slices certifies the exact original String slices.
The equality transport erases; only bounded slice work remains at runtime. -/
def IndexedCharacters.decide₂ (left : IndexedCharacters a) (first count : Nat)
    (right : IndexedCharacters b) (otherFirst otherCount : Nat)
    (predicate : String → String → Prop) [DecidableRel predicate] :
    Decidable (predicate ((a.drop first).take count).copy ((b.drop otherFirst).take otherCount).copy) :=
  decidable_of_iff (predicate (left.slice first count) (right.slice otherFirst otherCount))
    (by rw [slice_exact, slice_exact])

theorem IndexedCharacters.decide₂_eq (left : IndexedCharacters a) (first count : Nat)
    (right : IndexedCharacters b) (otherFirst otherCount : Nat)
    (predicate : String → String → Prop) [DecidableRel predicate] :
    left.decide₂ first count right otherFirst otherCount predicate =
      (inferInstance : Decidable (predicate ((a.drop first).take count).copy
        ((b.drop otherFirst).take otherCount).copy)) := Subsingleton.elim _ _

def IndexedCharacters.branch₂ (left : IndexedCharacters a) (first count : Nat)
    (right : IndexedCharacters b) (otherFirst otherCount : Nat)
    (predicate : String → String → Prop) [DecidableRel predicate]
    (yes : predicate ((a.drop first).take count).copy ((b.drop otherFirst).take otherCount).copy → γ)
    (no : ¬predicate ((a.drop first).take count).copy ((b.drop otherFirst).take otherCount).copy → γ) : γ :=
  @dite γ _ (left.decide₂ first count right otherFirst otherCount predicate) yes no

theorem IndexedCharacters.branch₂_exact (left : IndexedCharacters a) (first count : Nat)
    (right : IndexedCharacters b) (otherFirst otherCount : Nat)
    (predicate : String → String → Prop) [DecidableRel predicate]
    (yes : predicate ((a.drop first).take count).copy ((b.drop otherFirst).take otherCount).copy → γ)
    (no : ¬predicate ((a.drop first).take count).copy ((b.drop otherFirst).take otherCount).copy → γ) :
    left.branch₂ first count right otherFirst otherCount predicate yes no =
      if h : predicate ((a.drop first).take count).copy ((b.drop otherFirst).take otherCount).copy then
        yes h else no h := by
  unfold branch₂
  rw [decide₂_eq]

end Eggshell
