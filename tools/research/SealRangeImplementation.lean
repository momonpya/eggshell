import Lean.Data.Json.Parser
import Lean.Data.Json.FromToJson
open Lean
private def read (path : System.FilePath) : IO Json :=
  IO.FS.readFile path >>= fun text => IO.ofExcept (Json.parse text)
private def copy (source target : System.FilePath) : IO Unit := do
  IO.FS.createDirAll target.parent.get!
  IO.FS.writeBinFile target (← IO.FS.readBinFile source)

/-- Preserve the completed native checks even when storage prevents the
subsequent actual-hook observation. This never labels component checks as
delivery, latency or model-token success. -/
def main : IO Unit := do
  let base := System.FilePath.mk "/Users/ovm/.codex/experiments/eggshell"
  let root := base / "range-postings-20261027"
  let project := System.FilePath.mk "/Users/ovm/.codex/worktrees/hook-deadline-baseline/eggshell"
  let output := project / "docs/candidates/range-postings/native-only"
  unless !(← output.pathExists) do throw (IO.userError "preserve native implementation evidence")
  let checks ← read (root / "checked-ranges/result.json")
  unless checks.getObjValD "allPassed" == toJson true do throw (IO.userError "native checks did not pass")
  let dependencies ← IO.ofExcept (fromJson? (α := Array (String × String))
    (← read (root / "audit-build/tools_research_RangePostingsChecks.dependencies")))
  IO.FS.createDirAll output
  let mut artifacts := #[(root / "product-build/StudyMain").toString]
  let mut patch := ""
  for name in ["tools.PointBuckets","Eggshell.Handoff"] do
    let file := name.replace "." "/" ++ ".lean"
    let source := root / "checkout" / System.FilePath.mk file
    let stem := root / "product-build" / System.FilePath.mk (name.replace "." "_")
    let stamp := System.FilePath.mk (stem.toString ++ ".source")
    let fields ← IO.ofExcept ((← read stamp).getArr?)
    unless fields[0]!.getStr?.toOption == some (← IO.FS.readFile source) do
      throw (IO.userError "native source differs from current candidate")
    let some (_,checked) := dependencies.find? (·.1 == name) |
      throw (IO.userError "native checks did not use the changed module")
    unless checked == (← IO.FS.readFile stamp) do throw (IO.userError "native checks used different source")
    copy source (output / "contracts" / System.FilePath.mk file)
    copy stamp (output / "contracts" / (name ++ ".source"))
    artifacts := artifacts ++ #[stem.toString ++ ".o",stamp.toString]
    let previous := base / "filtered-postings-20261027/checkout" / System.FilePath.mk file
    let difference ← IO.Process.output {cmd := "/usr/bin/diff",args := #["-U0","-L","a/" ++ file,"-L","b/" ++ file,
      if ← previous.pathExists then previous.toString else "/dev/null",source.toString]}
    unless difference.exitCode == 1 do throw (IO.userError "expected isolated range change")
    patch := patch ++ difference.stdout
  IO.FS.writeFile (output / "core.patch") patch
  copy (root / "checked-ranges/result.json") (output / "checks/result.json")
  copy (root / "checked-ranges/native-artifacts.json") (output / "checks/native-artifacts.json")
  copy (root / "audit-build/tools_research_RangePostingsChecks.source") (output / "checks/source.stamp")
  copy (root / "audit-build/tools_research_RangePostingsChecks-lean.stdout") (output / "checks/axioms.txt")
  let digests ← IO.Process.output {
    cmd := (base / "study-services-20261026/assessed-controller").toString
    args := #["artifacts"] ++ artifacts}
  unless digests.exitCode == 0 do throw (IO.userError digests.stderr)
  IO.FS.writeFile (output / "native-input-digests.json") digests.stdout
  for file in ["retired-build-cache.json","retired-superseded-runtime.json","retired-obsolete-checkpoint.json"] do
    copy (root / file) (output / file)
  if ← (root / "driver-interfaces/tools.research.NativeTrialAudit.stderr").pathExists then
    copy (root / "driver-interfaces/tools.research.NativeTrialAudit.stderr") (output / "controller-memory-failure.stderr")
  let mut guards := #[]
  for entry in ← root.readDir do
    if entry.fileName.endsWith ".guard.json" then
      let guard ← read entry.path
      unless guard.getObjValD "state" == toJson "finished" && guard.getObjValD "ownedPids" == toJson (#[] : Array Nat) do
        throw (IO.userError "a candidate operation remains live")
      guards := guards.push (entry.fileName,guard)
  IO.FS.writeFile (output / "terminal-guards.json") (toJson guards).pretty
  IO.FS.writeFile (output / "status.json") (Json.mkObj [
    ("nativeChecksPassed",toJson true),("actualHookExecuted",toJson false),
    ("productionLatencyOrDeliveryClaim",toJson false),("answeringModelCalls",toJson (0 : Nat)),
    ("adopted",toJson false),("pending",toJson "controller compilation and actual-hook observation")]).pretty
