import Lean.Data.Json.Parser
import Lean.Data.Json.FromToJson
open Lean

private def check (ok : Bool) (message : String) : IO Unit := unless ok do throw (IO.userError message)
private def read (path : System.FilePath) : IO Json := IO.FS.readFile path >>= fun text => IO.ofExcept (Json.parse text)
private def hash (path : System.FilePath) : IO String := do
  let result ← IO.Process.output {cmd := "/usr/bin/shasum",args := #["-a","256",path.toString]}
  check (result.exitCode == 0) "cannot seal routing cleanup"
  return (result.stdout.splitOn " ").headD ""
private def verify (files : Array (String × String)) : IO Unit := do
  for (path,expected) in files do check ((← hash (.mk path)) == expected) "protected original/runtime changed"
private def inside (path root : System.FilePath) : Bool := path == root || path.toString.startsWith (root.toString ++ "/")
private partial def protect (directory : System.FilePath) (targets : Array System.FilePath) : IO Unit := do
  for entry in ← directory.readDir do
    let info ← entry.path.symlinkMetadata
    if info.type == .dir then protect entry.path targets
    else if info.type == .symlink then
      check (!(targets.any (inside (← IO.FS.realPath entry.path)))) "retained interface needs routing candidate"
private partial def remove (path : System.FilePath) : IO (Nat × Nat) := do
  let info ← path.symlinkMetadata
  if info.type == .dir then
    let mut count := (0,0)
    for entry in ← path.readDir do
      let part ← remove entry.path
      count := (count.1+part.1,count.2+part.2)
    IO.FS.removeDir path
    return count
  IO.FS.removeFile path
  return (1,if info.type == .file then info.byteSize.toNat else 0)

private def trimLogs (records : System.FilePath) : IO Unit := do
  check (← (records / "retired.json").pathExists) "candidate artifacts must be retired first"
  check (!(← (records / "retired-duplicate-logs.json").pathExists)) "preserve log cleanup"
  let report ← read (records / "hooks/results.json")
  check (report.getObjValD "sameActualBodyWithinDeadline" == toJson true) "actual hook evidence is incomplete"
  let mut removed := #[]
  for arm in ["baseline","candidate"] do
    let mut paths := [records / "hooks" / arm / "warm/stdin",records / "hooks" / arm / "warm/stdout",
      records / "hooks" / arm / "warm/stderr"]
    for repetition in ["0","1"] do
      for event in ["SessionStart","UserPromptSubmit"] do
        for name in ["stdout","stderr"] do
          paths := paths ++ [records / "hooks" / arm / ("rep-" ++ repetition) / event / name]
    for path in paths do
      if ← path.pathExists then
        let info ← path.symlinkMetadata
        check (info.type == .file) "duplicate log is not an owned regular file"
        removed := removed.push (path.toString,info.byteSize.toNat,← hash path)
        IO.FS.removeFile path
  IO.FS.writeFile (records / "retired-duplicate-logs.json") (Json.mkObj [("removed",toJson removed),
    ("actualBodiesTimingRequestsAndAuditsRetained",toJson true),("archiveCreated",toJson false)]).pretty
  IO.println "Deleted duplicate/empty process logs; actual bodies, requests, timing and audits retained"

private def shareBodies (records : System.FilePath) : IO Unit := do
  check (← (records / "retired.json").pathExists) "candidate must be retired first"
  let target := records / "hooks/body.txt"
  check (!(← target.pathExists)) "preserve shared actual body"
  let measured ← read (records / "hooks/results.json")
  let results : Array Json ← IO.ofExcept (measured.getObjValAs? _ "results")
  check (results.size == 4 && measured.getObjValD "sameActualBodyWithinDeadline" == toJson true)
    "four equal actual bodies required"
  let mut files := #[]
  let mut expected : Option String := none
  for result in results do
    let arm ← IO.ofExcept (result.getObjValAs? String "arm")
    let rep ← IO.ofExcept (result.getObjValAs? String "repetition")
    let path := records / "hooks" / arm / ("rep-" ++ rep) / "body.txt"
    let recorded ← IO.ofExcept (result.getObjValAs? String "bodySha256")
    let digest ← hash path
    check (recorded == digest && expected.all (· == digest)) "actual body changed or differs"
    if expected.isNone then expected := some digest
    files := files.push (path,digest)
  let some first := files[0]? | throw (IO.userError "actual bodies missing")
  IO.FS.writeFile target (← IO.FS.readFile first.1)
  check ((← hash target) == first.2) "shared actual body changed bytes"
  IO.FS.writeFile (records / "hooks/body-references.json") (Json.mkObj [
    ("body",toJson "body.txt"),("sha256",toJson first.2),
    ("originalActualFiles",toJson (files.map fun (path,digest) => (path.toString,digest))),
    ("allFourActualBytesVerifiedBeforeRemoval",toJson true),("archiveCreated",toJson false)]).pretty
  for (path,_) in files do IO.FS.removeFile path
  IO.println "Stored one byte-identical actual body with four verified run references"

def main (args : List String) : IO Unit := do
  let project : System.FilePath := "/Users/ovm/.codex/worktrees/hook-deadline-baseline/eggshell"
  let root : System.FilePath := "/Users/ovm/.codex/experiments/eggshell/scope-token-study-20261028/shared-snapshot"
  let records := project / "docs/candidates/routing-scope"
  if args == ["logs"] then trimLogs records; return
  if args == ["bodies"] then shareBodies records; return
  check args.isEmpty "only the owned experiment or duplicate logs may be retired"
  check (!(← (records / "retired.json").pathExists)) "preserve completed routing cleanup"
  let pureResult ← read (records / "pure-domain/results.json")
  check (pureResult.getObjValD "clients" == toJson (80 : Nat) &&
    pureResult.getObjValD "sharedUsageNotWritten" == toJson true) "routing lane audit is incomplete"
  let service ← read (records / "service/results.json")
  for flag in ["allOriginalOrdersCountersAndGroupsEqual","serviceAccountUsageIgnored",
      "routingDeltaWithoutCanonicalRebuild","oldRoutingPinPreserved","shutdownAcknowledged","endpointRemoved"] do
    check (service.getObjValD flag == toJson true) "routing service audit failed or is live"
  let hooks ← read (records / "hooks/results.json")
  check (hooks.getObjValD "adopted" == toJson false &&
    hooks.getObjValD "answeringModelCalls" == toJson (0 : Nat)) "hook outcome is missing or adopted"
  let results : Array Json ← IO.ofExcept (hooks.getObjValAs? _ "results")
  check (!results.isEmpty) "actual hooks were not executed"
  for result in results do
    let arm ← IO.ofExcept (result.getObjValAs? String "arm")
    let repetition ← IO.ofExcept (result.getObjValAs? String "repetition")
    let folder := records / "hooks" / arm / ("rep-" ++ repetition)
    check (result.getObjValD "bodySha256" == toJson (← hash (folder / "body.txt"))) "actual hook body changed"
    for name in ["shutdown.json","publisher-shutdown.json"] do
      let stopped ← read (folder / name)
      check (stopped.getObjValD "acknowledged" == toJson true && stopped.getObjValD "processExited" == toJson true &&
        stopped.getObjValD "endpointRemoved" == toJson true) "a hook service is still live"
  for entry in ← records.readDir do
    if entry.fileName.endsWith ".guard.json" then
      let guard ← read entry.path
      check (guard.getObjValD "state" == toJson "finished" && guard.getObjValD "ownedPids" == toJson (#[] : Array Nat))
        "routing guard is live"
  let files : Array (String × String) ← IO.ofExcept ((← read
    (project / "docs/candidates/read-signal-trace/native-seal.json")).getObjValAs? _ "verifiedOriginalFilesAndRuntimes")
  let files := files.push ((root / "register-runtime-build/StudyMain").toString,
    "1bd3d15bb3c708a14785c983fcb8e1c95d650bc55f837202d84538de0bda787b")
  verify files
  let mut patch := ""
  for name in ["PublicationClient","PublicationService","PublicationWire","SynapseRecommend","SynapseTransport","SynapticTransport","SynapticRoutingStore"] do
    let file := "Eggshell/" ++ name ++ ".lean"
    let diff ← IO.Process.output {cmd := "/usr/bin/git",args := #["diff","--no-index","--",
      (root / "query-cache-baseline-core" / file).toString,(root / "routing-scope-core" / file).toString]}
    check (diff.exitCode == 1) "candidate patch is missing"
    patch := patch ++ diff.stdout
  IO.FS.writeFile (records / "core.patch") patch
  let mut targets := #[]
  for entry in ← root.readDir do
    if entry.fileName.startsWith "routing-scope-" then targets := targets.push entry.path
  let retained := #[root / "query-cache-baseline-build",root / "prepared-bindings-build",root / "register-runtime-build"]
  let mut links := #[]
  for build in retained do
    for line in (← IO.FS.readFile (build / "runtime.rsp")).splitOn "\n" do
      if line.trimAscii.isEmpty then continue
      let path : System.FilePath := .mk (← IO.ofExcept (Json.parse line >>= Json.getStr?))
      check (!(targets.any (inside path))) "retained native object depends on routing trial"
      links := links.push path
    protect (build / "lib") targets
  let running ← IO.Process.output {cmd := "/bin/ps",args := #["-axo","command="]}
  check (running.exitCode == 0) "cannot inspect routing processes"
  for target in targets do check ((running.stdout.splitOn target.toString).length == 1) "routing artifact is live"
  let mut removed := #[]
  let mut total := (0,0)
  for target in targets do
    let part ← remove target
    removed := removed.push (target.toString,part.1,part.2)
    total := (total.1+part.1,total.2+part.2)
  verify files
  for path in links do check (← path.pathExists) "cleanup removed a retained link input"
  IO.FS.writeFile (records / "retired.json") (Json.mkObj [("removed",toJson removed),
    ("files",toJson total.1),("logicalBytes",toJson total.2),("protectedHashesBeforeAndAfter",toJson true),
    ("retainedNativeLinkInputs",toJson links.size),("archiveCreated",toJson false),("adopted",toJson false)]).pretty
  IO.println s!"Deleted ended routing trial: {total.1} files, {total.2} logical bytes"
