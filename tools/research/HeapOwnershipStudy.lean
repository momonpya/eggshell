import Lean.Data.Json.FromToJson
import Lean.Data.Json.Parser
open Lean
namespace Eggshell.Research.HeapOwnershipStudy
def workspace : System.FilePath := "/Users/ovm/.codex/worktrees/hook-deadline-baseline/eggshell"
def base : System.FilePath := "/Users/ovm/.codex/experiments/eggshell/scope-token-study-20261028/fixed-frame-study"
def compiler : System.FilePath := "/Users/ovm/.elan/toolchains/leanprover--lean4---v4.33.0"
def parent := base/"shared-view-build"
def source := base/"heap-ownership-source"
def target := base/"heap-ownership-build"
def study := workspace/"docs/candidates/heap-ownership"
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
  check (!(process.splitOn "\n").any (fun row => row.contains "controller/StudyMain guard ")) "native guard remains live"
  for entry in ← base.readDir do
    if entry.fileName.startsWith "heap-ownership-" && entry.fileName.endsWith ".guard.json" then
      let guard ← read entry.path
      check (guard.getObjValD "state" == toJson "finished" && guard.getObjValD "ownedPids" == toJson (#[] : Array Nat))
        "heap ownership guard not drained"
def prepare : IO Unit := do
  drained
  check ((← hash (parent/"StudyMain")) == "a9827fcedad5a2d390f64f0e191aee00d0bec5a3f395f6baf5596af0b7d3e7fb") "selected parent changed"
  discard <| command (compiler/"bin/lean").toString #["-j1","-M1536","--run",
    (workspace/"tools/research/DiscoveryStagesStudy.lean").toString,"materialize-native",parent.toString,
    source.toString,target.toString,"tools.research.HeapOwnershipChecks",(base/"heap-ownership-settings.json").toString]
  IO.FS.writeFile (source/"tools/research/AbandonedHeap.lean") (← IO.FS.readFile (workspace/"tools/research/AbandonedHeap.lean"))
  IO.FS.createDirAll target
  IO.FS.writeFile (target/"adapter.c") (← IO.FS.readFile (workspace/"tools/research/native/abandoned_heap.c"))
  let response := (← IO.FS.readFile (parent/"runtime.rsp"))++(toJson (target/"adapter.o").toString).compress++"\n"
  let baseline := base/"heap-ownership-parent.rsp"
  IO.FS.writeFile baseline response
  let settings ← read (base/"heap-ownership-settings.json")
  write (base/"heap-ownership-settings.json") (settings.setObjVal! "baselineResponse" (toJson baseline.toString))
  IO.FS.createDirAll study
  write (study/"plan.json") (Json.mkObj [("purpose",toJson "distinguish abandoned allocator bookkeeping from still allocated blocks after producer OS exit"),
    ("parentRuntimeSha256",toJson (← hash (parent/"StudyMain"))),
    ("priorDiagnosticOffControl",toJson "same bodies32/32,host179920->667824->891312KiB;detailed tracing does not explain growth"),
    ("positiveControlBeforeAnySearchTrial",toJson "hold16MiB after producer OS exit,then release and count allocated blocks"),
    ("noMiCollectOrPolicyTuning",toJson true),("diagnosticCensusConsolidatesRemoteFreeLists",toJson true),
    ("onlyAllocatorApiUsesC",toJson true),("selectionPersistenceAndExperimentControllerUseLean",toJson true),
    ("answeringModelCalls",toJson (0 : Nat)),("adopted",toJson false)])
def build : IO Unit := do
  let sdk := (← command "/usr/bin/xcrun" #["--show-sdk-path"]).trimAscii.toString
  discard <| command (compiler/"bin/leanc").toString #["-c","-O2","-Wall","-Wextra","-Werror",
    "-isysroot",sdk,"-isystem",sdk++"/usr/include","-o",(target/"adapter.o").toString,(target/"adapter.c").toString]
  discard <| command (compiler/"bin/lean").toString #["-j1","-M1536","--run",
    (workspace/"tools/research/StudyBuildMain.lean").toString,(base/"heap-ownership-settings.json").toString]
  write (study/"native-adapter.json") (Json.mkObj [("sdk",toJson sdk),
    ("sourceSha256",toJson (← hash (target/"adapter.c"))),("objectSha256",toJson (← hash (target/"adapter.o"))),
    ("selectedInResponse",toJson ((← IO.FS.readFile (target/"runtime.rsp")).contains (toJson (target/"adapter.o").toString).compress)),
    ("runtimeSha256",toJson (← hash (target/"StudyMain")))])
