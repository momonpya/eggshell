import Lean.Data.Json.FromToJson
import Lean.Data.Json.Parser
open Lean
namespace Eggshell.Research.RetentionStudy
def workspace : System.FilePath := "/Users/ovm/.codex/worktrees/hook-deadline-baseline/eggshell"
def base : System.FilePath := "/Users/ovm/.codex/experiments/eggshell/scope-token-study-20261028/fixed-frame-study"
def compiler : System.FilePath := "/Users/ovm/.elan/toolchains/leanprover--lean4---v4.33.0"
def source := base/"retention-source"
def target := base/"retention-build"
def clientSource := base/"retention-client-source"
def clientTarget := base/"retention-client-build"
def parent := base/"shared-view-build"
def clientParent := base/"frontend-traffic-stop-build"
def study := workspace/"docs/candidates/retention"
def fixedSource := base/"selector-cleanup-source"
def fixedTarget := base/"selector-cleanup-build"
def fixedStudy := workspace/"docs/candidates/selector-cleanup"
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
    if (entry.fileName.startsWith "retention-" || entry.fileName.startsWith "selector-cleanup-") &&
        entry.fileName.endsWith ".guard.json" then
      let guard ← read entry.path
      check (guard.getObjValD "state" == toJson "finished" && guard.getObjValD "ownedPids" == toJson (#[] : Array Nat))
        "retention guard not drained"
def patches : IO Unit := do
  for (name,left,right) in [("PublicationService",base/"shared-view-source/Eggshell/PublicationService.lean",source/"Eggshell/PublicationService.lean"),
      ("Client",base/"frontend-traffic-stop-source/tools/research/WorkerCpuProfile.lean",clientSource/"tools/research/WorkerCpuProfile.lean")] do
    let result ← IO.Process.output {cmd := "/usr/bin/diff",args := #["-U0","--label","parent/"++name,
      "--label","candidate/"++name,left.toString,right.toString]}
    check (result.exitCode == 1) "missing retention observation change"
    IO.FS.writeFile (study/(name++".patch")) result.stdout
def prepare : IO Unit := do
  drained
  IO.FS.createDirAll study
  for name in ["HeapObservation","RetentionProbe","RetentionChecks"] do
    let relative := "tools/research/"++name++".lean"
    IO.FS.writeFile (source/relative) (← IO.FS.readFile (workspace/relative))
  IO.FS.createDirAll target
  for (name,relative) in [("observer","heap_observation.c"),("intervention","retention_probe.c")] do
    IO.FS.writeFile (target/(name++".c")) (← IO.FS.readFile (workspace/"tools/research/native"/relative))
  let response := (← IO.FS.readFile (parent/"runtime.rsp"))++
    (toJson (target/"observer.o").toString).compress++"\n"++(toJson (target/"intervention.o").toString).compress++"\n"
  IO.FS.writeFile (base/"retention-parent.rsp") response
  let settings ← read (base/"retention-settings.json")
  write (base/"retention-settings.json") (settings.setObjVal! "baselineResponse" (toJson (base/"retention-parent.rsp").toString))
  patches
  if !(← (study/"plan.json").pathExists) then
    write (study/"plan.json") (Json.mkObj [("previousGoalTurn",toJson "progress:fd745e58 validated heap/large-buffer observations and excluded I/O-owner/default-option hypotheses"),
      ("purpose",toJson "quiescent same-process sham then forced collection;post-intervention exact original delivery check"),
      ("parentRuntimeSha256",toJson (← hash (parent/"StudyMain"))),
      ("noProductionCollectionPolicy",toJson true),("no80SearchRetry",toJson true),
      ("noRankingSourceDomainDeadlineOrResourceChange",toJson true),
      ("answeringModelCalls",toJson (0 : Nat)),("adopted",toJson false)])
def build : IO Unit := do
  let sdk := (← command "/usr/bin/xcrun" #["--show-sdk-path"]).trimAscii.toString
  for name in ["observer","intervention"] do
    discard <| command (compiler/"bin/leanc").toString #["-c","-O2","-Wall","-Wextra","-Werror",
      "-isysroot",sdk,"-isystem",sdk++"/usr/include","-o",(target/(name++".o")).toString,(target/(name++".c")).toString]
  for settings in ["retention-settings.json","retention-client-settings.json"] do
    discard <| command (compiler/"bin/lean").toString #["-j1","-M1536","--run",
      (workspace/"tools/research/StudyBuildMain.lean").toString,(base/settings).toString]
  write (study/"native-adapters.json") (Json.mkObj [("runtimeSha256",toJson (← hash (target/"StudyMain"))),
    ("clientSha256",toJson (← hash (clientTarget/"StudyMain"))),
    ("observerSourceSha256",toJson (← hash (target/"observer.c"))),
    ("observerObjectSha256",toJson (← hash (target/"observer.o"))),
    ("interventionSourceSha256",toJson (← hash (target/"intervention.c"))),
    ("interventionObjectSha256",toJson (← hash (target/"intervention.o")))])
