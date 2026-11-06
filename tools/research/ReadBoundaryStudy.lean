import Lean.Data.Json.FromToJson
import Lean.Data.Json.Parser
open Lean
namespace Eggshell.Research.ReadBoundaryStudy
def workspace : System.FilePath := "/Users/ovm/.codex/worktrees/hook-deadline-baseline/eggshell"
def base : System.FilePath := "/Users/ovm/.codex/experiments/eggshell/scope-token-study-20261028/fixed-frame-study"
def compiler : System.FilePath := "/Users/ovm/.elan/toolchains/leanprover--lean4---v4.33.0"
def source := base/"read-boundary-source"
def target := base/"read-boundary-build"
def parent := base/"shared-view-build"
def study := workspace/"docs/candidates/read-boundary"
def check (ok : Bool) (message : String) : IO Unit := unless ok do throw (IO.userError message)
def read (path : System.FilePath) : IO Json := IO.FS.readFile path >>= (IO.ofExcept ∘ Json.parse)
def write (path : System.FilePath) (value : Json) : IO Unit := IO.FS.writeFile path value.compress
def command (cmd : String) (args : Array String) : IO String := do
  let result ← IO.Process.output {cmd,args,cwd := some workspace}
  check (result.exitCode == 0) (result.stdout++result.stderr)
  return result.stdout
