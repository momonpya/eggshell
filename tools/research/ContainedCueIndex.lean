module
public import tools.PointBuckets
public import tools.PreparedCueIndex
@[expose] public section
namespace Eggshell.ContainedCueIndex
structure Coordinates (α : Type) where
  family : α → Nat
  first : α → Nat
  last : α → Nat

/-- Nominate well-ordered intervals by their first point. The original total
predicate can also accept empty/inverted pieces, so retain that exact domain. -/
def key (width : Nat) (coordinates : Coordinates α) (value : α) : String :=
  if coordinates.first value < coordinates.last value then
    PointBuckets.key width (toString (coordinates.family value)) (coordinates.first value)
  else toString (coordinates.family value)++":unordered"

def keys (width family : Nat) (spans : List (Nat × Nat)) : List String :=
  (spans.flatMap fun (first,last) => PointBuckets.keys width (toString family) first last) ++
    [toString family++":unordered"]

def accepts (coordinates : Coordinates α) (family : Nat) (spans : List (Nat × Nat))
    (keep : α → Bool) (value : α) : Bool :=
  keep value && coordinates.family value == family &&
    spans.any (fun (first,last) => first ≤ coordinates.first value && coordinates.last value ≤ last)

theorem accepted_key (width family : Nat) (coordinates : Coordinates α) (spans : List (Nat × Nat))
    (keep : α → Bool) (value : α) (accepted : accepts coordinates family spans keep value = true) :
    key width coordinates value ∈ keys width family spans := by
  simp only [accepts,Bool.and_eq_true,beq_iff_eq] at accepted
  rcases accepted with ⟨⟨_,same⟩,present⟩
  by_cases ordered : coordinates.first value < coordinates.last value
  · obtain ⟨span,member,inside⟩ := List.any_eq_true.mp present
    have bounds : span.1 ≤ coordinates.first value ∧ coordinates.last value ≤ span.2 := by
      simpa only [Bool.and_eq_true,decide_eq_true_eq] using inside
    have point : span.1 ≤ coordinates.first value ∧ coordinates.first value < span.2 := by omega
    simp only [key,if_pos ordered,same,keys]
    apply List.mem_append_left
    exact List.mem_flatMap.mpr ⟨span,member,
      PointBuckets.key_mem_keys width (toString family) span.1 span.2 (coordinates.first value) point⟩
  · simp [key,keys,ordered,same]

def query (width : Nat) (coordinates : Coordinates α) (values : Array α)
    (index : PreparedCueIndex.Prepared (key width coordinates) values)
    (family : Nat) (spans : List (Nat × Nat)) (keep : α → Bool) : List α :=
  index.many (keys width family spans) (accepts coordinates family spans keep)

/-- Stable original values and duplicates, for every width, arbitrary input
piece and range, not only the well-formed cases of the current fixture. -/
theorem query_exact (width family : Nat) (coordinates : Coordinates α) (values : Array α)
    (index : PreparedCueIndex.Prepared (key width coordinates) values)
    (spans : List (Nat × Nat)) (keep : α → Bool) :
    query width coordinates values index family spans keep = values.toList.filter (accepts coordinates family spans keep) := by
  exact index.many_exact _ _ (accepted_key width family coordinates spans keep)

#print axioms accepted_key
#print axioms query_exact
end Eggshell.ContainedCueIndex
