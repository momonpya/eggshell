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
  let records := project / "docs/candidates/receipt-reconciliation"
  ensure (!(← (records / "retired.json").pathExists)) "preserve previous cleanup"
  for (directory,name) in [(project / "docs/candidates/checked-original","replay-run.guard.json"),
      (records,"hook-run.guard.json"),(records,"run.guard.json")] do
    let guard ← read (directory / name)
    ensure (guard.getObjValD "state" == toJson "finished" && guard.getObjValD "ownedPids" == toJson (#[] : Array Nat))
      "related job is still active"
  let result ← read (records / "hook/result.json")
  ensure (result.getObjValD "sameSavedBaselineBody" == toJson true &&
    result.getObjValD "bodyPresent" == toJson true) "normal-hook regression did not pass"
  let originals : Array (String × String) ← IO.ofExcept
    ((← read (project / "docs/candidates/read-signal-trace/native-seal.json")).getObjValAs? _ "verifiedOriginalFilesAndRuntimes")
  let targets := #[root / "checked-original-hook-trial",root / "checked-original-replay-trial",
    root / "checked-original-replay-build",root / "receipt-reconciliation-hook-trial",
    root / "receipt-reconciliation-hook-build",root / "checked-original-core",
    root / "checked-original-runtime-build/StudyMain",root / "checked-original-fixed-runtime-build/StudyMain",
    root / "checked-original-negative-audit-build/StudyMain",root / "receipt-reconciliation-build/StudyMain"]
  let retained := #[root / "query-cache-baseline-build",root / "prepared-bindings-build",root / "register-runtime-build",
    root / "checked-original-runtime-build",root / "checked-original-negative-audit-build",
    root / "checked-original-fixed-runtime-build",root / "receipt-reconciliation-build",
    root / "receipt-reconciliation-runtime-build"]
  for directory in retained do
    let response ← IO.FS.readFile (directory / "runtime.rsp")
    for target in targets do
      ensure ((response.splitOn target.toString).length == 1) "retained runtime depends on ended staging"
  for (path,expected) in originals do
    for target in targets do
      ensure (!(path == target.toString || path.startsWith (target.toString ++ "/"))) "cleanup target contains a protected input"
    ensure ((← hash (.mk path)) == expected) "protected original/runtime changed before cleanup"
  let mut total := (0,0)
  for target in targets do
    let counts ← remove target
    total := (total.1+counts.1,total.2+counts.2)
  let mut settings := 0
  for entry in ← root.readDir do
    if (entry.fileName.startsWith "checked-original-replay" || entry.fileName.startsWith "receipt-reconciliation-hook-") &&
        entry.fileName.endsWith ".json" then
      IO.FS.removeFile entry.path
      settings := settings+1
  for (path,expected) in originals do ensure ((← hash (.mk path)) == expected) "cleanup changed a protected input"
  let mut inputs := 0
  for directory in retained do
    for line in (← IO.FS.readFile (directory / "runtime.rsp")).splitOn "\n" do
      if line.trimAscii.isEmpty then continue
      let path : System.FilePath := .mk (← IO.ofExcept (Json.parse line >>= Json.getStr?))
      ensure (← path.pathExists) "cleanup lost a retained native input"
      inputs := inputs+1
  IO.FS.writeFile (records / "retired.json") (Json.mkObj [
    ("targets",toJson (targets.map (·.toString))),("files",toJson total.1),("logicalBytes",toJson total.2),
    ("removedSettings",toJson settings),("retainedNativeInputs",toJson inputs),
    ("protectedHashesBeforeAndAfter",toJson true),("currentCandidate",toJson (root / "receipt-reconciliation-core").toString),
    ("currentRuntime",toJson (root / "receipt-reconciliation-runtime-build/StudyMain").toString),
    ("archiveCreated",toJson false)]).pretty
  IO.println s!"Deleted ended trials: {total.1} files, {total.2} logical bytes; no archive"