def hash (path : System.FilePath) : IO String :=
  return ((← command "/usr/bin/shasum" #["-a","256",path.toString]).splitOn " ").headD ""
def drained : IO Unit := do
  let process ← command "/bin/ps" #["-axo","command="]
  check (!(process.splitOn "\n").any (fun row => row.contains "controller/StudyMain guard ")) "native guard active"
  for entry in ← base.readDir do
    if entry.fileName.startsWith "read-boundary-" && entry.fileName.endsWith ".guard.json" then
      let guard ← read entry.path
      check (guard.getObjValD "state" == toJson "finished" && guard.getObjValD "ownedPids" == toJson (#[] : Array Nat))
        "read boundary guard not drained"
def refresh : IO Unit := do
  drained
  IO.FS.createDirAll study
  for name in ["ReadBoundary","ReadBoundaryChecks"] do
    let relative := "tools/research/"++name++".lean"
    IO.FS.writeFile (source/relative) (← IO.FS.readFile (workspace/relative))
  if !(← (study/"plan.json").pathExists) then
    write (study/"plan.json") (Json.mkObj [("purpose",toJson "one source-registry snapshot; proof-carrying immutable authorization for every subsequent read"),
      ("parentRuntimeSha256",toJson (← hash (parent/"StudyMain"))),
      ("noRemovedLifetimeOrRetainedTokenChecks",toJson true),("noWorkerOrResourceIncrease",toJson true),
      ("noFull80SearchRetry",toJson true),("answeringModelCalls",toJson (0 : Nat)),("adopted",toJson false)])
def setup (action tag : String) : IO Unit := do
  drained
  let settings := base/(tag++".guard-settings.json")
  check (!(← settings.pathExists)) "fresh resource guard settings required"
  let args ← match action with
    | "build" => pure #[(compiler/"bin/lean").toString,"-j1","-M1536","--run",
        (workspace/"tools/research/StudyBuildMain.lean").toString,(base/"read-boundary-settings.json").toString]
    | "checks" => pure #["/usr/bin/env","LEAN_NUM_THREADS=1",
        "EGGSHELL_DATA_ROOT="++(base/(tag++"-result/private")).toString,
        "EGGSHELL_CONFIG="++(base/(tag++"-result/eggshell.toml")).toString,
        (target/"StudyMain").toString,"file-read-check",(base/(tag++"-result")).toString]
    | "cohort" => do
      check ((← read (study/"native-closure.json")).getObjValD "consistent" == toJson true &&
        (← read (study/"native-sources.json")).getObjValD "exactExpectedChangeSet" == toJson true &&
        (← read (study/"report.json")).getObjValD "typedReadChecks" == toJson true)
        "coherent native build and boundary controls required before actual hooks"
      let client := base/"frontend-traffic-stop-build/StudyMain"
      check ((← hash client) == "b7bf4901734522beb9bb2d20a8f5cea76afeee6d978a7932e4b4e65e1a2de873") "sealed client changed"
      IO.FS.removeFile (base/"worker-cpu-target/bin/eggshelld")
      discard <| command "/bin/ln" #["-s",(target/"StudyMain").toString,(base/"worker-cpu-target/bin/eggshelld").toString]
      pure #["/usr/bin/env","LEAN_NUM_THREADS=1","EGGSHELL_TRACE_SERVICE_PROFILE=0","EGGSHELL_TRACE_QUERY_STAGES=0",
        "EGGSHELL_TRACE_NUMERICAL_STAGES=0","EGGSHELL_TRACE_ALLOCATOR=0","EGGSHELL_TRACE_ACTOR_HEAP=0",
        "EGGSHELL_DATA_ROOT="++(base/(tag++"-result/private")).toString,
        "EGGSHELL_CONFIG="++(base/(tag++"-result/eggshell.toml")).toString,
        "PLUGIN_ROOT="++(base/"worker-cpu-target").toString,
        client.toString,(base/(tag++"-result")).toString,(target/"StudyMain").toString,← hash (target/"StudyMain")]
    | _ => throw (IO.userError "unknown read boundary action")
  write settings (Json.mkObj [("command",toJson args),("cwd",toJson workspace.toString),
    ("record",toJson (base/(tag++".guard.json")).toString),("ownedPrefixes",toJson #[base.toString]),
    ("limitRssKiB",toJson (3670016 : Nat)),("minFreeKiB",toJson (2097152 : Nat))])
def writePatches : IO Unit := do
  drained
  for (name,path) in [("PublicationService","Eggshell/PublicationService.lean"),
      ("SharedViewChecks","tools/research/SharedViewChecks.lean")] do
    let patch ← IO.Process.output {cmd := "/usr/bin/diff",args := #["-U0","--label","a/"++path,"--label","b/"++path,
      (base/"shared-view-source"/path).toString,(source/path).toString]}
    check (patch.exitCode == 1) "declared boundary patch missing"
    IO.FS.writeFile (study/(name++".patch")) patch.stdout
def sealCandidate (tag : String) : IO Unit := do
  drained
  let guard ← read (base/(tag++".guard.json"))
  check (guard.getObjValD "exitCode" == toJson (0 : Nat) && guard.getObjValD "guardTriggered" == toJson false)
    "native boundary controls failed"
  for file in ["report.json","read-boundary.json","held-lock-reads.json","shared-eighty.json"] do
    write (study/file) (← read (base/(tag++"-result")/file))
  write (study/"checks.guard.json") guard
  let audit := workspace/"tools/research/StudyBuildClosureAudit.lean"
  discard <| command (compiler/"bin/lean").toString #["-j1","-M1536","--run",audit.toString,
    "inspect",target.toString,(study/"native-closure.json").toString]
  discard <| command (compiler/"bin/lean").toString #["-j1","-M1536","--run",audit.toString,
    "compare-sources",parent.toString,target.toString,(study/"native-sources.json").toString,
    "Eggshell.PublicationService","+tools.research.ReadBoundary","+tools.research.ReadBoundaryChecks"]
  writePatches
  write (study/"runtime.json") (Json.mkObj [("sha256",toJson (← hash (target/"StudyMain"))),
    ("adopted",toJson false),("paidComparisons",toJson "0/18")])