def prepareFixed : IO Unit := do
  drained
  IO.FS.createDirAll fixedStudy
  IO.FS.writeFile (fixedSource/"tools/research/OwnedSelect.lean")
    (← IO.FS.readFile (workspace/"tools/research/OwnedSelect.lean"))
  for relative in ["Eggshell/TaskDeadline.lean","Eggshell/DaemonWire.lean","Eggshell/Numerical.lean",
      "Eggshell/OperationPool.lean","Eggshell/PublicationService.lean","tools/research/RetentionProbe.lean"] do
    let patch ← IO.Process.output {cmd := "/usr/bin/diff",args := #["-U0","--label","a/"++relative,
      "--label","b/"++relative,(source/relative).toString,(fixedSource/relative).toString]}
    check (patch.exitCode == 1) "missing selector cleanup connection"
    IO.FS.writeFile (fixedStudy/(relative.replace "/" "_"++".patch")) patch.stdout
  write (fixedStudy/"plan.json") (Json.mkObj [("purpose",toJson "repair deferred-error source cleanup without altering winner arbitration or original results"),
    ("parentRuntimeSha256",toJson (← hash (target/"StudyMain"))),
    ("unchangedClientSha256",toJson (← hash (clientTarget/"StudyMain"))),
    ("nativeReproducer",← read (study/"selector-controls.json")),
    ("selectorSourceSha256",toJson (← hash (fixedSource/"tools/research/OwnedSelect.lean"))),
    ("noAdditionalMutexCasOrDedicatedWorker",toJson true),("no80SearchRetry",toJson true),
    ("noRankingDomainClockOrResourceChange",toJson true),("adopted",toJson false)])
