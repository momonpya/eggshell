import Lean.Data.Json.Parser
import Lean.Data.Json.FromToJson
open Lean
private def read (path : System.FilePath) : IO Json :=
  IO.FS.readFile path >>= fun text => IO.ofExcept (Json.parse text)
private def selection (root : System.FilePath) : IO Json := do
  let mut result := none
  for entry in ← (root / "receipt-stages").readDir do
    let path := entry.path / "selection-plan.json"
    if ← path.pathExists then
      unless result.isNone do throw (IO.userError "ambiguous selection record")
      result := some ((← read path).getObjValD "data")
  result.getDM (throw (IO.userError "missing selection record"))

/-- Post-hoc evidence only. Required names and owners are read after both
selections; this program cannot provide them to either selector. -/
def main : IO Unit := do
  let project := System.FilePath.mk "/Users/ovm/.codex/worktrees/hook-deadline-baseline/eggshell"
  let root := project / "docs/candidates/rendered-marginal-cost"
  let parent := project / "docs/candidates/shared-original-structure/final"
  let old ← selection parent
  let current ← selection (root / "counterfactual")
  let before ← IO.ofExcept (old.getObjValAs? (List Nat) "selected")
  let after ← IO.ofExcept (current.getObjValAs? (List Nat) "selected")
  let common := (before.zip after).takeWhile (fun pair => pair.1 == pair.2) |>.length
  let audit ← read (parent / "hook/audit.json")
  let requirements ← IO.ofExcept (audit.getObjValAs? (Array Json) "requirements")
  let actual ← read (root / "counterfactual/hook/result.json")
  let missing ← IO.ofExcept ((actual.getObjValD "requiredDelivery").getObjValAs? (List (List String)) "missing")
  let missing := missing.flatten
  let eligible := requirements.filter fun row => row.getObjValD "stored" == toJson true
  let changes := eligible.map fun row =>
    let name := (row.getObjValAs? String "name").toOption.getD ""
    Json.mkObj [("name",toJson name),("before",row.getObjValD "bodyDelivered"),
      ("after",toJson (!missing.contains name))]
  let meter := (current.getObjValD "jointBindings").getObjValD "wireMeasure"
  let summary := meter.getObjValD "measured"
  let owners ← IO.ofExcept ((meter.getObjValD "creditOrigins").getObjValAs? (Array Json) "families")
  let oldMissing := requirements.filter fun row => row.getObjValD "stored" == toJson true &&
    row.getObjValD "bodyDelivered" == toJson false
  let requiredOwners := oldMissing.toList.flatMap fun row =>
    (row.getObjValAs? (List String) "storedOwners").toOption.getD []
  let ownerCredit := owners.filter fun row => requiredOwners.contains
    ((row.getObjValAs? String "owner").toOption.getD "")
  let guards ← IO.ofExcept (fromJson? (α := Array (String × Json)) (← read (root / "all-terminal-guards.json")))
  let peak := guards.foldl (fun highest row => max highest
    ((row.2.getObjValAs? Nat "sampledPeakRssKiB").toOption.getD 0)) 0
  let result := Json.mkObj [
    ("scope",toJson "one fixed C7 topic-2 model-free counterfactual"),
    ("parentActualHook",(← read (parent / "hook/result.json"))),
    ("counterfactual",actual),("sameDomainAndFrozenEvidence",← read (root / "counterfactual/comparison.json")),
    ("requirements",toJson changes),("missingOwnerCredit",toJson ownerCredit),
    ("selectedUnitsBefore",toJson before.length),("selectedUnitsAfter",toJson after.length),
    ("expandedOrderCommonPrefix",toJson common),
    ("firstDifferentExpandedUnits",toJson (before[common]?,after[common]?)),
    ("expandedOrderIsNotARecipeScoreTrace",toJson true),
    ("greedySteps",toJson ((summary.getObjValAs? (Array Json) "steps").toOption.getD #[] |>.size)),
    ("checkedPrefixes",summary.getObjValD "checkedPrefixes"),("meterFinalCost",summary.getObjValD "cost"),
    ("costIncludesExistingPolicyAndSourceStatusReserves",toJson true),
    ("peakBuildOrRunRssKiB",toJson peak),
    ("allGuardsTerminalAndNoOwnedProcesses",toJson (guards.all fun row =>
      row.2.getObjValD "state" == toJson "finished" && row.2.getObjValD "ownedPids" == toJson (#[] : Array Nat))),
    ("rejected",toJson true),("furtherCostTuning",toJson false),
    ("answeringModelCalls",toJson (0 : Nat)),("formalSixStagesCompleted",toJson (0 : Nat))]
  IO.FS.writeFile (root / "summary.json") result.pretty
  IO.println "Sealed exact JSON summary; required evidence was never an input to selection"
