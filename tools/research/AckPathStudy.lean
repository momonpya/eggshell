import tools.research.StudyLocal
open Lean StudyLocal
namespace AckPathStudy
def root := base/"ack-path-diagnosis"
def source := root/"source"
def build := root/"build"
def parent := base/"canonical-decoder-runtime"
def records := project/"docs/candidates/cursor-codec/ack-diagnosis"
def driver := project/"tools/research/AckPathStudy.lean"
def cursorRoot := base/"cursor-reader-runtime"
def cursorSource := root/"cursor-source"
def cursorBuild := root/"cursor-build"
def transformed : IO String := do
  let original ← IO.FS.readFile (parent/"source/tools/research/MemoryCapacity.lean")
  check ((original.splitOn "def memoryCapacityEntry").length == 2) "native entry boundary changed"
  let mut text := (original.replace "def memoryCapacityEntry" "def memoryCapacityTraceEntry").replace
    "Eggshell.Research.MemoryCapacity" "Eggshell.Research.MemoryCapacityTrace"
  let replacements := [
    ("  let mut failure : Option String := none\n", "  let mut failure : Option String := none\n"++
      "  let mark := fun (step : String) => Receipt.observe (some receipt)\n"++
      "    (\"capacity-path-\"++step.replace \":\" \"-\") (Json.mkObj [(\"step\",toJson step)])\n"),
    ("    let output := (← IO.ofExcept (reply.getObjValAs? String \"output\"))", "    mark \"hook:end\"\n    let output := (← IO.ofExcept (reply.getObjValAs? String \"output\"))"),
    ("    let decoded ← IO.ofExcept (Json.parse output)\n", "    mark \"published:end\"\n    let decoded ← IO.ofExcept (Json.parse output)\n    mark \"body:parsed\"\n"),
    ("    if complete && ack != Json.null then\n", "    mark \"body:compared\"\n    if complete && ack != Json.null then\n      mark \"endpoint:start\"\n"),
    ("      let endpoint ← Daemon.readyEndpoint id\n", "      let endpoint ← Daemon.readyEndpoint id\n      mark \"endpoint:end\"\n"),
    ("Daemon.exchangeBefore endpoint \"ack\" ack deadline", "Daemon.exchangeBefore endpoint \"ack\" ack deadline (fun step => mark (\"ack:\"++step))"),
    ("    failure := some error.toString\n", "    mark \"client:exception\"\n    failure := some error.toString\n")]
  for (before,after) in replacements do
    check ((text.splitOn before).length == 2) "unique native diagnostic boundary changed"
    text := text.replace before after
  return text
