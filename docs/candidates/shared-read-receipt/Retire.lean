import Lean.Data.Json.Parser
import Lean.Data.Json.FromToJson
open Lean
private def read (path : System.FilePath) : IO Json :=
  IO.FS.readFile path >>= fun text => IO.ofExcept (Json.parse text)
private partial def size (path : System.FilePath) : IO Nat := do
  let info ← path.symlinkMetadata
  if info.type == .symlink then throw (IO.userError "refuse symlink in ended fixture")
  if info.type == .file then return info.byteSize.toNat
  unless info.type == .dir do throw (IO.userError "refuse special file in ended fixture")
  let mut total := 0
  for entry in ← path.readDir do total := total+(← size entry.path)
  return total
private partial def remove (path : System.FilePath) : IO Unit := do
  if (← path.symlinkMetadata).type == .dir then
    for entry in ← path.readDir do remove entry.path
    IO.FS.removeDir path
  else IO.FS.removeFile path
def main : IO Unit := do
  let candidate : System.FilePath := "/Users/ovm/.codex/experiments/eggshell/scope-token-study-20261028/shared-snapshot"
  let records : System.FilePath := "/Users/ovm/.codex/worktrees/hook-deadline-baseline/eggshell/docs/candidates/shared-read-receipt"
  unless !(← (records / "retired.json").pathExists) &&
      (← read (records / "result.json")) == (← read (candidate / "shared-receipt-fixed/result.json")) do
    throw (IO.userError "seal exact results before retiring fixtures")
  for path in [records / "native.guard.json",candidate / "receipt-run.guard.json"] do
    let guard ← read path
    unless guard.getObjValD "exitCode" == toJson (0 : Nat) &&
      guard.getObjValD "state" == toJson "finished" &&
      guard.getObjValD "ownedPids" == toJson (#[] : Array Nat) do
      throw (IO.userError "ended fixture has not finished")
  let targets := #[candidate / "shared-receipt-fixed",candidate / "shared-receipt-audit"]
  let processes ← IO.Process.output {cmd := "/bin/ps",args := #["-axo","command="]}
  unless processes.exitCode == 0 && targets.all (fun path => (processes.stdout.splitOn path.toString).length == 1) do
    throw (IO.userError "fixture still has a live process")
  let mut sizes := #[]
  for target in targets do sizes := sizes.push (target.toString,← size target)
  for target in targets do remove target
  for target in targets do
    if ← target.pathExists then throw (IO.userError "fixture survived deletion")
  IO.FS.writeFile (records / "retired.json") (Json.mkObj [
    ("targets",toJson sizes),("logicalBytes",toJson (sizes.foldl (fun total entry => total+entry.2) 0)),
    ("archiveCreated",toJson false),("originalSeedAndNeededBuildDependenciesRetained",toJson true)]).pretty
  IO.println "Deleted completed receipt fixtures; no archive"
