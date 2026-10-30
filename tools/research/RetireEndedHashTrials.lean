import Lean.Data.Json.Parser
import Lean.Data.Json.FromToJson
open Lean

private def read (path : System.FilePath) : IO Json :=
  IO.FS.readFile path >>= fun value => IO.ofExcept (Json.parse value)
private def check (ok : Bool) (message : String) : IO Unit :=
  unless ok do throw (IO.userError message)
private def hash (path : System.FilePath) : IO String := do
  let value ← IO.Process.output {cmd := "/usr/bin/shasum",args := #["-a","256",path.toString]}
  check (value.exitCode == 0) "cannot seal cleanup input"
  let digest := (value.stdout.splitOn " ").headD ""
  check (digest.length == 64) "invalid cleanup digest"
  return digest
private def verify (originals : Json) : IO Unit := do
  let files : Array (String × String) ← IO.ofExcept (originals.getObjValAs? _ "verifiedOriginalFilesAndRuntimes")
  for (path,expected) in files do
    check ((← hash (.mk path)) == expected) "protected original or runtime changed"
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
private def inside (path target : System.FilePath) : Bool :=
  path == target || path.toString.startsWith (target.toString ++ "/")
private partial def protect (directory : System.FilePath) (targets : Array System.FilePath) : IO Unit := do
  for entry in ← directory.readDir do
    let info ← entry.path.symlinkMetadata
    if info.type == .dir then protect entry.path targets
    else if info.type == .symlink then
      let actual ← IO.FS.realPath entry.path
      check (!(targets.any (inside actual))) "retained interface depends on ended trial"

def main : IO Unit := do
  let project : System.FilePath := "/Users/ovm/.codex/worktrees/hook-deadline-baseline/eggshell"
  let root : System.FilePath := "/Users/ovm/.codex/experiments/eggshell/scope-token-study-20261028/shared-snapshot"
  let records := project / "docs/candidates/register-hash"
  let report := records / "retired.json"
  check (!(← report.pathExists)) "preserve prior retirement receipt"
  let actual ← read (records / "hooks/result.json")
  check (actual.getObjValD "allBodiesUnchangedAndWithinDeadline" == toJson true &&
    actual.getObjValD "answeringModelCalls" == toJson (0 : Nat) &&
    actual.getObjValD "adopted" == toJson false) "actual comparison is unfinished"
  let display ← read (project / "docs/candidates/canonical-record-domain/replay.json")
  check (display.getObjValD "sourceUnchanged" == toJson true &&
    display.getObjValD "adopted" == toJson false) "display candidate is unfinished"
  let results : Array Json ← IO.ofExcept (actual.getObjValAs? _ "results")
  check (results.size == 4) "both predeclared repetitions are required"
  for arm in ["baseline","candidate"] do
    for repetition in [0:2] do
      let parent := records / "hooks" / arm / s!"rep-{repetition}"
      let measured ← read (parent / "result.json")
      check (measured.getObjValD "bodySha256" == toJson (← hash (parent / "body.txt")))
        "actual body changed before cleanup"
      for name in ["shutdown.json","publisher-shutdown.json"] do
        let stopped ← read (parent / name)
        check (stopped.getObjValD "acknowledged" == toJson true &&
          stopped.getObjValD "daemonExitCode" == toJson (0 : Nat) &&
          stopped.getObjValD "processExited" == toJson true &&
          stopped.getObjValD "endpointRemoved" == toJson true) "a trial service did not stop"
  let processes ← IO.Process.output {cmd := "/bin/ps",args := #["-axo","command="]}
  check (processes.exitCode == 0) "cannot verify trial quiescence"
  check ((processes.stdout.splitOn (project / "tools/research/RegisterMix.lean").toString).length == 1)
    "interrupted proof is still referenced by a process"
  let oldProof ← read (records / "proof.guard.json")
  check (oldProof.getObjValD "state" == toJson "running") "interrupted proof receipt changed"
  let proofReceiptDigest ← hash (records / "proof.guard.json")
  for directory in [records,project / "docs/candidates/canonical-record-domain"] do
    for entry in ← directory.readDir do
      if !entry.fileName.endsWith ".guard.json" || entry.fileName == "retired.guard.json" ||
          entry.path == records / "proof.guard.json" then continue
      let guard ← read entry.path
      check (guard.getObjValD "state" == toJson "finished" &&
        guard.getObjValD "ownedPids" == toJson (#[] : Array Nat)) "another experiment is still running"
  let originals ← read (project / "docs/candidates/read-signal-trace/native-seal.json")
  verify originals
  let candidate := root / "register-runtime-build/StudyMain"
  let candidateSeal := (← read (records / "hooks/candidate-runtime.json")).getObjValD "runtime"
  check (candidateSeal.getObjValD "sha256" == toJson (← hash candidate)) "retained hash runtime changed"
  let retained := #[root / "query-cache-baseline-build",root / "prepared-bindings-build",root / "register-runtime-build"]
  let mut targets : Array System.FilePath := #[]
  for entry in ← root.readDir do
    if entry.fileName.startsWith "record-closure-" || entry.fileName.startsWith "register-hook-" ||
        entry.fileName.startsWith "register-hash-" then targets := targets.push entry.path
  for build in retained do
    for line in (← IO.FS.readFile (build / "runtime.rsp")).splitOn "\n" do
      if line.trimAscii.isEmpty then continue
      let path : System.FilePath := .mk (← IO.ofExcept (Json.parse line >>= Json.getStr?))
      check (!(targets.any (inside path))) "retained native link needs an ended experiment"
    protect (build / "lib") targets
  for target in targets do
    check ((processes.stdout.splitOn target.toString).length == 1) "target still has a live process"
  -- Keep measurements, actual bodies, source seals and small terminal receipts;
  -- discard duplicated hook stdio, unused warm logs and failed compiler logs.
  for arm in ["baseline","candidate"] do
    let parent := records / "hooks" / arm
    IO.FS.writeFile (parent / "warm-record.json") (← IO.FS.readFile (parent / "warm/record.json"))
    targets := targets.push (parent / "warm")
    for repetition in [0:2] do
      for name in ["SessionStart","UserPromptSubmit"] do
        let folder := parent / s!"rep-{repetition}" / name
        IO.FS.writeFile (parent / s!"rep-{repetition}" / (name ++ "-record.json"))
          (← IO.FS.readFile (folder / "record.json"))
        targets := targets.push folder
  for entry in ← records.readDir do
    if entry.fileName.endsWith ".stdout" then targets := targets.push entry.path
  let mut total := (0,0)
  let mut removed := #[]
  for target in targets do
    let count ← remove target
    total := (total.1+count.1,total.2+count.2)
    removed := removed.push (Json.mkObj [("path",toJson target.toString),
      ("files",toJson count.1),("logicalBytes",toJson count.2)])
    check (!(← target.pathExists)) "retirement left a target behind"
  verify originals
  check (candidateSeal.getObjValD "sha256" == toJson (← hash candidate)) "cleanup changed retained runtime"
  let mut retainedInputs := 0
  for build in retained do
    for line in (← IO.FS.readFile (build / "runtime.rsp")).splitOn "\n" do
      if line.trimAscii.isEmpty then continue
      let path : System.FilePath := .mk (← IO.ofExcept (Json.parse line >>= Json.getStr?))
      check (← path.pathExists) "retirement deleted a retained native link input"
      retainedInputs := retainedInputs+1
  IO.FS.writeFile report (Json.mkObj [("removed",toJson removed),("files",toJson total.1),
    ("logicalBytes",toJson total.2),("archiveCreated",toJson false),("followsSymlinks",toJson false),
    ("protectedHashesBeforeAndAfter",toJson true),("retainedNativeLinkInputs",toJson retainedInputs),
    ("originalInterruptedProofReceiptSha256",toJson proofReceiptDigest),
    ("originalInterruptedProofReceiptUnchanged",toJson true),
    ("interruptedProofCurrentlyUnreferencedByProcesses",toJson true),
    ("trialDatabasesCachesInstallationsAndUnusedBuildsRemoved",toJson true)]).pretty
  IO.println s!"Deleted {total.1} files / {total.2} logical bytes; originals and active native inputs retained"
