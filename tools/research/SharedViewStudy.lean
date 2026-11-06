import Lean.Data.Json.FromToJson
import Lean.Data.Json.Parser
open Lean
namespace Eggshell.Research.SharedViewStudy
def workspace : System.FilePath := "/Users/ovm/.codex/worktrees/hook-deadline-baseline/eggshell"
def base : System.FilePath := "/Users/ovm/.codex/experiments/eggshell/scope-token-study-20261028/fixed-frame-study"
def compiler : System.FilePath := "/Users/ovm/.elan/toolchains/leanprover--lean4---v4.33.0"
def source := base/"shared-view-source"
def target := base/"shared-view-build"
def parent := base/"frontend-finalizer-build"
def study := workspace/"docs/candidates/shared-view"
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
  check (!(process.splitOn "\n").any (fun row => row.contains "controller/StudyMain guard "))
    "another native resource guard is active"
  for entry in ← base.readDir do
    if entry.fileName.startsWith "shared-view-" && entry.fileName.endsWith ".guard.json" then
      let value ← read entry.path
      check (value.getObjValD "state" == toJson "finished" && value.getObjValD "ownedPids" == toJson (#[] : Array Nat))
        "previous shared-view guard is not drained"
def prepare : IO Unit := do
  drained
  check ((← hash (parent/"StudyMain")) == "b5e370dc591a3b89ea9004b161548a52cffe509a9c88b0d54707e0c3f915b6f8") "selected parent changed"
  discard <| command (compiler/"bin/lean").toString #["-j1","-M1536","--run",
    (workspace/"tools/research/DiscoveryStagesStudy.lean").toString,"materialize-native",parent.toString,
    source.toString,target.toString,"tools.research.SharedViewChecks",(base/"shared-view-settings.json").toString]
  IO.FS.createDirAll study
  write (study/"plan.json") (Json.mkObj [("status",toJson "isolated,not adopted"),
    ("previousGoalTurn",toJson "progress:live frontend finalization repaired with native counterfactual"),
    ("purpose",toJson "intern immutable source views;independent authorized leases and request-specific focus"),
    ("bounds",toJson "same128MiB;at most8resident/building images;existing160operation limit;30s hook and4GiB/3.5GiB guard unchanged"),
    ("no80FullSearchRetryBeforeMeasuredImprovement",toJson true),("answeringModelCalls",toJson (0 : Nat)),
    ("paidComparisons",toJson "0/18")])
def setup (action tag : String) : IO Unit := do
  drained
  let settings := base/(tag++".guard-settings.json")
  check (!(← settings.pathExists)) "fresh resource guard required"
  let args ← match action with
    | "build" => pure #[(compiler/"bin/lean").toString,"-j1","-M1536","--run",
        (workspace/"tools/research/StudyBuildMain.lean").toString,(base/"shared-view-settings.json").toString]
    | "preflight" => pure #["/usr/bin/env","LEAN_PATH="++(parent/"lib").toString,
        (compiler/"bin/lean").toString,"--root="++source.toString,"-j1","-M1536",
        (source/"tools/research/SharedReadViews.lean").toString]
    | "checks" => pure #["/usr/bin/env","LEAN_NUM_THREADS=1",
        "EGGSHELL_DATA_ROOT="++(base/(tag++"-result/private")).toString,
        "EGGSHELL_CONFIG="++(base/(tag++"-result/eggshell.toml")).toString,
        (target/"StudyMain").toString,"file-read-check",(base/(tag++"-result")).toString]
    | "cohort" | "cohort-quiet" => do
      check ((← read (study/"native-closure.json")).getObjValD "consistent" == toJson true &&
        (← read (study/"native-checks.json")).getObjValD "typedReadChecks" == toJson true)
        "native closure and read controls required before ordinary traffic"
      let client := base/"frontend-traffic-stop-build/StudyMain"
      check ((← hash client) == "b7bf4901734522beb9bb2d20a8f5cea76afeee6d978a7932e4b4e65e1a2de873")
        "sealed cohort client changed"
      let trace := if action == "cohort-quiet" then "0" else "1"
      if action == "cohort-quiet" then
        check ((← hash (target/"StudyMain")) == "a9827fcedad5a2d390f64f0e191aee00d0bec5a3f395f6baf5596af0b7d3e7fb")
          "diagnostic-off control changed the selected native runtime"
        IO.FS.removeFile (base/"worker-cpu-target/bin/eggshelld")
        discard <| command "/bin/ln" #["-s",(target/"StudyMain").toString,(base/"worker-cpu-target/bin/eggshelld").toString]
        write (study/"quiet-plan.json") (Json.mkObj [("previousGoalTurn",toJson "progress:bounded shared images implemented,proved and exercised in actual32-query cohort"),
          ("purpose",toJson "unchanged runtime/source/query/harness;only optional five diagnostic flags disabled"),
          ("runtimeSha256",toJson (← hash (target/"StudyMain"))),("clientSha256",toJson (← hash client)),
          ("cohort",toJson "same16sources/32queries/two waves"),("noEightySearchRetry",toJson true),
          ("deadlinesAndResourceBoundsUnchanged",toJson true),("adopted",toJson false)])
      pure #["/usr/bin/env","LEAN_NUM_THREADS=1","EGGSHELL_TRACE_SERVICE_PROFILE="++trace,
        "EGGSHELL_TRACE_QUERY_STAGES="++trace,"EGGSHELL_TRACE_NUMERICAL_STAGES="++trace,
        "EGGSHELL_TRACE_ALLOCATOR="++trace,"EGGSHELL_TRACE_ACTOR_HEAP="++trace,
        "EGGSHELL_DATA_ROOT="++(base/(tag++"-result/private")).toString,
        "EGGSHELL_CONFIG="++(base/(tag++"-result/eggshell.toml")).toString,
        "PLUGIN_ROOT="++(base/"worker-cpu-target").toString,
        client.toString,(base/(tag++"-result")).toString,(target/"StudyMain").toString,← hash (target/"StudyMain")]
    | _ => throw (IO.userError "unknown shared-view action")
  write settings (Json.mkObj [("command",toJson args),("cwd",toJson workspace.toString),
    ("record",toJson (base/(tag++".guard.json")).toString),("ownedPrefixes",toJson #[base.toString]),
    ("limitRssKiB",toJson (3670016 : Nat)),("minFreeKiB",toJson (2097152 : Nat))])

def sealCandidate (tag : String) : IO Unit := do
  drained
  let guard ← read (base/(tag++".guard.json"))
  check (guard.getObjValD "exitCode" == toJson (0 : Nat) && guard.getObjValD "guardTriggered" == toJson false)
    "native read controls did not pass"
  for (file,record) in [("report.json","native-checks.json"),("shared-eighty.json","eighty-leases.json"),
      ("held-lock-reads.json","held-lock-reads.json")] do
    write (study/record) (← read (base/(tag++"-result")/file))
  let audit := workspace/"tools/research/StudyBuildClosureAudit.lean"
  discard <| command (compiler/"bin/lean").toString #["-j1","-M1536","--run",audit.toString,
    "inspect",target.toString,(study/"native-closure.json").toString]
  discard <| command (compiler/"bin/lean").toString #["-j1","-M1536","--run",audit.toString,
    "compare-sources",parent.toString,target.toString,(study/"native-sources.json").toString,
    "tools.research.SourceViewBatch","tools.research.SharedReadViews","Eggshell.PublicationService"]
  for (name,path) in [("SourceViewBatch","tools/research/SourceViewBatch.lean"),
      ("SharedReadViews","tools/research/SharedReadViews.lean"),("PublicationService","Eggshell/PublicationService.lean")] do
    let patch ← IO.Process.output {cmd := "/usr/bin/diff",args := #["-U0","--label","a/"++path,
      "--label","b/"++path,(base/"frontend-finalizer-source"/path).toString,(source/path).toString]}
    check (patch.exitCode == 1) "missing declared source-view change"
    IO.FS.writeFile (study/(name++".patch")) patch.stdout
  write (study/"build.json") (Json.mkObj [("runtime",toJson (← hash (target/"StudyMain"))),
    ("parent",toJson (← hash (parent/"StudyMain"))),
    ("kernelAndOrdinaryContractAudit",toJson (← IO.FS.readFile (target/"tools_research_SharedViewChecks-lean.stdout")))])
  IO.FS.removeFile (base/"worker-cpu-target/bin/eggshelld")
  discard <| command "/bin/ln" #["-s",(target/"StudyMain").toString,(base/"worker-cpu-target/bin/eggshelld").toString]

