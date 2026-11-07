import Lean.Data.Json.FromToJson
import Lean.Data.Json.Parser
open Lean
namespace Eggshell.Research.NumericalBurstStudy
def workspace : System.FilePath := "/Users/ovm/.codex/worktrees/hook-deadline-baseline/eggshell"
def base : System.FilePath := "/Users/ovm/.codex/experiments/eggshell/scope-token-study-20261028/fixed-frame-study"
def compiler : System.FilePath := "/Users/ovm/.elan/toolchains/leanprover--lean4---v4.33.0"
def folder := workspace/"docs/candidates/encoder-events/protocol"
def check (ok : Bool) (message : String) : IO Unit := unless ok do throw (IO.userError message)
def read (path : System.FilePath) : IO Json := IO.FS.readFile path >>= (IO.ofExcept ∘ Json.parse)
def write (path : System.FilePath) (value : Json) : IO Unit := IO.FS.writeFile path value.compress
def command (cmd : String) (args : Array String) : IO String := do
  let result ← IO.Process.output {cmd,args,cwd := some workspace}
  check (result.exitCode == 0) (result.stdout++result.stderr)
  return result.stdout
def lean (args : Array String) : IO Unit := do discard <| command (compiler/"bin/lean").toString (#["-j1","-M1536","--run"]++args)
def hash (path : System.FilePath) : IO String :=
  return ((← command "/usr/bin/shasum" #["-a","256",path.toString]).splitOn " ").headD ""
def drained : IO Unit := do
  let processes ← command "/bin/ps" #["-axo","command="]
  check (!processes.contains "controller/StudyMain guard ") "a resource guard is still active"
def name (arm : String) : IO String := do
  check (["parent","candidate"].contains arm) "unknown numerical protocol arm"
  return "encoder-protocol-"++arm
def product (arm : String) : IO String := do
  discard <| name arm
  return if arm == "parent" then "shared-model" else "encoder-events"
def prepare : IO Unit := do
  drained
  IO.FS.createDirAll folder
  let manifest := folder/"plan.json"
  check (!(← manifest.pathExists)) "preserve the frozen protocol plan"
  let delivered ← read (workspace/"docs/candidates/encoder-events/delivery-cells.json")
  check (delivered.getObjValD "actualDeliveryAllSixPassed" == toJson true &&
    delivered.getObjValD "allParentBodiesByteEqual" == toJson true && delivered.getObjValD "candidatePathPassed" == toJson true)
    "actual six-hook gate is required before the numerical burst"
  let mut arms := #[]
  for arm in ["parent","candidate"] do
    let family ← product arm
    let stem ← name arm
    let source := base/(stem++"-source")
    check (!(← source.pathExists)) "fresh numerical protocol source required"
    lean #[(workspace/"tools/research/DiscoveryStagesStudy.lean").toString,"materialize-native",
      (base/(family++"-build")).toString,source.toString,(base/(stem++"-build")).toString,
      "tools.research.NumericalProtocolProbe",(base/(stem++"-settings.json")).toString]
    let sourceDigest ← hash (source/"tools/research/NumericalProtocolProbe.lean")
    arms := arms.push (Json.mkObj [("arm",toJson arm),("family",toJson family),
      ("productSha256",toJson (← hash (base/(family++"-build/StudyMain")))),
      ("probeSourceSha256",toJson sourceDigest)])
  let input := base/"shared-model-capacity-80-input.json"
  write manifest (Json.mkObj [("arms",toJson arms),("counts",toJson #[(16 : Nat),80]),
    ("armOrder",toJson #["parent","candidate"]),("repetitions",toJson (1 : Nat)),
    ("purpose",toJson "diagnose numerical admission and transport separately from WorkGraph"),
    ("fixedInput",toJson input.toString),("fixedInputSha256",toJson (← hash input)),
    ("realQuestions",toJson (3 : Nat)),("rows",toJson (1933 : Nat)),
    ("encodesPerRequest",toJson (2 : Nat)),("fullScorePassesPerRequest",toJson (2 : Nat)),
    ("scoreBatchRows",toJson (256 : Nat)),("requestDeadlineMs",toJson (28800 : Nat)),
    ("hookSemanticBudgetMs",toJson (14500 : Nat)),("fullHookOrAdoptionComparison",toJson false),
    ("answeringModelCalls",toJson (0 : Nat)),("adopted",toJson false)])
def setupBuild (arm tag : String) : IO Unit := do
  drained
  let stem ← name arm
  check (tag.startsWith (stem++"-build")) "build tag escaped its numerical arm"
  let path := base/(tag++".guard-settings.json")
  check (!(← path.pathExists)) "preserve previous numerical protocol build"
  write path (Json.mkObj [("command",toJson #[(compiler/"bin/lean").toString,"-j1","-M1536","--run",
    (workspace/"tools/research/StudyBuildMain.lean").toString,(base/(stem++"-settings.json")).toString]),
    ("cwd",toJson workspace.toString),("record",toJson (base/(tag++".guard.json")).toString),
    ("ownedPrefixes",toJson #[base.toString]),("limitRssKiB",toJson (3670016 : Nat)),("minFreeKiB",toJson (2097152 : Nat))])
def sealArms (suffix : String := "") : IO Unit := do
  drained
  let audit := (workspace/"tools/research/StudyBuildClosureAudit.lean").toString
  let plan ← read (folder/"plan.json")
  check (plan.getObjValD "fixedInputSha256" == toJson (← hash (base/"shared-model-capacity-80-input.json")))
    "fixed protocol questions or source manifest changed"
  let mut entries := #[]
  for arm in ["parent","candidate"] do
    let stem ← name arm
    let family ← product arm
    let build := base/(stem++"-build")
    lean #[audit,"inspect",build.toString,(folder/(arm++"-closure"++suffix++".json")).toString]
    lean #[audit,"common-sources",(base/(family++"-build")).toString,build.toString,
      (folder/(arm++"-product-sources"++suffix++".json")).toString]
    let witness := build/"tools_research_NumericalProtocolProbe.source"
    let pair ← IO.ofExcept (fromJson? (← read witness) : Except String (String × Array (String × String)))
    check (pair.1 == (← IO.FS.readFile (workspace/"tools/research/NumericalProtocolProbe.lean")))
      "protocol entry differs from its current checked source"
    entries := entries.push (Json.mkObj [("arm",toJson arm),("nativeWitnessSha256",toJson (← hash witness)),
      ("runtimeSha256",toJson (← hash (build/"StudyMain")))])
  check (entries[0]!.getObjValD "nativeWitnessSha256" == entries[1]!.getObjValD "nativeWitnessSha256")
    "the numerical arms use different controllers"
  lean #[audit,"compare-sources",(base/"encoder-protocol-parent-build").toString,
    (base/"encoder-protocol-candidate-build").toString,(folder/("paired-sources"++suffix++".json")).toString,
    "tools.research.EncoderPool","Eggshell.ContractAudit"]
  write (folder/("entries"++suffix++".json")) (toJson entries)
def setupRun (arm : String) (count : Nat) (attempt : Nat := 2) : IO Unit := do
  drained
  check ([16,80].contains count) "fixed numerical protocol count required"
  let stem ← name arm
  let plan ← read (folder/"plan.json")
  check (plan.getObjValD "fixedInputSha256" == toJson (← hash (base/"shared-model-capacity-80-input.json")))
    "fixed numerical source or questions changed after sealing"
  let audit ← read (folder/(arm++"-product-sources-current.json"))
  let executableDigest ← hash (base/(stem++"-build/StudyMain"))
  check (audit.getObjValD "commonSourcesUnchanged" == toJson true && audit.getObjValD "allProductCorePresent" == toJson true &&
    audit.getObjValD "auditorSha256" == toJson executableDigest)
    "numerical protocol executable no longer matches its sealed product"
  if count == 80 then
    for preceding in ["parent","candidate"] do
      let gate ← read (base/("encoder-protocol-"++preceding++"-16-result/report.json"))
      check (gate.getObjValD "allQueriesReferenceEqual" == toJson true && gate.getObjValD "clients" == toJson (16 : Nat))
        "both numerical 16-request gates must complete before either 80-request arm"
  let tag := stem++"-"++toString count++toString attempt
  let settings := base/(tag++".guard-settings.json")
  let root := base/(stem++"-"++toString count++"-result")
  check (!(← settings.pathExists) && !(← root.pathExists)) "preserve previous numerical protocol load"
  write settings (Json.mkObj [("command",toJson #["/usr/bin/env","-u","CODEX_THREAD_ID","-u","CODEX_TURN_ID",
    "LEAN_NUM_THREADS=1","HF_HUB_OFFLINE=1","OMP_NUM_THREADS=1","OPENBLAS_NUM_THREADS=1","MKL_NUM_THREADS=1",
    "TOKENIZERS_PARALLELISM=false","EGGSHELL_PROFILE=work","EGGSHELL_PREFIX="++(base/"prefix").toString,
    "EGGSHELL_TRACE_NUMERICAL_STAGES=1","EGGSHELL_DATA_ROOT="++(base/"real-source-search-read-trial-result/data").toString,
    (base/(stem++"-build/StudyMain")).toString,root.toString,toString count]),
    ("cwd",toJson workspace.toString),("record",toJson (base/(tag++".guard.json")).toString),
    ("ownedPrefixes",toJson #[base.toString]),("limitRssKiB",toJson (3670016 : Nat)),("minFreeKiB",toJson (2097152 : Nat))])
def optionalRead (path : System.FilePath) : IO Json := do
  if ← path.pathExists then read path else pure Json.null
def recoverCacheContext : IO Unit := do
  drained
  let destination := folder/"cache-context-preflight.json"
  check (!(← destination.pathExists)) "preserve the original cache-context failure"
  let guard ← read (base/"encoder-protocol-parent-161.guard.json")
  check (guard.getObjValD "state" == toJson "finished" && guard.getObjValD "ownedPids" == toJson (#[] : Array Nat))
    "cache-context preflight still owns a process"
  let root := base/"encoder-protocol-parent-16-result"
  check (!(← (root/"references.json").pathExists) && !(← (root/"results.json").pathExists) &&
    !(← (root/"report.json").pathExists)) "the preflight reached the parallel workload"
  let failure ← IO.FS.readFile (base/"encoder-protocol-parent-161.stderr")
  check (failure.contains "original projections are pending explicit warm") "unexpected numerical cache-context failure"
  write destination (Json.mkObj [("guard",guard),("frozen",← read (root/"frozen.json")),
    ("stderr",toJson failure),("parallelWorkloadStarted",toJson false),
    ("firstControllerSha256",toJson (← hash (base/"encoder-protocol-parent-source/tools/research/NumericalProtocolProbe.lean"))),
    ("firstRuntimeSha256",toJson (← hash (base/"encoder-protocol-parent-build/StudyMain"))),
    ("removedScratchRoot",toJson root.toString),("sourceDBAndPreparedProjectCacheRetained",toJson true),("archived",toJson false)])
  IO.FS.removeDirAll root
  for arm in ["parent","candidate"] do
    let stem ← name arm
    IO.FS.writeFile (base/(stem++"-source/tools/research/NumericalProtocolProbe.lean"))
      (← IO.FS.readFile (workspace/"tools/research/NumericalProtocolProbe.lean"))
def retireEndedClients : IO Unit := do
  drained
  let destination := folder/"retired-ended-clients.json"
  check (!(← destination.pathExists)) "preserve previous ended-client retirement"
  let delivered ← read (workspace/"docs/candidates/encoder-events/delivery-cells.json")
  check (delivered.getObjValD "actualDeliveryAllSixPassed" == toJson true &&
    delivered.getObjValD "allParentBodiesByteEqual" == toJson true) "retain the completed real-hook evidence"
  let current ← read (workspace/"docs/candidates/encoder-events/auditor-sources.json")
  let transport ← read (workspace/"docs/candidates/shared-model/transport-controls.json")
  let processes ← command "/bin/ps" #["-axo","command="]
  let mut files := #[]
  for (relative,digest) in [("encoder-events-auditor-build/StudyMain",current.getObjValD "auditorSha256"),
    ("shared-transport-build/StudyMain",transport.getObjValD "runtimeSha256")] do
    let path := base/relative
    if !(← path.pathExists) then continue
    check (!processes.contains path.toString && digest == toJson (← hash path)) "ended client is active or differs from its frozen native source"
    files := files.push (Json.mkObj [("path",toJson path.toString),("sha256",digest),
      ("bytes",toJson (← path.metadata).byteSize.toNat)])
  check (!(← (base/"encoder-protocol-parent-161.guard.json").pathExists)) "numerical load already started"
  let failure ← IO.FS.readFile (base/"encoder-protocol-parent-161.stderr")
  check (failure.contains "not enough disk space to start") "unexpected numerical load preflight failure"
  write (folder/"load-preflight.json") (Json.mkObj [("message",toJson failure),("childStarted",toJson false),
    ("settings",← read (base/"encoder-protocol-parent-161.guard-settings.json")),("limitsUnchanged",toJson true)])
  let record := Json.mkObj [("removed",toJson files),("completed",toJson false),("archived",toJson false),
    ("currentParentBaselineProductsProjectCacheOriginalsModelsAndNativeDependenciesRetained",toJson true)]
  write destination record
  for file in files do IO.FS.removeFile (.mk (← IO.ofExcept (file.getObjValAs? String "path")))
  write destination (record.setObjVal! "completed" (toJson true))
def collect (count : Nat) : IO Unit := do
  drained
  check ([16,80].contains count) "fixed numerical protocol count required"
  let destination := folder/s!"results-{count}.json"
  check (!(← destination.pathExists)) "preserve previous numerical protocol evidence"
  let mut arms := #[]
  for arm in ["parent","candidate"] do
    let stem ← name arm
    let tag := stem++"-"++toString count++"2"
    let root := base/(stem++"-"++toString count++"-result")
    let guard ← read (base/(tag++".guard.json"))
    check (guard.getObjValD "state" == toJson "finished" && guard.getObjValD "ownedPids" == toJson (#[] : Array Nat))
      "numerical protocol owner has not drained"
    arms := arms.push (Json.mkObj [("arm",toJson arm),("guard",guard),
      ("frozen",← optionalRead (root/"frozen.json")),("report",← optionalRead (root/"report.json")),
      ("results",← optionalRead (root/"results.json")),("references",← optionalRead (root/"references.json")),
      ("shutdown",← optionalRead (root/"shutdown.json")),("stderr",toJson (← IO.FS.readFile (base/(tag++".stderr"))))])
  let referenceKeys := fun (arm : Json) => ((arm.getObjValD "references").getArr?.toOption.getD #[]).map fun row =>
    (row.getObjValD "encodingSha256",row.getObjValD "scoreSha256")
  let sameReferences := referenceKeys arms[0]! == referenceKeys arms[1]! && (referenceKeys arms[0]!).size == 3
  let sameInput := arms[0]!.getObjValD "frozen" == arms[1]!.getObjValD "frozen" &&
    arms[0]!.getObjValD "frozen" != Json.null
  write destination (Json.mkObj [("clients",toJson count),("arms",toJson arms),("sameFrozenInput",toJson sameInput),
    ("sameReferenceVectorsAndScores",toJson sameReferences),("componentOnly",toJson true),
    ("pairedLatencyCausalClaim",toJson false),("answeringModelCalls",toJson (0 : Nat)),("adopted",toJson false)])
def eventAt? (value : Json) (name : String) : Option Nat := do
  let events ← (value.getObjValAs? (Array (String × Nat)) "events").toOption
  return (← events.find? (·.1 == name)).2
def difference? (start finish : Option Nat) : Option Nat := do
  let start ← start
  let finish ← finish
  if finish < start then none else some (finish-start)
def stats (values : Array Nat) : Json := Id.run do
  if values.isEmpty then return Json.null
  let ordered := values.qsort (· < ·)
  let percentile := fun percentage => ordered[((values.size*percentage+99)/100)-1]!
  return Json.mkObj [("n",toJson values.size),("min",toJson ordered[0]!),
    ("p50",toJson (percentile 50)),("p95",toJson (percentile 95)),("max",toJson ordered[ordered.size-1]!)]
def summarize (count : Nat) (suffix : String := "") : IO Unit := do
  drained
  let destination := folder/s!"summary-{count}{suffix}.json"
  check (!(← destination.pathExists)) "preserve previous numerical timing summary"
  let evidence ← read (folder/s!"results-{count}.json")
  let mut arms := #[]
  for arm in (evidence.getObjValD "arms").getArr?.toOption.getD #[] do
    let report := arm.getObjValD "report"
    let queries := (report.getObjValD "results").getArr?.toOption.getD #[]
    let profiles := queries.flatMap fun query => (query.getObjValD "profiles").getArr?.toOption.getD #[]
    let mut kinds := #[]
    for kind in ["encode","blocks"] do
      let selected := profiles.filter (fun profile => profile.getObjValD "kind" == toJson kind)
      let stem := if kind == "encode" then "encode" else "score"
      let metrics := [("admissionMs",true,stem++"-admission:start",true,stem++"-admission:end"),
        ("kernelRoundTripMs",true,stem++"-kernel:start",true,stem++"-kernel:end"),
        ("prepareMs",true,"score-prepare:start",true,"score-prepare:end"),
        ("pipeWriteMs",true,"raw-pipe-write:start",true,"raw-pipe-write:end"),
        ("pipeReadMs",true,"raw-line-read:start",true,"raw-line-read:end"),
        ("afterPipeReadMs",true,"raw-line-read:end",true,"raw-pipe-task-ready"),
        ("outputReadyToBodyReceivedMs",true,"output-ready",false,"body-ready"),
        ("outerDecodeMs",false,"body-ready",false,"outer-decoded"),
        ("innerDecodeMs",false,"outer-decoded",false,"inner-decoded"),
        ("repackMs",false,"inner-decoded",false,"client-repacked"),
        ("providerDecodeMs",false,"client-repacked",false,"provider-decoded")].map fun (label,leftServer,left,rightServer,right) =>
          (label,stats (selected.filterMap fun profile =>
            difference? (eventAt? (if leftServer then profile.getObjValD "server" else profile) left)
              (eventAt? (if rightServer then profile.getObjValD "server" else profile) right)))
      kinds := kinds.push (Json.mkObj ([("kind",toJson kind),("receivedRpcProfiles",toJson selected.size)]++metrics))
    arms := arms.push (Json.mkObj [("arm",arm.getObjValD "arm"),("wallMs",report.getObjValD "wallMs"),
      ("allQueriesReferenceEqual",report.getObjValD "allQueriesReferenceEqual"),
      ("queryElapsedMs",stats (queries.filterMap fun query => (query.getObjValAs? Nat "elapsedMs").toOption)),
      ("kinds",toJson kinds),("peakRssKiB",(arm.getObjValD "guard").getObjValD "sampledPeakRssKiB")])
  write destination (Json.mkObj [("clients",toJson count),("arms",toJson arms),("observedRepliesOnly",toJson true),
    ("newModelOrHookRuns",toJson (0 : Nat)),("fullHookOrAdoptionClaim",toJson false)])
def retireProbes : IO Unit := do
  drained
  let output := folder/"retired-probe-executables.json"
  check (!(← output.pathExists)) "preserve previous numerical probe retirement"
  let evidence ← read (folder/"results-80.json")
  let entries ← IO.ofExcept ((← read (folder/"entries-current.json")).getArr?)
  let processes ← command "/bin/ps" #["-axo","command="]
  let mut removed := #[]
  for arm in (evidence.getObjValD "arms").getArr?.toOption.getD #[] do
    let label ← IO.ofExcept (arm.getObjValAs? String "arm")
    let stem ← name label
    let executable := base/(stem++"-build/StudyMain")
    let some entry := entries.find? (fun row => row.getObjValD "arm" == toJson label) |
      throw (IO.userError "missing sealed numerical probe")
    check ((arm.getObjValD "guard").getObjValD "state" == toJson "finished" &&
      (arm.getObjValD "guard").getObjValD "ownedPids" == toJson (#[] : Array Nat) &&
      (arm.getObjValD "shutdown").getObjValD "processExited" == toJson true)
      "numerical protocol still owns its workload"
    check (!processes.contains executable.toString && entry.getObjValD "runtimeSha256" == toJson (← hash executable))
      "numerical probe executable is active or changed"
    removed := removed.push (Json.mkObj [("path",toJson executable.toString),("sha256",entry.getObjValD "runtimeSha256"),
      ("bytes",toJson (← executable.metadata).byteSize.toNat)])
  check (removed.size == 2) "both numerical probe arms must be retained as evidence before cleanup"
  let record := Json.mkObj [("removed",toJson removed),("archived",toJson false),("completed",toJson false),
    ("originalsProjectCacheModelsProductBaselinesProfilesAndNativeDependenciesRetained",toJson true)]
  write output record
  for file in removed do IO.FS.removeFile (.mk (← IO.ofExcept (file.getObjValAs? String "path")))
  write output (record.setObjVal! "completed" (toJson true))
def main (args : List String) : IO Unit := do
  match args with
  | ["prepare"] => prepare
  | ["setup-build",arm,tag] => setupBuild arm tag
  | ["seal"] => sealArms
  | ["seal-current"] => sealArms "-current"
  | ["recover-cache-context"] => recoverCacheContext
  | ["retire-ended-clients"] => retireEndedClients
  | ["retire-probes"] => retireProbes
  | ["setup-run",arm,count] =>
      let some count := count.toNat? | throw (IO.userError "invalid numerical count")
      setupRun arm count
  | ["collect",count] =>
      let some parsed := count.toNat? | throw (IO.userError "invalid numerical count")
      collect parsed
  | ["summarize",count] =>
      let some parsed := count.toNat? | throw (IO.userError "invalid numerical count")
      summarize parsed
  | ["summarize-pipes",count] =>
      let some parsed := count.toNat? | throw (IO.userError "invalid numerical count")
      summarize parsed "-pipes"
  | _ => throw (IO.userError "prepare|setup-build|seal|setup-run")
end Eggshell.Research.NumericalBurstStudy
def main := Eggshell.Research.NumericalBurstStudy.main
