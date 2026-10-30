import Lean.Data.Json.Parser
import Lean.Data.Json.FromToJson
open Lean

private def check (ok : Bool) (message : String) : IO Unit := unless ok do throw (IO.userError message)
private def read (path : System.FilePath) : IO Json := IO.FS.readFile path >>= fun text => IO.ofExcept (Json.parse text)
private def hash (path : System.FilePath) : IO String := do
  let value ← IO.Process.output {cmd := "/usr/bin/shasum",args := #["-a","256",path.toString]}
  check (value.exitCode == 0) "cannot seal owner experiment cleanup"
  return (value.stdout.splitOn " ").headD ""
private def verify (files : Array (String × String)) : IO Unit := do
  for (path,expected) in files do check ((← hash (.mk path)) == expected) "protected source/runtime changed"
private def inside (path root : System.FilePath) : Bool := path == root || path.toString.startsWith (root.toString ++ "/")
private partial def protect (directory : System.FilePath) (targets : Array System.FilePath) : IO Unit := do
  for entry in ← directory.readDir do
    let info ← entry.path.symlinkMetadata
    if info.type == .dir then protect entry.path targets
    else if info.type == .symlink then
      check (!(targets.any (inside (← IO.FS.realPath entry.path)))) "retained interface needs owner experiment"
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

def main : IO Unit := do
  let project : System.FilePath := "/Users/ovm/.codex/worktrees/hook-deadline-baseline/eggshell"
  let root : System.FilePath := "/Users/ovm/.codex/experiments/eggshell/scope-token-study-20261028/shared-snapshot"
  let records := project / "docs/candidates/owner-bindings"
  check (!(← (records / "retired.json").pathExists)) "preserve completed owner cleanup"
  check ((← read (records / "fixture-result.json")).getObjValD "sameCompleteOrderedReads" == toJson true)
    "owner fixture failed"
  check ((← read (records / "actual/result.json")).getObjValD "sameAllRequestedReadSequences" == toJson true)
    "actual inventory mismatch"
  let hooks ← read (records / "hooks/results.json")
  check (hooks.getObjValD "sameActualBodyWithinDeadline" == toJson true &&
    hooks.getObjValD "answeringModelCalls" == toJson (0 : Nat)) "actual hooks incomplete"
  let results : Array Json ← IO.ofExcept (hooks.getObjValAs? _ "results")
  check (results.size == 4) "four completed actual hooks required"
  for result in results do
    let arm ← IO.ofExcept (result.getObjValAs? String "arm")
    let repetition ← IO.ofExcept (result.getObjValAs? String "repetition")
    let folder := records / "hooks" / arm / ("rep-" ++ repetition)
    check (result.getObjValD "bodySha256" == toJson (← hash (folder / "body.txt"))) "actual body changed"
    for name in ["shutdown.json","publisher-shutdown.json"] do
      let stopped ← read (folder / name)
      check (stopped.getObjValD "acknowledged" == toJson true && stopped.getObjValD "processExited" == toJson true &&
        stopped.getObjValD "endpointRemoved" == toJson true) "owner hook process live"
  for entry in ← records.readDir do
    if entry.fileName.endsWith ".guard.json" then
      let guard ← read entry.path
      check (guard.getObjValD "state" == toJson "finished" && guard.getObjValD "ownedPids" == toJson (#[] : Array Nat))
        "owner experiment guard live"
  let files : Array (String × String) ← IO.ofExcept ((← read
    (project / "docs/candidates/read-signal-trace/native-seal.json")).getObjValAs? _ "verifiedOriginalFilesAndRuntimes")
  let files := files.push ((root / "register-runtime-build/StudyMain").toString,
    "1bd3d15bb3c708a14785c983fcb8e1c95d650bc55f837202d84538de0bda787b")
  verify files
  let mut patch := ""
  for name in ["SynapseIndex","SynapticBindings"] do
    let file := "Eggshell/" ++ name ++ ".lean"
    let diff ← IO.Process.output {cmd := "/usr/bin/git",args := #["diff","--no-index","--",
      (root / "query-cache-baseline-core" / file).toString,(root / "owner-bindings-core" / file).toString]}
    check (diff.exitCode == 1) "candidate owner patch missing"
    patch := patch ++ diff.stdout
  IO.FS.writeFile (records / "core.patch") patch
  let mut targets := #[]
  for entry in ← root.readDir do
    if entry.fileName.startsWith "owner-bindings-" then targets := targets.push entry.path
  let mut links := #[]
  for name in ["query-cache-baseline-build","prepared-bindings-build","register-runtime-build"] do
    let build := root / name
    for line in (← IO.FS.readFile (build / "runtime.rsp")).splitOn "\n" do
      if line.trimAscii.isEmpty then continue
      let path : System.FilePath := .mk (← IO.ofExcept (Json.parse line >>= Json.getStr?))
      check (!(targets.any (inside path))) "retained native object needs owner trial"
      links := links.push path
    protect (build / "lib") targets
  let running ← IO.Process.output {cmd := "/bin/ps",args := #["-axo","command="]}
  check (running.exitCode == 0) "cannot inspect owner experiment processes"
  for target in targets do check ((running.stdout.splitOn target.toString).length == 1) "owner artifact is live"
  let first ← IO.ofExcept (results[0]!.getObjValAs? String "arm")
  let repetition ← IO.ofExcept (results[0]!.getObjValAs? String "repetition")
  let body := records / "hooks" / first / ("rep-" ++ repetition) / "body.txt"
  let digest ← hash body
  let common := project / "docs/candidates/routing-scope/hooks/body.txt"
  let (retained,label) ← if (← hash common) == digest then
      pure (common,"docs/candidates/routing-scope/hooks/body.txt")
    else do
      let target := records / "hooks/body.txt"
      check (!(← target.pathExists)) "preserve shared actual body"
      IO.FS.writeFile target (← IO.FS.readFile body)
      pure (target,"docs/candidates/owner-bindings/hooks/body.txt")
  check ((← hash retained) == digest) "retained body changed bytes"
  let mut total := (0,0)
  let mut removed := #[]
  for result in results do
    let arm ← IO.ofExcept (result.getObjValAs? String "arm")
    let repetition ← IO.ofExcept (result.getObjValAs? String "repetition")
    let folder := records / "hooks" / arm / ("rep-" ++ repetition)
    check ((← hash (folder / "body.txt")) == digest) "actual hook bodies differ"
    IO.FS.writeFile (folder / "body-reference.json") (Json.mkObj [("projectRelativeBody",toJson label),
      ("sha256",toJson digest),("actualBytesVerifiedBeforeRemovingDuplicate",toJson true)]).pretty
    let mut logs := #[folder / "body.txt"]
    for event in ["SessionStart","UserPromptSubmit"] do
      for stream in ["stdout","stderr"] do logs := logs.push (folder / event / stream)
    for path in logs do
      if ← path.pathExists then
        let part ← remove path
        total := (total.1+part.1,total.2+part.2)
        removed := removed.push (path.toString,part.1,part.2)
  for arm in ["baseline","candidate"] do
    for stream in ["stdin","stdout","stderr"] do
      let path := records / "hooks" / arm / "warm" / stream
      if ← path.pathExists then
        let part ← remove path
        total := (total.1+part.1,total.2+part.2)
        removed := removed.push (path.toString,part.1,part.2)
  for target in targets do
    let part ← remove target
    total := (total.1+part.1,total.2+part.2)
    removed := removed.push (target.toString,part.1,part.2)
  verify files
  for path in links do check (← path.pathExists) "cleanup removed retained link input"
  IO.FS.writeFile (records / "retired.json") (Json.mkObj [("removed",toJson removed),
    ("files",toJson total.1),("logicalBytes",toJson total.2),("protectedHashesBeforeAndAfter",toJson true),
    ("retainedNativeLinkInputs",toJson links.size),("archiveCreated",toJson false),("adopted",toJson false)]).pretty
  IO.println s!"Retired ended owner inventory experiment: {total.1} files, {total.2} logical bytes"