def record (tag : String) : IO Unit := do
  drained
  discard <| command (compiler/"bin/lean").toString #["-j1","-M1536","--run",
    (workspace/"tools/research/DiscoveryStagesStudy.lean").toString,"record-native",tag,study.toString,
    "--shared-view",(workspace/"docs/candidates/frontend-finalizer/evidence.json").toString,"shared-view-"]
  write (study/"shutdown-sample.json") (← read (base/(tag++"-result/shutdown-sample.json")))

def finish (tag : String) : IO Unit := do
  drained
  let verification ← read (study/"verification.json")
  let parity ← read (study/"parity.json")
  check (verification.getObjValD "actualOutputs" == toJson (35 : Nat)) "actual outputs must be retained before cleanup"
  let measurements ← read (study/"measurements.json")
  let guard ← read (base/(tag++".guard.json"))
  let frontend := measurements.getObjValD "frontendShutdown"
  let started ← IO.ofExcept (frontend.getObjValAs? Nat "startedAtMs")
  let finished ← IO.ofExcept (frontend.getObjValAs? Nat "finishedAtMs")
  write (study/"summary.json") (Json.mkObj [("verification",verification),("parity",parity),
    ("heldLockReads",← read (study/"held-lock-reads.json")),("eightyComponentLeases",← read (study/"eighty-leases.json")),
    ("frontendStopMs",toJson (finished-started)),("frontendExit",frontend.getObjValD "exitCode"),
    ("publisherExit",(measurements.getObjValD "shutdown").getObjValD "publisherExit"),
    ("guardPeakRssKiB",guard.getObjValD "sampledPeakRssKiB"),("guardIntervened",guard.getObjValD "guardTriggered"),
    ("hostAfterWaves",measurements.getObjValD "hostAfterWaves"),
    ("fullEightySearchesTested",toJson false),("answeringModelCalls",toJson (0 : Nat)),
    ("paidComparisons",toJson "0/18"),("adopted",toJson false)])
  let baseline := base/"allocator-service-build/StudyMain"
  check ((← hash baseline) == "4e4c9b9c95cb2c72b4447a86f5abc81b6bb619854889eb5ffa8492ba592e593a") "active baseline changed"
  IO.FS.removeFile (base/"worker-cpu-target/bin/eggshelld")
  discard <| command "/bin/ln" #["-s",baseline.toString,(base/"worker-cpu-target/bin/eggshelld").toString]
  let mut removed := #[]
  for ending in [tag,"shared-view-checks1"] do
    let root := base/(ending++"-result")
    check (← root.pathExists) "ended study root already removed"
    IO.FS.removeDirAll root
    removed := removed.push root.toString
  write (study/"development.json") (Json.mkObj [
    ("nativeBuildFailures",toJson #["build1:IO.Promise Unit lacks Inhabited;replace unsafe array index with checked lookup",
      "build2:multiline service result record layout;use explicit field layout"]),
    ("preflightFailures",toJson #["preflight1:qualified charge,decidability and record layout",
      "preflight2:checked empty state constructor and explicit layout"]),
    ("controllerPreflightErrors",toJson #["seal is a reserved Lean identifier;rename to sealCandidate before invocation"]),
    ("canonicalImageIdentityCorrectedBeforeAnySearchTrial",toJson true),
    ("sourcesNeverEditedUnderLiveNativeBuildOrGuard",toJson true),
    ("diskFloorRefusalBeforeFirstPreflightLaunch",toJson true)])
  let mut logs := 0
  for entry in ← target.readDir do
    if entry.fileName.endsWith ".stdout" || entry.fileName.endsWith ".stderr" then
      let text ← IO.FS.readFile entry.path
      check (!(text.contains "error:" || text.contains "error(")) "preserve unexpected compiler failure before cleanup"
      IO.FS.removeFile entry.path
      logs := logs+1
  write (study/"cleanup.json") (Json.mkObj [("endedDbCacheSessionsAndRawLogsRemoved",toJson removed),
    ("compilerLogsRemoved",toJson logs),("baselineAliasRestored",toJson true),
    ("originalsAndRequiredNativeInputsRetained",toJson true),("archived",toJson false)])
  discard <| command (compiler/"bin/lean").toString #["-j1","-M1536","--run",
    (workspace/"tools/research/DiscoveryStagesStudy.lean").toString,"compact-native",study.toString]

