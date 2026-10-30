import Lean.Data.Json.Parser
import Lean.Data.Json.FromToJson
open Lean

private def check (ok : Bool) (message : String) : IO Unit := unless ok do throw (IO.userError message)
private def read (path : System.FilePath) : IO Json := IO.FS.readFile path >>= fun text => IO.ofExcept (Json.parse text)
private def hash (path : System.FilePath) : IO String := do
  let result ← IO.Process.output {cmd := "/usr/bin/shasum",args := #["-a","256",path.toString]}
  check (result.exitCode == 0) "cannot seal incidence cleanup"
  return (result.stdout.splitOn " ").headD ""
private def verify (files : Array (String × String)) : IO Unit := do
  for (path,expected) in files do check ((← hash (.mk path)) == expected) "protected original/runtime changed"
private def inside (path root : System.FilePath) : Bool := path == root || path.toString.startsWith (root.toString ++ "/")
private partial def protect (directory : System.FilePath) (targets : Array System.FilePath) : IO Unit := do
  for entry in ← directory.readDir do
    let info ← entry.path.symlinkMetadata
    if info.type == .dir then protect entry.path targets
    else if info.type == .symlink then
      check (!(targets.any (inside (← IO.FS.realPath entry.path)))) "retained interface needs incidence candidate"
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
  let records := project / "docs/candidates/record-incidence"
  check (!(← (records / "retired.json").pathExists)) "preserve completed cleanup"
  let bench ← read (records / "bench.json")
  let samples : Array Json ← IO.ofExcept (bench.getObjValAs? _ "samples")
  check (bench.getObjValD "exactOriginalClosures" == toJson true && samples.size == 12 &&
    bench.getObjValD "queryGroupsPerCycle" == toJson (1792 : Nat) &&
    bench.getObjValD "malformedRejected" == toJson (84 : Nat)) "native audit incomplete"
  let a ← IO.ofExcept (bench.getObjValAs? Nat "baselineUpperMedianNs")
  let b ← IO.ofExcept (bench.getObjValAs? Nat "candidateUpperMedianNs")
  check (a < b && bench.getObjValD "actualHookMeasured" == toJson false &&
    bench.getObjValD "adopted" == toJson false) "negative stop rule not met"
  check ((← read (records / "bench-exit.json")).getObjValD "exitCode" == toJson (0 : Nat)) "audit not finished"
  for entry in ← records.readDir do
    if entry.fileName.endsWith ".guard.json" then
      let guard ← read entry.path
      check (guard.getObjValD "state" == toJson "finished" && guard.getObjValD "ownedPids" == toJson (#[] : Array Nat))
        "incidence process still live"
  let files : Array (String × String) ← IO.ofExcept ((← read
    (project / "docs/candidates/read-signal-trace/native-seal.json")).getObjValAs? _ "verifiedOriginalFilesAndRuntimes")
  let files := files.push ((root / "register-runtime-build/StudyMain").toString,
    "1bd3d15bb3c708a14785c983fcb8e1c95d650bc55f837202d84538de0bda787b")
  verify files
  let mut patch := ""
  for name in ["CanonicalSourceRecipe","CanonicalSourcePrepared","PublicationService","SynapseTransport","Handoff","CanonicalSourceCache"] do
    let file := "Eggshell/" ++ name ++ ".lean"
    let diff ← IO.Process.output {cmd := "/usr/bin/git",args := #["diff","--no-index","--",
      (root / "query-cache-baseline-core" / file).toString,(root / "record-incidence-core" / file).toString]}
    check (diff.exitCode == 1) "candidate patch missing"
    patch := patch ++ diff.stdout
  IO.FS.writeFile (records / "core.patch") patch
  let mut targets := #[]
  for entry in ← root.readDir do
    if entry.fileName.startsWith "record-incidence-" then targets := targets.push entry.path
  let mut links := #[]
  for name in ["query-cache-baseline-build","prepared-bindings-build","register-runtime-build"] do
    let build := root / name
    for line in (← IO.FS.readFile (build / "runtime.rsp")).splitOn "\n" do
      if line.trimAscii.isEmpty then continue
      let path : System.FilePath := .mk (← IO.ofExcept (Json.parse line >>= Json.getStr?))
      check (!(targets.any (inside path))) "retained native object depends on trial"
      links := links.push path
    protect (build / "lib") targets
  let processes ← IO.Process.output {cmd := "/bin/ps",args := #["-axo","command="]}
  check (processes.exitCode == 0) "cannot inspect process ownership"
  for target in targets do check ((processes.stdout.splitOn target.toString).length == 1) "artifact still live"
  let mut removed := #[]
  let mut total := (0,0)
  for target in targets do
    let part ← remove target
    removed := removed.push (target.toString,part.1,part.2)
    total := (total.1+part.1,total.2+part.2)
  verify files
  for path in links do check (← path.pathExists) "cleanup removed retained input"
  IO.FS.writeFile (records / "retired.json") (Json.mkObj [("files",toJson total.1),("logicalBytes",toJson total.2),
    ("removed",toJson removed),("protectedHashesBeforeAndAfter",toJson true),
    ("retainedNativeLinkInputs",toJson links.size),("archiveCreated",toJson false),("adopted",toJson false)]).pretty
  IO.println s!"Retired negative incidence candidate: {total.1} files, {total.2} logical bytes"
