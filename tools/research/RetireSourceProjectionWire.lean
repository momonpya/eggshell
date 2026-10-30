import Lean.Data.Json.Parser
import Lean.Data.Json.FromToJson
open Lean

private def check (ok : Bool) (message : String) : IO Unit := unless ok do throw (IO.userError message)
private def read (path : System.FilePath) : IO Json := IO.FS.readFile path >>= fun text => IO.ofExcept (Json.parse text)
private def hash (path : System.FilePath) : IO String := do
  let result ← IO.Process.output {cmd := "/usr/bin/shasum",args := #["-a","256",path.toString]}
  check (result.exitCode == 0) "cannot verify source projection artifact"
  return (result.stdout.splitOn " ").headD ""
private def verify (originals : Array (String × String)) : IO Unit := do
  for (path,expected) in originals do check ((← hash (.mk path)) == expected) "protected original changed"
private partial def remove (path : System.FilePath) : IO (Nat × Nat) := do
  let info ← path.symlinkMetadata
  if info.type == .dir then
    let mut result := (0,0)
    for entry in ← path.readDir do
      let part ← remove entry.path
      result := (result.1+part.1,result.2+part.2)
    IO.FS.removeDir path
    return result
  IO.FS.removeFile path
  return (1,if info.type == .file then info.byteSize.toNat else 0)
private def inside (path root : System.FilePath) : Bool := path == root || path.toString.startsWith (root.toString ++ "/")
private partial def protect (directory : System.FilePath) (targets : Array System.FilePath) : IO Unit := do
  for entry in ← directory.readDir do
    let info ← entry.path.symlinkMetadata
    if info.type == .dir then protect entry.path targets
    else if info.type == .symlink then
      check (!(targets.any (inside (← IO.FS.realPath entry.path)))) "retained native interface needs this experiment"

private def retireCorrected : IO Unit := do
  let project : System.FilePath := "/Users/ovm/.codex/worktrees/hook-deadline-baseline/eggshell"
  let root : System.FilePath := "/Users/ovm/.codex/experiments/eggshell/scope-token-study-20261028/shared-snapshot"
  let records := project / "docs/candidates/source-projection-wire"
  check ((← (records / "retired.json").pathExists) && !(← (records / "corrected-retired.json").pathExists))
    "corrected experiment cleanup is not fresh"
  let measured ← read (records / "bench.json")
  let samples : Array Json ← IO.ofExcept (measured.getObjValAs? _ "samples")
  check (samples.size == 12 && measured.getObjValD "completeProjectionEqual" == toJson true) "corrected benchmark unfinished"
  for sample in samples do
    let digest ← IO.ofExcept (sample.getObjValAs? String "wireBlake3")
    check (digest.length == 64) "corrected digest is not a hash"
  for name in ["corrected-build.guard.json","corrected-run.guard.json"] do
    let guard ← read (records / name)
    check (guard.getObjValD "state" == toJson "finished" && guard.getObjValD "exitCode" == toJson (0 : Nat) &&
      guard.getObjValD "ownedPids" == toJson (#[] : Array Nat)) "corrected benchmark is live"
  let mut originals : Array (String × String) ← IO.ofExcept ((← read
    (project / "docs/candidates/read-signal-trace/native-seal.json")).getObjValAs? _ "verifiedOriginalFilesAndRuntimes")
  originals := originals.push ((root / "register-runtime-build/StudyMain").toString,
    "1bd3d15bb3c708a14785c983fcb8e1c95d650bc55f837202d84538de0bda787b")
  verify originals
  let binaryDigest ← hash (root / "source-projection-wire-corrected-bench-build/StudyMain")
  let mut targets : Array System.FilePath := #[]
  for entry in ← root.readDir do
    if entry.fileName.startsWith "source-projection-wire-corrected-" then targets := targets.push entry.path
  let builds := #[root / "query-cache-baseline-build",root / "prepared-bindings-build",root / "register-runtime-build"]
  for build in builds do protect (build / "lib") targets
  let running ← IO.Process.output {cmd := "/bin/ps",args := #["-axo","command="]}
  check (running.exitCode == 0) "cannot inspect corrected benchmark processes"
  for target in targets do check ((running.stdout.splitOn target.toString).length == 1) "corrected artifact remains live"
  let mut removed := #[]
  let mut total := (0,0)
  for target in targets do
    let part ← remove target
    removed := removed.push (target.toString,part.1,part.2)
    total := (total.1+part.1,total.2+part.2)
  verify originals
  let mut links := 0
  for build in builds do
    for line in (← IO.FS.readFile (build / "runtime.rsp")).splitOn "\n" do
      if line.trimAscii.isEmpty then continue
      let path : System.FilePath := .mk (← IO.ofExcept (Json.parse line >>= Json.getStr?))
      check (← path.pathExists) "corrected cleanup removed an active link input"
      links := links+1
  IO.FS.writeFile (records / "corrected-retired.json") (Json.mkObj [("removed",toJson removed),
    ("files",toJson total.1),("logicalBytes",toJson total.2),("runtimeSha256",toJson binaryDigest),
    ("protectedHashesBeforeAndAfter",toJson true),("retainedNativeLinkInputs",toJson links),
    ("archiveCreated",toJson false),("adopted",toJson false)]).pretty
  IO.println s!"Deleted corrected benchmark: {total.1} files, {total.2} logical bytes"

def main (args : List String) : IO Unit := do
  if args == ["corrected-bench"] then
    retireCorrected
    return
  check args.isEmpty "only the ended original or corrected experiment may be retired"
  let project : System.FilePath := "/Users/ovm/.codex/worktrees/hook-deadline-baseline/eggshell"
  let root : System.FilePath := "/Users/ovm/.codex/experiments/eggshell/scope-token-study-20261028/shared-snapshot"
  let records := project / "docs/candidates/source-projection-wire"
  check (!(← (records / "retired.json").pathExists)) "preserve completed cleanup"
  let bench ← read (records / "bench.json")
  check (bench.getObjValD "completeProjectionEqual" == toJson true && bench.getObjValD "sourceUnchanged" == toJson true &&
    bench.getObjValD "adopted" == toJson false) "native codec benchmark is unfinished"
  let ended ← read (records / "service-exit.json")
  check (ended.getObjValD "exitCode" == toJson (0 : Nat) && ended.getObjValD "protectedHashesBeforeAndAfter" == toJson true)
    "service experiment is unfinished"
  let report ← read (records / "service-results.json")
  check (report.getObjValD "productionAdoption" == toJson false) "experiment was adopted"
  let reports : Array Json ← IO.ofExcept (report.getObjValAs? _ "reports")
  check (reports.size == 2) "both fixed service profiles are required"
  for result in reports do
    check (result.getObjValD "clients" == toJson (80 : Nat)) "client profile changed"
    for name in ["allOriginalRowsEqual","allPublishedLayoutsEqual","allSourceBindingSequencesEqual"] do
      check (result.getObjValD name == toJson true) "source service comparison failed"
  let lifecycle ← read (records / "service-lifecycle.json")
  for result in reports.push lifecycle do
    let shutdown := result.getObjValD "shutdown"
    check (shutdown.getObjValD "acknowledged" == toJson true && shutdown.getObjValD "exitCode" == toJson (0 : Nat) &&
      shutdown.getObjValD "endpointRemoved" == toJson true) "a service is still live"
  for entry in ← records.readDir do
    if entry.fileName.endsWith ".guard.json" && entry.fileName != "retired.guard.json" then
      let guard ← read entry.path
      check (guard.getObjValD "state" == toJson "finished" && guard.getObjValD "ownedPids" == toJson (#[] : Array Nat))
        "another experiment task is live"
  let proofs ← IO.FS.readFile (records / "proofs.stdout")
  check ((proofs.splitOn "sorryAx").length == 1 && (proofs.splitOn "unpack_pack").length == 2) "proof audit failed"
  let mut originals : Array (String × String) ← IO.ofExcept ((← read
    (project / "docs/candidates/read-signal-trace/native-seal.json")).getObjValAs? _ "verifiedOriginalFilesAndRuntimes")
  originals := originals.push ((root / "register-runtime-build/StudyMain").toString,
    "1bd3d15bb3c708a14785c983fcb8e1c95d650bc55f837202d84538de0bda787b")
  verify originals
  let mut seals := #[]
  for name in ["source-projection-wire-bench-build","source-projection-wire-runtime-build","source-projection-wire-service-audit-build"] do
    seals := seals.push ((root / name / "StudyMain").toString,← hash (root / name / "StudyMain"))
  check ((← IO.FS.readFile (root / "source-projection-wire-core/Eggshell/Handoff.lean")) ==
    (← IO.FS.readFile (root / "query-cache-baseline-core/Eggshell/Handoff.lean"))) "evidence selection changed"
  let mut patchText := ""
  for name in ["Eggshell/PublicationClient.lean","Eggshell/PublicationService.lean","Eggshell/PublicationWire.lean"] do
    let diff ← IO.Process.output {cmd := "/usr/bin/diff",args := #["-u",
      (root / "query-cache-baseline-core" / name).toString,(root / "source-projection-wire-core" / name).toString]}
    check (diff.exitCode == 1) "candidate source difference missing"
    patchText := patchText ++ diff.stdout
  IO.FS.writeFile (records / "candidate.patch") patchText
  let mut targets : Array System.FilePath := #[]
  for entry in ← root.readDir do
    if entry.fileName.startsWith "source-projection-wire-" then targets := targets.push entry.path
  let builds := #[root / "query-cache-baseline-build",root / "prepared-bindings-build",root / "register-runtime-build"]
  for build in builds do
    for line in (← IO.FS.readFile (build / "runtime.rsp")).splitOn "\n" do
      if line.trimAscii.isEmpty then continue
      let path : System.FilePath := .mk (← IO.ofExcept (Json.parse line >>= Json.getStr?))
      check (!(targets.any (inside path))) "active runtime uses an ended artifact"
    protect (build / "lib") targets
  let running ← IO.Process.output {cmd := "/bin/ps",args := #["-axo","command="]}
  check (running.exitCode == 0) "cannot inspect active processes"
  for target in targets do check ((running.stdout.splitOn target.toString).length == 1) "an artifact remains in use"
  for name in ["proofs.stderr","service.stdout","service.stderr"] do
    if ← (records / name).pathExists then targets := targets.push (records / name)
  let mut total := (0,0)
  let mut removed := #[]
  for target in targets do
    let count ← remove target
    total := (total.1+count.1,total.2+count.2)
    removed := removed.push (target.toString,count.1,count.2)
    check (!(← target.pathExists)) "cleanup left a temporary artifact"
  verify originals
  let mut links := 0
  for build in builds do
    for line in (← IO.FS.readFile (build / "runtime.rsp")).splitOn "\n" do
      if line.trimAscii.isEmpty then continue
      let path : System.FilePath := .mk (← IO.ofExcept (Json.parse line >>= Json.getStr?))
      check (← path.pathExists) "cleanup removed an active native input"
      links := links+1
  IO.FS.writeFile (records / "retired.json") (Json.mkObj [("removed",toJson removed),("files",toJson total.1),
    ("logicalBytes",toJson total.2),("seals",toJson seals),("protectedHashesBeforeAndAfter",toJson true),
    ("retainedNativeLinkInputs",toJson links),("archiveCreated",toJson false),("followsSymlinks",toJson false),
    ("adopted",toJson false)]).pretty
  IO.println s!"Retired source projection experiment: {total.1} files, {total.2} logical bytes"
