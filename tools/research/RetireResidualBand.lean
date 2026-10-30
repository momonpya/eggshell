import Lean.Data.Json.Parser
import Lean.Data.Json.FromToJson
open Lean

private def read (p : System.FilePath) : IO Json := IO.FS.readFile p >>= fun s => IO.ofExcept (Json.parse s)
private def check (ok : Bool) (message : String) : IO Unit := unless ok do throw (IO.userError message)
private def hash (path : System.FilePath) : IO String := do
  let result ← IO.Process.output {cmd := "/usr/bin/shasum",args := #["-a","256",path.toString]}
  check (result.exitCode == 0) "cannot seal helper retirement input"
  return (result.stdout.splitOn " ").headD ""
private def verify (files : Array (String × String)) : IO Unit := do
  for (path,digest) in files do check ((← hash (.mk path)) == digest) "helper retirement changed a protected original"
private def inside (path target : System.FilePath) : Bool :=
  path == target || path.toString.startsWith (target.toString ++ "/")
private partial def protect (directory : System.FilePath) (targets : Array System.FilePath) : IO Unit := do
  for entry in ← directory.readDir do
    let info ← entry.path.symlinkMetadata
    if info.type == .dir then protect entry.path targets
    else if info.type == .symlink then
      let actual ← IO.FS.realPath entry.path
      check (!(targets.any (inside actual))) "active native interface depends on the ended helper"
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

def main : IO Unit := do
  let project : System.FilePath := "/Users/ovm/.codex/worktrees/hook-deadline-baseline/eggshell"
  let root : System.FilePath := "/Users/ovm/.codex/experiments/eggshell/scope-token-study-20261028/shared-snapshot"
  let records := project / "docs/candidates/residual-band"
  check (!(← (records / "retired.json").pathExists)) "preserve helper retirement evidence"
  let result ← read (records / "result.json")
  check (result.getObjValD "sourceUnchanged" == toJson true && result.getObjValD "adopted" == toJson false &&
    result.getObjValD "priceCount" == toJson (25 : Nat)) "only the finished diagnostic may be retired"
  for name in ["run.guard.json","build.guard.json","build-parse-failure.guard.json","build-bound-index-failure.guard.json"] do
    let guard ← read (records / name)
    check (guard.getObjValD "state" == toJson "finished" &&
      guard.getObjValD "ownedPids" == toJson (#[] : Array Nat)) "helper still running"
  let originals : Array (String × String) ← IO.ofExcept ((← read (project / "docs/candidates/read-signal-trace/native-seal.json")).getObjValAs? _ "verifiedOriginalFilesAndRuntimes")
  let additional := root / "register-runtime-build/StudyMain"
  check ((← hash additional) == "1bd3d15bb3c708a14785c983fcb8e1c95d650bc55f837202d84538de0bda787b") "active hash runtime changed"
  verify originals
  let mut targets := #[root / "residual-band-build",root / "residual-band-build.settings.json",
    root / "residual-band-build.guard-settings.json",root / "residual-band-run.guard-settings.json"]
  let mut seals := #[]
  for path in [root / "residual-band-build/StudyMain",project / "tools/research/ClosureFlow.lean",
      project / "tools/research/PrincipalNetwork.lean",project / "tools/research/ResidualInterval.lean",
      project / "tools/research/ResidualBandAudit.lean",project / "docs/candidates/principal-offers/frontier-replay.json",
      project / "docs/candidates/prepared-bindings/resumed/cue-capture/receipts/43ba2a13af5aae5fc34557e5b8747cafce13fa0063d0da7356b09f43de8cd9ca/selection-plan.json"] do
    seals := seals.push (path.toString,← hash path)
  for entry in ← records.readDir do
    if entry.fileName.endsWith ".stdout" || entry.fileName.endsWith ".stderr" then targets := targets.push entry.path
  let processes ← IO.Process.output {cmd := "/bin/ps",args := #["-axo","command="]}
  check (processes.exitCode == 0) "cannot confirm helper stopped"
  for target in targets do
    check ((processes.stdout.splitOn target.toString).length == 1) "selected helper artifact is live"
  let keep := #[root / "query-cache-baseline-build",root / "prepared-bindings-build",root / "register-runtime-build"]
  for build in keep do
    for line in (← IO.FS.readFile (build / "runtime.rsp")).splitOn "\n" do
      if line.trimAscii.isEmpty then continue
      let path : System.FilePath := .mk (← IO.ofExcept (Json.parse line >>= Json.getStr?))
      check (!(targets.any (inside path))) "active native link depends on the helper"
    protect (build / "lib") targets
  let mut total := (0,0)
  let mut removed := #[]
  for target in targets do
    let count ← remove target
    total := (total.1+count.1,total.2+count.2)
    removed := removed.push (target.toString,count.1,count.2)
    check (!(← target.pathExists)) "helper retirement left an artifact"
  verify originals
  check ((← hash additional) == "1bd3d15bb3c708a14785c983fcb8e1c95d650bc55f837202d84538de0bda787b") "helper retirement changed active hash runtime"
  let mut retained := 0
  for build in keep do
    for line in (← IO.FS.readFile (build / "runtime.rsp")).splitOn "\n" do
      if line.trimAscii.isEmpty then continue
      let path : System.FilePath := .mk (← IO.ofExcept (Json.parse line >>= Json.getStr?))
      check (← path.pathExists) "helper retirement removed an active native input"
      retained := retained+1
  IO.FS.writeFile (records / "retired.json") (Json.mkObj [("removed",toJson removed),
    ("files",toJson total.1),("logicalBytes",toJson total.2),("sealsBeforeRemoval",toJson seals),
    ("archiveCreated",toJson false),("followsSymlinks",toJson false),
    ("protectedOriginalHashesBeforeAndAfter",toJson true),("retainedNativeLinkInputs",toJson retained)]).pretty
  IO.println s!"Retired residual diagnostic: {total.1} files / {total.2} logical bytes"