def inspectRetained : IO Unit := do
  let evidence ← read (study/"evidence.json")
  let runs ← IO.ofExcept (evidence.getObjValAs? (Array Json) "runs")
  let some run := runs[0]? | throw (IO.userError "missing retained cohort")
  let mut snapshots := #[]
  for wave in ← IO.ofExcept (run.getObjValAs? (Array Json) "waves") do
    let stats := wave.getObjValD "serviceStats"
    snapshots := snapshots.push (Json.mkObj [("name",wave.getObjValD "name"),
      ("paletteQueries",stats.getObjValD "paletteQueries"),
      ("metadataCache",(stats.getObjValD "preparedSources").getObjValD "views"),
      ("preparation",stats.getObjValD "preparation")])
  write (study/"shared-cache.json") (toJson snapshots)
  let summary ← read (study/"summary.json")
  let mut hosts := #[]
  for host in ← IO.ofExcept (summary.getObjValAs? (Array (String × Json)) "hostAfterWaves") do
    hosts := hosts.push (host.1,host.2.getObjValD "rssKiB")
  IO.println (Json.mkObj [("peakRssKiB",summary.getObjValD "guardPeakRssKiB"),
    ("frontendStopMs",summary.getObjValD "frontendStopMs"),("frontendExit",summary.getObjValD "frontendExit"),
    ("publisherExit",summary.getObjValD "publisherExit"),("hostRssKiB",toJson hosts),
    ("snapshots",toJson snapshots)]).compress