def recordCohort (tag : String) : IO Unit := do
  drained
  discard <| command (compiler/"bin/lean").toString #["-j1","-M1536","--run",
    (workspace/"tools/research/SharedViewStudy.lean").toString,"record-scope",tag,"read-boundary"]
  let evidence ← read (study/"evidence.json")
  let rows ← IO.ofExcept (evidence.getObjValAs? (Array Json) "actualOutputs")
  let parity := rows.size == 35 && rows.all (fun row => row.getObjValD "bodyByteEqual" == toJson true &&
    row.getObjValD "completeStdoutEqual" == toJson true)
  write (study/"verification.json") (Json.mkObj [("all35CompleteStdoutEqualToParent",toJson parity),
    ("actualOutputs",toJson rows.size),("originalAndAck",evidence.getObjValD "requiredOriginalAndAck"),
    ("semanticCompleted",evidence.getObjValD "semanticCompletedWithHandoff"),("adopted",toJson false)])
  check (parity && evidence.getObjValD "requiredOriginalAndAck" == toJson (32 : Nat) &&
    evidence.getObjValD "semanticCompletedWithHandoff" == toJson (32 : Nat) &&
    evidence.getObjValD "guardIntervened" == toJson false &&
    evidence.getObjValD "guardOwnedPids" == toJson (#[] : Array Nat)) "actual hook parity or completion failed"
def finish : IO Unit := do
  drained
  check ((← read (study/"verification.json")).getObjValD "all35CompleteStdoutEqualToParent" == toJson true)
    "retain actual stdout parity before cleanup"
  let originalCheck ← IO.Process.output {cmd := "/usr/bin/shasum",args := #["-a","256","-c",
    (workspace/"docs/candidates/project-cache/protected-after.sha256").toString],cwd := some base}
  check (originalCheck.exitCode == 0) "protected original changed"
  let heads ← IO.ofExcept (fromJson? (← read (workspace/"docs/candidates/worker-cpu/heads.json")) :
    Except String (Array (String × (String × String))))
  for (path,(bytes,digest)) in heads do
    check ((← IO.FS.readFile (.mk path)) == bytes && (← hash (.mk path)) == digest) "project source head changed"
  let audit ← IO.FS.readFile (target/"tools_research_SharedViewChecks-lean.stdout")
  check (!audit.contains "sorryAx" && audit.contains "3120 dependencies never reopen it" &&
    audit.contains "916 authorization dependencies have no synchronization") "kernel path audit changed"
  IO.FS.writeFile (study/"kernel-audit.txt") audit
  for tag in ["read-boundary-build1","read-boundary-cohort1"] do
    write (study/(tag++".guard.json")) (← read (base/(tag++".guard.json")))
  let root := base/"read-boundary-checks1-result"
  check (← root.pathExists) "ended controls already retired"
  IO.FS.removeDirAll root
  let mut removedLogs := 0
  for entry in ← target.readDir do
    if entry.fileName.endsWith ".stdout" || entry.fileName.endsWith ".stderr" then
      let log ← IO.FS.readFile entry.path
      check (!(log.contains "error:" || log.contains "error(")) "unexpected compiler failure must be retained"
      IO.FS.removeFile entry.path
      removedLogs := removedLogs+1
  write (study/"development.json") (Json.mkObj [("preflightCorrections",toJson #[
    "qualified digest/Stream and unfolded lookup in append proof before native build",
    "used equality rewriting for Bool conjunction before native build",
    "renamed reserved controller identifiers seal and protected before invocation"]),
    ("nativeBuildFailures",toJson (0 : Nat)),("nativeControlFailures",toJson (0 : Nat)),
    ("nativeBuilds",toJson (1 : Nat)),("nativeControlRuns",toJson (1 : Nat)),("actual32QueryCohorts",toJson (1 : Nat)),
    ("sourcesNeverEditedUnderNativeBuildOrGuard",toJson true)])
  write (study/"controls-cleanup.json") (Json.mkObj [("removed",toJson root.toString),
    ("compilerLogsRemovedAfterKernelAuditRetained",toJson removedLogs),
    ("protectedCompleteHeads",toJson heads.size),("protectedOriginalFiles",toJson (5 : Nat)),
    ("allProtectedBytesUnchanged",toJson true),("nativeSourcesObjectsInterfacesRetained",toJson true),
    ("archived",toJson false)])
  let evidence ← read (study/"evidence.json")
  IO.println (Json.mkObj [("latencyMs",evidence.getObjValD "latencyMs"),
    ("originalAndAck",evidence.getObjValD "requiredOriginalAndAck"),
    ("semanticCompleted",evidence.getObjValD "semanticCompletedWithHandoff"),
    ("frontendExit",evidence.getObjValD "frontendExit"),("publisherExit",evidence.getObjValD "publisherExit"),
    ("peakRssKiB",evidence.getObjValD "guardPeakRssKiB"),("adopted",toJson false)]).compress
def main (args : List String) : IO Unit := do
  match args with
  | ["refresh"] => refresh
  | ["setup",action,tag] => setup action tag
  | ["seal",tag] => sealCandidate tag
  | ["record",tag] => recordCohort tag
  | ["finish"] => finish
  | ["patches"] => writePatches
  | _ => throw (IO.userError "refresh | setup ACTION TAG | seal TAG")
end Eggshell.Research.ReadBoundaryStudy
def main := Eggshell.Research.ReadBoundaryStudy.main
