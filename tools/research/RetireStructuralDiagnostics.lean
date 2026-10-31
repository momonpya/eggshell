import Lean
open Lean
private def check (ok : Bool) (message : String) : IO Unit := unless ok do throw (IO.userError message)
private def read (path : System.FilePath) : IO Json := IO.FS.readFile path >>= fun text => IO.ofExcept (Json.parse text)
private def hash (path : System.FilePath) : IO String := do
  let found ← IO.Process.output {cmd := "/usr/bin/shasum",args := #["-a","256",path.toString]}
  check (found.exitCode == 0) "cannot verify protected diagnostic input"
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
  let output := project / "docs/candidates/recorded-navigation/retired.json"
  check (!(← output.pathExists)) "preserve diagnostic cleanup"
  for name in ["recorded-navigation","projection-domain"] do
    let directory := project / "docs/candidates" / name
    let stopped ← read (directory / "audit.guard.json")
    check (stopped.getObjValD "state" == toJson "finished" && stopped.getObjValD "exitCode" == toJson (0 : Nat) &&
      stopped.getObjValD "ownedPids" == toJson (#[] : Array Nat)) "diagnostic is not terminal"
    let inspected ← IO.Process.output {
      cmd := "/Users/ovm/.elan/toolchains/leanprover--lean4---v4.33.0/bin/lean"
      args := #["-M3072","--run",(project / "tools/research/StudyBuildClosureAudit.lean").toString,
        "inspect",(root / (name ++ "-build")).toString,(directory / "native-closure.json").toString]}
    check (inspected.exitCode == 0) "diagnostic native closure mismatch"
  let originals : Array (String × String) ← IO.ofExcept (fromJson?
    ((← read (project / "docs/candidates/read-signal-trace/native-seal.json")).getObjValD "verifiedOriginalFilesAndRuntimes"))
  for (path,expected) in originals do check ((← hash (.mk path)) == expected) "protected source changed"
  let mut retained := #[]
  let mut runtimes := #[]
  for name in ["service-plan-runtime-build","source-plan-runtime-build","owner-palette-runtime-build",
      "owner-palette-build","receipt-reconciliation-runtime-build","query-cache-baseline-build"] do
    let directory := root / name
    let binary := directory / "StudyMain"
    runtimes := runtimes.push (binary,← hash binary)
    for line in (← IO.FS.readFile (directory / "runtime.rsp")).splitOn "\n" do
      if line.trimAscii.isEmpty then continue
      let path ← IO.ofExcept (Json.parse line >>= Json.getStr?)
      check (!(path.contains "recorded-navigation-build") && !(path.contains "projection-domain-build"))
        "active runtime borrows a completed diagnostic"
      if path.endsWith ".o" then
        check (← System.FilePath.pathExists path) "missing active native input"
        retained := retained.push path
  let mut deleted := #[]
  let discard (path : System.FilePath) : IO Json := do
    let (files,bytes) ← remove path
    return Json.mkObj [("path",toJson path.toString),("files",toJson files),("logicalBytes",toJson bytes)]
  for name in ["recorded-navigation","projection-domain"] do
    let directory := project / "docs/candidates" / name
    deleted := deleted.push (← discard (root / (name ++ "-build")))
    for entry in ← (directory / "audit").readDir do
      if entry.fileName.endsWith ".txt" then deleted := deleted.push (← discard entry.path)
  for name in ["RecordedNavigation","RecordedNavigationAudit","ProjectionDomainAudit"] do
    let path := root / "service-plan-core/tools/research" / (name ++ ".lean")
    if ← path.pathExists then deleted := deleted.push (← discard path)
  for path in retained do check (← System.FilePath.pathExists path) "cleanup removed an active input"
  for (path,expected) in runtimes do check ((← hash path) == expected) "cleanup changed active runtime"
  for (path,expected) in originals do check ((← hash (.mk path)) == expected) "cleanup changed original source"
  IO.FS.writeFile output (Json.mkObj [("deleted",toJson deleted),("retainedNativeInputs",toJson retained.size),
    ("sourceUnchanged",toJson true),("runtimesUnchanged",toJson true),("compressedOrArchived",toJson false),
    ("remainingEvidence",toJson "plans, source, proofs, fixtures, compact result/range metadata and body hashes; diagnostic bodies/builds deleted")]).pretty
  IO.println "Deleted ended structural-diagnostic builds and full bodies; protected inputs unchanged"