def setup (action tag : String) : IO Unit := do
  drained
  let fixed := action.startsWith "fixed-"
  let selected := if fixed then fixedTarget else target
  let destination := if fixed then fixedStudy else study
  let settings := base/(tag++".guard-settings.json")
  check (!(← settings.pathExists)) "fresh resource guard settings required"
  let args ← match action with
    | "build" => pure #[(compiler/"bin/lean").toString,"-j1","-M1536","--run",
        (workspace/"tools/research/RetentionStudy.lean").toString,"build"]
    | "fixed-build" => pure #[(compiler/"bin/lean").toString,"-j1","-M1536","--run",
        (workspace/"tools/research/StudyBuildMain.lean").toString,(base/"selector-cleanup-settings.json").toString]
    | "checks" | "fixed-checks" => pure #["/usr/bin/env","LEAN_NUM_THREADS=1",(selected/"StudyMain").toString,
        "retention-check",(base/(tag++"-result")).toString]
    | "protocol" => pure #[(compiler/"bin/lean").toString,"-j1","-M1536","--run",
        (workspace/"tools/research/RetentionStudy.lean").toString,"protocol",tag]
    | "fixed-protocol" => pure #[(compiler/"bin/lean").toString,"-j1","-M1536","--run",
        (workspace/"tools/research/RetentionStudy.lean").toString,"protocol-fixed",tag]
    | "selector" => pure #[(compiler/"bin/lean").toString,"-j1","-M1536","--run",
        (workspace/"tools/research/RetentionStudy.lean").toString,"selector",tag]
    | "cohort" | "fixed-cohort" => do
      check ((← read (destination/"native-closure.json")).getObjValD "consistent" == toJson true &&
        (← read (destination/"native-sources.json")).getObjValD "exactExpectedChangeSet" == toJson true &&
        (← read (destination/"native-controls.json")).getObjValD "allOriginalDigestsEqual" == toJson true &&
        (← read (destination/"protocol.json")).getObjValD "disabledRuntimeRejectedIntervention" == toJson true &&
        (← read (destination/"protocol.json")).getObjValD "bothServicesExited" == toJson true)
        "native provenance and retained-original controls required"
      IO.FS.removeFile (base/"worker-cpu-target/bin/eggshelld")
      discard <| command "/bin/ln" #["-s",(selected/"StudyMain").toString,(base/"worker-cpu-target/bin/eggshelld").toString]
      pure #["/usr/bin/env","LEAN_NUM_THREADS=1","EGGSHELL_TRACE_SERVICE_PROFILE=0","EGGSHELL_TRACE_QUERY_STAGES=0",
        "EGGSHELL_TRACE_NUMERICAL_STAGES=0","EGGSHELL_TRACE_ALLOCATOR=0","EGGSHELL_TRACE_ACTOR_HEAP=0",
        "EGGSHELL_RESEARCH_RETENTION=1","PLUGIN_ROOT="++(base/"worker-cpu-target").toString,
        "EGGSHELL_DATA_ROOT="++(base/(tag++"-result/private")).toString,
        "EGGSHELL_CONFIG="++(base/(tag++"-result/eggshell.toml")).toString,
        (clientTarget/"StudyMain").toString,(base/(tag++"-result")).toString,(selected/"StudyMain").toString,← hash (selected/"StudyMain")]
    | _ => throw (IO.userError "unknown retention action")
  write settings (Json.mkObj [("command",toJson args),("cwd",toJson workspace.toString),
    ("record",toJson (base/(tag++".guard.json")).toString),("ownedPrefixes",toJson #[base.toString]),
    ("limitRssKiB",toJson (3670016 : Nat)),("minFreeKiB",toJson (2097152 : Nat))])
def sealCandidate (tag : String) : IO Unit := do
  drained
  let guard ← read (base/(tag++".guard.json"))
  check (guard.getObjValD "exitCode" == toJson (0 : Nat) && guard.getObjValD "guardTriggered" == toJson false)
    "retained-original intervention controls failed"
  write (study/"native-controls.json") (← read (base/(tag++"-result/report.json")))
  write (study/"controls.guard.json") guard
  let audit := workspace/"tools/research/StudyBuildClosureAudit.lean"
  for (directory,output) in [(target,"native-closure.json"),(clientTarget,"client-native-closure.json")] do
    discard <| command (compiler/"bin/lean").toString #["-j1","-M1536","--run",audit.toString,
      "inspect",directory.toString,(study/output).toString]
  discard <| command (compiler/"bin/lean").toString #["-j1","-M1536","--run",audit.toString,
    "compare-sources",parent.toString,target.toString,(study/"native-sources.json").toString,
    "Eggshell.PublicationService","+tools.research.HeapObservation","+tools.research.RetentionProbe"]
  discard <| command (compiler/"bin/lean").toString #["-j1","-M1536","--run",audit.toString,
    "compare-sources",clientParent.toString,clientTarget.toString,(study/"client-native-sources.json").toString]
def sealFixed (tag : String) : IO Unit := do
  drained
  let guard ← read (base/(tag++".guard.json"))
  check (guard.getObjValD "exitCode" == toJson (0 : Nat) && guard.getObjValD "guardTriggered" == toJson false)
    "fixed native controls failed"
  write (fixedStudy/"native-controls.json") (← read (base/(tag++"-result/report.json")))
  let audit := workspace/"tools/research/StudyBuildClosureAudit.lean"
  discard <| command (compiler/"bin/lean").toString #["-j1","-M1536","--run",audit.toString,
    "inspect",fixedTarget.toString,(fixedStudy/"native-closure.json").toString]
  discard <| command (compiler/"bin/lean").toString #["-j1","-M1536","--run",audit.toString,
    "compare-sources",target.toString,fixedTarget.toString,(fixedStudy/"native-sources.json").toString,
    "Eggshell.TaskDeadline","Eggshell.DaemonWire","Eggshell.Numerical","Eggshell.OperationPool",
    "Eggshell.PublicationService","tools.research.RetentionProbe","+tools.research.OwnedSelect"]
