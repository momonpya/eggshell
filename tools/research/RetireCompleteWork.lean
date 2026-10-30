import Lean
open Lean

private def check (ok : Bool) (message : String) : IO Unit := unless ok do throw (IO.userError message)
private def read (path : System.FilePath) : IO Json := IO.FS.readFile path >>= fun text => IO.ofExcept (Json.parse text)
private def hash (path : System.FilePath) : IO String := do
  let result ← IO.Process.output {cmd := "/usr/bin/shasum",args := #["-a","256",path.toString]}
  check (result.exitCode == 0) "cannot verify protected artifact"
  return (result.stdout.splitOn " ").headD ""

private partial def remove (path : System.FilePath) : IO (Nat × Nat) := do
  let info ← path.symlinkMetadata
  if info.type != .dir then
    IO.FS.removeFile path
    return (1,if info.type == .file then info.byteSize.toNat else 0)
  let mut total := (0,0)
  for entry in ← path.readDir do
    let counts ← remove entry.path
    total := (total.1+counts.1,total.2+counts.2)
  IO.FS.removeDir path
  return total

def main : IO Unit := do
  let project : System.FilePath := "/Users/ovm/.codex/worktrees/hook-deadline-baseline/eggshell"
  let root : System.FilePath := "/Users/ovm/.codex/experiments/eggshell/scope-token-study-20261028/shared-snapshot"
  let records := project / "docs/candidates/complete-work"
  check (!(← (records / "retired.json").pathExists)) "preserve previous retirement"
  for entry in ← records.readDir do
    if entry.fileName.endsWith ".guard.json" && !entry.fileName.startsWith "retire" then
      let receipt ← read entry.path
      check (receipt.getObjValD "state" == toJson "finished" &&
        receipt.getObjValD "ownedPids" == toJson (#[] : Array Nat)) "experiment still running"
  for name in ["runtime","helper"] do
    check ((← read (records / (name ++ "-native-closure.json"))).getObjValD "consistent" == toJson true)
      "native closure was not verified"
  let result ← read (records / "hooks/candidate/rep-0/topic-1/result.json")
  check ((result.getObjValD "availableDelivery").getObjValD "targetMet" == toJson false)
    "experiment does not have its terminal negative result"
  let mut retainedFiles : Array (String × String) ← IO.ofExcept
    ((← read (project / "docs/candidates/read-signal-trace/native-seal.json")).getObjValAs? _ "verifiedOriginalFilesAndRuntimes")
  retainedFiles := retainedFiles.push ((root / "register-runtime-build/StudyMain").toString,
    "1bd3d15bb3c708a14785c983fcb8e1c95d650bc55f837202d84538de0bda787b")
  for (path,stamp) in retainedFiles do check ((← hash (.mk path)) == stamp) "protected artifact changed"
  let targets := #[root / "complete-work-core",root / "complete-work-runtime-build",
    root / "complete-work-hook-candidate-build",root / "complete-work-hook-trial"]
  let running ← IO.Process.output {cmd := "/usr/bin/pgrep",args := #["-f","/complete-work-(runtime-build|hook-candidate-build)/StudyMain( |$)"]}
  check (running.exitCode == 1) "experiment executable still running"
  let builds := #[root / "query-cache-baseline-build",root / "prepared-bindings-build",root / "register-runtime-build"]
  for build in builds do
    let response ← IO.FS.readFile (build / "runtime.rsp")
    for target in targets do check ((response.splitOn target.toString).length == 1) "protected build uses retired input"
  let seals := Json.mkObj [
    ("runtimeSha256",toJson (← hash (root / "complete-work-runtime-build/StudyMain"))),
    ("helperSha256",toJson (← hash (root / "complete-work-hook-candidate-build/StudyMain"))),
    ("bodySha256",toJson (← hash (records / "hooks/candidate/rep-0/topic-1/body.txt")))]
  let mut files := 0
  let mut bytes := 0
  for target in targets do
    let counts ← remove target
    files := files+counts.1
    bytes := bytes+counts.2
  let mut settings := 0
  for entry in ← root.readDir do
    if entry.fileName.startsWith "complete-work-" && entry.fileName.endsWith ".json" then
      IO.FS.removeFile entry.path
      settings := settings+1
  for (path,stamp) in retainedFiles do check ((← hash (.mk path)) == stamp) "cleanup changed protected artifact"
  let mut links := 0
  for build in builds do
    for line in (← IO.FS.readFile (build / "runtime.rsp")).splitOn "\n" do
      if line.trimAscii.isEmpty then continue
      let path : System.FilePath := .mk (← IO.ofExcept (Json.parse line >>= Json.getStr?))
      check (← path.pathExists) "cleanup lost a retained native input"
      links := links+1
  IO.FS.writeFile (records / "retired.json") (Json.mkObj [
    ("files",toJson files),("logicalBytes",toJson bytes),("settings",toJson settings),
    ("seals",seals),("protectedHashesBeforeAndAfter",toJson true),("retainedNativeLinkInputs",toJson links),
    ("archiveCreated",toJson false),("adopted",toJson false)]).pretty
  IO.println s!"Retired complete Work experiment: {files} files, {bytes} logical bytes"
