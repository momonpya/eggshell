import Lean.Data.Json.Parser
import Lean.Data.Json.FromToJson
open Lean

private def project : System.FilePath := "/Users/ovm/.codex/worktrees/hook-deadline-baseline/eggshell"
private def trial : System.FilePath := "/Users/ovm/.codex/experiments/eggshell/verified-winner-20261027"

private partial def files (path : System.FilePath) : IO (Array (System.FilePath × Nat)) := do
  let state ← path.symlinkMetadata
  if state.type == .dir then
    let mut found := #[]
    for entry in ← path.readDir do found := found ++ (← files entry.path)
    return found
  return #[(path,if state.type == .file then state.byteSize.toNat else 0)]

private partial def emptyDirectories (path : System.FilePath) : IO Unit := do
  if (← path.symlinkMetadata).type == .dir then
    for entry in ← path.readDir do emptyDirectories entry.path
    unless (← path.readDir).isEmpty do throw (IO.userError "unexpected remaining file")
    IO.FS.removeDir path

def main : IO Unit := do
  let record := project / "docs/candidates/batched-bindings/cleanup.json"
  unless !(← record.pathExists) do throw (IO.userError "cleanup already recorded")
  for name in ["batched-bindings/result.json","batched-bindings/queries.json",
      "batched-bindings/run.guard.json","source-rpc-removal/removal.patch",
      "source-rpc-removal/before-digests.json","source-rpc-removal/after-digests.json"] do
    unless ← (project / "docs/candidates" / name).pathExists do
      throw (IO.userError "capture is incomplete")
  let targets := #[trial / "batch-build",trial / "batched-bindings-audit",trial / "discarded-source-rpc"]
  let live ← IO.Process.output {cmd := "/bin/ps",args := #["-axo","command="]}
  unless live.exitCode == 0 do throw (IO.userError live.stderr)
  for target in targets do
    unless (live.stdout.splitOn target.toString).length == 1 do
      throw (IO.userError s!"active process uses ended trial: {target}")
  for response in ["product-build/runtime.rsp","controller-build/runtime.rsp","objects.json"] do
    let text ← IO.FS.readFile (trial / response)
    for target in targets do
      unless (text.splitOn target.toString).length == 1 do
        throw (IO.userError s!"current dependency uses ended trial: {target}")
  let current := #[trial / "product-build/StudyMain",trial / "controller-build/StudyMain"]
  let digest : IO String := do
    let result ← IO.Process.output {
      cmd := "/usr/bin/shasum",
      args := #["-a","256"] ++ current.map (·.toString)}
    unless result.exitCode == 0 do throw (IO.userError result.stderr)
    pure result.stdout
  let before ← digest
  let mut removed := #[]
  for target in targets do removed := removed ++ (← files target)
  unless removed.all (fun row => !row.1.toString.endsWith ".egg") do
    throw (IO.userError "this cleanup must not delete a DB")
  for (path,_) in removed do IO.FS.removeFile path
  for target in targets do emptyDirectories target
  unless (← digest) == before do throw (IO.userError "current executable changed")
  IO.FS.writeFile record (Json.mkObj [
    ("deletedPaths",toJson (targets.map (·.toString))),
    ("deletedFiles",toJson removed.size),
    ("deletedLogicalBytes",toJson (removed.foldl (fun sum row => sum + row.2) 0)),
    ("currentBinariesUnchanged",toJson true),("newDatabaseCreated",toJson false),
    ("archiveCreated",toJson false)]).pretty
