import Lean.Data.Json.Parser
import Lean.Data.Json.FromToJson
open Lean

private def check (ok : Bool) (message : String) : IO Unit := unless ok do throw (IO.userError message)
private def read (path : System.FilePath) : IO Json := IO.FS.readFile path >>= fun text => IO.ofExcept (Json.parse text)
private def hash (path : System.FilePath) : IO String := do
  let result ← IO.Process.output {cmd := "/usr/bin/shasum",args := #["-a","256",path.toString]}
  check (result.exitCode == 0) "cannot seal local reader cleanup"
  return (result.stdout.splitOn " ").headD ""
private def verify (originals : Array (String × String)) : IO Unit := do
  for (path,expected) in originals do check ((← hash (.mk path)) == expected) "protected original changed"
private def inside (path root : System.FilePath) : Bool :=
  path == root || path.toString.startsWith (root.toString ++ "/")
private partial def protect (directory : System.FilePath) (targets : Array System.FilePath) : IO Unit := do
  for entry in ← directory.readDir do
    let info ← entry.path.symlinkMetadata
    if info.type == .dir then protect entry.path targets
    else if info.type == .symlink then
      check (!(targets.any (inside (← IO.FS.realPath entry.path)))) "retained interface needs this trial"
private partial def remove (path : System.FilePath) : IO (Nat × Nat) := do
  let metadata ← path.symlinkMetadata
  if metadata.type == .dir then
    let mut total := (0,0)
    for entry in ← path.readDir do
      let part ← remove entry.path
      total := (total.1+part.1,total.2+part.2)
    IO.FS.removeDir path
    return total
  IO.FS.removeFile path
  return (1,if metadata.type == .file then metadata.byteSize.toNat else 0)

def main : IO Unit := do
  let project : System.FilePath := "/Users/ovm/.codex/worktrees/hook-deadline-baseline/eggshell"
  let root : System.FilePath := "/Users/ovm/.codex/experiments/eggshell/scope-token-study-20261028/shared-snapshot"
  let records := project / "docs/candidates/local-reader"
  check (!(← (records / "retired.json").pathExists)) "preserve completed cleanup"
  let exit ← read (records / "exit.json")
  check (exit.getObjValD "exitCode" == toJson (0 : Nat) &&
    exit.getObjValD "protectedHashesBeforeAndAfter" == toJson true) "local reader trial is unfinished"
  let report ← read (records / "results.json")
  check (report.getObjValD "adopted" == toJson false && report.getObjValD "answeringModels" == toJson (0 : Nat) &&
    report.getObjValD "oldPinAfterPublication" == toJson true && report.getObjValD "stop" == toJson true)
    "local reader trial is incomplete or adopted"
  for name in ["actual","fixture"] do
    let result := report.getObjValD name
    check ((result.getObjValD "transport").getObjValD "samePlan" == toJson true &&
      result.getObjValD "authScopeExpiryAndRelease" == toJson true) "reader equivalence failed"
  for entry in ← records.readDir do
    if entry.fileName.endsWith ".guard.json" then
      let guard ← read entry.path
      check (guard.getObjValD "state" == toJson "finished" && guard.getObjValD "ownedPids" == toJson (#[] : Array Nat))
        "local reader guard is live"
  for name in ["runtime-lease-native-closure.json","audit-native-closure.json"] do
    check ((← read (records / name)).getObjValD "consistent" == toJson true) "native closure audit missing"
  let originals : Array (String × String) ← IO.ofExcept ((← read
    (project / "docs/candidates/read-signal-trace/native-seal.json")).getObjValAs? _ "verifiedOriginalFilesAndRuntimes")
  let originals := originals.push ((root / "register-runtime-build/StudyMain").toString,
    "1bd3d15bb3c708a14785c983fcb8e1c95d650bc55f837202d84538de0bda787b")
  verify originals
  let mut targets := #[]
  for entry in ← root.readDir do
    if entry.fileName.startsWith "local-reader-" then targets := targets.push entry.path
  check (targets.size > 0) "no owned local reader artifacts"
  let retained := #[root / "query-cache-baseline-build",root / "prepared-bindings-build",root / "register-runtime-build"]
  let mut links := #[]
  for build in retained do
    for line in (← IO.FS.readFile (build / "runtime.rsp")).splitOn "\n" do
      if line.trimAscii.isEmpty then continue
      let path : System.FilePath := .mk (← IO.ofExcept (Json.parse line >>= Json.getStr?))
      check (!(targets.any (inside path))) "retained runtime needs local reader artifact"
      links := links.push path
    protect (build / "lib") targets
  let running ← IO.Process.output {cmd := "/bin/ps",args := #["-axo","command="]}
  check (running.exitCode == 0) "cannot inspect local reader processes"
  for path in targets do
    check ((running.stdout.splitOn path.toString).length == 1) "local reader artifact is live"
  let mut removed := #[]
  let mut total := (0,0)
  for path in targets do
    let part ← remove path
    removed := removed.push (path.toString,part.1,part.2)
    total := (total.1+part.1,total.2+part.2)
  verify originals
  for path in links do check (← path.pathExists) "cleanup removed a retained native input"
  IO.FS.writeFile (records / "retired.json") (Json.mkObj [("removed",toJson removed),
    ("files",toJson total.1),("logicalBytes",toJson total.2),("retainedNativeLinkInputs",toJson links.size),
    ("protectedHashesBeforeAndAfter",toJson true),("archiveCreated",toJson false),("adopted",toJson false)]).pretty
  IO.println s!"Deleted ended local reader trial: {total.1} files, {total.2} logical bytes"
