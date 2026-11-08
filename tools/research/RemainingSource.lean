module
public import Eggshell.CanonicalSourceDelivery
public import Std.Data.HashSet.Lemmas
@[expose] public section
namespace Eggshell.Synapses.CanonicalSource.Delivery

theorem Part.remaining_nil (part : Part) : part.remaining [] = some part := by
  cases part with
  | mk rows plan nonempty =>
      have keep : rows.filter (fun _ => true) = rows := Array.filter_eq_self.mpr (by simp)
      simp only [Part.remaining,List.contains_nil,Bool.and_false,Bool.false_eq_true,↓reduceIte,
        Bool.not_false,keep,nonempty,↓reduceDIte]

/-- A new reader has acknowledged no rows. Otherwise compute the existing
file identity once per distinct file, rather than once per source line.
This changes neither the acknowledgement domain nor any original payload. -/
def remainingSource (part : Part) : List String → Option Part
  | [] => some part
  | key :: rest =>
      let acknowledged := key :: rest
      if !part.plan.isEmpty && acknowledged.contains part.plan then none else
        let seen := Std.HashSet.ofList acknowledged
        let files := PreparedFileIdentities.prepare (part.rows.toList.map (·.key.file))
        let rows := part.rows.filter fun row =>
          !seen.contains (PreparedFileIdentities.rowKey files row.key)
        if nonempty : rows.isEmpty = false then some {part with rows,nonempty} else none

theorem remainingSource_exact (part : Part) (acknowledged : List String) :
    remainingSource part acknowledged = part.remaining acknowledged := by
  cases acknowledged with
  | nil => exact part.remaining_nil.symm
  | cons key rest =>
      simp only [remainingSource,Part.remaining,Std.HashSet.contains_ofList,
        PreparedFileIdentities.rowKey_exact,rowKey]
      rfl

@[csimp] theorem remaining_source_compiled : @Part.remaining = @remainingSource :=
  funext fun part => funext fun acknowledged => (remainingSource_exact part acknowledged).symm

#print axioms Part.remaining_nil
#print axioms remainingSource_exact
#print axioms remaining_source_compiled
end Eggshell.Synapses.CanonicalSource.Delivery
