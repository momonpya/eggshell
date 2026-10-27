import Lean.Data.Json.Parser
import Lean.Data.Json.FromToJson
open Lean

private def read (path : System.FilePath) : IO Json :=
  IO.FS.readFile path >>= fun text => IO.ofExcept (Json.parse text)

def main : IO Unit := do
  let project := System.FilePath.mk "/Users/ovm/.codex/worktrees/hook-deadline-baseline/eggshell"
  let old := project / "docs/candidates/shared-original-structure/final"
  let current := project / "docs/candidates/evidence-cause-contract/fixed-topic2"
  let output := project / "docs/candidates/evidence-cause-contract/summary.json"
  unless !(← output.pathExists) do throw (IO.userError "preserve prior comparison")
  let previous ← read (old / "hook/result.json")
  let result ← read (current / "hook/result.json")
  let selection ← read (current / "receipt-stages/c46e83d66bac2702e84db13f01a076a335527a61eda7b6d876b12e845200f96f/selection-plan.json")
  let baseline ← read (old / "receipt-stages/5fb9c697fb0410a7d4e3c92a3ca86c8c5a7737b415acdd8e3a32a394145d3bb1/selection-plan.json")
  let sameBody := (← IO.FS.readBinFile (old / "hook/body.txt")) == (← IO.FS.readBinFile (current / "hook/body.txt"))
  let sameSelected := (selection.getObjValD "data").getObjValD "selected" == (baseline.getObjValD "data").getObjValD "selected"
  let comparison ← read (current / "comparison.json")
  unless comparison.getObjValD "sameDomain" == toJson true &&
      comparison.getObjValD "sameFrozenEvidence" == toJson true do
    throw (IO.userError "source comparison was not matched")
  let value := Json.mkObj [
    ("parent",previous),("candidate",result),("sameBodyBytes",toJson sameBody),
    ("sameSelectedUnitIds",toJson sameSelected),
    ("parentJointBindings",(baseline.getObjValD "data").getObjValD "jointBindings"),
    ("candidateJointBindings",(selection.getObjValD "data").getObjValD "jointBindings"),
    ("sameDomainAndFrozenEvidence",toJson true),("deliveryImproved",toJson false),
    ("latencySingleObservationOnly",toJson true),("tokenImprovementMeasured",toJson false),
    ("modelCalls",toJson (0 : Nat)),("formalAnsweringStages",toJson (0 : Nat)),("adopted",toJson false)]
  IO.FS.writeFile output value.pretty
  IO.println value.pretty