def recordQuiet (tag : String) (census : Bool := false) (scope : String := "heap-ownership") : IO Unit := do
  drained
  let destination := if census then workspace/"docs/candidates"/scope else study
  let recordName := if census then "evidence.json" else "quiet-result.json"
  check (tag == (if census then scope++"-cohort1" else "shared-view-quiet1") &&
    !(← (destination/recordName).pathExists)) "preserve the fixed diagnostic control"
  let root := base/(tag++"-result")
  let report ← read (root/"report.json")
  let guard ← read (base/(tag++".guard.json"))
  let parentEvidence ← read (study/"evidence.json")
  let runs ← IO.ofExcept (parentEvidence.getObjValAs? (Array Json) "runs")
  let some previous := runs[0]? | throw (IO.userError "missing diagnostic-on cohort")
  let priorRows ← IO.ofExcept (previous.getObjValAs? (Array Json) "rowsIncludingPrime")
  let bodies ← IO.ofExcept (fromJson? (← read (study/"bodies.json")) : Except String (Array Json))
  let mut actual := #[]
  let mut waves := #[]
  let mut differences := #[]
  let mut complete := 0
  let mut originalAck := 0
  let mut latencies := #[]
  for name in ["prime","first","second"] do
    let wave := report.getObjValD name
    let receipts ← IO.ofExcept (wave.getObjValAs? (Array Json) "receipts")
    if name != "prime" then
      complete := complete+(receipts.filter fun receipt =>
        let semantic := receipt.getObjValD "search-phase-semantic"
        semantic.getObjValD "status" == toJson "completed" && semantic.getObjValD "hasHandoff" == toJson true).size
    for row in ← IO.ofExcept (wave.getObjValAs? (Array Json) "rows") do
      let session ← IO.ofExcept (row.getObjValAs? String "session")
      let raw ← IO.FS.readFile (root/(session++".stdout"))
      check (row.getObjValD "stdoutSha256" == toJson (← hash (root/(session++".stdout")))) "quiet actual stdout changed"
      let output ← IO.ofExcept (Json.parse raw)
      let body := ((output.getObjValD "hookSpecificOutput").getObjValAs? String "additionalContext").toOption.getD ""
      let index ← IO.ofExcept (row.getObjValAs? Nat "case")
      let both := body.contains s!"\"observed-head-case-{index}-7b319c\"" && body.contains s!"\"observed-tail-case-{index}-d82a04\""
      check (row.getObjValD "bothFields" == toJson both && row.getObjValD "bodyBytes" == toJson body.utf8ByteSize)
        "quiet independent original-field check disagrees"
      let some prior := priorRows.find? (fun old => old.getObjValD "session" == row.getObjValD "session") |
        throw (IO.userError "quiet query is outside the fixed control domain")
      let ref ← IO.ofExcept (prior.getObjValAs? Nat "bodyRef")
      let some retained := bodies[ref]? | throw (IO.userError "missing retained parent body")
      let sameBody := retained.getObjValD "body" == toJson body
      if !sameBody then differences := differences.push (session,body)
      actual := actual.push (row.setObjVal! "parentBodyRef" (toJson ref)
        |>.setObjVal! "bodyByteEqual" (toJson sameBody)
        |>.setObjVal! "completeStdoutEqual" (toJson (row.getObjValD "stdoutSha256" == prior.getObjValD "stdoutSha256")))
      if name != "prime" then
        let elapsed ← IO.ofExcept (row.getObjValAs? Nat "elapsedMs")
        latencies := latencies.push elapsed
        if both && row.getObjValD "acknowledged" == toJson true && elapsed < 30000 then originalAck := originalAck+1
    let after ← IO.ofExcept (wave.getObjValAs? (Array Json) "after")
    let host := after.find? (fun process => process.getObjValD "role" == toJson "publication-service")
    waves := waves.push (Json.mkObj [("name",toJson name),("hostRssKiB",host.map (·.getObjValD "rssKiB") |>.getD Json.null),
      ("serviceStats",wave.getObjValD "serviceStats"),("receipts",toJson receipts)])
  let sorted := latencies.qsort (· < ·)
  let frontend ← read (root/"shutdown-frontend.json")
  let shutdown ← read (root/"shutdown.json")
  let start ← IO.ofExcept (frontend.getObjValAs? Nat "startedAtMs")
  let finish ← IO.ofExcept (frontend.getObjValAs? Nat "finishedAtMs")
  let result := Json.mkObj [("tag",toJson tag),("runtimeSha256",report.getObjValD "runtimeSha256"),
    ("parent",toJson "shared-view-cohort1"),("bodies",toJson (if census then "../shared-view/bodies.json" else "bodies.json")),
    ("actualOutputs",toJson actual),
    ("unexpectedBodies",toJson differences),("waves",toJson waves),("requiredOriginalAndAck",toJson originalAck),
    ("semanticCompletedWithHandoff",toJson complete),("queries",toJson sorted.size),
    ("latencyMs",Json.mkObj [("min",toJson sorted[0]?),("median",toJson sorted[sorted.size/2]?),("max",toJson sorted.back?)]),
    ("frontendExit",frontend.getObjValD "exitCode"),("frontendStopMs",toJson (finish-start)),
    ("publisherExit",shutdown.getObjValD "publisherExit"),("originalHeadsUnchanged",report.getObjValD "originalHeadsUnchanged"),
    ("guardPeakRssKiB",guard.getObjValD "sampledPeakRssKiB"),("guardIntervened",guard.getObjValD "guardTriggered"),
    ("guardOwnedPids",guard.getObjValD "ownedPids"),("answeringModelCalls",toJson (0 : Nat)),
    ("paidComparisons",toJson "0/18"),("adopted",toJson false)]
  write (destination/recordName) result
  check (actual.size == 35 && sorted.size == 32) "diagnostic-off control did not retain the fixed cohort"
  let baseline := base/"allocator-service-build/StudyMain"
  check ((← hash baseline) == "4e4c9b9c95cb2c72b4447a86f5abc81b6bb619854889eb5ffa8492ba592e593a") "active baseline changed"
  IO.FS.removeFile (base/"worker-cpu-target/bin/eggshelld")
  discard <| command "/bin/ln" #["-s",baseline.toString,(base/"worker-cpu-target/bin/eggshelld").toString]
  IO.FS.removeDirAll root
  write (destination/(if census then "cleanup.json" else "quiet-cleanup.json")) (Json.mkObj [("removed",toJson root.toString),
    ("actualBodiesRetainedOrReferencedBeforeDeletion",toJson true),("baselineAliasRestored",toJson true),("archived",toJson false)])
  IO.println (Json.mkObj [("latencyMs",result.getObjValD "latencyMs"),("requiredOriginalAndAck",toJson originalAck),
    ("semanticCompletedWithHandoff",toJson complete),("peakRssKiB",guard.getObjValD "sampledPeakRssKiB"),
    ("hostRssKiB",toJson (waves.map fun wave => (wave.getObjValD "name",wave.getObjValD "hostRssKiB"))),
    ("abandonedHeap",toJson (waves.map fun wave => (wave.getObjValD "name",(wave.getObjValD "serviceStats").getObjValD "abandonedHeap"))),
    ("ownerHeaps",toJson (waves.map fun wave => (wave.getObjValD "name",(wave.getObjValD "serviceStats").getObjValD "ownerHeaps"))),
    ("bodyDifferences",toJson differences.size),("frontendExit",result.getObjValD "frontendExit"),
    ("publisherExit",result.getObjValD "publisherExit")]).compress

