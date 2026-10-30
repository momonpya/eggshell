import Lean
open Lean
private def check (ok : Bool) (message : String) : IO Unit := unless ok do throw (IO.userError message)
private def read (path : System.FilePath) : IO Json := IO.FS.readFile path >>= fun text => IO.ofExcept (Json.parse text)
private partial def remove (path : System.FilePath) : IO (Nat × Nat) := do
  let info ← path.symlinkMetadata
  if info.type != .dir then
    IO.FS.removeFile path
    return (1,if info.type == .file then info.byteSize.toNat else 0)
  let mut result := (0,0)
  for entry in ← path.readDir do
    let counts ← remove entry.path
    result := (result.1+counts.1,result.2+counts.2)
  IO.FS.removeDir path
  return result

def main : IO Unit := do
  let project : System.FilePath := "/Users/ovm/.codex/worktrees/hook-deadline-baseline/eggshell"
  let root : System.FilePath := "/Users/ovm/.codex/experiments/eggshell/scope-token-study-20261028/shared-snapshot"
  let records := project / "docs/candidates/prepared-owner-arena"
  check (!(← (records / "retired-trials.json").pathExists)) "preserve previous trial cleanup"
  let result ← read (records / "result.json")
  check (result.getObjValD "sourceUnchanged" == toJson true &&
    result.getObjValD "protectedHashesBeforeAndAfter" == toJson true) "source was not verified"
  for name in ["run-typed.guard.json","run-manifest.guard.json"] do
    let record ← read (records / name)
    check (record.getObjValD "state" == toJson "finished" &&
      record.getObjValD "ownedPids" == toJson (#[] : Array Nat)) "native audit remains active"
  let live ← IO.Process.output {cmd := "/usr/bin/pgrep",args := #["-f","/prepared-owner-build/StudyMain( |$)"]}
  check (live.exitCode == 1) "native audit executable remains active"
  IO.FS.writeFile (records / "fixture-manifest.json")
    (← IO.FS.readFile (root / "prepared-owner-audit-manifest/canonical/manifest.json"))
  let mut files := 0
  let mut bytes := 0
  for path in [root / "prepared-owner-audit",root / "prepared-owner-audit-manifest"] do
    let counts ← remove path
    files := files+counts.1
    bytes := bytes+counts.2
  let mut settings := 0
  for entry in ← root.readDir do
    if entry.fileName.startsWith "prepared-owner-" && entry.fileName.endsWith ".guard.settings.json" then
      IO.FS.removeFile entry.path
      settings := settings+1
  IO.FS.writeFile (records / "retired-trials.json") (Json.mkObj [
    ("files",toJson files),("logicalBytes",toJson bytes),("removedSettings",toJson settings),
    ("keptCurrentImplementationAndNativeBuild",toJson true),("originalSourceTouched",toJson false),
    ("archiveCreated",toJson false)]).pretty
  IO.println s!"Deleted ended arena DBs: {files} files, {bytes} logical bytes"
