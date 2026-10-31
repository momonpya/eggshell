import Lean
open Lean
private def ensure (ok : Bool) (message : String) : IO Unit := unless ok do throw (IO.userError message)
private def read (path : System.FilePath) : IO Json := IO.FS.readFile path >>= fun text => IO.ofExcept (Json.parse text)
private def hash (path : System.FilePath) : IO String := do
  let result ← IO.Process.output {cmd := "/usr/bin/shasum",args := #["-a","256",path.toString]}
  ensure (result.exitCode == 0) "cannot verify protected source/runtime"
  return (result.stdout.splitOn " ").headD ""
private partial def remove (path : System.FilePath) : IO (Nat × Nat) := do
  let metadata ← path.symlinkMetadata
  if metadata.type != .dir then
    IO.FS.removeFile path
    return (1,if metadata.type == .file then metadata.byteSize.toNat else 0)
  let mut total := (0,0)
  for entry in ← path.readDir do
    let counts ← remove entry.path
    total := (total.1+counts.1,total.2+counts.2)
  IO.FS.removeDir path
  return total

def main : IO Unit := do
  let project : System.FilePath := "/Users/ovm/.codex/worktrees/hook-deadline-baseline/eggshell"
  let root : System.FilePath := "/Users/ovm/.codex/experiments/eggshell/scope-token-study-20261028/shared-snapshot"
  let records := project / "docs/candidates/owner-palette"
  ensure (!(← (records / "retired.json").pathExists)) "preserve previous palette cleanup"
  let result ← read (records / "compact/result.json")
  ensure (result.getObjValD "sourceUnchanged" == toJson true &&
    (result.getObjValD "cold").getObjValD "successes" == toJson (80 : Nat) &&
    (result.getObjValD "warm").getObjValD "successes" == toJson (80 : Nat)) "palette audit did not finish"
  let stopped ← read (records / "compact/shutdown.json")
  ensure (stopped.getObjValD "processExited" == toJson true && stopped.getObjValD "acknowledged" == toJson true)
    "palette service did not stop"
  for relative in ["run.guard.json","resumed/run.guard.json","leased/run.guard.json","compact/run.guard.json"] do
    let guard ← read (records / relative)
    ensure (guard.getObjValD "state" == toJson "finished" && guard.getObjValD "ownedPids" == toJson (#[] : Array Nat))
      "related palette process remains active"
  let originals : Array (String × String) ← IO.ofExcept
    ((← read (project / "docs/candidates/read-signal-trace/native-seal.json")).getObjValAs? _ "verifiedOriginalFilesAndRuntimes")
  for (path,expected) in originals do ensure ((← hash (.mk path)) == expected) "protected input changed before cleanup"
  let target := root / "owner-palette-trial"
  let retained := #[root / "query-cache-baseline-build",root / "prepared-bindings-build",root / "register-runtime-build",
    root / "receipt-reconciliation-runtime-build",root / "owner-palette-build"]
  for build in retained do
    ensure (((← IO.FS.readFile (build / "runtime.rsp")).splitOn target.toString).length == 1)
      "retained native build uses ended trial"
  let counts ← remove target
  let mut removedSettings := 0
  for entry in ← root.readDir do
    if entry.fileName.startsWith "owner-palette-" && entry.fileName.endsWith ".guard.settings.json" then
      IO.FS.removeFile entry.path
      removedSettings := removedSettings+1
  for (path,expected) in originals do ensure ((← hash (.mk path)) == expected) "cleanup changed a protected input"
  let mut nativeInputs := 0
  for build in retained do
    for line in (← IO.FS.readFile (build / "runtime.rsp")).splitOn "\n" do
      if line.trimAscii.isEmpty then continue
      let path : System.FilePath := .mk (← IO.ofExcept (Json.parse line >>= Json.getStr?))
      ensure (← path.pathExists) "cleanup lost a retained native dependency"
      nativeInputs := nativeInputs+1
  IO.FS.writeFile (records / "retired.json") (Json.mkObj [
    ("files",toJson counts.1),("logicalBytes",toJson counts.2),("removedSettings",toJson removedSettings),
    ("retainedNativeInputs",toJson nativeInputs),("protectedHashesBeforeAndAfter",toJson true),
    ("activeImplementation",toJson (root / "owner-palette-core").toString),
    ("activeSourceService",toJson (root / "owner-palette-build/StudyMain").toString),
    ("trialDatabaseAndCachesRemoved",toJson true),("archiveCreated",toJson false)]).pretty
  IO.println s!"Deleted ended palette DB/cache: {counts.1} files, {counts.2} logical bytes; no archive"
