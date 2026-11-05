import Lean.Data.Json.FromToJson
import Lean.Data.Json.Parser
open Lean
def workspace : System.FilePath := "/Users/ovm/.codex/worktrees/hook-deadline-baseline/eggshell"
def base : System.FilePath := "/Users/ovm/.codex/experiments/eggshell/scope-token-study-20261028/fixed-frame-study"
def core := base/"interest-traffic-core"
def destination := workspace/"docs/candidates/numerical-waits"
def check (ok : Bool) (message : String) : IO Unit := unless ok do throw (IO.userError message)
def read (path : System.FilePath) : IO Json := do IO.ofExcept (Json.parse (← IO.FS.readFile path))
def arr (value : Json) (key : String) : Array Json := (value.getObjValAs? (Array Json) key).toOption.getD #[]
def nat (value : Json) (key : String) : Nat := (value.getObjValAs? Nat key).toOption.getD 0
def run (command : String) (arguments : Array String) (directory : System.FilePath := workspace) : IO String := do
  let result ← IO.Process.output {cmd := command,args := arguments,cwd := some directory}
  check (result.exitCode == 0) (result.stdout++result.stderr)
  pure result.stdout
def digest (path : System.FilePath) : IO String := do
  return ((← run "/usr/bin/shasum" #["-a","256",path.toString]).splitOn " ").headD ""
def verifyOriginals : IO Unit := do
  discard <| run "/usr/bin/shasum" #["-a","256","-c",(workspace/"docs/candidates/project-cache/protected-after.sha256").toString] base
  let heads ← IO.ofExcept (fromJson? (← read (workspace/"docs/candidates/worker-cpu/heads.json")) : Except String (Array (String × String × String)))
  for (path,bytes,sha) in heads do
    check ((← IO.FS.readFile (.mk path)) == bytes && (← digest (.mk path)) == sha) "original head changed"
def completedGuards : IO (Array Json) := do
  let mut guards := #[]
  for entry in ← base.readDir do
    unless entry.fileName.endsWith ".guard.json" &&
      ["numerical-stages-","numerical-waits-"].any (entry.fileName.startsWith ·) &&
      !entry.fileName.contains "-finish" do continue
    let guard ← read entry.path
    check (guard.getObjValD "state" == toJson "finished" && guard.getObjValD "ownedPids" == toJson (#[] : Array Nat)) "study still active"
    let pid := nat guard "guardPid"
    let status ← IO.Process.output {cmd := "/bin/ps",args := #["-p",toString pid,"-o","command="]}
    check (!status.stdout.contains (base/(entry.fileName.dropEnd 11 |>.toString)).toString) "guard still active"
    guards := guards.push (Json.mkObj [("file",toJson entry.path.toString),("guard",guard)])
  return guards
def rows (file : System.FilePath) (tag : String) : IO (Array Json) := do
  let some trial := (arr (← read file) "runs").find? (fun run => run.getObjValD "tag" == toJson tag) |
    throw (IO.userError "control run missing")
  return (arr trial "rowsIncludingPrime").filter (fun row =>
    ((row.getObjValAs? String "session").toOption.getD "").startsWith "cpu-wave-")
def record : IO Unit := do
  let mut controls := #[]
  for (leftStudy,leftTag,rightStudy,rightTag,count) in [
      ("numerical-stages","numerical-stages-parent16-1","numerical-stages","numerical-stages-off16-1",32),
      ("numerical-stages","numerical-stages-off16-1","numerical-stages","numerical-stages-on16-1",32),
      ("numerical-stages","numerical-stages-parent16-1","numerical-waits","numerical-waits-off16-1",32),
      ("numerical-waits","numerical-waits-off16-1","numerical-waits","numerical-waits-on16-1",32)] do
    let left ← rows (workspace/"docs/candidates"/leftStudy/"evidence.json") leftTag
    let right ← rows (workspace/"docs/candidates"/rightStudy/"evidence.json") rightTag
    check (left.size == count && right.size == count) "control domain changed"
    for row in left do
      let some other := right.find? (fun item => item.getObjValD "session" == row.getObjValD "session") |
        throw (IO.userError "control lost session")
      check (row.getObjValD "stdoutSha256" == other.getObjValD "stdoutSha256" &&
        row.getObjValD "stdoutSha256" != Json.null) "actual control bytes differ"
    controls := controls.push (toJson (leftTag,rightTag,count))
  let prior32 ← rows (workspace/"docs/candidates/numerical-stages/evidence.json") "numerical-stages-on32-1"
  let next32 ← rows (destination/"evidence.json") "numerical-waits-on32-1"
  let successful := prior32.filter (fun row => row.getObjValD "bothFields" == toJson true && row.getObjValD "acknowledged" == toJson true)
  check (prior32.size == 32 && next32.size == 32 && successful.size == 21) "thirty-two-client domain changed"
  for row in successful do
    let some next := next32.find? (fun item => item.getObjValD "session" == row.getObjValD "session") |
      throw (IO.userError "candidate lost prior successful session")
    check (row.getObjValD "stdoutSha256" == next.getObjValD "stdoutSha256") "prior successful original changed"
  let mut accounting := #[]
  for study in ["numerical-stages","numerical-waits"] do
    for profile in arr (← read (workspace/"docs/candidates"/study/"rpc-profiles.json")) "profiles" do
      let metric := profile.getObjValD "metric"
      let counters := metric.getObjValD "counters"
      let scoreReplies := (arr counters "numericalReplies").filter (fun reply => reply.getObjValD "kind" == toJson "blocks")
      let scoreRoundtrip := scoreReplies.foldl (fun total reply => total+nat reply "clientReceivedAt"-nat reply "clientStartedAt") 0
      check (scoreRoundtrip ≤ nat counters "scoreMs") "returned scoring spans exceed sequential completed scoring interval"
      accounting := accounting.push (Json.mkObj [("tag",profile.getObjValD "tag"),("session",profile.getObjValD "session"),
        ("purpose",(metric.getObjValD "corpus").getObjValD "purpose"),("status",metric.getObjValD "status"),
        ("phase",counters.getObjValD "phase"),("elapsedMs",metric.getObjValD "elapsedMs"),
        ("completedScoreWallMs",counters.getObjValD "scoreMs"),("returnedScoreRpcRoundtripMs",toJson scoreRoundtrip),
        ("remainingCompletedScoreWallMs",if scoreReplies.isEmpty && 0 < nat counters "scoreMs" then Json.null else toJson (nat counters "scoreMs"-scoreRoundtrip)),
        ("scoreRoundtripsObserved",toJson (!scoreReplies.isEmpty)),
        ("returnedScoreRpcs",toJson scoreReplies.size)])
  IO.FS.writeFile (destination/"accounting.json") (Json.mkObj [("profiles",toJson accounting),
    ("controlsByteIdentical",toJson controls),("failedCurrentRpcExcluded",toJson true),
    ("thirtyTwoPriorSuccessesByteIdentical",toJson successful.size),
    ("wallIntervalsNotCpuAttribution",toJson true),("adopted",toJson false)]).pretty
def restore : IO Unit := do
  discard <| completedGuards
  verifyOriginals
  for path in ["numerical-waits/candidate.patch","numerical-stages/candidate.patch","numerical-ready/candidate.patch",
      "provider-stages/candidate.patch","query-stages/candidate.patch","shared-leases/combined.patch","numerical-stages/controller.patch"] do
    let patch := workspace/"docs/candidates"/path
    discard <| run "/usr/bin/git" #["apply","--reverse","--unidiff-zero","--check",patch.toString] core
    discard <| run "/usr/bin/git" #["apply","--reverse","--unidiff-zero",patch.toString] core
  let checks := core/"tools/research/NumericalReadyChecks.lean"
  check ((← IO.FS.readFile checks) == (← IO.FS.readFile (workspace/"tools/research/NumericalReadyChecks.lean"))) "check source changed"
  IO.FS.removeFile checks
  verifyOriginals
  IO.FS.writeFile (destination/"restoration.json") (Json.mkObj [("overlaysReversed",toJson true),
    ("controllerRestored",toJson true),("originalHeadsUnchanged",toJson true),("adopted",toJson false)]).pretty
partial def remove (path : System.FilePath) : IO (Nat × Nat) := do
  let metadata ← path.symlinkMetadata
  if metadata.type != .dir then
    IO.FS.removeFile path
    return (1,metadata.byteSize.toNat)
  let mut count := 0
  let mut bytes := 0
  for entry in ← path.readDir do
    let (n,b) ← remove entry.path
    count := count+n
    bytes := bytes+b
  IO.FS.removeDir path
  return (count,bytes)
def retireBuilds : IO Unit := do
  let output := destination/"compiled-cleanup.json"
  check (!(← output.pathExists)) "build cleanup already recorded"
  discard <| completedGuards
  for study in ["numerical-stages","numerical-waits"] do
    check ((← read (workspace/"docs/candidates"/study/"cleanup.json")).getObjValD "archive" == toJson false) "raw cleanup missing"
  let targets := #[base/"numerical-ready-build/StudyMain",base/"numerical-stages-build/StudyMain",
    base/"session-dispatch-client-build/StudyMain",base/"numerical-waits-checks-build"]
  let processes ← run "/bin/ps" #["-axo","command="]
  let aliasTarget ← IO.FS.realPath (base/"worker-cpu-target/bin/eggshelld")
  let mut responses := #[]
  for name in ["controller","focus-locators-build","hosted-endpoint-build","metadata-ingress-candidate-build",
      "numerical-waits-build","numerical-stages-client-build"] do
    let path := base/name/"runtime.rsp"
    let text ← IO.FS.readFile path
    for target in targets do check (!text.contains target.toString) "retained runtime links retired input"
    responses := responses.push (path,← digest path)
  for target in targets do
    check (!processes.contains target.toString && aliasTarget != target) "retired build still selected or live"
  verifyOriginals
  let mut removed := #[]
  for target in targets do
    let sha ← if (← target.symlinkMetadata).type == .file then digest target else pure "directory"
    let (files,bytes) ← remove target
    removed := removed.push (Json.mkObj [("path",toJson target.toString),("sha256",toJson sha),
      ("files",toJson files),("logicalBytes",toJson bytes)])
  for (path,sha) in responses do check ((← digest path) == sha) "retained native link inputs changed"
  verifyOriginals
  let mut preflights := #[]
  let mut endedLogs : Array System.FilePath := #[]
  for entry in ← base.readDir do
    unless entry.fileName.endsWith ".log" &&
      ["numerical-stages-","numerical-waits-"].any (entry.fileName.startsWith ·) do continue
    let tag := entry.fileName.dropEnd 4 |>.toString
    let guardPath := base/(tag++".guard.json")
    if !(← guardPath.pathExists) then continue
    let guard ← read guardPath
    if guard.getObjValD "state" != toJson "finished" then continue
    check (guard.getObjValD "ownedPids" == toJson (#[] : Array Nat)) "cleanup helper still owns a process"
    let text ← IO.FS.readFile entry.path
    check (text.utf8ByteSize < 32768) "unexpected cleanup log size"
    preflights := preflights.push (Json.mkObj [("tag",toJson tag),("guard",guard),
      ("logSha256",toJson (← digest entry.path)),("log",toJson text)])
    endedLogs := endedLogs.push entry.path
  IO.FS.writeFile output (Json.mkObj [("removed",toJson removed),("retainedLinkResponses",toJson responses),
    ("cleanupPreflights",toJson preflights),
    ("protectedOriginalsUnchanged",toJson true),("retainedObjectsAndInterfacesUnchanged",toJson true),
    ("rebuildRetiredControlsBeforeRerun",toJson true),("archive",toJson false)]).pretty
  for log in endedLogs do IO.FS.removeFile log
def main (args : List String) : IO Unit := do
  match args with
  | ["record"] => record
  | ["record-restore"] => record; restore
  | ["restore"] => restore
  | ["retire-builds"] => retireBuilds
  | ["verify"] =>
    verifyOriginals
    let guards ← completedGuards
    for (study,expected) in [("numerical-stages",140),("numerical-waits",188)] do
      discard <| run "/Users/ovm/.elan/toolchains/leanprover--lean4---v4.33.0/bin/lean"
        #["-j1","-M1536","--run",(workspace/"docs/candidates/shared-leases/records.lean").toString,
          "--"++study,"verify",toString expected]
      let verified ← read (workspace/"docs/candidates"/study/"verification.json")
      check (nat verified "actualOutputs" == expected) "actual body verification missing"
      check ((← read (workspace/"docs/candidates"/study/"cleanup.json")).getObjValD "archive" == toJson false) "cleanup incomplete"
    let status ← run "/usr/bin/git" #["diff","--name-only","--","Eggshell","Main.lean","lakefile.lean","lean-toolchain"]
    check (status.isEmpty) "product core changed"
    let runtime ← digest (base/"numerical-waits-build/StudyMain")
    let client ← digest (base/"numerical-stages-client-build/StudyMain")
    let sealed ← read (destination/"seal.json")
    check (sealed.getObjValD "observer" == toJson runtime && sealed.getObjValD "client" == toJson client) "retained executable changed"
    let mut preflights := #[]
    let mut logs : Array System.FilePath := #[]
    for entry in ← base.readDir do
      unless entry.fileName.endsWith ".guard.json" && entry.fileName.startsWith "numerical-waits-finish-" do continue
      let guard ← read entry.path
      if guard.getObjValD "state" != toJson "finished" then continue
      check (guard.getObjValD "ownedPids" == toJson (#[] : Array Nat)) "milestone helper still owns a process"
      let tag := entry.fileName.dropEnd 11 |>.toString
      let log := base/(tag++".log")
      let text ← if ← log.pathExists then IO.FS.readFile log else pure ""
      check (text.utf8ByteSize < 32768) "unexpected milestone log size"
      preflights := preflights.push (Json.mkObj [("tag",toJson tag),("guard",guard),("log",toJson text)])
      if ← log.pathExists then logs := logs.push log
    IO.FS.writeFile (destination/"completion.json") (Json.mkObj [("guards",toJson guards),
      ("milestonePreflights",toJson preflights),("retainedRuntimeSha256",toJson runtime),("retainedClientSha256",toJson client),
      ("actualOutputsVerified",toJson (328 : Nat)),("productCoreUnchanged",toJson true),
      ("isolatedSourceRestored",(← read (destination/"restoration.json")).getObjValD "overlaysReversed"),
      ("originalHeadsUnchanged",toJson true),("answeringModelCalls",toJson (0 : Nat)),
      ("paidComparisons",toJson "0/18"),("goalAchieved",toJson false),("adopted",toJson false)]).pretty
    for log in logs do IO.FS.removeFile log
  | _ => throw (IO.userError "record,restore,retire-builds or verify required")
