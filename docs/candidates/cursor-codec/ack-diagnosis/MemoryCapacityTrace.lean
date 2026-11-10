import Main
import Eggshell.ContractAudit
import tools.research.StudyRuntime
import tools.research.StudyCommand
import tools.research.StudyProfile
import tools.research.StudyWarm
namespace Eggshell.Research.MemoryCapacityTrace
open Lean Plugin

structure Topic where
  topic : Nat
  prompt : String
  body : String
  sha256 : String
  available : Nat
  deriving FromJson
structure Input where
  output : String
  project : String
  workspace : String
  runtime : String
  runtimeSha256 : String
  plugin : String
  data : String
  config : String
  handoffChars : Nat
  environment : Array (String × Option String)
  sourceFiles : Array (String × String)
  topics : Array Topic
  counts : Array Nat
  gate : Option String := none
  diagnostic : Bool := false
  deriving FromJson
structure Expected where
  topic : Topic
  text : String

def workloadKey (input : Input) : String := Sha256.hex (Json.mkObj [
  ("project",toJson input.project),("sourceFiles",toJson input.sourceFiles),
  ("runtimeSha256",toJson input.runtimeSha256),("workspace",toJson input.workspace),
  ("handoffChars",toJson input.handoffChars),
  ("topics",toJson (input.topics.map fun topic =>
    (topic.topic,topic.prompt,topic.sha256,topic.available)))]).compress.toUTF8

