import Eggshell.Handoff
open Lean Eggshell Eggshell.Plugin Eggshell.Plugin.SharedRangeAdapter

#print axioms DeliveryInterval.coalesce_covers
#print axioms Plan.keeps_control
#print axioms Plan.within_budget
#print axioms LinearOutput.loop_compiled
#print axioms LinearOutput.pair_loop_compiled
#print axioms LinearNodes.reference_linear
#print axioms problem_prepared_compiled

private def check (condition : Bool) (message : String) : IO Unit :=
  unless condition do throw (IO.userError message)

private def owner (name : String) : OutcomeEdge :=
  OutcomeEdge.make (.text (name ++ "-work")) (.text (name ++ "-data")) [] (by simp) (by simp)

private def slice : TransportSlice := {keys := [],text := "",members := [],visibleKeys := []}

def main (args : List String) : IO Unit := do
  let [output] := args | throw (IO.userError "new output directory required")
  let root := System.FilePath.mk output
  unless !(← root.pathExists) do throw (IO.userError "preserve previous range audit")
  IO.FS.createDir root
  let family := fun name => ({owner := owner name,template := slice,windows := []} : Family)
  let units : Array UnitPlan := #[
    {family := 0,slice,ranges := [(0,4),(2,6)]},
    {family := 0,slice,ranges := [(8,10)]},
    {family := 1,slice,ranges := [(1,4)]}]
  let cost := fun _ : List TransportSlice => (0,0)
  let plan : Plan (100,100) cost [] := {
    families := #[family "first",family "second",family "empty"]
    units,selected := [0,2],scale := 1
    problem := {costs := #[],weights := #[],offers := #[],limit := (100,100)}
    result := ⟨[],by simp [cost],by simp [cost],⟨[],rfl⟩⟩}
  let normal := plan.receipt
  check ((normal.getObjVal? "rangeAudit").toOption.isNone) "normal receipt performed the independent range audit"
  let audit := plan.rangeReceipt
  let rows ← IO.ofExcept (audit.getObjValAs? (Array Json) "rangeAudit")
  check (rows.size == 3) "an owner with no candidates disappeared from diagnosis"
  check ((rows[0]!.getObjValD "candidateRanges") == toJson ([(0,6),(8,10)] : List (Nat × Nat)))
    "overlap merging filled an original gap or lost a candidate"
  check ((rows[0]!.getObjValD "selectedRanges") == toJson ([(0,6)] : List (Nat × Nat)))
    "unselected bytes were marked selected"
  check ((rows[1]!.getObjValD "selectedRanges") == toJson ([(1,4)] : List (Nat × Nat)))
    "another owner's selection leaked across families"
  check ((rows[2]!.getObjValD "candidateRanges") == toJson ([] : List (Nat × Nat)))
    "an empty family acquired evidence"
  check ((audit.getObjValAs? Bool "assertsActualDelivery").toOption == some false)
    "planned ranges claimed actual model delivery"
  check (audit.getObjValD "selected" == normal.getObjValD "selected")
    "diagnosis changed the selector result"
  let scalarStep := fun (state : Nat) (value : Nat) =>
    if value == 91 then none else some (state+value,value%7)
  let scalar := (List.range 64) ++ [1,1,1,2]
  check (LinearOutput.loop scalarStep scalar 11 [4,4] ==
      LinearOutput.append scalarStep scalar 11 [4,4]) "compiled output log changed order, duplicates or state"
  check ((LinearOutput.loop scalarStep [1,3,91,5] 0 []).isNone &&
      (LinearOutput.append scalarStep [1,3,91,5] 0 []).isNone) "compiled output log suppressed a failure"
  let sameNodes := fun (left right : LinearNodes.Costs × LinearNodes.Payloads × List (List Nat)) =>
    left.1 == right.1 && left.2.2 == right.2.2 &&
      left.2.1.size == right.2.1.size && left.2.1.toArray.all (fun (key,value) => right.2.1[key]? == some value)
  let nativeUnits := (List.range 128).map fun id => ({
    family := id%3,ranges := [(0,3)],slice := {slice with text := toString (id%11)}} : UnitPlan)
  let reference := LinearNodes.reference {} {} nativeUnits #[(0,0),(0,0),(0,0)] {} [[9]]
  let compiled := LinearOutput.pairLoop (LinearNodes.step {} {}) nativeUnits #[(0,0),(0,0),(0,0)] {} [[9]]
  let some expected := reference | throw (IO.userError "native reference unexpectedly failed")
  let some observed := compiled | throw (IO.userError "native compiled builder unexpectedly failed")
  check (sameNodes expected observed && observed.2.2.length == nativeUnits.length+1)
    "compiled node builder changed costs, payload identities, order or initial rows"
  IO.FS.writeFile (root / "range-audit.json") audit.pretty
  IO.FS.writeFile (root / "result.json") (Json.mkObj [
    ("overlapsPreservedWithoutClosingGaps",toJson true),("ownersRemainSeparate",toJson true),
    ("emptyOwnersVisible",toJson true),("selectedOnly",toJson true),
    ("plannedRangesDoNotClaimDelivery",toJson true),("normalReceiptUnchanged",toJson true),
    ("linearOutputOrderStateAndFailureChecked",toJson true),("nativeNodeClosuresChecked",toJson nativeUnits.length),
    ("modelCalls",toJson (0 : Nat)),("warmCalls",toJson (0 : Nat)),("adopted",toJson false)]).pretty
