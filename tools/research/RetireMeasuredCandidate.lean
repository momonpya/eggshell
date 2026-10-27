import Lean.Data.Json.Parser
import Lean.Data.Json.FromToJson
open Lean
private def read (path : System.FilePath) : IO Json :=
  IO.FS.readFile path >>= fun text => IO.ofExcept (Json.parse text)
private partial def remove (path : System.FilePath) : IO Unit := do
  if (← path.symlinkMetadata).type == .dir then
    for entry in ← path.readDir do remove entry.path
    IO.FS.removeDir path
  else IO.FS.removeFile path
private partial def protect (path target : System.FilePath) : IO Unit := do
  for entry in ← path.readDir do
    let metadata ← entry.path.symlinkMetadata
    if metadata.type == .dir then protect entry.path target
    else if metadata.type == .symlink then
      let actual ← IO.FS.realPath entry.path
      unless actual != target && !actual.toString.startsWith (target.toString ++ "/") do
        throw (IO.userError "retained runtime depends on rejected candidate")

/-- Seal the final native differential checks and remove the rejected
candidate, including all run caches and duplicate executables. No DB source,
current prepared checkpoint, baseline dependency or archive is involved. -/
def main : IO Unit := do
  let base := System.FilePath.mk "/Users/ovm/.codex/experiments/eggshell"
  let root := base / "rendered-marginal-cost-20261027"
  let keep := base / "shared-original-structure-20261027"
  let project := System.FilePath.mk "/Users/ovm/.codex/worktrees/hook-deadline-baseline/eggshell"
  let output := project / "docs/candidates/rendered-marginal-cost"
  unless !(← (output / "retirement.json").pathExists) do throw (IO.userError "preserve prior retirement")
  let report ← read (root / "checked-final/result.json")
  unless report.getObjValD "allPassed" == toJson true do throw (IO.userError "final native checks did not pass")
  let sourceCache := root / "audit-build/tools_research_MeasuredCoverageChecks.source"
  let source ← IO.ofExcept ((← read sourceCache).getArr?)
  unless source[0]!.getStr?.toOption == some (← IO.FS.readFile (project / "tools/research/MeasuredCoverageChecks.lean")) do
    throw (IO.userError "differential check source changed")
  let dependencies ← IO.ofExcept (fromJson? (α := Array (String × String))
    (← read (root / "audit-build/tools_research_MeasuredCoverageChecks.dependencies")))
  for (name,stem) in [("Eggshell.Handoff","Eggshell_Handoff"),("tools.research.MeasuredCoverage","tools_research_MeasuredCoverage")] do
    let some (_,stamp) := dependencies.find? (·.1 == name) | throw (IO.userError "missing native dependency stamp")
    unless stamp == (← IO.FS.readFile (root / "product-build" / (stem ++ ".source"))) do
      throw (IO.userError "final native checks used a different candidate source")
  let trial := root / "causal-replay"
  unless (← read (trial / "result.json")) == (← read (output / "counterfactual/hook/result.json")) &&
      (← IO.FS.readBinFile (trial / "body.txt")) == (← IO.FS.readBinFile (output / "counterfactual/hook/body.txt")) do
    throw (IO.userError "capture the counterfactual before retirement")
  let actual ← read (trial / "result.json")
  unless actual.getObjValD "adopted" == toJson false &&
      (actual.getObjValD "requiredDelivery").getObjValD "targetMet" == toJson false do
    throw (IO.userError "this retirement is for the rejected diagnostic only")
  let processes ← IO.Process.output {cmd := "/bin/ps",args := #["-axo","command="]}
  unless processes.exitCode == 0 && (processes.stdout.splitOn root.toString).length == 1 do
    throw (IO.userError "candidate still owns or is referenced by a process")
  protect (keep / "product-build/lib") root
  protect (keep / "checkout") root
  unless ((← IO.FS.readFile (keep / "product-build/runtime.rsp")).splitOn root.toString).length == 1 do
    throw (IO.userError "baseline linker references rejected candidate")
  let mut guards := #[]
  for entry in ← root.readDir do
    if entry.fileName.endsWith ".guard.json" then
      let value ← read entry.path
      unless value.getObjValD "state" == toJson "finished" && value.getObjValD "ownedPids" == toJson (#[] : Array Nat) do
        throw (IO.userError "candidate guard is still live")
      guards := guards.push (entry.fileName,value)
  IO.FS.createDirAll (output / "checks")
  IO.FS.writeFile (output / "checks/result.json") report.pretty
  IO.FS.writeFile (output / "checks/source.stamp") (← IO.FS.readFile sourceCache)
  let artifacts ← IO.Process.output {
    cmd := (base / "study-services-20261026/assessed-controller").toString
    args := #["artifacts",(root / "product-build/StudyMain").toString,(root / "audit-build/StudyMain").toString,
      sourceCache.toString,(root / "audit-build/tools_research_MeasuredCoverageChecks.dependencies").toString]}
  unless artifacts.exitCode == 0 do throw (IO.userError artifacts.stderr)
  let hashes ← IO.ofExcept (Json.parse artifacts.stdout >>= Json.getArr?)
  unless hashes[0]!.getObjValD "sha256" == actual.getObjValD "runtimeSha256" do
    throw (IO.userError "final checks and counterfactual runtime differ")
  IO.FS.writeFile (output / "checks/native-input-digests.json") artifacts.stdout
  IO.FS.writeFile (output / "all-terminal-guards.json") (toJson guards).pretty
  IO.FS.writeFile (output / "retirement.json") (Json.mkObj [
    ("target",toJson root.toString),("nativeDependenciesChecked",toJson true),
    ("baselineSourceObjectsInterfacesAndRuntimeRetained",toJson true),
    ("originalSeedAndOnePreparedCheckpointRetained",toJson true),("archiveCreated",toJson false),
    ("rejected",toJson true)]).pretty
  remove root
  IO.println "Sealed final native checks; deleted rejected candidate and every run/cache/build without an archive"
