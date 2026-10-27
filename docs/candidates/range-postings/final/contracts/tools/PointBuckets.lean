module
public import Std
public import Init.Data.List.Nat.Range
@[expose] public section

namespace Eggshell.PointBuckets

/-- A coarse key is only a necessary condition. The caller keeps its exact
predicate, original IDs, duplicate handling and stable order. -/
def key (width : Nat) (scope : String) (point : Nat) : String :=
  scope ++ ":" ++ toString (point/width)

def keys (width : Nat) (scope : String) (first limit : Nat) : List String :=
  if first < limit then
    (List.range' (first/width) ((limit-1)/width+1-first/width)).map fun bucket =>
      scope ++ ":" ++ toString bucket
  else []

/-- Every point in the original half-open interval is nominated. This holds
for every width, including the degenerate all-in-one width zero. -/
theorem key_mem_keys (width : Nat) (scope : String) (first limit point : Nat)
    (inside : first ≤ point ∧ point < limit) :
    key width scope point ∈ keys width scope first limit := by
  have ordered : first < limit := by omega
  have lower : first/width ≤ point/width := Nat.div_le_div_right inside.1
  have upper : point/width ≤ (limit-1)/width := Nat.div_le_div_right (by omega)
  simp only [key,keys,if_pos ordered,List.mem_map]
  refine ⟨point/width,?_,rfl⟩
  simp only [List.mem_range'_1]
  exact ⟨lower,by omega⟩

end Eggshell.PointBuckets