def protocol (tag : String) (fixed : Bool := false) : IO Unit := do
  let selected := if fixed then fixedTarget else target
  let destination := if fixed then fixedStudy else study
  let root := base/(tag++"-result")
  check (!(← root.pathExists)) "fresh protocol root required"
  IO.FS.createDirAll root
  let mut reports := #[]
  for enabled in [true,false] do
    let privateRoot := root/(if enabled then "enabled" else "disabled")
    let environment := #["LEAN_NUM_THREADS=1","EGGSHELL_RESEARCH_RETENTION="++(if enabled then "1" else "0"),
      "PLUGIN_ROOT="++(base/"worker-cpu-target").toString,
      "EGGSHELL_DATA_ROOT="++(privateRoot/"private").toString,
      "EGGSHELL_CONFIG="++(privateRoot/"eggshell.toml").toString]
    let invoke := fun (args : Array String) =>
      IO.Process.output {cmd := "/usr/bin/env",args := environment++#[(selected/"StudyMain").toString]++args}
    let child ← IO.Process.spawn {
      cmd := "/usr/bin/env"
      args := environment++#[(selected/"StudyMain").toString,"codex-publication-daemon"] }
    let reaped ← IO.mkRef false
    try
      let deadline := (← IO.monoMsNow)+5000
      repeat
        let ping ← invoke #["publication-control","stats"]
        if ping.exitCode == 0 && ping.stdout.trimAscii.toString != "null" then break
        check ((← IO.monoMsNow) < deadline) "protocol service did not start"
        IO.sleep 20
      let sham ← invoke #["retention-probe","sham"]
      let mut result := Json.mkObj [("enabled",toJson enabled),("shamExit",toJson sham.exitCode.toNat)]
      if enabled then
        check (sham.exitCode == 0) ("enabled sham protocol failed: "++sham.stderr)
        let value ← IO.ofExcept (Json.parse sham.stdout)
        check (value.getObjValD "quiescentBeforeAndAfter" == toJson true &&
          (value.getObjValD "observation").getObjValD "collectionRequested" == toJson false)
          "sham protocol changed its intervention"
        let collected ← invoke #["retention-probe","collect"]
        check (collected.exitCode == 0) ("collection protocol failed: "++collected.stderr)
        let actual ← IO.ofExcept (Json.parse collected.stdout)
        check ((actual.getObjValD "observation").getObjValD "collectionRequested" == toJson true)
          "collection protocol did not execute"
        result := result.setObjVal! "sham" value |>.setObjVal! "collect" actual
      else
        check (sham.exitCode != 0 && sham.stderr.contains "diagnostic-only") "ordinary runtime accepted diagnostic collection"
        result := result.setObjVal! "expectedRejection" (toJson sham.stderr)
      let stopped ← invoke #["publication-control","shutdown"]
      check (stopped.exitCode == 0) "protocol service shutdown failed"
      let status ← child.wait
      reaped.set true
      check (status == 0) "protocol service did not exit cleanly"
      reports := reports.push (result.setObjVal! "serviceExit" (toJson status.toNat))
    finally
      if !(← reaped.get) then
        try child.kill catch _ => pure ()
        discard <| child.wait
  write (destination/"protocol.json") (Json.mkObj [("reports",toJson reports),("bothServicesExited",toJson true),
    ("disabledRuntimeRejectedIntervention",toJson true),("adopted",toJson false)])
def selectorControls (tag : String) : IO Unit := do
  let root := base/(tag++"-result")
  check (!(← root.pathExists)) "fresh selector control required"
  IO.FS.createDirAll (root/"lib/tools/research")
  for name in ["OwnedSelect","SelectorErrorChecks"] do
    let path := workspace/("tools/research/"++name++".lean")
    discard <| command "/usr/bin/env" #["LEAN_PATH="++(root/"lib").toString,
      (compiler/"bin/lean").toString,"-j1","-M1536","-o",(root/("lib/tools/research/"++name++".olean")).toString,
      "-c",(root/(name++".c")).toString,path.toString]
    discard <| command (compiler/"bin/leanc").toString #["-c","-O2","-o",(root/(name++".o")).toString,
      (root/(name++".c")).toString]
  discard <| command (compiler/"bin/leanc").toString #["-Wl,-dead_strip","-o",(root/"StudyMain").toString,
    (root/"SelectorErrorChecks.o").toString,(root/"OwnedSelect.o").toString]
  write (study/"selector-native.json") (Json.mkObj [("runtimeSha256",toJson (← hash (root/"StudyMain"))),
    ("sourceSha256",toJson (← hash (workspace/"tools/research/OwnedSelect.lean"))),
    ("checksSha256",toJson (← hash (workspace/"tools/research/SelectorErrorChecks.lean"))),
    ("stdlibSourceSha256",toJson (← hash (compiler/"src/lean/Std/Async/Select.lean"))),
    ("stdlibNativeSha256",toJson (← hash (compiler/"lib/lean/libStd.a"))),
    ("noProductRuntimeChange",toJson true)])
  let output ← command (root/"StudyMain").toString #[(study/"selector-controls.json").toString]
  IO.println output
