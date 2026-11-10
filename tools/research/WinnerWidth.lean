module
public import tools.StableWinnerIndex
@[expose] public section
namespace StableWinnerIndex.Width
variable {α : Type} {order : Preference α} {depth : Nat} {best : Option α}

/-- Carry the already known subtree width. Each descending step divides by
two instead of evaluating another power, without changing the update path. -/
def updated : {depth : Nat} → {best : Option α} → Tree order depth best →
    Nat → Nat → Option α → Cache order depth
  | _,_,.leaf _,_,_,value => ⟨value,.leaf value⟩
  | _,_,@Tree.branch _ _ _ _ _ left right,width,index,value =>
    let half := width/2
    if index < half then join (updated left half index value) ⟨_,right⟩
    else join ⟨_,left⟩ (updated right half (index-half) value)

theorem updated_exact (tree : Tree order depth best) (index : Nat) (value : Option α) :
    updated tree (2^depth) index value = tree.updated index value := by
  induction tree generalizing index with
  | leaf => rfl
  | @branch depth leftBest rightBest left right ihl ihr =>
    have half : 2^depth*2/2 = 2^depth := by omega
    simp only [updated,Tree.updated,Nat.pow_succ,half,ihl,ihr]

/-- Every point update has the original order, including duplicate positions.
The width is computed once for this entire batch. -/
def updateMany (cache : Cache order depth) (updates : List (Nat × Option α)) : Cache order depth :=
  let width := 2^depth
  updates.foldl (fun current row => updated current.tree width row.1 row.2) cache

theorem updateMany_exact (cache : Cache order depth) (updates : List (Nat × Option α)) :
    updateMany cache updates =
      updates.foldl (fun current row => current.tree.updated row.1 row.2) cache := by
  have same : (fun (current : Cache order depth) (row : Nat × Option α) =>
      updated current.tree (2^depth) row.1 row.2) =
      (fun current row => current.tree.updated row.1 row.2) := by
    funext current row
    exact updated_exact ..
  simp only [updateMany,same]

#print axioms updated_exact
#print axioms updateMany_exact
end StableWinnerIndex.Width
