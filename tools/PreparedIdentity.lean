module
public import Std.Data.DHashMap.Basic
@[expose] public section

namespace Eggshell.PreparedIdentity

/-- The key itself carries its relationship to the complete original value.
Hash collisions in the table cannot replace that value or its identity. -/
abbrev Index (identify : α → String) [BEq α] [Hashable α] :=
  Std.DHashMap α (fun value => {key : String // key = identify value})

def prepare [BEq α] [Hashable α] (identify : α → String) (values : Array α) : Index identify :=
  values.foldl (fun table value =>
    if table.contains value then table else table.insert value ⟨identify value,rfl⟩) {}

/-- A miss is computed only on a miss; eager `getD (identify value)` would
perform the expensive identity calculation even when the table has a hit. -/
def get [BEq α] [Hashable α] [LawfulBEq α] {identify : α → String}
    (index : Index identify) (value : α) : String :=
  match index.get? value with
  | some key => key.val
  | none => identify value

theorem get_exact [BEq α] [Hashable α] [LawfulBEq α] {identify : α → String}
    (index : Index identify) (value : α) : get index value = identify value := by
  unfold get
  split
  · rename_i key _
    exact key.property
  · rfl

end Eggshell.PreparedIdentity
