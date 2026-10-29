import Lean.Data.Json.Parser
import Lean.Data.Json.FromToJson
open Lean

private def read (path : System.FilePath) : IO Json :=
  IO.FS.readFile path >>= fun text => IO.ofExcept (Json.parse text)

private partial def size (path : System.FilePath) : IO Nat := do
  let metadata ← path.symlinkMetadata
  if metadata.type == .dir then
    let mut bytes := 0
    for entry in ← path.readDir do bytes := bytes+(← size entry.path)
    return bytes
  return metadata.byteSize.toNat

private partial def remove (path : System.FilePath) : IO Unit := do
  if (← path.symlinkMetadata).type == .dir then
    for entry in ← path.readDir do remove entry.path
    IO.FS.removeDir path
  else IO.FS.removeFile path

def main : IO Unit := do
  let root : System.FilePath := "/Users/ovm/.codex/experiments/eggshell/scope-token-study-20261028/shared-snapshot"
  let records : System.FilePath := "/Users/ovm/.codex/worktrees/hook-deadline-baseline/eggshell/docs/candidates/source-knowledge"
  unless (← records.pathExists) && !(← (records / "retired.json").pathExists) do
    throw (IO.userError "seal evidence before retiring ended fixtures")
  for name in ["hook.guard.json","scope-and-recovery.guard.json","negative-checks.guard.json"] do
    let guard ← read (records / name)
    unless guard.getObjValD "state" == toJson "finished" && guard.getObjValD "exitCode" == toJson (0 : Nat) &&
        guard.getObjValD "ownedPids" == toJson (#[] : Array Nat) do
      throw (IO.userError "wait for successful terminal fixture guards")
  let directories := #["source-knowledge-contract","cached-knowledge-contract","usage-prepared-trial",
    "source-knowledge-hook","checked-source-knowledge-hook"]
  let executables := #["source-knowledge-build","source-knowledge-contract-fixed-build",
    "source-knowledge-runtime-build","usage-prepared-hook-build","cached-source-knowledge-pass-build",
    "prepared-usage-build","cached-usage-runtime-build","prepared-usage-hook-build",
    "checked-usage-hook-build","cached-knowledge-contract-fixed-build","source-knowledge-negative-build"]
  let targets := directories.map (fun name => root / System.FilePath.mk name) ++
    executables.map (fun name => root / System.FilePath.mk name / "StudyMain")
  let processes ← IO.Process.output {cmd := "/bin/ps",args := #["-axo","command="]}
  unless processes.exitCode == 0 && targets.all (fun target =>
      (processes.stdout.splitOn target.toString).length == 1) do
    throw (IO.userError "ended fixture still owns a process")
  let retained := root / "dependency-checked-runtime-build/StudyMain"
  unless (← retained.pathExists) && targets.all (· != retained) do
    throw (IO.userError "retain the checked current candidate")
  let mut rows := #[]
  let mut bytes := 0
  for target in targets do
    if !(← target.pathExists) then continue
    let count ← size target
    bytes := bytes+count
    rows := rows.push (target.toString,count)
  IO.FS.writeFile (records / "retired.json") (Json.mkObj [("targets",toJson rows),
    ("logicalBytes",toJson bytes),("archiveCreated",toJson false),
    ("sourceSeedAndCheckedRuntimeRetained",toJson true),("objectsAndInterfacesRetained",toJson true)]).pretty
  for target in targets do if ← target.pathExists then remove target
  IO.println s!"Deleted {rows.size} ended targets, {bytes} logical bytes; no archive"
