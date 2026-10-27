import Lean.Data.Json.Parser
import Lean.Data.Json.FromToJson
open Lean
private def read (path : System.FilePath) : IO Json :=
  IO.FS.readFile path >>= fun text => IO.ofExcept (Json.parse text)
private def copy (source target : System.FilePath) : IO Unit := do
  IO.FS.createDirAll target.parent.get!
  IO.FS.writeBinFile target (← IO.FS.readBinFile source)

def main : IO Unit := do
  let base := System.FilePath.mk "/Users/ovm/.codex/experiments/eggshell"
  let root := base / "selector-input-20261027"
  let parent := base / "range-postings-20261027"
  let project := System.FilePath.mk "/Users/ovm/.codex/worktrees/hook-deadline-baseline/eggshell"
  let output := project / "docs/candidates/selector-input/native"
  unless !(← output.pathExists) do throw (IO.userError "preserve captured selector evidence")
  let mut guards : Array (String × Json) := #[]
  for entry in ← root.readDir do
    if entry.fileName.endsWith ".guard.json" then
      let guard ← read entry.path
      unless guard.getObjValD "state" == toJson "finished" &&
          guard.getObjValD "ownedPids" == toJson (#[] : Array Nat) do
        throw (IO.userError "a selector operation is still live")
      guards := guards.push (entry.fileName,guard)
  let checks ← read (root / "compare-changed-winner/result.json")
  unless checks.getObjValD "actualInputExactSequence" == toJson true &&
      (← read (root / "measured-selector-changes/result.json")).getObjValD "sameNativeReferenceSequence" == toJson true do
    throw (IO.userError "actual-input comparison failed")
  let dependencies ← IO.ofExcept (fromJson? (α := Array (String × String))
    (← read (root / "changed-build/tools_research_ChangedWinnerAudit.dependencies")))
  IO.FS.createDirAll output
  let mut artifacts := #[(root / "changed-build/StudyMain").toString]
  let mut patch := ""
  for name in ["tools.SharedCoverageInput","tools.StableWinnerIndex","tools.SelectionRating","tools.ChangedWinnerCoverage"] do
    let directory := root / (if name == "tools.SharedCoverageInput" then "product-build" else "changed-build")
    let stem := name.replace "." "_"
    let stamp := directory / (stem ++ ".source")
    let source := root / "checkout" / System.FilePath.mk (name.replace "." "/" ++ ".lean")
    let fields ← IO.ofExcept ((← read stamp).getArr?)
    unless fields[0]!.getStr?.toOption == some (← IO.FS.readFile source) do
      throw (IO.userError "native selector input does not match current source")
    let some (_,used) := dependencies.find? (·.1 == name) | throw (IO.userError "native comparison omitted module")
    unless used == (← IO.FS.readFile stamp) do throw (IO.userError "native comparison used different source")
    copy source (output / "contracts" / System.FilePath.mk (name.replace "." "/" ++ ".lean"))
    copy stamp (output / "contracts" / (name ++ ".source"))
    artifacts := artifacts ++ #[stamp.toString,(directory / (stem ++ ".o")).toString]
  let coreFiles := ["Eggshell/Handoff.lean","tools/SharedCoverageInput.lean","tools/StableWinnerIndex.lean",
    "tools/SelectionRating.lean","tools/ChangedWinnerCoverage.lean","tools/SelectionBudget.lean"]
  for file in coreFiles do
    let previous := parent / "checkout" / System.FilePath.mk file
    let source := root / "checkout" / System.FilePath.mk file
    let difference ← IO.Process.output {cmd := "/usr/bin/diff",args := #["-U0","-L","a/" ++ file,"-L","b/" ++ file,
      if ← previous.pathExists then previous.toString else "/dev/null",source.toString]}
    unless difference.exitCode == 1 do throw (IO.userError "expected isolated selector change")
    patch := patch ++ difference.stdout
  IO.FS.writeFile (output / "core.patch") patch
  copy (root / "checkout/tools/SelectionBudget.lean") (output / "contracts/tools/SelectionBudget.lean")
  let proof ← IO.Process.output {
    cmd := "/Users/ovm/.elan/toolchains/leanprover--lean4---v4.33.0/bin/lean"
    args := #["--root=" ++ (root / "checkout").toString,"-j1","-M1024",(root / "checkout/tools/SelectionBudget.lean").toString]
    env := #[("LEAN_PATH",some (root / "product-build/lib").toString),("LEAN_NUM_THREADS",some "1")]}
  unless proof.exitCode == 0 do throw (IO.userError (proof.stdout ++ proof.stderr))
  IO.FS.writeFile (output / "budget-axioms.txt") proof.stdout
  let hashed ← IO.Process.output {
    cmd := (base / "study-services-20261026/assessed-controller").toString
    args := #["artifacts"] ++ artifacts}
  unless hashed.exitCode == 0 do throw (IO.userError hashed.stderr)
  IO.FS.writeFile (output / "digests.json") hashed.stdout
  copy (root / "changed-build/tools_research_ChangedWinnerAudit.source") (output / "changed-audit.source")
  copy (root / "changed-build/tools_research_ChangedWinnerAudit-lean.stdout") (output / "changed-axioms.txt")
  copy (root / "replay-build/tools_research_SelectorChangeReplay.source") (output / "replay.source")
  copy (root / "replay-build/tools_research_SelectorChangeReplay-lean.stdout") (output / "replay-axioms.txt")
  copy (root / "measured-selector-changes/result.json") (output / "actual-input-counts.json")
  copy (root / "measured-selector-changes/summary.json") (output / "actual-input-summary.json")
  copy (root / "compare-changed-winner/result.json") (output / "changed-winner-comparison.json")
  IO.FS.writeFile (output / "terminal-guards.json") (toJson guards).pretty
  IO.FS.writeFile (output / "status.json") (Json.mkObj [
    ("actualInputCapturedLosslessly",toJson true),("pointUpdatesProved",toJson true),
    ("sameActualInputSelectionSequence",toJson true),("fullOrderedRefinementProved",toJson false),
    ("productionConnected",toJson false),("productionLatencyClaim",toJson false),
    ("newSeedStudy",toJson false),("answeringModelCalls",toJson (0 : Nat)),("adopted",toJson false)]).pretty