def recordCohort (tag : String) (fixed : Bool := false) : IO Unit := do
  drained
  let destination := if fixed then fixedStudy else study
  let scope := if fixed then "selector-cleanup" else "retention"
  for mode in ["sham","collect"] do
    write (destination/(mode++".json")) (← read (base/(tag++"-result")/("retention-"++mode++".json")))
  discard <| command (compiler/"bin/lean").toString #["-j1","-M1536","--run",
    (workspace/"tools/research/SharedViewStudy.lean").toString,"record-after",tag,scope]
  let evidence ← read (destination/"evidence.json")
  let rows ← IO.ofExcept (evidence.getObjValAs? (Array Json) "actualOutputs")
  check (rows.size == 36 && rows.all (fun row => row.getObjValD "bodyByteEqual" == toJson true &&
    row.getObjValD "completeStdoutEqual" == toJson true) &&
    evidence.getObjValD "requiredOriginalAndAck" == toJson (33 : Nat) &&
    evidence.getObjValD "semanticCompletedWithHandoff" == toJson (33 : Nat)) "actual original/semantic/parity regression"
  let mut summary := #[]
  for mode in ["sham","collect"] do
    let result ← read (destination/(mode++".json"))
    check (result.getObjValD "quiescentBeforeAndAfter" == toJson true) "intervention overlapped work"
    let observation := result.getObjValD "observation"
    summary := summary.push (Json.mkObj [("mode",toJson mode),
      ("collectionRequested",observation.getObjValD "collectionRequested"),
      ("osMainThread",observation.getObjValD "osMainThread"),
      ("beforeRssKiB",(observation.getObjValD "before").getObjValD "rssKiB"),
      ("immediateRssKiB",(observation.getObjValD "immediate").getObjValD "rssKiB"),
      ("settledRssKiB",(observation.getObjValD "settled").getObjValD "rssKiB"),
      ("selectionErrorsBefore",(observation.getObjValD "before").getObjValD "selectionErrors"),
      ("selectionErrorsAfter",(observation.getObjValD "settled").getObjValD "selectionErrors"),
      ("interventionMs",observation.getObjValD "interventionMs")])
  write (destination/"summary.json") (Json.mkObj [("interventions",toJson summary),
    ("all36StdoutExact",toJson true),("originalAndAck",toJson (33 : Nat)),
    ("noProductionAdoption",toJson true)])
  IO.println (Json.mkObj [("interventions",toJson summary),("all36StdoutExact",toJson true)]).compress