def check (ok : Bool) (message : String) : IO Unit := unless ok do throw (IO.userError message)
def read (path : System.FilePath) : IO Json := IO.FS.readFile path >>= (IO.ofExcept ∘ Json.parse)
def save (path : System.FilePath) (value : Json) : IO Unit := IO.FS.writeFile path value.compress
def hash (path : System.FilePath) : IO String := do
  let output ← IO.Process.output {cmd := "/usr/bin/shasum",args := #["-a","256",path.toString]}
  check (output.exitCode == 0) "cannot hash capacity evidence"
  return (output.stdout.splitOn " ").headD ""
def session (root : System.FilePath) (phase index : Nat) : String :=
  "capacity-"++Sha256.hex s!"{root}:{phase}:{index}".toUTF8
def request (input : Input) (id event : String) (prompt : String := "") : Json :=
  Json.mkObj [("session_id",toJson id),("turn_id",toJson "first"),("cwd",toJson input.workspace),
    ("_eggshell_config",toJson input.config),
    ("hook_event_name",toJson event),("prompt",toJson prompt)]

/-- Each completed client writes its own result before returning. No giant
receipt JSON or original-source audit is retained in the concurrent driver. -/
def client (input : Input) (expected : Expected) (root : System.FilePath) (phase index : Nat) : IO Json := do
  let id := session (.mk input.output) phase index
  let directory := root/s!"client-{index}"
  IO.FS.createDirAll directory
  let receipt ← Receipt.fresh
  let began ← IO.monoMsNow
  let deadline := began+30000
  let mut acked := false
  let mut same := false
  let mut bodyBytes := 0
  let mut failure : Option String := none
  let mark := fun (step : String) => Receipt.observe (some receipt)
    ("capacity-path-"++step.replace ":" "-") (Json.mkObj [("step",toJson step)])
  try
    let reply ← Daemon.hookRequest (request input id "UserPromptSubmit" expected.topic.prompt) deadline receipt
    mark "hook:end"
    let output := (← IO.ofExcept (reply.getObjValAs? String "output")).trimAscii.toString++"\n"
    -- Persist the original stdout before acknowledging its publication.
    IO.FS.writeFile (directory/"stdout") output
    let flushed ← IO.monoMsNow
    let complete := (Daemon.decodeHookReply (some reply)).isComplete
    Receipt.write receipt "published" (Json.mkObj [("output",toJson output),("bytes",toJson output.utf8ByteSize),
      ("sha256",toJson (Sha256.hex output.toUTF8)),("replyComplete",toJson complete),
      ("startedMs",toJson began),("flushedMs",toJson flushed),("deadlineMs",toJson deadline)])
    mark "published:end"
    let decoded ← IO.ofExcept (Json.parse output)
    mark "body:parsed"
    let body ← IO.ofExcept ((decoded.getObjValD "hookSpecificOutput").getObjValAs? String "additionalContext")
    bodyBytes := body.utf8ByteSize
    same := body == expected.text
    let ack := reply.getObjValD "ack"
    mark "body:compared"
    if complete && ack != Json.null then
      mark "endpoint:start"
      let endpoint ← Daemon.readyEndpoint id
      mark "endpoint:end"
      acked := (← Daemon.exchangeBefore endpoint "ack" ack deadline (fun step => mark ("ack:"++step))) == "true"
      Receipt.write receipt "ack" (Json.mkObj [("rpcCompleted",toJson true),("offerAccepted",toJson acked)])
  catch error =>
    mark "client:exception"
    failure := some error.toString
    Receipt.observe (some receipt) "capacity-client-error" (Json.mkObj [("error",toJson error.toString)])
  let elapsed := (← IO.monoMsNow)-began
  let result := Json.mkObj [("session",toJson id),("receipt",toJson receipt),("client",toJson index),
    ("topic",toJson expected.topic.topic),("elapsedMs",toJson elapsed),("bodyBytes",toJson bodyBytes),
    ("frozenOriginals",toJson expected.topic.available),("bodyByteEqual",toJson same),
    ("acknowledged",toJson acked),("error",toJson failure),
    ("success",toJson (same && acked && failure.isNone && elapsed < 30000))]
  save (directory/"result.json") result
  return result

def receiptSummary (input : Input) (row : Json) : IO Json := do
  let id ← IO.ofExcept (row.getObjValAs? String "receipt")
  let directory := System.FilePath.mk input.data/"receipts"/id
  let mut fields := []
  for name in ["search","operation-service","ack","transport"] do
    let path := directory/(name++".json")
    if ← path.pathExists then fields := fields++[(name,(← read path).getObjValD "data")]
  -- Extract only the checked scalar fields from the large synapse record.
  let synapsePath := directory/"synaptic-delivery.json"
  if ← synapsePath.pathExists then
    let value := (← read synapsePath).getObjValD "data"
    fields := fields++[("synapse",Json.mkObj [("complete",value.getObjValD "complete"),
      ("packetVerified",value.getObjValD "packetVerified"),("unverifiedParts",value.getObjValD "unverifiedParts")])]
  return Json.mkObj fields

def phase (input : Input) (topics : Array Expected) (count : Nat) : IO Json := do
  let root := System.FilePath.mk input.output/s!"phase-{count}"
  IO.FS.createDirAll root
  let mut initializations := #[]
  for index in [:count] do
    let id := session (.mk input.output) count index
    let before ← IO.monoMsNow
    let reply ← Daemon.hookRequest (request input id "SessionStart") (before+30000) (← Receipt.fresh)
    check ((reply.getObjValAs? String "output").isOk) "fresh session initialization failed"
    initializations := initializations.push (Json.mkObj [("session",toJson id),
      ("elapsedMs",toJson ((← IO.monoMsNow)-before))])
  save (root/"initializations.json") (toJson initializations)
  let ready ← Std.Mutex.new (0 : Nat)
  let start ← IO.mkRef false
  let tasks ← (Array.range count).mapM fun index => IO.asTask (do
    ready.atomically (modify (·+1))
    while !(← start.get) do IO.sleep 1
    let some topic := topics[index%topics.size]? | throw (IO.userError "missing frozen topic")
    try client input topic root count index
    catch error =>
      let row := Json.mkObj [("session",toJson (session (.mk input.output) count index)),
        ("client",toJson index),("topic",toJson topic.topic.topic),("success",toJson false),
        ("error",toJson error.toString),("failedOutsideHook",toJson true)]
      IO.FS.createDirAll (root/s!"client-{index}")
      save (root/s!"client-{index}/result.json") row
      return row) .dedicated
  let barrier := (← IO.monoMsNow)+10000
  try
    while (← ready.atomically get) < count do
      check ((← IO.monoMsNow) < barrier) "capacity launch barrier expired"
      IO.sleep 1
    let began ← IO.monoMsNow
    start.set true
    let rows ← tasks.mapM fun task => do IO.ofExcept (← IO.wait task)
    -- Save all client timings before diagnostics or service shutdown can fail.
    save (root/"clients.json") (toJson rows)
    let wall := (← IO.monoMsNow)-began
    let receipts ← rows.mapM fun row => do
      if (row.getObjValAs? String "receipt").isOk then receiptSummary input row
      else pure (Json.mkObj [("clientFailedBeforeReceipt",toJson true)])
    save (root/"receipts.json") (toJson receipts)
    let semantic := receipts.filter fun row =>
      ((row.getObjValD "search").getObjValD "trace").getObjValD "semantic" == toJson "completed"
    let synapses := receipts.filter fun row =>
      (row.getObjValD "synapse").getObjValD "complete" == toJson true &&
      (row.getObjValD "synapse").getObjValD "packetVerified" == toJson true
    let success := rows.filter (fun row => row.getObjValD "success" == toJson true)
    let result := Json.mkObj [("clients",toJson count),("successes",toJson success.size),
      ("allBodiesByteEqual",toJson (rows.all (fun row => row.getObjValD "bodyByteEqual" == toJson true))),
      ("semanticCompleted",toJson semantic.size),("synapsesCompleted",toJson synapses.size),
      ("wallMs",toJson wall),("rows",toJson rows),
      ("passed",toJson (success.size == count && semantic.size == count && synapses.size == count))]
    save (root/"result.json") result
    return result
  finally
    start.set true
    for task in tasks do IO.cancel task
    for task in tasks do discard <| IO.wait task

def run (path : System.FilePath) : IO Unit := do
  let input ← IO.ofExcept (fromJson? (← read path) : Except String Input)
  let root : System.FilePath := .mk input.output
  check (root.isAbsolute && !(← root.pathExists) && input.topics.map (·.topic) == #[1,2,3]) "fresh frozen capacity inputs required"
  check ((input.diagnostic && input.counts == #[4]) ||
    (!input.diagnostic && (input.counts == #[4,16] || input.counts == #[40] || input.counts == #[80])))
    "predeclared capacity stages or four-client diagnosis required"
  if input.counts == #[40] || input.counts == #[80] then
    let some gate := input.gate | throw (IO.userError "40/80 clients require a completed small-load gate")
    let previous ← read (.mk gate)
    check (previous.getObjValD "allPhasesPassed" == toJson true &&
      previous.getObjValD "runtimeSha256" == toJson input.runtimeSha256 &&
      previous.getObjValD "workloadSha256" == toJson (workloadKey input) &&
      previous.getObjValD "counts" == toJson (#[(4 : Nat),16])) "small-load gate does not match this exact runtime"
  check ((← hash (.mk input.runtime)) == input.runtimeSha256) "capacity runtime changed"
  check ((← IO.getEnv "EGGSHELL_DATA_ROOT") == some input.data) "capacity client has a different data root"
  check ((← StudyRuntime.files (.mk input.project)) == input.sourceFiles) "frozen project publication changed"
  IO.FS.createDirAll root
  check (input.config == (root/"config.toml").toString && input.handoffChars == 500000)
    "capacity changed the reviewed delivery envelope or config scope"
  IO.FS.writeFile (.mk input.config) (StudyProfile.render input.runtime input.project
    (← IO.ofExcept (StudyProfile.checked input.handoffChars)) false)
  let topics ← input.topics.mapM fun topic => do
    check ((← hash (.mk topic.body)) == topic.sha256) "frozen audited body changed"
    return (⟨topic,← IO.FS.readFile (.mk topic.body)⟩ : Expected)
  let publisher ← StudyRuntime.startPublisher (.mk input.runtime) (.mk input.data) input.environment
  try
    let warmed ← StudyCommand.run input.runtime #["egg","warm","work"] input.environment input.workspace "" (root/"warm") 240000
    check (warmed.exitCode == 0) "explicit project warm failed"
    let source ← DB.PageMap.pin (.mk input.project)
    discard <| IO.ofExcept (StudyWarm.decode warmed.stdout #[input.project] #[source.head]
      MiniLM.model SearchProvider.encoderContract true)
    let managed ← StudyRuntime.startManaged (.mk input.runtime) (.mk input.plugin) "capacity-host"
      (System.FilePath.mk input.data/"daemon.json") input.environment
    try
      -- One warm prime per topic, recorded separately from measured concurrency.
      let primeInput := {input with output := (root/"prime").toString}
      IO.FS.createDirAll (root/"prime")
      let mut primes := #[]
      for i in [:topics.size] do
        let some topic := topics[i]? | throw (IO.userError "prime topic missing")
        let before ← IO.monoMsNow
        discard <| Daemon.hookRequest (request primeInput (session (root/"prime") 0 i) "SessionStart")
          (before+30000) (← Receipt.fresh)
        let row ← client primeInput topic (root/"prime") 0 i
        primes := primes.push row
        save (root/"prime.json") (toJson primes)
        check (row.getObjValD "success" == toJson true) "real-source warm prime failed"
      let captureCaches := fun (label : String) => do
        let record ← try
          let some endpoint ← Publication.Client.endpoint? | throw (IO.userError "owned publisher endpoint is absent")
          check (endpoint.pid == StudyRuntime.pid publisher && endpoint.session == "publisher")
            "statistics endpoint belongs to another publisher"
          IO.ofExcept (Json.parse (← Daemon.exchange endpoint "stats" (budget := 5000)))
          catch error => pure (Json.mkObj [("error",toJson error.toString)])
        save (root/("cache-stats-"++label++".json")) record
      captureCaches "prime"
      let mut results := #[]
      for count in input.counts do
        let result ← phase input topics count
        results := results.push result
        save (root/"progress.json") (toJson results)
        captureCaches ("phase-"++toString count)
        check (result.getObjValD "passed" == toJson true) "capacity phase failed; do not escalate unchanged load"
      check ((← StudyRuntime.files (.mk input.project)) == input.sourceFiles) "capacity changed the original DB"
      save (root/"report.json") (Json.mkObj [("runtimeSha256",toJson input.runtimeSha256),
        ("workloadSha256",toJson (workloadKey input)),
        ("counts",toJson input.counts),("phases",toJson results),("allPhasesPassed",toJson (!input.diagnostic)),
        ("diagnosticOnly",toJson input.diagnostic),
        ("originalSourceFilesUnchanged",toJson true),("originalProjectSources",toJson (1 : Nat)),
        ("initializationOutsideMeasuredWave",toJson true),("answeringModelCalls",toJson (0 : Nat)),
        ("clientTransport",toJson "independent in-process native hook callers;stdout file publication before ACK;not 80 local CLI subprocesses"),
        ("eightHourOrGrowingProjectValidation",toJson false),("adopted",toJson false)])
    finally StudyRuntime.stopManaged managed (root/"frontend-shutdown.json")
  finally StudyRuntime.stopManaged publisher (root/"publisher-shutdown.json")

end Eggshell.Research.MemoryCapacityTrace
def memoryCapacityTraceEntry (args : List String) : IO Unit := do
  let [input] := args | throw (IO.userError "capacity input required")
  Eggshell.Research.MemoryCapacityTrace.run (.mk input)
