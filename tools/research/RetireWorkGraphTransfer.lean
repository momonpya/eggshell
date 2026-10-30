import Lean
open Lean
private def check (ok : Bool) (message : String) : IO Unit := unless ok do throw (IO.userError message)
private def read (path : System.FilePath) : IO Json := IO.FS.readFile path >>= fun text => IO.ofExcept (Json.parse text)
private def hash (path : System.FilePath) : IO String := do
  let response ← IO.Process.output {cmd := "/usr/bin/shasum",args := #["-a","256",path.toString]}
  check (response.exitCode == 0) "cannot seal retained evidence"
  return (response.stdout.splitOn " ").headD ""
private partial def remove (path : System.FilePath) : IO (Nat × Nat) := do
  let metadata ← path.symlinkMetadata
  if metadata.type != .dir then
    IO.FS.removeFile path
    return (1,if metadata.type == .file then metadata.byteSize.toNat else 0)
  let mut total := (0,0)
  for entry in ← path.readDir do
    let next ← remove entry.path
    total := (total.1+next.1,total.2+next.2)
  IO.FS.removeDir path
  return total
private def inside (path root : System.FilePath) : Bool := path == root || path.toString.startsWith (root.toString ++ "/")
private partial def protectLinks (directory : System.FilePath) (targets : Array System.FilePath) : IO Unit := do
  for entry in ← directory.readDir do
    let metadata ← entry.path.symlinkMetadata
    if metadata.type == .dir then protectLinks entry.path targets
    else if metadata.type == .symlink then
      check (!(targets.any (inside (← IO.FS.realPath entry.path)))) "retained native input uses candidate artifact"

def main : IO Unit := do
  let project : System.FilePath := "/Users/ovm/.codex/worktrees/hook-deadline-baseline/eggshell"
  let root : System.FilePath := "/Users/ovm/.codex/experiments/eggshell/scope-token-study-20261028/shared-snapshot"
  let records := project / "docs/candidates/workgraph-transfer"
  check (!(← (records / "retired.json").pathExists)) "preserve completed retirement"
  let delta ← read (records / "original-delta.json")
  check (delta.getObjValD "rangePartitionOnly" == toJson false &&
    delta.getObjValD "newHookCalls" == toJson (0 : Nat)) "original difference not diagnosed"
  let results : Array Json ← IO.ofExcept (fromJson? (← read (records / "hooks/progress.json")))
  check (results.size == 2 && results.all (fun row => row.getObjValD "adopted" == toJson false &&
    row.getObjValD "answeringModelCalls" == toJson (0 : Nat))) "unexpected experiment state"
  for arm in ["baseline","candidate"] do
    let folder := records / "hooks" / arm / "rep-0/topic-1"
    let result ← read (folder / "result.json")
    check (result.getObjValD "bodySha256" == toJson (← hash (folder / "body.txt"))) "actual hook body changed"
    for name in ["shutdown.json","publisher-shutdown.json"] do
      let stopped ← read (folder / name)
      check (stopped.getObjValD "acknowledged" == toJson true && stopped.getObjValD "daemonExitCode" == toJson (0 : Nat) &&
        stopped.getObjValD "processExited" == toJson true && stopped.getObjValD "endpointRemoved" == toJson true)
        "hook service still active"
  for entry in ← records.readDir do
    if entry.fileName.endsWith ".guard.json" && !entry.fileName.startsWith "retire" then
      let guard ← read entry.path
      check (guard.getObjValD "state" == toJson "finished" && guard.getObjValD "ownedPids" == toJson (#[] : Array Nat))
        "an experiment process remains active"
  let mut originals : Array (String × String) ← IO.ofExcept ((← read (project / "docs/candidates/read-signal-trace/native-seal.json")).getObjValAs? _ "verifiedOriginalFilesAndRuntimes")
  originals := originals.push ((root / "register-runtime-build/StudyMain").toString,
    "1bd3d15bb3c708a14785c983fcb8e1c95d650bc55f837202d84538de0bda787b")
  for (path,expected) in originals do check ((← hash (.mk path)) == expected) "protected original/runtime changed"
  let mut targets : Array System.FilePath := #[]
  for entry in ← root.readDir do
    if entry.fileName.startsWith "workgraph-transfer-" then targets := targets.push entry.path
  let retained := #[root / "query-cache-baseline-build",root / "prepared-bindings-build",root / "register-runtime-build"]
  for build in retained do
    for row in (← IO.FS.readFile (build / "runtime.rsp")).splitOn "\n" do
      if row.trimAscii.isEmpty then continue
      let path : System.FilePath := .mk (← IO.ofExcept (Json.parse row >>= Json.getStr?))
      check (!(targets.any (inside path))) "retained runtime depends on retired candidate"
    protectLinks (build / "lib") targets
  let running ← IO.Process.output {cmd := "/bin/ps",args := #["-axo","command="]}
  check (running.exitCode == 0) "cannot inspect experiment ownership"
  for target in targets do check ((running.stdout.splitOn target.toString).length == 1) "artifact still in use"
  let mut patches := ""
  for name in ["Eggshell/Handoff.lean","Eggshell/PublicationWire.lean"] do
    let patch ← IO.Process.output {cmd := "/usr/bin/diff",args := #["-u",
      (root / "query-cache-baseline-core" / name).toString,(root / "workgraph-transfer-core" / name).toString]}
    check (patch.exitCode == 1) "isolated candidate patch missing"
    patches := patches ++ patch.stdout
  IO.FS.writeFile (records / "candidate.patch") patches
  for arm in ["baseline","candidate"] do
    let parent := records / "hooks" / arm
    IO.FS.writeFile (parent / "warm-record.json") (← IO.FS.readFile (parent / "warm/record.json"))
    targets := targets.push (parent / "warm")
    let folder := parent / "rep-0/topic-1"
    for event in ["SessionStart","UserPromptSubmit"] do
      IO.FS.writeFile (folder / (event ++ "-record.json")) (← IO.FS.readFile (folder / event / "record.json"))
      targets := targets.push (folder / event)
  let mut total := (0,0)
  let mut removed := #[]
  for target in targets do
    let counts ← remove target
    check (!(← target.pathExists)) "retired artifact remains"
    total := (total.1+counts.1,total.2+counts.2)
    removed := removed.push (target.toString,counts.1,counts.2)
  for (path,expected) in originals do check ((← hash (.mk path)) == expected) "cleanup changed original/runtime"
  let mut inputs := 0
  for build in retained do
    for row in (← IO.FS.readFile (build / "runtime.rsp")).splitOn "\n" do
      if row.trimAscii.isEmpty then continue
      let path : System.FilePath := .mk (← IO.ofExcept (Json.parse row >>= Json.getStr?))
      check (← path.pathExists) "active native input removed"
      inputs := inputs+1
  IO.FS.writeFile (records / "retired.json") (Json.mkObj [("removed",toJson removed),("files",toJson total.1),
    ("logicalBytes",toJson total.2),("protectedHashesBeforeAndAfter",toJson true),
    ("retainedNativeLinkInputs",toJson inputs),("archiveCreated",toJson false),("followsSymlinks",toJson false),
    ("answeringModelCalls",toJson (0 : Nat)),("adopted",toJson false)]).pretty
  IO.println s!"Removed ended WorkGraph transfer artifacts: {total.1} files, {total.2} logical bytes"
