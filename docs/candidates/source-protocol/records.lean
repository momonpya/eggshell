import Lean.Data.Json.FromToJson
import Lean.Data.Json.Parser
open Lean
def base : System.FilePath := "/Users/ovm/.codex/experiments/eggshell/scope-token-study-20261028/fixed-frame-study"
def output : System.FilePath := "/Users/ovm/.codex/worktrees/hook-deadline-baseline/eggshell/docs/candidates/source-protocol"
def check (ok : Bool) (message : String) : IO Unit := unless ok do throw (IO.userError message)
def read (path : System.FilePath) : IO Json := do IO.ofExcept (Json.parse (← IO.FS.readFile path))
def array (value : Json) (key : String) := (value.getObjValAs? (Array Json) key).toOption.getD #[]
def leanRun (path : System.FilePath) (arguments : Array String := #[]) : IO Unit := do
  let result ← IO.Process.output {
    cmd := "/Users/ovm/.elan/toolchains/leanprover--lean4---v4.33.0/bin/lean"
    args := #["-j1","-M1536","--run",path.toString]++arguments,
    cwd := some "/Users/ovm/.codex/worktrees/hook-deadline-baseline/eggshell"}
  IO.print result.stdout
  IO.eprint result.stderr
  check (result.exitCode == 0) "source protocol record helper failed"
def captureGuard (tag : String) : IO Json := do
  let guard ← read (base/(tag++".guard.json"))
  check (guard.getObjValD "state" == toJson "finished" && guard.getObjValD "ownedPids" == toJson (#[] : Array Nat))
    "protocol guard still owns a workload"
  let pid ← IO.ofExcept (guard.getObjValAs? Nat "guardPid")
  let live ← IO.Process.output {cmd := "/bin/ps",args := #["-p",toString pid,"-o","command="]}
  check (!live.stdout.contains (base/(tag++".guard-settings.json")).toString) "protocol guard still live"
  return guard
def captureAcquisition : IO Unit := do
  check (!(← (output/"acquisition.json").pathExists)) "source protocol records already sealed"
  let mut runs := #[]
  let mut guards := #[]
  let mut frozen := Json.null
  for tag in ["source-protocol-external1","source-protocol-hosted1","source-protocol-hosted2",
      "source-protocol-external2","source-protocol-external3","source-protocol-hosted3"] do
    let guard ← captureGuard tag
    check (guard.getObjValD "exitCode" == toJson (0 : Nat) && guard.getObjValD "guardTriggered" == toJson false)
      "protocol acquisition/lifecycle gate failed"
    let root := base/(tag++"-result")
    let report ← read (root/"report.json")
    let sources ← read (root/"frozen-sources.json")
    if frozen == Json.null then frozen := sources
    check (frozen == sources && report.getObjValD "originalHeadsUnchanged" == toJson true)
      "protocol run changed source cut"
    let wave := report.getObjValD "eighty"
    let rows := array wave "rows"
    check (rows.size == 80 && rows.all (fun row => row.getObjValD "complete" == toJson true &&
      row.getObjValD "tokens" == toJson (16 : Nat) && (array row "errors").isEmpty)) "full received-cut check failed"
    let shutdown ← read (root/"shutdown.json")
    check (shutdown.getObjValD "ack" == toJson true && shutdown.getObjValD "ownerExited" == toJson true)
      "protocol owner failed to stop"
    for state in [wave.getObjValD "full",wave.getObjValD "drained"] do
      let retained := state.getObjValD "retainedSources"
      check (retained.getObjValD "accountedExact" == toJson true && retained.getObjValD "borrowersExact" == toJson true)
        "protocol lease accounting not exact"
    check (((wave.getObjValD "full").getObjValD "retainedSources").getObjValD "active" == toJson (1280 : Nat) &&
      ((wave.getObjValD "drained").getObjValD "retainedSources").getObjValD "active" == toJson (0 : Nat) &&
      (array wave "releaseErrors").all (· == Json.null)) "protocol leases did not acquire/release completely"
    runs := runs.push (Json.mkObj [("tag",toJson tag),("mode",report.getObjValD "mode"),
      ("runtimeSha256",report.getObjValD "runtimeSha256"),("controllerSha256",report.getObjValD "controllerSha256"),
      ("prime",report.getObjValD "prime"),("eighty",wave),("shutdown",shutdown),("guard",guard)])
  for tag in ["source-protocol-build1","source-protocol-build2","source-protocol-build3",
      "source-protocol-observer-build1","source-protocol-observer-build2","task-waiter-records1"] do
    let guard ← captureGuard tag
    let log ← IO.FS.readFile (base/(tag++".log"))
    let errors := log.splitOn "\n" |>.filter (fun line => line.contains "error:")
    guards := guards.push (Json.mkObj [("tag",toJson tag),("guard",guard),("errorSummary",toJson errors)])
  IO.FS.writeFile (output/"frozen-sources.json") frozen.pretty
  IO.FS.writeFile (output/"acquisition.json") (Json.mkObj [("runs",toJson runs),("buildGuards",toJson guards),
    ("completeCuts",toJson (480 : Nat)),("receivedSourceTokens",toJson (7680 : Nat)),
    ("queriesPerRun",toJson (80 : Nat)),("sourcesPerCut",toJson (16 : Nat)),
    ("wholeWorkGraphSearches",toJson (0 : Nat)),("answeringModelCalls",toJson (0 : Nat)),("adopted",toJson false)]).pretty
def verifyRetired : IO Unit := do
  check (!(← (output/"completion.json").pathExists)) "completion already recorded"
  let workspace := output.parent.getD output |>.parent.getD output |>.parent.getD output
  leanRun (workspace/"docs/candidates/shared-leases/records.lean") #["--source-protocol","verify","402"]
  let cleanup ← read (output/"cleanup.json")
  check (cleanup.getObjValD "protectedOriginalsUnchanged" == toJson true && cleanup.getObjValD "archive" == toJson false)
    "cleanup changed protected data"
  for item in array cleanup "removed" do
    let path ← IO.ofExcept (item.getObjValAs? String "path")
    check (!(← (System.FilePath.mk path).pathExists)) "ended trial path remains"
  let changed ← IO.Process.output {cmd := "/usr/bin/git",args := #["diff","--name-only","HEAD","--","Eggshell","Main.lean"],cwd := some workspace}
  check (changed.exitCode == 0 && changed.stdout.trimAscii.isEmpty) "product core changed"
  for (root,path) in [(base/"interest-traffic-core",workspace/"docs/candidates/shared-leases/combined.patch"),
      (base/"task-observer-parent-core",output/"candidate.patch")] do
    let result ← IO.Process.output {cmd := "/usr/bin/git",args := #["apply","--check","--unidiff-zero",path.toString],cwd := some root}
    check (result.exitCode == 0) "isolated overlay does not replay against restored parent"
  let protectedResult ← IO.Process.output {cmd := "/usr/bin/shasum",args := #["-a","256","-c",
    (workspace/"docs/candidates/project-cache/protected-after.sha256").toString],cwd := some base}
  check (protectedResult.exitCode == 0) "protected artifacts changed after cleanup"
  let heads ← IO.ofExcept (fromJson? (← read (workspace/"docs/candidates/worker-cpu/heads.json")) : Except String (Array (String × String × String)))
  for (path,bytes,_) in heads do check ((← IO.FS.readFile (.mk path)) == bytes) "source head changed after cleanup"
  let mut guards := #[]
  for entry in ← base.readDir do
    let name := entry.fileName
    if !name.endsWith ".guard.json" ||
        !["source-protocol-","task-observer-","task-waiter-"].any (fun (startText : String) => name.startsWith startText) then continue
    if name.startsWith "task-waiter-complete" && (← read entry.path).getObjValD "state" == toJson "running" then continue
    let tag := name.dropEnd 11 |>.toString
    let guard ← captureGuard tag
    let logPath := base/(tag++".log")
    let errors ← if ← logPath.pathExists then do
        let log ← IO.FS.readFile logPath
        pure (log.splitOn "\n" |>.filter (fun line => line.contains "error:" || line.contains "uncaught exception:") |>.take 20)
      else pure []
    guards := guards.push (Json.mkObj [("tag",toJson tag),("guard",guard),("errors",toJson errors)])
    if ← logPath.pathExists then IO.FS.removeFile logPath
  IO.FS.writeFile (output/"completion.json") (Json.mkObj [("guards",toJson guards),
    ("postCleanupActualOutputsVerified",toJson (402 : Nat)),("originalHeadsUnchanged",toJson true),
    ("productCoreUnchanged",toJson true),("candidateSourceRestored",toJson true),
    ("adopted",toJson false),("answeringModelCalls",toJson (0 : Nat)),("paidComparisons",toJson "0/18")]).pretty
def main (arguments : List String) : IO Unit := do
  if arguments == ["verify"] then return ← verifyRetired
  check arguments.isEmpty "unknown protocol record stage"
  if ← (output/"acquisition.json").pathExists then
    check ((← read (output/"acquisition.json")).getObjValD "completeCuts" == toJson (480 : Nat))
      "incomplete acquisition checkpoint"
  else captureAcquisition
  let tags := #["source-protocol-overlap1","source-protocol-overlap-no-trace1",
    "task-observer-build1","task-observer-build2","task-observer-policy1",
    "task-observer-smoke1","task-observer-eighty1","task-waiter-build1",
    "task-waiter-policy1","task-waiter-smoke1","task-waiter-eighty1"]
  let workspace := output.parent.getD output |>.parent.getD output |>.parent.getD output
  if !(← (output/"evidence.json").pathExists) then
    leanRun (workspace/"docs/candidates/shared-leases/records.lean") (#["--source-protocol"]++tags)
  leanRun (workspace/"docs/candidates/shared-leases/records.lean") #["--source-protocol","verify","402"]
  leanRun (workspace/"tools/research/CaptureConcurrentPatches.lean") #["source-protocol"]
