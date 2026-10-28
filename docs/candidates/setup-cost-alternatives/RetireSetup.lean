import Lean.Data.Json.Parser
import Lean.Data.Json.FromToJson
open Lean
private partial def remove (path : System.FilePath) : IO Nat := do
  let metadata ← path.symlinkMetadata
  if metadata.type == .dir then
    let mut bytes := 0
    for entry in ← path.readDir do bytes := bytes+(← remove entry.path)
    IO.FS.removeDir path
    return bytes
  IO.FS.removeFile path
  return metadata.byteSize.toNat
def main : IO Unit := do
  let root : System.FilePath := "/Users/ovm/.codex/experiments/eggshell/scope-token-study-20261028/shared-snapshot"
  let output : System.FilePath := "/Users/ovm/.codex/worktrees/hook-deadline-baseline/eggshell/docs/candidates/setup-cost-alternatives"
  unless !(← (output / "retired-data.json").pathExists) do throw (IO.userError "keep retirement record")
  let decision ← IO.ofExcept (Json.parse (← IO.FS.readFile (output / "decision.json")))
  unless decision.getObjValD "rejected" == toJson true do throw (IO.userError "candidate not sealed")
  let targets := #[root / "missing-build",root / "setup-build"]
  let processes ← IO.Process.output {cmd := "/bin/ps",args := #["-axo","command="]}
  unless processes.exitCode == 0 && targets.all (fun path => (processes.stdout.splitOn path.toString).length == 1) do
    throw (IO.userError "native trial still live")
  for retained in ["product-build","hook-build"] do
    let response ← IO.FS.readFile (root / retained / "runtime.rsp")
    unless targets.all (fun path => (response.splitOn path.toString).length == 1) do
      throw (IO.userError "current runtime refers to ended build")
  let mut retired := #[]
  for path in targets do retired := retired.push (path.toString,← remove path)
  IO.FS.writeFile (output / "retired-data.json") (Json.mkObj [("targets",toJson retired),
    ("archiveCreated",toJson false),("newDatabaseOrCacheCreated",toJson false),
    ("currentSourceAndRuntimeRetained",toJson true)]).pretty
  IO.println "Deleted both ended native builds, no archive or DB changes"
