import Lean.Data.Json.Parser
import Lean.Data.Json.FromToJson
open Lean

private def read (path : System.FilePath) : IO Json :=
  IO.FS.readFile path >>= fun text => IO.ofExcept (Json.parse text)
private def check (ok : Bool) (message : String) : IO Unit :=
  unless ok do throw (IO.userError message)

private partial def remove (path : System.FilePath) : IO (Nat × Nat) := do
  let info ← path.symlinkMetadata
  if info.type == .dir then
    let mut total := (0,0)
    for entry in ← path.readDir do
      let count ← remove entry.path
      total := (total.1+count.1,total.2+count.2)
    IO.FS.removeDir path
    return total
  IO.FS.removeFile path
  return (1,if info.type == .file then info.byteSize.toNat else 0)

private def verify (originals : Json) : IO Unit := do
  let files : Array (String × String) ← IO.ofExcept (originals.getObjValAs? _ "verifiedOriginalFilesAndRuntimes")
  for (path,expected) in files do
    let hash ← IO.Process.output {cmd := "/usr/bin/shasum",args := #["-a","256",path]}
    check (hash.exitCode == 0 && hash.stdout.startsWith (expected ++ " ")) "protected original or runtime changed"

def main : IO Unit := do
  let project : System.FilePath := "/Users/ovm/.codex/worktrees/hook-deadline-baseline/eggshell"
  let root : System.FilePath := "/Users/ovm/.codex/experiments/eggshell/scope-token-study-20261028/shared-snapshot"
  let records := project / "docs/candidates/group-cue-coverage"
  let report := records / "retired.json"
  check (!(← report.pathExists)) "preserve previous cleanup receipt"
  let actual ← read (records / "actual/result.json")
  check (actual.getObjValD "adopted" == toJson false && actual.getObjValD "sourceUnchanged" == toJson true)
    "do not retire an unfinished or adopted runtime"
  for entry in ← records.readDir do
    if entry.fileName.endsWith ".guard.json" && entry.fileName != "retired.guard.json" then
      let guard ← read entry.path
      check (guard.getObjValD "state" == toJson "finished" &&
        guard.getObjValD "ownedPids" == toJson (#[] : Array Nat)) "a candidate operation is still live"
  let originals ← read (project / "docs/candidates/read-signal-trace/native-seal.json")
  verify originals
  let baselineResponse ← IO.FS.readFile (root / "query-cache-baseline-build/runtime.rsp")
  let candidateResponse ← IO.FS.readFile (root / "prepared-bindings-build/runtime.rsp")
  let processes ← IO.Process.output {cmd := "/bin/ps",args := #["-axo","command="]}
  check (processes.exitCode == 0) "cannot verify trial quiescence"
  let mut targets : Array System.FilePath := #[]
  for entry in ← root.readDir do
    if entry.fileName.startsWith "group-cue-" || entry.fileName.startsWith "record-domain-" then
      check ((processes.stdout.splitOn entry.path.toString).length == 1 &&
        (baselineResponse.splitOn entry.path.toString).length == 1 &&
        (candidateResponse.splitOn entry.path.toString).length == 1) "candidate is still a live dependency"
      targets := targets.push entry.path
  -- Keep only current selector inputs, actual bodies/audits and small receipts.
  -- No compressed or archived copy is created.
  for parent in [records / "actual/topic-1",records / "actual/topic-2",
      records / "topic-2-capture",records / "topic-2-profile"] do
    for name in ["SessionStart","UserPromptSubmit"] do
      let path := parent / name
      if ← path.pathExists then targets := targets.push path
  for path in [records / "actual/warm",records / "topic-2-profile/receipts",
      records / "topic-2-profile/worker.sample.txt"] do
    if ← path.pathExists then targets := targets.push path
  let mut removed := #[]
  let mut total := (0,0)
  for target in targets do
    let result ← remove target
    total := (total.1+result.1,total.2+result.2)
    removed := removed.push (Json.mkObj [("path",toJson target.toString),
      ("files",toJson result.1),("logicalBytes",toJson result.2)])
    check (!(← target.pathExists)) "cleanup left a retired artifact"
  verify originals
  let mut nativeObjects := 0
  for response in [baselineResponse,candidateResponse] do
    for line in response.splitOn "\n" do
      if line.trimAscii.isEmpty then continue
      let path ← IO.ofExcept (Json.parse line >>= Json.getStr?)
      check (← System.FilePath.pathExists (.mk path)) "cleanup removed a protected native link input"
      nativeObjects := nativeObjects+1
  IO.FS.writeFile report (Json.mkObj [("targets",toJson removed),("files",toJson total.1),
    ("logicalBytes",toJson total.2),("archiveCreated",toJson false),("followsSymlinks",toJson false),
    ("protectedHashesBeforeAndAfter",toJson true),("retainedNativeLinkInputs",toJson nativeObjects),
    ("trialDatabaseAndBuildsRemoved",toJson true)]).pretty
  IO.println s!"Deleted {total.1} files / {total.2} logical bytes; originals and {nativeObjects} link inputs retained"