def setup (action tag : String) : IO Unit := do
  drained
  let settings := base/(tag++".guard-settings.json")
  check (!(← settings.pathExists)) "fresh guard tag required"
  let args ← match action with
    | "build" => pure #[(compiler/"bin/lean").toString,"-j1","-M1536","--run",
      (workspace/"tools/research/HeapOwnershipStudy.lean").toString,"build"]
    | "checks" => pure #["/usr/bin/env","LEAN_NUM_THREADS=1",(target/"StudyMain").toString,
      "abandoned-heap-check",(base/(tag++"-result")).toString]
    | "cohort" => do
      let client := base/"frontend-traffic-stop-build/StudyMain"
      check ((← read (study/"native-closure.json")).getObjValD "consistent" == toJson true &&
        (← hash client) == "b7bf4901734522beb9bb2d20a8f5cea76afeee6d978a7932e4b4e65e1a2de873")
        "coherent observer and unchanged native client required"
      IO.FS.removeFile (base/"worker-cpu-target/bin/eggshelld")
      discard <| command "/bin/ln" #["-s",(target/"StudyMain").toString,(base/"worker-cpu-target/bin/eggshelld").toString]
      pure #["/usr/bin/env","LEAN_NUM_THREADS=1","EGGSHELL_TRACE_SERVICE_PROFILE=0",
        "EGGSHELL_TRACE_QUERY_STAGES=0","EGGSHELL_TRACE_NUMERICAL_STAGES=0","EGGSHELL_TRACE_ALLOCATOR=0",
        "EGGSHELL_TRACE_ACTOR_HEAP=0","EGGSHELL_RESEARCH_ABANDONED_HEAP=1",
        "EGGSHELL_DATA_ROOT="++(base/(tag++"-result/private")).toString,
        "EGGSHELL_CONFIG="++(base/(tag++"-result/eggshell.toml")).toString,
        "PLUGIN_ROOT="++(base/"worker-cpu-target").toString,
        client.toString,(base/(tag++"-result")).toString,(target/"StudyMain").toString,← hash (target/"StudyMain")]
    | _ => throw (IO.userError "unknown heap ownership action")
  write settings (Json.mkObj [("command",toJson args),("cwd",toJson workspace.toString),
    ("record",toJson (base/(tag++".guard.json")).toString),("ownedPrefixes",toJson #[base.toString]),
    ("limitRssKiB",toJson (3670016 : Nat)),("minFreeKiB",toJson (2097152 : Nat))])
def recordChecks : IO Unit := do
  drained
  let guard ← read (base/"heap-ownership-checks1.guard.json")
  check (guard.getObjValD "exitCode" == toJson (0 : Nat) && guard.getObjValD "guardTriggered" == toJson false)
    "allocator observer did not pass its positive and negative controls"
  write (study/"native-controls.json") (Json.mkObj [("guard",guard),
    ("report",← read (base/"heap-ownership-checks1-result/report.json")),
    ("runtimeSha256",toJson (← hash (target/"StudyMain")))])
  let audit := workspace/"tools/research/StudyBuildClosureAudit.lean"
  discard <| command (compiler/"bin/lean").toString #["-j1","-M1536","--run",audit.toString,
    "inspect",target.toString,(study/"component-native-closure.json").toString]
  discard <| command (compiler/"bin/lean").toString #["-j1","-M1536","--run",audit.toString,
    "compare-sources",parent.toString,target.toString,(study/"component-native-sources.json").toString,
    "+tools.research.AbandonedHeap"]
  IO.FS.removeDirAll (base/"heap-ownership-checks1-result")
def sealObserver : IO Unit := do
  drained
  check (← (study/"native-controls.json").pathExists) "hold/release controls required before actual workload"
  let audit := workspace/"tools/research/StudyBuildClosureAudit.lean"
  discard <| command (compiler/"bin/lean").toString #["-j1","-M1536","--run",audit.toString,
    "inspect",target.toString,(study/"native-closure.json").toString]
  discard <| command (compiler/"bin/lean").toString #["-j1","-M1536","--run",audit.toString,
    "compare-sources",parent.toString,target.toString,(study/"native-sources.json").toString,
    "Eggshell.PublicationService","+tools.research.AbandonedHeap"]
  let patch ← IO.Process.output {cmd := "/usr/bin/diff",args := #["-U0","--label","a/Eggshell/PublicationService.lean",
    "--label","b/Eggshell/PublicationService.lean",(base/"shared-view-source/Eggshell/PublicationService.lean").toString,
    (source/"Eggshell/PublicationService.lean").toString]}
  check (patch.exitCode == 1) "observer source change missing"
  IO.FS.writeFile (study/"observer.patch") patch.stdout