def verifyMemoryControls : IO Unit := do
  drained
  let bodies ← IO.ofExcept (fromJson? (← read (study/"bodies.json")) : Except String (Array Json))
  let mut runs := #[]
  for path in [study/"quiet-result.json",workspace/"docs/candidates/heap-ownership/evidence.json"] do
    let run ← read path
    let outputs ← IO.ofExcept (run.getObjValAs? (Array Json) "actualOutputs")
    check (outputs.size == 35 && outputs.all (fun row => row.getObjValD "bodyByteEqual" == toJson true &&
      row.getObjValD "completeStdoutEqual" == toJson true) && run.getObjValD "unexpectedBodies" == toJson (#[] : Array Json))
      "retained actual stdout domain or bytes differ"
    for row in outputs do
      let index ← IO.ofExcept (row.getObjValAs? Nat "parentBodyRef")
      let some body := bodies[index]? | throw (IO.userError "missing referenced actual body")
      check (row.getObjValD "bodyBytes" == body.getObjValD "utf8Bytes") "retained actual body reference changed"
    check (run.getObjValD "requiredOriginalAndAck" == toJson (32 : Nat) &&
      run.getObjValD "semanticCompletedWithHandoff" == toJson (32 : Nat) &&
      run.getObjValD "guardIntervened" == toJson false && run.getObjValD "guardOwnedPids" == toJson (#[] : Array Nat))
      "memory control did not complete its actual required output and lifetime checks"
    runs := runs.push (run.getObjValD "tag",outputs.size)
  for body in bodies do
    let raw ← IO.ofExcept (body.getObjValAs? String "body")
    let digest ← IO.Process.output {cmd := "/usr/bin/shasum",args := #["-a","256"]} (some raw)
    check (digest.exitCode == 0 && body.getObjValD "sha256" == toJson ((digest.stdout.splitOn " ").headD "") &&
      body.getObjValD "utf8Bytes" == toJson raw.utf8ByteSize) "actual shared body bytes changed"
  write (workspace/"docs/candidates/heap-ownership/verification.json") (Json.mkObj [("actualOutputs",toJson (70 : Nat)),
    ("allCompleteStdoutEqualToSealedParent",toJson true),("referencedBodyDigestsVerified",toJson bodies.size),
    ("runs",toJson runs),("adopted",toJson false)])
def retireDerived : IO Unit := do
  drained
  let verify := fun (_ : Unit) => do
    let result ← IO.Process.output {cmd := "/usr/bin/shasum",args := #["-a","256","-c",
      (workspace/"docs/candidates/project-cache/protected-after.sha256").toString],cwd := some base}
    check (result.exitCode == 0) "protected original bytes changed"
    let heads ← IO.ofExcept (fromJson? (← read (workspace/"docs/candidates/worker-cpu/heads.json")) :
      Except String (Array (String × (String × String))))
    for (path,(bytes,digest)) in heads do
      check ((← IO.FS.readFile (.mk path)) == bytes && (← hash (.mk path)) == digest) "protected project source changed"
    return heads.size
  let count ← verify ()
  let mut removed := #[]
  for path in [base/"native-study/study/seed-1/work.egg/derived",
      base/"frontend-quiescence-fixture-small1/private/read-cache",
      base/"frontend-quiescence-fixture-small1/private/query-cache",
      base/"frontend-quiescence-fixture-small1/private/semantic"] do
    if ← path.pathExists then
      check ((← path.symlinkMetadata).type == .dir) "derived cleanup target is not an ordinary directory"
      let size ← command "/usr/bin/du" #["-sk",path.toString]
      removed := removed.push (path.toString,size.trimAscii.toString)
      IO.FS.removeDirAll path
  check ((← verify ()) == count) "original inventory changed during derived cleanup"
  write (study/"retired-derived.json") (Json.mkObj [("removed",toJson removed),
    ("protectedCompleteProjectHeads",toJson count),("otherProtectedOriginalChecks",toJson (5 : Nat)),
    ("beforeAndAfterUnchanged",toJson true),("archived",toJson false),
    ("preflightRefusedBeforeLaunchForDiskFloor",toJson true)])
def main (args : List String) : IO Unit := do
  match args with
  | ["prepare"] => prepare
  | ["setup",action,tag] => setup action tag
  | ["seal",tag] => sealCandidate tag
  | ["record",tag] => record tag
  | ["finish",tag] => finish tag
  | ["inspect"] => inspectRetained
  | ["record-quiet",tag] => recordQuiet tag
  | ["record-heap",tag] => recordQuiet tag true
  | ["record-scope",tag,scope] => recordQuiet tag true scope
  | ["record-io",tag] => recordQuiet tag true "io-heap"
  | ["verify-memory-controls"] => verifyMemoryControls
  | ["retire-derived"] => retireDerived
  | _ => throw (IO.userError "prepare | setup ACTION TAG")
end Eggshell.Research.SharedViewStudy
def main := Eggshell.Research.SharedViewStudy.main
