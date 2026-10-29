import Lean.Data.Json.Parser
import Lean.Data.Json.FromToJson
open Lean
private def read (path : System.FilePath) : IO Json :=
  IO.FS.readFile path >>= fun text => IO.ofExcept (Json.parse text)
private partial def inspect (path : System.FilePath) : IO Nat := do
  let info ← path.symlinkMetadata
  if info.type == .symlink then throw (IO.userError "fixture cleanup refuses symlinks")
  if info.type == .file then return info.byteSize.toNat
  unless info.type == .dir do throw (IO.userError "fixture cleanup refuses special files")
  let mut total := 0
  for entry in ← path.readDir do total := total+(← inspect entry.path)
  return total
private partial def remove (path : System.FilePath) : IO Unit := do
  if (← path.symlinkMetadata).type == .dir then
    for entry in ← path.readDir do remove entry.path
    IO.FS.removeDir path
  else IO.FS.removeFile path
def main : IO Unit := do
  let candidate : System.FilePath := "/Users/ovm/.codex/experiments/eggshell/scope-token-study-20261028/shared-snapshot"
  let root := candidate / "project-query-audit"
  let records : System.FilePath := "/Users/ovm/.codex/worktrees/hook-deadline-baseline/eggshell/docs/candidates/project-query-cache"
  unless !(← (records / "retired.json").pathExists) &&
      (← read (records / "result.json")) == (← read (root / "result.json")) do
    throw (IO.userError "seal the exact successful fixture first")
  let guard ← read (records / "native.guard.json")
  unless guard.getObjValD "exitCode" == toJson (0 : Nat) &&
    guard.getObjValD "state" == toJson "finished" &&
    guard.getObjValD "ownedPids" == toJson (#[] : Array Nat) do
    throw (IO.userError "fixture process did not finish")
  let process ← IO.Process.output {cmd := "/bin/ps",args := #["-axo","command="]}
  unless process.exitCode == 0 && (process.stdout.splitOn root.toString).length == 1 do
    throw (IO.userError "fixture still has a live process")
  let mut targets := #[]
  for name in ["project-a.egg","project-b.egg","read-only.egg","private","temporary","another-chat"] do
    let path := root / name
    if ← path.pathExists then targets := targets.push (path,← inspect path)
  for (path,_) in targets do remove path
  for (path,_) in targets do
    if ← path.pathExists then throw (IO.userError "fixture survived deletion")
  IO.FS.writeFile (records / "retired.json") (Json.mkObj [
    ("targets",toJson (targets.map fun (path,bytes) => (path.toString,bytes))),
    ("logicalBytes",toJson (targets.foldl (fun total entry => total+entry.2) 0)),
    ("archiveCreated",toJson false),("originalSeedAndCurrentRuntimeRetained",toJson true)]).pretty
  IO.println "Deleted completed query-cache fixtures; retained only their evidence"