def applyObserver : IO Unit := do
  drained
  check (← (study/"native-controls.json").pathExists) "native observer controls required"
  let patch := study/"observer.patch"
  let checked ← IO.Process.output {cmd := "/usr/bin/git",args := #["apply","--check","--unidiff-zero",patch.toString],cwd := some source}
  check (checked.exitCode == 0) "observer is already applied or source differs"
  let applied ← IO.Process.output {cmd := "/usr/bin/git",args := #["apply","--unidiff-zero",patch.toString],cwd := some source}
  check (applied.exitCode == 0) applied.stderr
def finish : IO Unit := do
  drained
  let evidence ← read (study/"evidence.json")
  let outputs ← IO.ofExcept (evidence.getObjValAs? (Array Json) "actualOutputs")
  check (outputs.size == 35 && outputs.all (fun row => row.getObjValD "bodyByteEqual" == toJson true &&
    row.getObjValD "completeStdoutEqual" == toJson true)) "retain all exact actual stdout evidence before cleanup"
  let mut observations := #[]
  for wave in ← IO.ofExcept (evidence.getObjValAs? (Array Json) "waves") do
    let stats := wave.getObjValD "serviceStats"
    let abandoned := stats.getObjValD "abandonedHeap"
    check (abandoned.getObjValD "complete" == toJson (1 : Nat)) "abandoned census was truncated"
    observations := observations.push (Json.mkObj [("name",wave.getObjValD "name"),
      ("hostRssKiB",wave.getObjValD "hostRssKiB"),("abandoned",abandoned),
      ("activeSearchActors",(stats.getObjValD "operations").getObjValD "activeSearchActors"),
      ("preparation",stats.getObjValD "preparation")])
  write (study/"summary.json") (Json.mkObj [("observations",toJson observations),
    ("requiredOriginalAndAck",evidence.getObjValD "requiredOriginalAndAck"),
    ("semanticCompletedWithHandoff",evidence.getObjValD "semanticCompletedWithHandoff"),
    ("latencyMs",evidence.getObjValD "latencyMs"),("guardPeakRssKiB",evidence.getObjValD "guardPeakRssKiB"),
    ("matchingCompleteStdout",toJson outputs.size),("frontendExit",evidence.getObjValD "frontendExit"),
    ("frontendStopMs",evidence.getObjValD "frontendStopMs"),("publisherExit",evidence.getObjValD "publisherExit"),
    ("interpretation",toJson "abandoned pages do not account for most host RSS;this is not a whole-process live-heap census"),
    ("next",toJson "distinguish live I/O-owner allocations from unused allocator arenas;do not tune collection,threads,deadlines or ranking"),
    ("fullEightySearchesRun",toJson false),("answeringModelCalls",toJson (0 : Nat)),("paidComparisons",toJson "0/18"),
    ("adopted",toJson false)])
  let mut guards := #[]
  for entry in ← base.readDir do
    if entry.fileName.startsWith "heap-ownership-" && entry.fileName.endsWith ".guard.json" then
      let guard ← read entry.path
      let rows ← IO.ofExcept (guard.getObjValAs? (Array Json) "peakProcesses")
      let rows ← rows.mapM fun row => do
        let program := (row.getObjValAs? String "program").toOption.getD ""
        if program.utf8ByteSize ≤ 512 then return row
        let digest ← IO.Process.output {cmd := "/usr/bin/shasum",args := #["-a","256"]} (some program)
        check (digest.exitCode == 0) "cannot digest numerical command"
        return row.setObjVal! "program" (toJson ((program.splitOn " -c ").headD ""++" [inline code omitted]"))
          |>.setObjVal! "programSha256" (toJson ((digest.stdout.splitOn " ").headD ""))
      guards := guards.push (entry.fileName,guard.setObjVal! "peakProcesses" (toJson rows))
  write (study/"controls.json") (toJson guards)
  write (study/"development.json") (Json.mkObj [("nativeBuildFailure",toJson "build2:early return in nested stats branch inferred IO Unit;replace with explicit pure Json branches;build3 passed"),
    ("noSourceEditUnderLiveBuildOrGuard",toJson true),("observerPositiveAndNegativeControlsBeforeSearch",toJson true),
    ("diagnosticChangesAllocatorBookkeepingDuringCensus",toJson true),("performanceRepairClaimed",toJson false)])
  let process ← command "/bin/ps" #["-axo","command="]
  let mut removed := #[]
  for path in [target,source,base/"heap-ownership-parent.rsp"] do
    check ((← path.pathExists) && !process.contains path.toString) "diagnostic artifact is absent or still live"
    let size ← command "/usr/bin/du" #["-sk",path.toString]
    if ← path.isDir then IO.FS.removeDirAll path else IO.FS.removeFile path
    removed := removed.push (path.toString,size.trimAscii.toString)
  let old := base/"frontend-finalizer-build/StudyMain"
  check (!process.contains old.toString && (← hash old) == "b5e370dc591a3b89ea9004b161548a52cffe509a9c88b0d54707e0c3f915b6f8")
    "superseded finalizer executable is live or changed"
  let oldHash ← hash old
  IO.FS.removeFile old
  write (study/"retirement.json") (Json.mkObj [("removed",toJson removed),("supersededExecutable",toJson (old.toString,oldHash)),
    ("selectedSharedViewRuntimeAndAllRequiredInputsRetained",toJson true),("archived",toJson false)])
def main (args : List String) : IO Unit := do
  match args with
  | ["prepare"] => prepare
  | ["build"] => build
  | ["setup",action,tag] => setup action tag
  | ["record-checks"] => recordChecks
  | ["seal-observer"] => sealObserver
  | ["apply-observer"] => applyObserver
  | ["finish"] => finish
  | _ => throw (IO.userError "prepare | setup ACTION TAG")
end Eggshell.Research.HeapOwnershipStudy
def main := Eggshell.Research.HeapOwnershipStudy.main
