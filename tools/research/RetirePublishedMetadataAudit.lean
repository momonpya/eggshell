import Lean
open Lean
private def check (ok : Bool) (message : String) : IO Unit := unless ok do throw (IO.userError message)
private def read (path : System.FilePath) : IO Json := IO.FS.readFile path >>= fun text => IO.ofExcept (Json.parse text)
private def hash (path : System.FilePath) : IO String := do
  let found ← IO.Process.output {cmd := "/usr/bin/shasum",args := #["-a","256",path.toString]}
  check (found.exitCode == 0) "cannot check protected input"
  return (found.stdout.splitOn " ").headD ""
private partial def remove (path : System.FilePath) : IO (Nat × Nat) := do
  let info ← path.symlinkMetadata
  if info.type != .dir then
    IO.FS.removeFile path
    return (1,if info.type == .file then info.byteSize.toNat else 0)
  let mut total := (0,0)
  for entry in ← path.readDir do
    let next ← remove entry.path
    total := (total.1+next.1,total.2+next.2)
  IO.FS.removeDir path
  return total

def main : IO Unit := do
  let project : System.FilePath := "/Users/ovm/.codex/worktrees/hook-deadline-baseline/eggshell"
  let root : System.FilePath := "/Users/ovm/.codex/experiments/eggshell/scope-token-study-20261028/shared-snapshot"
  let records := project / "docs/candidates/published-plan"
  let output := records / "metadata-retired.json"
  check (!(← output.pathExists)) "preserve metadata cleanup receipt"
  for name in ["audit.guard.json","audit-compact.guard.json","audit-current.guard.json"] do
    let stopped ← read (records / name)
    check (stopped.getObjValD "state" == toJson "finished" && stopped.getObjValD "exitCode" == toJson (0 : Nat) &&
      stopped.getObjValD "ownedPids" == toJson (#[] : Array Nat)) "metadata audit is not terminal"
  let inspected ← IO.Process.output {
    cmd := "/Users/ovm/.elan/toolchains/leanprover--lean4---v4.33.0/bin/lean",
    args := #["-M3072","--run",(project / "tools/research/StudyBuildClosureAudit.lean").toString,
      "inspect",(root / "published-plan-audit-build").toString,(records / "metadata-native-closure.json").toString]}
  check (inspected.exitCode == 0) "metadata native closure mismatch"
  let originals : Array (String × String) ← IO.ofExcept (fromJson?
    ((← read (project / "docs/candidates/read-signal-trace/native-seal.json")).getObjValD "verifiedOriginalFilesAndRuntimes"))
  for (path,expected) in originals do check ((← hash (.mk path)) == expected) "protected original changed"
  let mut retained := #[]
  let mut binaries := #[]
  for name in ["published-plan-runtime-build","service-plan-runtime-build","source-plan-runtime-build",
      "owner-palette-runtime-build","owner-palette-build","receipt-reconciliation-runtime-build","query-cache-baseline-build"] do
    let directory := root / name
    binaries := binaries.push (directory / "StudyMain",← hash (directory / "StudyMain"))
    for line in (← IO.FS.readFile (directory / "runtime.rsp")).splitOn "\n" do
      if line.trimAscii.isEmpty then continue
      let path ← IO.ofExcept (Json.parse line >>= Json.getStr?)
      check (!(path.contains "published-plan-audit-build")) "runtime borrows completed audit input"
      if path.endsWith ".o" then
        check (← System.FilePath.pathExists path) "missing live native input"
        retained := retained.push path
  let mut deleted := #[]
  for name in ["published-plan-audit-db","published-plan-compact-audit-db","published-plan-current-audit-db","published-plan-audit-build"] do
    let path := root / name
    if ← path.pathExists then
      check ((← path.symlinkMetadata).type == .dir) "cleanup target is not its owned directory"
      let (files,bytes) ← remove path
      deleted := deleted.push (Json.mkObj [("path",toJson path.toString),("files",toJson files),("logicalBytes",toJson bytes)])
  for path in retained do check (← System.FilePath.pathExists path) "cleanup removed live native input"
  for (path,expected) in binaries do check ((← hash path) == expected) "cleanup changed runtime"
  for (path,expected) in originals do check ((← hash (.mk path)) == expected) "cleanup changed original"
  IO.FS.writeFile output (Json.mkObj [("deleted",toJson deleted),("retainedNativeInputs",toJson retained.size),
    ("sourceAndRuntimesUnchanged",toJson true),("compressedOrArchived",toJson false)]).pretty
  IO.println "Removed terminal metadata audit databases and helper; retained original sources and active native inputs"
