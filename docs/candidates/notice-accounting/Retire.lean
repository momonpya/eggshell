import Lean.Data.Json.Parser
import Lean.Data.Json.FromToJson
open Lean
private def read (path : System.FilePath) : IO Json :=
  IO.FS.readFile path >>= fun text => IO.ofExcept (Json.parse text)
private partial def size (path : System.FilePath) : IO Nat := do
  let info ← path.symlinkMetadata
  if info.type != .dir then return info.byteSize.toNat
  let mut total := 0
  for entry in ← path.readDir do total := total+(← size entry.path)
  return total
private partial def remove (path : System.FilePath) : IO Unit := do
  if (← path.symlinkMetadata).type == .dir then
    for entry in ← path.readDir do remove entry.path
    IO.FS.removeDir path
  else IO.FS.removeFile path
private partial def protect (directory : System.FilePath) (targets : Array System.FilePath) : IO Unit := do
  for entry in ← directory.readDir do
    let info ← entry.path.symlinkMetadata
    if info.type == .dir then protect entry.path targets
    else if info.type == .symlink then
      let actual ← IO.FS.realPath entry.path
      unless targets.all (fun target => actual != target &&
        !actual.toString.startsWith (target.toString ++ "/")) do
        throw (IO.userError "active interface depends on ended replay")
def main : IO Unit := do
  let root : System.FilePath := "/Users/ovm/.codex/experiments/eggshell/scope-token-study-20261028/shared-snapshot"
  let project : System.FilePath := "/Users/ovm/.codex/worktrees/hook-deadline-baseline/eggshell"
  let records := project / "docs/candidates/notice-accounting"
  unless !(← (records / "retired.json").pathExists) &&
    (← read (records / "decision.json")).getObjValD "nativeSourceExact" == toJson true &&
    (← read (records / "replay.json")) == (← read (root / "family-pricing-final.json")) &&
    (← IO.FS.readBinFile (records / "Replay.lean")) == (← IO.FS.readBinFile (project / "tools/research/NoticeCostReplay.lean")) do
    throw (IO.userError "seal exact result and source first")
  for name in ["native.guard.json","build.guard.json","invalid-stale-run.guard.json"] do
    let guard ← read (records / name)
    unless guard.getObjValD "state" == toJson "finished" &&
      guard.getObjValD "ownedPids" == toJson (#[] : Array Nat) do throw (IO.userError "wait for ended replay")
  let targets := #[root / "notice-build",root / "notice-replay.json",root / "catalog-control-replay.json",
    root / "family-pricing-replay.json",root / "family-pricing-final.json"]
  let processes ← IO.Process.output {cmd := "/bin/ps",args := #["-axo","command="]}
  unless processes.exitCode == 0 && targets.all (fun target =>
    (processes.stdout.splitOn target.toString).length == 1) do throw (IO.userError "replay still has a live process")
  for build in #[root / "product-build",root / "hook-build",root.parent.get! / "controller-build"] do
    protect (build / "lib") targets
    let response ← IO.FS.readFile (build / "runtime.rsp")
    unless targets.all (fun target => (response.splitOn target.toString).length == 1) do
      throw (IO.userError "native dependency remains live")
  let mut total := 0
  let mut sizes := #[]
  for target in targets do
    let bytes ← size target
    total := total+bytes
    sizes := sizes.push (target.toString,bytes)
  IO.FS.writeFile (records / "retired.json") (Json.mkObj [("targets",toJson sizes),
    ("logicalBytes",toJson total),("archiveCreated",toJson false),
    ("sourceAndCurrentRuntimeRetained",toJson true),("activeDependenciesChecked",toJson true)]).pretty
  for target in targets do remove target
  IO.println s!"Deleted {targets.size} ended targets, {total} logical bytes; no archive"
