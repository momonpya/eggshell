import Lean.Data.Json.Parser
import Lean.Data.Json.FromToJson
open Lean
private def read (path : System.FilePath) : IO Json :=
  IO.FS.readFile path >>= fun text => IO.ofExcept (Json.parse text)
private partial def size (path : System.FilePath) : IO Nat := do
  let metadata ← path.symlinkMetadata
  if metadata.type == .dir then
    let mut total := 0
    for entry in ← path.readDir do total := total+(← size entry.path)
    return total
  return metadata.byteSize.toNat
private partial def remove (path : System.FilePath) : IO Unit := do
  if (← path.symlinkMetadata).type == .dir then
    for entry in ← path.readDir do remove entry.path
    IO.FS.removeDir path
  else IO.FS.removeFile path
private partial def protect (path : System.FilePath) (targets : Array System.FilePath) : IO Unit := do
  for entry in ← path.readDir do
    let metadata ← entry.path.symlinkMetadata
    if metadata.type == .dir then protect entry.path targets
    else if metadata.type == .symlink then
      let actual ← IO.FS.realPath entry.path
      unless targets.all (fun target => actual != target &&
          !actual.toString.startsWith (target.toString ++ "/")) do
        throw (IO.userError "retained build depends on ended trial")
def main : IO Unit := do
  let root : System.FilePath := "/Users/ovm/.codex/experiments/eggshell/scope-token-study-20261028/shared-snapshot"
  let project : System.FilePath := "/Users/ovm/.codex/worktrees/hook-deadline-baseline/eggshell"
  let output := project / "docs/candidates/aggregate-delta"
  unless !(← (output / "retired-data.json").pathExists) do throw (IO.userError "preserve prior retirement")
  let report ← read (output / "hook-comparison.json")
  unless report.getObjValD "sameBodyBytes" == toJson true &&
      report.getObjValD "sameFrozenEvidenceAndAlternatives" == toJson true &&
      (← IO.FS.readBinFile (output / "hook/body.txt")) ==
      (← IO.FS.readBinFile (root / "distinct-hook-trial/body.txt")) do
    throw (IO.userError "seal unchanged actual delivery first")
  for name in ["distinct-hook.guard.json","distinct-native.guard.json","point-run.guard.json",
      "point-profile.guard.json","aggregate-run.guard.json","aggregate-reference-2.guard.json"] do
    let guard ← read (root / name)
    unless guard.getObjValD "state" == toJson "finished" &&
        guard.getObjValD "ownedPids" == toJson (#[] : Array Nat) do
      throw (IO.userError "wait for ended trial guards")
  let targets := #[root / "distinct-hook-trial",root / "prefix",root / "aggregate-build",root / "aggregate-delta"]
  let processes ← IO.Process.output {cmd := "/bin/ps",args := #["-axo","command="]}
  unless processes.exitCode == 0 && targets.all (fun target =>
      (processes.stdout.splitOn target.toString).length == 1) do
    throw (IO.userError "target still owns a process")
  for name in ["product-build","hook-build"] do
    protect (root / name / "lib") targets
    let response ← IO.FS.readFile (root / name / "runtime.rsp")
    unless targets.all (fun target => (response.splitOn target.toString).length == 1) do
      throw (IO.userError "retained native build depends on target")
  let mut retired := #[]
  let mut bytes := 0
  for path in targets do
    let count ← size path
    bytes := bytes+count
    retired := retired.push (path.toString,count)
  IO.FS.writeFile (output / "retired-data.json") (Json.mkObj [("targets",toJson retired),
    ("logicalBytes",toJson bytes),("sourceSeedAndCurrentRuntimeRetained",toJson true),
    ("currentNativeDependenciesChecked",toJson true),("archiveCreated",toJson false)]).pretty
  for path in targets do remove path
  IO.println s!"Deleted {targets.size} ended targets, {bytes} logical bytes; no archive"
