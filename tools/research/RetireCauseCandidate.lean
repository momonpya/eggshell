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
        throw (IO.userError "retained baseline refers to this candidate")

/-- Seal the unchanged delivery result and CPU observation, then remove the
ended candidate and every duplicate executable/cache. Retain source evidence
and the one shared prepared DB, with no compressed archive. -/
def main : IO Unit := do
  let base := System.FilePath.mk "/Users/ovm/.codex/experiments/eggshell"
  let root := base / "evidence-cause-contract-20261027"
  let keep := base / "shared-original-structure-20261027"
  let project := System.FilePath.mk "/Users/ovm/.codex/worktrees/hook-deadline-baseline/eggshell"
  let output := project / "docs/candidates/evidence-cause-contract"
  unless !(← (output / "retirement.json").pathExists) do throw (IO.userError "preserve prior retirement")
  let summary ← read (output / "summary.json")
  unless summary.getObjValD "adopted" == toJson false &&
      summary.getObjValD "deliveryImproved" == toJson false && summary.getObjValD "sameBodyBytes" == toJson true do
    throw (IO.userError "retirement requires the measured unchanged delivery")
  let actual := root / "actual-causal-hook"
  let captured := output / "fixed-topic2"
  unless (← read (actual / "result.json")) == (← read (captured / "hook/result.json")) &&
      (← IO.FS.readBinFile (actual / "body.txt")) == (← IO.FS.readBinFile (captured / "hook/body.txt")) &&
      (← read (root / "native-causes/result.json")) == (← read (captured / "checks/result.json")) do
    throw (IO.userError "capture the actual hook and native checks first")
  let observed ← read (output / "cpu-profile/observation.json")
  unless observed.getObjValD "instrumentedHook" == (← read (root / "profile-causal-hook/result.json")) &&
      (← IO.FS.readBinFile (root / "cpu-sampling/worker.sample.txt")) ==
        (← IO.FS.readBinFile (output / "cpu-profile/worker.sample.txt")) do
    throw (IO.userError "capture the measured CPU observation first")
  let processes ← IO.Process.output {cmd := "/bin/ps",args := #["-axo","command="]}
  unless processes.exitCode == 0 && (processes.stdout.splitOn root.toString).length == 1 do
    throw (IO.userError "candidate still owns or is process-referenced")
  protect (keep / "checkout") root
  protect (keep / "product-build/lib") root
  unless ((← IO.FS.readFile (keep / "product-build/runtime.rsp")).splitOn root.toString).length == 1 do
    throw (IO.userError "retained native linker refers to this candidate")
  let mut guards := #[]
  let mut maximum := 0
  for entry in ← root.readDir do
    if entry.fileName.endsWith ".guard.json" then
      let guard ← read entry.path
      unless guard.getObjValD "state" == toJson "finished" && guard.getObjValD "ownedPids" == toJson (#[] : Array Nat) do
        throw (IO.userError "candidate guard is live")
      maximum := max maximum ((guard.getObjValAs? Nat "sampledPeakRssKiB").toOption.getD 0)
      guards := guards.push (entry.fileName,guard)
  IO.FS.writeFile (output / "terminal-guards.json") (toJson guards).pretty
  IO.FS.writeFile (output / "retirement.json") (Json.mkObj [
    ("target",toJson root.toString),("nativeContractAndSourceEvidenceCaptured",toJson true),
    ("actualAndInstrumentedRunsCaptured",toJson true),("sampledGuardPeakRssKiB",toJson maximum),
    ("originalAndOnePreparedDatabaseRetained",toJson true),("baselineDependenciesRetained",toJson true),
    ("adopted",toJson false),("archiveCreated",toJson false)]).pretty
  remove root
  IO.println "Deleted ended cause candidate, run caches and duplicate runtimes; no archive"
