module
public import tools.research.PreparedSourceView
public import tools.research.PreparedRecordGroups
@[expose] public section
namespace Eggshell.Research.PreparedOwnerGroups
open Eggshell Eggshell.Synapses Eggshell.Synapses.PreparedSourceView

/-- Borrow the owner's already compiled record membership. No parser,
coordinate inference, cache admission or mutable state is reachable here. -/
def groupWith (owner : String) (ready : OwnerReady) (expand : List Nat → List Nat)
    (spans : List (Nat × Nat)) : Except String (Option UnitRef) := do
  let requested := (Array.range ready.rows.size).toList.filter fun i =>
    (ready.rows[i]?).any fun row => row.origins.any fun origin =>
      origin.binding.owner == owner && spans.any fun (first,limit) =>
        first < origin.binding.limit && origin.binding.first < limit
  let selected := expand requested
  if selected.isEmpty then return none
  let rows ← selected.toArray.mapM fun i => requireSome (ready.rows[i]?) "source group escaped its row domain"
  return some {keys := rows.map (·.key),ranges := bindings owner rows}

def original (owner : String) (ready : OwnerReady) (spans : List (Nat × Nat)) :=
  groupWith owner ready (fun requested => hashDistinct (requested ++
    (ready.stored.records.filter fun record => record.any requested.contains).flatten)) spans

def groupUsing (owner : String) (ready : OwnerReady)
    (index : PreparedRecordGroups.Index ready.stored.records) (spans : List (Nat × Nat)) :=
  groupWith owner ready index.expand spans

theorem groupUsing_original (owner : String) (ready : OwnerReady)
    (index : PreparedRecordGroups.Index ready.stored.records) (spans : List (Nat × Nat)) :
    groupUsing owner ready index spans = original owner ready spans := by
  simp only [groupUsing,original,groupWith,PreparedRecordGroups.Index.expand_exact]

/-- This checks the complete old product function, including the first error
and the row/key/range/coverage construction after membership selection. -/
theorem product_original (owner : String) (ready : OwnerReady) (spans : List (Nat × Nat)) :
    groupUnit? owner ready spans = original owner ready spans := by
  first
  | rfl
  | simp only [groupUnit?,original,groupWith,PreparedRecordGroups.Index.expand_exact]

theorem groupUsing_exact (owner : String) (ready : OwnerReady)
    (index : PreparedRecordGroups.Index ready.stored.records) (spans : List (Nat × Nat)) :
    groupUsing owner ready index spans = groupUnit? owner ready spans :=
  (groupUsing_original owner ready index spans).trans (product_original owner ready spans).symm

#print axioms groupUsing_exact
#print axioms product_original
end Eggshell.Research.PreparedOwnerGroups
