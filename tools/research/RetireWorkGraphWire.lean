import Lean.Data.Json.Parser
import Lean.Data.Json.FromToJson
open Lean

private def read (path : System.FilePath) : IO Json := IO.FS.readFile path >>= fun text => IO.ofExcept (Json.parse text)
private def check (ok : Bool) (message : String) : IO Unit := unless ok do throw (IO.userError message)
private def hash (path : System.FilePath) : IO String := do
  let response ← IO.Process.output {cmd := "/usr/bin/shasum",args := #["-a","256",path.toString]}
  check (response.exitCode == 0) "cannot seal experiment artifact"
  return (response.stdout.splitOn " ").headD ""
private def verify (originals : Array (String × String)) : IO Unit := do
  for (path,expected) in originals do check ((← hash (.mk path)) == expected) "protected source/runtime changed"
private partial def remove (path : System.FilePath) : IO (Nat × Nat) := do
  let info ← path.symlinkMetadata
  if info.type == .dir then
    let mut total := (0,0)
    for entry in ← path.readDir do
      let part ← remove entry.path
      total := (total.1+part.1,total.2+part.2)
    IO.FS.removeDir path
    return total
  IO.FS.removeFile path
  return (1,if info.type == .file then info.byteSize.toNat else 0)
private def inside (path root : System.FilePath) : Bool := path == root || path.toString.startsWith (root.toString ++ "/")
private partial def protect (directory : System.FilePath) (targets : Array System.FilePath) : IO Unit := do
  for entry in ← directory.readDir do
    let info ← entry.path.symlinkMetadata
    if info.type == .dir then protect entry.path targets
    else if info.type == .symlink then
      check (!(targets.any (inside (← IO.FS.realPath entry.path)))) "retained interface needs ended experiment"

def main : IO Unit := do
  let project : System.FilePath := "/Users/ovm/.codex/worktrees/hook-deadline-baseline/eggshell"
  let root : System.FilePath := "/Users/ovm/.codex/experiments/eggshell/scope-token-study-20261028/shared-snapshot"
  let records := project / "docs/candidates/workgraph-wire"
  check (!(← (records / "retired.json").pathExists)) "preserve completed cleanup"
  let measured ← read (records / "hooks/result.json")
  check (measured.getObjValD "adopted" == toJson false && measured.getObjValD "answeringModelCalls" == toJson (0 : Nat))
    "only this ended isolated candidate may be retired"
  let results : Array Json ← IO.ofExcept (measured.getObjValAs? _ "results")
  check (results.size > 0 && results.size ≤ 2) "actual hook results missing"
  for result in results do
    let repetition ← IO.ofExcept (result.getObjValAs? Nat "repetitionIndex")
    let folder := records / "hooks/candidate" / s!"rep-{repetition}"
    check (result.getObjValD "bodySha256" == toJson (← hash (folder / "body.txt"))) "actual body digest changed"
    for name in ["shutdown.json","publisher-shutdown.json"] do
      let stopped ← read (folder / name)
      check (stopped.getObjValD "acknowledged" == toJson true && stopped.getObjValD "daemonExitCode" == toJson (0 : Nat) &&
        stopped.getObjValD "processExited" == toJson true && stopped.getObjValD "endpointRemoved" == toJson true)
        "hook service did not terminate"
  for entry in ← records.readDir do
    if entry.fileName.endsWith ".guard.json" && entry.fileName != "retired.guard.json" then
      let guard ← read entry.path
      check (guard.getObjValD "state" == toJson "finished" && guard.getObjValD "ownedPids" == toJson (#[] : Array Nat))
        "a related task is still live"
  let mut originals : Array (String × String) ← IO.ofExcept ((← read (project / "docs/candidates/read-signal-trace/native-seal.json")).getObjValAs? _ "verifiedOriginalFilesAndRuntimes")
  originals := originals.push ((root / "register-runtime-build/StudyMain").toString,
    "1bd3d15bb3c708a14785c983fcb8e1c95d650bc55f837202d84538de0bda787b")
  verify originals
  let mut seals := #[]
  for name in ["workgraph-wire-runtime-build","workgraph-wire-hook-candidate-build","workgraph-wire-runner-build","workgraph-wire-audit-build"] do
    seals := seals.push ((root / name / "StudyMain").toString,← hash (root / name / "StudyMain"))
  let mut patchText := ""
  for name in ["Eggshell/Handoff.lean","Eggshell/PublicationWire.lean"] do
    let patch ← IO.Process.output {cmd := "/usr/bin/diff",args := #["-u",
      (root / "query-cache-baseline-core" / name).toString,(root / "workgraph-wire-core" / name).toString]}
    check (patch.exitCode == 1) "candidate patch is missing"
    patchText := patchText ++ patch.stdout
  IO.FS.writeFile (records / "candidate.patch") patchText
  let mut targets : Array System.FilePath := #[]
  for entry in ← root.readDir do
    if entry.fileName.startsWith "workgraph-wire-" then targets := targets.push entry.path
  let retained := #[root / "query-cache-baseline-build",root / "prepared-bindings-build",root / "register-runtime-build"]
  for build in retained do
    for row in (← IO.FS.readFile (build / "runtime.rsp")).splitOn "\n" do
      if row.trimAscii.isEmpty then continue
      let path : System.FilePath := .mk (← IO.ofExcept (Json.parse row >>= Json.getStr?))
      check (!(targets.any (inside path))) "retained runtime depends on ended experiment"
    protect (build / "lib") targets
  let running ← IO.Process.output {cmd := "/bin/ps",args := #["-axo","command="]}
  check (running.exitCode == 0) "cannot inspect active processes"
  for target in targets do check ((running.stdout.splitOn target.toString).length == 1) "artifact remains in use"
  let parent := records / "hooks/candidate"
  IO.FS.writeFile (parent / "warm-record.json") (← IO.FS.readFile (parent / "warm/record.json"))
  targets := targets.push (parent / "warm")
  for result in results do
    let repetition ← IO.ofExcept (result.getObjValAs? Nat "repetitionIndex")
    let folder := parent / s!"rep-{repetition}"
    for event in ["SessionStart","UserPromptSubmit"] do
      IO.FS.writeFile (folder / (event ++ "-record.json")) (← IO.FS.readFile (folder / event / "record.json"))
      targets := targets.push (folder / event)
  let mut removed := #[]
  let mut total := (0,0)
  for target in targets do
    let part ← remove target
    total := (total.1+part.1,total.2+part.2)
    removed := removed.push (target.toString,part.1,part.2)
    check (!(← target.pathExists)) "cleanup left an artifact"
  verify originals
  let mut inputs := 0
  for build in retained do
    for row in (← IO.FS.readFile (build / "runtime.rsp")).splitOn "\n" do
      if row.trimAscii.isEmpty then continue
      let path : System.FilePath := .mk (← IO.ofExcept (Json.parse row >>= Json.getStr?))
      check (← path.pathExists) "cleanup removed an active native input"
      inputs := inputs+1
  IO.FS.writeFile (records / "retired.json") (Json.mkObj [("removed",toJson removed),("files",toJson total.1),
    ("logicalBytes",toJson total.2),("seals",toJson seals),("protectedHashesBeforeAndAfter",toJson true),
    ("retainedNativeLinkInputs",toJson inputs),("archiveCreated",toJson false),("followsSymlinks",toJson false),
    ("adopted",toJson false)]).pretty
  IO.println s!"Deleted ended WorkGraph experiment: {total.1} files, {total.2} logical bytes"
