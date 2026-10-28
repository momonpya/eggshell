import Lean.Data.Json.Parser
import Lean.Data.Json.FromToJson
open Lean
private def read (path : System.FilePath) : IO Json :=
  IO.FS.readFile path >>= fun text => IO.ofExcept (Json.parse text)
private def copy (source target : System.FilePath) : IO Unit := do
  IO.FS.createDirAll target.parent.get!
  IO.FS.writeBinFile target (← IO.FS.readBinFile source)
def main : IO Unit := do
  let root : System.FilePath := "/Users/ovm/.codex/experiments/eggshell/scope-token-study-20261028/shared-snapshot"
  let project : System.FilePath := "/Users/ovm/.codex/worktrees/hook-deadline-baseline/eggshell"
  let output := project / "docs/candidates/setup-cost-alternatives"
  unless !(← output.pathExists) do throw (IO.userError "preserve previous setup evidence")
  let result ← read (root / "setup-replay.json")
  let expected ← IO.ofExcept ((← read (project / "docs/candidates/optional-inference/selector-replay.json")).getArr?)
  unless result.getObjValD "chosenOffers" == expected[1]!.getObjValD "selected" do
    throw (IO.userError "selection is not unchanged")
  for name in ["missing-selection.guard.json","setup-replay.guard.json"] do
    let guard ← read (root / name)
    unless guard.getObjValD "state" == toJson "finished" && guard.getObjValD "exitCode" == toJson (0 : Nat) &&
        guard.getObjValD "ownedPids" == toJson (#[] : Array Nat) do
      throw (IO.userError "wait for completed native replay")
    copy (root / name) (output / name)
  for (source,target) in [
      (root / "missing-selection.json","missing-selection.json"),
      (root / "setup-replay.json","setup-replay.json"),
      (root / "setup-build/tools_research_SetupFrameReplay-lean.stdout","proofs.txt"),
      (root / "core/tools/SetupAlternatives.lean","SetupAlternatives.lean"),
      (project / "tools/research/SetupFrameReplay.lean","SetupFrameReplay.lean")] do
    copy source (output / target)
  IO.FS.writeFile (output / "decision.json") (Json.mkObj [("rejected",toJson true),
    ("reason",toJson "All selected offer IDs and their order remain identical; no evidence added"),
    ("sameOrderedSelection",toJson true),("candidateGroups",toJson (36 : Nat)),
    ("constructionMs",result.getObjValD "constructionMs"),("selectionMs",result.getObjValD "selectionMs"),
    ("newDatabase",toJson false),("newWarm",toJson false),("answeringModelCalls",toJson (0 : Nat)),
    ("productionAdoption",toJson false),("currentGoalMet",toJson false)]).pretty
  IO.println "Sealed unchanged-selection rejection and independent missing-evidence audit"