def setup : IO Unit := do
  idle
  check (!(← root.pathExists) && !(← records.pathExists)) "preserve ACK diagnosis"
  let failed ← read (project/"docs/candidates/cursor-codec/runtime/a-first-failed.json")
  check (failed.getObjValD "passed" == toJson false && failed.getObjValD "comparisonStopped" == toJson true) "failed original arm required"
  IO.FS.createDirAll records
  materialize (parent/"build") source build "tools.research.AckPathRuntime" "ack-path-settings.json"
  IO.FS.writeFile (source/"tools/research/MemoryCapacityTrace.lean") (← transformed)
  write (records/"plan.json") (Json.mkObj [("purpose",toJson "locate completed-body/ACK deadline;not a repaired performance comparison"),
    ("counts",toJson (#[(4 : Nat),16])),("productChanges",toJson (0 : Nat)),("answeringModelCalls",toJson (0 : Nat)),
    ("failedArmPreserved",toJson true),("noAdditionalUnobservedRetry",toJson true),
    ("instrumentation",toJson "scalar client steps;existing exchangeBefore marker;no payload/scheduling change")])
  guard "ack-path-build-entry" #[(compiler/"bin/lean").toString,"-j1","-M1536","--run",
    (project/"tools/research/StudyBuildMain.lean").toString,(base/"ack-path-settings.json").toString]
def setupCursor : IO Unit := do
  idle
  let monitor ← read (base/"ack-path-cursor-observed.guard.json")
  check (monitor.getObjValD "state" == toJson "finished" && monitor.getObjValD "exitCode" == toJson (1 : Nat) &&
    monitor.getObjValD "ownedPids" == toJson (#[] : Array Nat)) "cursor startup has not drained"
  let endpointPath := cursorRoot/"data/publisher/endpoint.json"
  let endpoint ← read endpointPath
  let pid ← IO.ofExcept (endpoint.getObjValAs? Nat "pid")
  let processes ← IO.ofExcept (monitor.getObjValAs? (Array Json) "peakProcesses")
  check (processes.any (fun row => row.getObjValD "pid" == toJson pid &&
    row.getObjValD "program" == toJson (cursorRoot/"prefix/libexec/eggshell").toString)) "stale endpoint not owned by failed startup"
  let status ← IO.Process.output {cmd := "/bin/ps",args := #["-p",toString pid,"-o","pid="]}
  check (status.exitCode != 0 && status.stdout.trimAscii.isEmpty) "startup child remains live"
  let operationsPath := cursorRoot/"data/publisher/operations.json"
  check ((← read operationsPath).getObjValD "pid" == toJson pid) "stale operation endpoint has another owner"
  write (records/"cursor-startup-rejected.json") (Json.mkObj [("guard",monitor),
    ("input",← read (root/"cursor-input.json")),("reason",toJson "publisher implementation differs from the frozen protocol"),
    ("beforeWarmAndHook",toJson true),("ownedChildAbsent",toJson true),("notADeliveryFailure",toJson true),
    ("removedOwnedEndpoints",toJson #[endpointPath.toString,operationsPath.toString])])
  IO.FS.removeFile endpointPath
  IO.FS.removeFile operationsPath
  -- Compile against the candidate contract; never learn the expected contract
  -- from a live endpoint or bypass the existing readiness comparison.
  materialize (cursorRoot/"build") cursorSource cursorBuild "tools.research.AckPathRuntime" "ack-path-cursor-settings.json"
  IO.FS.writeFile (cursorSource/"tools/research/MemoryCapacityTrace.lean") (← transformed)
  discard <| command "/bin/cp" #["-c","-R",(cursorRoot/"build").toString,cursorBuild.toString]
  guard "ack-path-cursor-build" #[(compiler/"bin/lean").toString,"-j1","-M1536","--run",
    (project/"tools/research/StudyBuildMain.lean").toString,(base/"ack-path-cursor-settings.json").toString]
def audit (cursor : Bool := false) : IO Unit := do
  idle
  discard <| finished (if cursor then "ack-path-cursor-build" else "ack-path-build-entry")
  let build := if cursor then cursorBuild else build
  let product := if cursor then cursorRoot else parent
  let file := fun name => records/((if cursor then "cursor-" else "")++name)
  let inspector := project/"tools/research/StudyBuildClosureAudit.lean"
  discard <| command (compiler/"bin/lean").toString #["-j1","-M1536","--run",inspector.toString,
    "inspect",build.toString,(file "native.json").toString]
  discard <| command (compiler/"bin/lean").toString #["-j1","-M1536","--run",inspector.toString,
    "compare-sources",(product/"build").toString,build.toString,(file "sources.json").toString,
    "+tools.research.MemoryCapacityTrace"]
  let (actual,literals) : String × Array (String × String) ← IO.ofExcept
    (fromJson? (← read (build/"tools_research_MemoryCapacityTrace.source")))
  check (actual == (← transformed) && literals.isEmpty) "actual native diagnostic differs"
  let (actual,literals) : String × Array (String × String) ← IO.ofExcept
    (fromJson? (← read (build/"tools_research_AckPathRuntime.source")))
  check (actual == (← IO.FS.readFile (project/"tools/research/AckPathRuntime.lean")) && literals.isEmpty) "actual diagnostic entry differs"
  let canonicalTrace := records/"MemoryCapacityTrace.lean"
  if cursor then check ((← IO.FS.readFile canonicalTrace) == (← transformed)) "diagnostic source differs between products"
  else IO.FS.writeFile canonicalTrace (← transformed)
  write (file "runtime.json") (Json.mkObj [("sha256",toJson (← hash (build/"StudyMain"))),
    ("configuredProductSha256",toJson (← hash (product/"build/StudyMain"))),
    ("productSourcesUnchanged",toJson true),("notAPerformanceComparison",toJson true)])
def prepare (cursor : Bool := false) : IO Unit := do
  idle
  let audit ← read (records/(if cursor then "cursor-runtime.json" else "runtime.json"))
  let observerBuild := if cursor then cursorBuild else build
  let product := if cursor then cursorRoot else parent
  check (audit.getObjValD "sha256" == toJson (← hash (observerBuild/"StudyMain")) &&
    audit.getObjValD "configuredProductSha256" == toJson (← hash (product/"build/StudyMain"))) "audited diagnosis changed"
  if cursor then
    discard <| finished "ack-path-observed"
    check ((← read (records/"observed.json")).getObjValD "allOriginalFilesUnchanged" == toJson true) "collect parent diagnosis first"
  let original ← read (project/"docs/candidates/cursor-codec/runtime/a-first-failed.json")
  let original := original.getObjValD "input"
  let installation := product/"prefix"
  let data := product/"data"
  let executable := installation/"libexec/eggshell"
  let expected ← if cursor then
    pure ((← read (project/"docs/candidates/cursor-codec/runtime/runtime.json")).getObjValD "sha256")
    else pure (audit.getObjValD "configuredProductSha256")
  check (expected == toJson (← hash executable)) "configured product changed"
  let output := root/(if cursor then "cursor-trace-trial" else "trial")
  let config := output/"config.toml"
  let environment : Array (String × Option String) ← IO.ofExcept (fromJson? (original.getObjValD "environment"))
  let plugin := installation/"share/eggshell/codex-plugin"
  let environment := environment.map (fun (key,value) => (key,match key with
    | "EGGSHELL_CONFIG" => some config.toString | "EGGSHELL_PREFIX" => some installation.toString
    | "PLUGIN_ROOT" => some plugin.toString | "EGGSHELL_DATA_ROOT" => some data.toString | _ => value))
  let input := original.setObjVal! "output" (toJson output.toString) |>.setObjVal! "config" (toJson config.toString)
    |>.setObjVal! "environment" (toJson environment) |>.setObjVal! "runtime" (toJson executable.toString)
    |>.setObjVal! "runtimeSha256" expected |>.setObjVal! "data" (toJson data.toString) |>.setObjVal! "plugin" (toJson plugin.toString)
  let path := root/(if cursor then "cursor-trace-input.json" else "input.json")
  check (!(← path.pathExists)) "preserve observed input"
  write path input
  if cursor then write (records/"cursor-compatible-plan.json") (Json.mkObj [("counts",input.getObjValD "counts"),
    ("input",input),("purpose",toJson "candidate full-hook resource/body check;original ABBA remains stopped"),
    ("notAPerformanceComparison",toJson true),("answeringModelCalls",toJson (0 : Nat))])
  let unset := environment.filterMap fun (key,value) => if value.isNone then some key else none
  let assignments := environment.filterMap fun (key,value) => value.map (key++"="++·)
  guard (if cursor then "ack-path-cursor-traced" else "ack-path-observed")
    (#["/usr/bin/env"]++unset.flatMap (fun key => #["-u",key])++assignments++#[(observerBuild/"StudyMain").toString,path.toString])
def collect (cursor : Bool := false) : IO Unit := do
  idle
  let recordName := if cursor then "cursor-observed.json" else "observed.json"
  check (!(← (records/recordName).pathExists)) "preserve traced diagnosis"
  let monitor ← read (base/(if cursor then "ack-path-cursor-traced.guard.json" else "ack-path-observed.guard.json"))
  check (monitor.getObjValD "state" == toJson "finished" && monitor.getObjValD "ownedPids" == toJson (#[] : Array Nat)) "diagnosis has not drained"
  let input ← read (root/(if cursor then "cursor-trace-input.json" else "input.json"))
  let database : System.FilePath := .mk (← IO.ofExcept (input.getObjValAs? String "project"))
  let files : Array (String × String) ← IO.ofExcept (fromJson? (input.getObjValD "sourceFiles"))
  for (name,digest) in files do check ((← hash (database/name)) == digest) "diagnosis changed original publication"
  let trial := root/(if cursor then "cursor-trace-trial" else "trial")
  let phases : Array Json ← IO.ofExcept (fromJson? (← read (trial/"progress.json")))
  let topics ← IO.ofExcept (input.getObjValAs? (Array Json) "topics")
  let data : System.FilePath := .mk (← IO.ofExcept (input.getObjValAs? String "data"))
  let mut clients : Array Json ← IO.ofExcept (fromJson? (← read (trial/"prime.json")))
  for phase in phases do clients := clients++(← IO.ofExcept (phase.getObjValAs? (Array Json) "rows"))
  let mut observations := #[]
  for client in clients do
    let receipt ← IO.ofExcept (client.getObjValAs? String "receipt")
    let directory := data/"receipts"/receipt
    let mut steps : Array Json := #[]
    for entry in ← directory.readDir do
      if entry.fileName.startsWith "capacity-path-" && entry.fileName.endsWith ".json" then steps := steps.push (← read entry.path)
    let ordered := steps.qsort (fun left right =>
      (left.getObjValAs? Nat "observedMs").toOption.getD 0 <
      (right.getObjValAs? Nat "observedMs").toOption.getD 0)
    let mut fields := [("client",client),("steps",toJson ordered)]
    for name in ["ack","capacity-client-error","request-pages","operation-service","transport","dispatch","search"] do
      let path := directory/(name++".json")
      if ← path.pathExists then fields := fields++[(name,← read path)]
    let published := directory/"published.json"
    if ← published.pathExists then
      let value ← read published
      let payload ← IO.ofExcept ((value.getObjValD "data").getObj?)
      let payload := payload.toList.filter (·.1 != "output")
      fields := fields++[("published",value.setObjVal! "data" (Json.mkObj payload))]
      let original ← IO.ofExcept ((value.getObjValD "data").getObjValAs? String "output")
      let parsed ← IO.ofExcept (Json.parse original)
      let body ← IO.ofExcept ((parsed.getObjValD "hookSpecificOutput").getObjValAs? String "additionalContext")
      let some expected := topics.find? (fun topic => topic.getObjValD "topic" == client.getObjValD "topic") |
        throw (IO.userError "trace has an undeclared question")
      let canonical ← IO.FS.readFile (.mk (← IO.ofExcept (expected.getObjValAs? String "body")))
      fields := fields++[("observedStdout",Json.mkObj [("bytes",toJson body.utf8ByteSize),
        ("bodyByteEqual",toJson (body == canonical)),("canonicalSha256",expected.getObjValD "sha256"),
        ("independentOfAckSuccess",toJson true)])]
    if client.getObjValD "success" != toJson true then
      let session ← IO.ofExcept (client.getObjValAs? String "session")
      let state ← read (data/"sessions"/session/"state.json")
      fields := fields++[("finalSession",Json.mkObj [("epoch",state.getObjValD "epoch"),
        ("offers",toJson ((state.getObjValD "offers").getArr?.toOption.getD #[] |>.map fun offer =>
          Json.mkObj [("id",offer.getObjValD "id"),("stamp",offer.getObjValD "stamp")])),
        ("confirmedDelivery",state.getObjValD "confirmedDelivery"),
        ("notAServerReplyTimestamp",toJson true)])]
    observations := observations.push (Json.mkObj fields)
  let mut fields := [("input",input),("guard",monitor),("phases",toJson phases),("clients",toJson observations),
    ("allOriginalFilesUnchanged",toJson true),("notAPerformanceComparison",toJson true),
    ("answeringModelCalls",toJson (0 : Nat)),("adopted",toJson false)]
  for name in ["cache-stats-prime","cache-stats-phase-4","cache-stats-phase-16","frontend-shutdown","publisher-shutdown"] do
    if ← (trial/(name++".json")).pathExists then fields := fields++[(name,← read (trial/(name++".json")))]
  write (records/recordName) (Json.mkObj fields)
def conclude : IO Unit := do
  idle
  check (!(← (records/"decision.json").pathExists)) "preserve diagnosis decision"
  let before ← read (records/"observed.json")
  let after ← read (records/"cursor-observed.json")
  let summary := fun (value : Json) => do
    let phases ← IO.ofExcept (value.getObjValAs? (Array Json) "phases")
    check (phases.map (·.getObjValD "clients") == #[toJson (4 : Nat),toJson (16 : Nat)] &&
      phases.all (fun phase => phase.getObjValD "passed" == toJson true)) "successful observed small-load checks required"
    let clients ← IO.ofExcept (value.getObjValAs? (Array Json) "clients")
    check (clients.size == 23 && clients.all (fun row => (row.getObjValD "client").getObjValD "success" == toJson true)) "all observed clients required"
    check (value.getObjValD "allOriginalFilesUnchanged" == toJson true) "diagnosis changed source"
    return Json.mkObj [("phases",toJson (phases.map fun phase => Json.mkObj
      [("clients",phase.getObjValD "clients"),("wallMs",phase.getObjValD "wallMs"),
       ("successes",phase.getObjValD "successes"),("semanticCompleted",phase.getObjValD "semanticCompleted"),
       ("synapsesCompleted",phase.getObjValD "synapsesCompleted")])),
      ("sampledPeakRssKiB",(value.getObjValD "guard").getObjValD "sampledPeakRssKiB")]
  let a := before.getObjValD "input"
  let b := after.getObjValD "input"
  for key in ["project","workspace","sourceFiles","topics","counts","handoffChars","diagnostic"] do
    check (a.getObjValD key == b.getObjValD key) "observed workload differs"
  write (records/"decision.json") (Json.mkObj [("parentObserved",← summary before),("cursorObserved",← summary after),
    ("sameOriginalSnapshotAndQuestions",toJson true),("observedBodiesAndAcks",toJson (46 : Nat)),
    ("measuredSemanticAndSynapticCompletions",toJson (40 : Nat)),
    ("originalUnobservedAbbaRemainsStopped",toJson true),("originalAckDeadlineFailureUnresolved",toJson true),
    ("notRepeatedPerformanceEvidence",toJson true),("clearWholeHookImprovementEstablished",toJson false),
    ("fewSecondsAt16Achieved",toJson false),("answeringModelCalls",toJson (0 : Nat)),("adopted",toJson false)])
def main (args : List String) : IO Unit := do
  match args with
  | ["setup"] => setup
  | ["finish-build",label] => do
    idle
    IO.FS.writeFile (source/"tools/research/AckPathRuntime.lean")
      (← IO.FS.readFile (project/"tools/research/AckPathRuntime.lean"))
    IO.FS.writeFile (source/"tools/research/MemoryCapacityTrace.lean") (← transformed)
    guard ("ack-path-"++label) #[(compiler/"bin/lean").toString,"-j1","-M1536","--run",
      (project/"tools/research/StudyBuildMain.lean").toString,(base/"ack-path-settings.json").toString]
  | ["audit"] => guard "ack-path-audit" #["/usr/bin/env","LEAN_PATH="++(base/"study-local-lib").toString,
      (compiler/"bin/lean").toString,"-j1","-M1536","--run",driver.toString,"audit-worker"]
  | ["audit-worker"] => audit
  | ["prepare"] => discard <| finished "ack-path-audit"; prepare
  | ["collect"] => collect
  | ["prepare-cursor"] => discard <| finished "ack-path-cursor-audit"; prepare true
  | ["collect-cursor"] => collect true
  | ["conclude"] => conclude
  | ["setup-cursor"] => setupCursor
  | ["audit-cursor"] => guard "ack-path-cursor-audit" #["/usr/bin/env","LEAN_PATH="++(base/"study-local-lib").toString,
      (compiler/"bin/lean").toString,"-j1","-M1536","--run",driver.toString,"audit-cursor-worker"]
  | ["audit-cursor-worker"] => audit true
  | _ => throw (IO.userError "ACK diagnosis setup|audit|prepare")
end AckPathStudy
def main := AckPathStudy.main