def finish : IO Unit := do
  drained
  let mut summaries := #[]
  for directory in [study,fixedStudy] do
    let evidence ← read (directory/"evidence.json")
    let summary ← read (directory/"summary.json")
    check (summary.getObjValD "all36StdoutExact" == toJson true &&
      evidence.getObjValD "requiredOriginalAndAck" == toJson (33 : Nat) &&
      evidence.getObjValD "semanticCompletedWithHandoff" == toJson (33 : Nat) &&
      evidence.getObjValD "frontendExit" == toJson (0 : Nat) &&
      evidence.getObjValD "publisherExit" == toJson (0 : Nat) &&
      evidence.getObjValD "guardIntervened" == toJson false &&
      evidence.getObjValD "guardOwnedPids" == toJson (#[] : Array Nat))
      "actual delivery or lifecycle regression must be investigated before retirement"
    summaries := summaries.push (Json.mkObj [("directory",toJson directory.toString),
      ("latencyMs",evidence.getObjValD "latencyMs"),("peakRssKiB",evidence.getObjValD "guardPeakRssKiB"),
      ("frontendStopMs",evidence.getObjValD "frontendStopMs"),("interventions",summary.getObjValD "interventions")])
  let mut guards := #[]
  for entry in ← base.readDir do
    if (entry.fileName.startsWith "retention-" || entry.fileName.startsWith "selector-cleanup-") &&
        entry.fileName.endsWith ".guard.json" then
      guards := guards.push (entry.fileName,← read entry.path)
  write (study/"guards.json") (toJson guards)
  let protectedCheck ← IO.Process.output {cmd := "/usr/bin/shasum",args := #["-a","256","-c",
    (workspace/"docs/candidates/project-cache/protected-after.sha256").toString],cwd := some base}
  check (protectedCheck.exitCode == 0) "protected original changed"
  let heads ← IO.ofExcept (fromJson? (← read (workspace/"docs/candidates/worker-cpu/heads.json")) :
    Except String (Array (String × (String × String))))
  for (path,(bytes,digest)) in heads do
    check ((← IO.FS.readFile (.mk path)) == bytes && (← hash (.mk path)) == digest) "complete project head changed"
  let audit := workspace/"tools/research/StudyBuildClosureAudit.lean"
  for (directory,name) in [(target,"parent-closure-final.json"),(clientTarget,"client-closure-final.json"),
      (fixedTarget,"candidate-closure-final.json")] do
    discard <| command (compiler/"bin/lean").toString #["-j1","-M1536","--run",audit.toString,
      "inspect",directory.toString,(study/name).toString]
  let mut retired := #[]
  for name in ["retention-checks1-result","retention-protocol1-result","retention-selector1-result",
      "selector-cleanup-checks1-result","selector-cleanup-protocol1-result"] do
    let directory := base/name
    if ← directory.pathExists then
      IO.FS.removeDirAll directory
      retired := retired.push directory.toString
  let mut failures := #[]
  let mut removedLogs := 0
  for directory in [target,clientTarget,fixedTarget] do
    for entry in ← directory.readDir do
      if entry.fileName.endsWith ".stdout" || entry.fileName.endsWith ".stderr" then
        let contents ← IO.FS.readFile entry.path
        if contents.contains "error:" || contents.contains "error(" then
          failures := failures.push (entry.path.toString,contents)
        IO.FS.removeFile entry.path
        removedLogs := removedLogs+1
  write (study/"development.json") (Json.mkObj [("guards",toJson guards.size),
    ("nativeFailures",toJson (guards.filter fun (_,guard) => guard.getObjValD "exitCode" != toJson (0 : Nat))),
    ("compilerFailureText",toJson failures),("preflightCorrections",toJson #[
      "renamed reserved at in intervention snapshot before successful native build",
      "explicit multiline process spawn record in protocol setup",
      "Except error predicate and exposed-import/private lemma boundaries in selector proof"]),
    ("sourcesNeverEditedUnderTheirNativeBuildOrGuard",toJson true),("answeringModelCalls",toJson (0 : Nat)),
    ("paidComparisons",toJson "0/18"),("adopted",toJson false)])
  write (study/"retirement.json") (Json.mkObj [("removedDirectories",toJson retired),
    ("compilerLogsRemovedAfterEvidence",toJson removedLogs),("archived",toJson false),
    ("protectedCompleteHeads",toJson heads.size),("otherProtectedOriginalFiles",toJson (5 : Nat)),
    ("allProtectedBytesUnchanged",toJson true),("requiredNativeSourcesObjectsInterfacesRetained",toJson true)])
  write (study/"comparison.json") (Json.mkObj [("runs",toJson summaries),
    ("libraryDeferredErrorCleanupReproduced",toJson true),("newMutexCasDedicatedWorker",toJson false),
    ("realServiceRetentionCauseNotEstablished",toJson true),("no80FullSearchRetry",toJson true),
    ("noProductionCollectionPolicy",toJson true),("noTokenQualityAdoptionEvidence",toJson true)])
  IO.println (Json.mkObj [("runs",toJson summaries),("retiredDirectories",toJson retired.size),
    ("protectedHeads",toJson heads.size),("adopted",toJson false)]).compress
def main (args : List String) : IO Unit := do
  match args with
  | ["prepare"] => prepare
  | ["prepare-fixed"] => prepareFixed
  | ["build"] => build
  | ["setup",action,tag] => setup action tag
  | ["seal",tag] => sealCandidate tag
  | ["seal-fixed",tag] => sealFixed tag
  | ["record",tag] => recordCohort tag
  | ["record-fixed",tag] => recordCohort tag true
  | ["protocol",tag] => protocol tag
  | ["protocol-fixed",tag] => protocol tag true
  | ["selector",tag] => selectorControls tag
  | ["finish"] => finish
  | _ => throw (IO.userError "prepare | setup ACTION TAG | seal TAG | record TAG")
end Eggshell.Research.RetentionStudy
def main := Eggshell.Research.RetentionStudy.main
