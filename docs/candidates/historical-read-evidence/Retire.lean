import Lean.Data.Json.Parser
import Lean.Data.Json.FromToJson
open Lean
private def read (path : System.FilePath) : IO Json := do
  IO.ofExcept (Json.parse (← IO.FS.readFile path))
def main : IO Unit := do
  let candidate : System.FilePath := "/Users/ovm/.codex/experiments/eggshell/scope-token-study-20261028/shared-snapshot"
  let records : System.FilePath := "/Users/ovm/.codex/worktrees/hook-deadline-baseline/eggshell/docs/candidates/historical-read-evidence"
  unless !(← (records / "retired.json").pathExists) &&
      (← read (records / "decision.json")).getObjValD "frozenOriginalEventsMatched" == toJson (51 : Nat) do
    throw (IO.userError "seal current results before retiring ended runtimes")
  for name in ["replay.guard.json","negative-checks.guard.json"] do
    let guard ← read (records / name)
    unless guard.getObjValD "exitCode" == toJson (0 : Nat) &&
        guard.getObjValD "ownedPids" == toJson (#[] : Array Nat) do throw (IO.userError "current tests still running")
  let targets := #["receipt-build","project-query-build","receipt-fixed-build","receipt-contract-build","historical-usage-build"]
    |>.map (fun (name : String) => candidate / System.FilePath.mk name / "StudyMain")
  let process ← IO.Process.output {cmd := "/bin/ps",args := #["-axo","command="]}
  unless process.exitCode == 0 && targets.all (fun path => (process.stdout.splitOn path.toString).length == 1) do
    throw (IO.userError "ended audit still has a live process")
  for build in #[candidate / "product-build",candidate / "hook-build",candidate / "historical-read-build",
      candidate / "historical-evidence-build",candidate.parent.get! / "controller-build"] do
    let response ← IO.FS.readFile (build / "runtime.rsp")
    unless targets.all (fun path => (response.splitOn path.toString).length == 1) do
      throw (IO.userError "an active native link depends on an ended executable")
  let mut rows := #[]
  let mut total := 0
  for path in targets do
    let metadata ← path.symlinkMetadata
    unless metadata.type == .file do throw (IO.userError "refuse non-regular runtime leaf")
    let checksum ← IO.Process.output {cmd := "/usr/bin/shasum",args := #["-a","256",path.toString]}
    unless checksum.exitCode == 0 do throw (IO.userError checksum.stderr)
    let some digest := (checksum.stdout.splitOn " ").head? | throw (IO.userError "missing runtime digest")
    rows := rows.push (path.toString,metadata.byteSize.toNat,digest)
    total := total+metadata.byteSize.toNat
  for path in targets do IO.FS.removeFile path
  IO.FS.writeFile (records / "retired.json") (Json.mkObj [
    ("executables",toJson rows),("logicalBytes",toJson total),("archiveCreated",toJson false),
    ("originalSeedAndCurrentRuntimesRetained",toJson true),("objectAndInterfaceDependenciesRetained",toJson true)]).pretty
  IO.println s!"Deleted {targets.size} completed audit executables, {total} logical bytes; no archive"
