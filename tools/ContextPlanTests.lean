import Eggshell.Handoff

open Lean Eggshell Plugin

private def check (accepted : Bool) (message : String) : IO Unit :=
  unless accepted do throw (IO.userError message)

def main : IO UInt32 := do
  let row := "  observed α日本語🐣 \\\"quoted\\\"\tvalue\n"
  let long := String.intercalate "" (List.replicate 160 row)
  let sources := ["short original", long, (Json.str long).compress]
  let slice : TransportSlice := {keys := ["original-key"], text := "original fallback", members := [], visibleKeys := []}
  let mut comparisons := 0
  for source in sources do
    let owner := OutcomeEdge.make (.text "inspect original tool response") (.text source) [] (by simp) (by simp)
    for windows in [[], [0], [1, 3, 6]] do
      let prepared := prepareContextualOwnerPlan [] windows owner "original connection" [] slice
      for budget in [0, 1, 32, 128, 512, 1024, 4096, 8192] do
        let actual := (prepared.eval budget).map toJson
        let expected := (prepareContextualOwnerPart [] windows owner "original connection" [] slice budget).map toJson
        check (actual == expected) "prepared budget changed original fragments, keys or conditions"
        comparisons := comparisons + 1
  let empty : BudgetPlan Nat := .constant none
  let constant : BudgetPlan Nat := .constant (some 7)
  let sized : BudgetPlan Nat := .sized (fun n => some (n + 1))
  for budget in [0, 1, 10000] do
    check ((empty.eval budget).isNone && constant.eval budget == some 7 &&
      ((sized.map (· * 2)).eval budget) == some ((budget + 1) * 2)) "budget plan lost its actual evaluation mode"
  IO.println (Json.mkObj [("passed", toJson true), ("comparisons", toJson comparisons),
    ("generationModelCalls", toJson (0 : Nat)), ("productionAdoption", toJson false)]).compress
  pure 0
