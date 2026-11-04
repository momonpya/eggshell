import Main
import tools.research.ProjectContextChecks

open Lean Eggshell Eggshell.Plugin

namespace Eggshell.Research.ConcurrentHookChecks

private def check (value : Bool) (message : String) : IO Unit :=
  unless value do throw (IO.userError message)

private def model : IO Unit := do
  let lane0 : OperationPlan.Lane := ⟨0,by decide⟩
  let lane3 : OperationPlan.Lane := ⟨3,by decide⟩
  let job := fun name role bytes cutoff => ({id := name,role,bytes,cutoff} : OperationPlan.Job)
  let (queued,_) := OperationPlan.admit OperationPlan.initial (job "a" .search 1 100)
  check (!(OperationPlan.admit queued (job "a" .search 1 100)).2) "duplicate request was admitted"
  check ((OperationPlan.take queued lane3 0).2.isNone) "save lane consumed a search"
  check ((OperationPlan.take queued lane0 100).2.isNone) "expired queue entry began execution"
  let (running,some first) := OperationPlan.take queued lane0 0 | throw (IO.userError "search slot did not start")
  let done := OperationPlan.finish running lane0 first.token
  let (again,_) := OperationPlan.admit done (job "b" .search 1 100)
  let (again,some second) := OperationPlan.take again lane0 0 | throw (IO.userError "reused slot did not start")
  check ((OperationPlan.finish again lane0 first.token).contents.running[lane0].any (·.token == second.token))
    "stale completion consumed another request"
  let stopped := OperationPlan.close again
  check (!(OperationPlan.admit stopped (job "closed" .save 1 100)).2 &&
    (OperationPlan.take stopped lane3 0).2.isNone) "closed scheduler admitted or started work"
  let mut full := OperationPlan.initial
  for i in [:OperationPlan.maxRequests] do
    let (next,accepted) := OperationPlan.admit full (job (toString i) .search 1 100)
    check accepted "request bound rejected a valid slot"
    full := next
  check (!(OperationPlan.admit full (job "overflow" .save 1 100)).2) "request bound overflowed"
  let (large,_) := OperationPlan.admit OperationPlan.initial (job "large" .search OperationPlan.maxBytes 100)
  check (!(OperationPlan.admit large (job "bytes" .save 1 100)).2) "byte bound overflowed"
  IO.println (Json.mkObj [("modelChecks",toJson true),("searchWorkers",toJson OperationPlan.searchWorkers),
    ("saveWorkers",toJson OperationPlan.saveWorkers),("requestBound",toJson OperationPlan.maxRequests)]).compress

private def serverStats : IO Json := do IO.ofExcept (Json.parse (← Publication.Client.control "stats"))
private def operations (value : Json) : Json := value.getObjValD "operations"
private def natural (value : Json) (key : String) : Nat := (value.getObjValAs? Nat key).toOption.getD 0

private def idle (deadline : Nat) : IO Json := do
  repeat
    let value ← serverStats
    let state := operations value
    if natural state "pending" == 0 && natural state "active" == 0 &&
        natural state "searchReplyBytes" == 0 && natural state "saveReplyBytes" == 0 then return value
    check ((← IO.monoMsNow) < deadline) s!"operation service did not drain: {state.compress}"
    IO.sleep 5
  throw (IO.userError "unreachable idle wait")

private def prepareSession (original : PendingTurn) (name : String) (command : Option (List String)) : IO PendingTurn := do
  let pending := {original with
    sessionId := name,turnId := "controlled-turn",semanticMatcher := command,
    tools := [],inFlight := [],finalMessage := none,closed := false}
  let some _ ← ProjectContext.open? pending ((← IO.monoMsNow)+20000) |
    throw (IO.userError "logical client lost its captured project scope")
  let files ← sessionFiles name
  writeJson files.state ({profile := pending.profile} : ThreadState)
  writeJson files.pending pending
  return pending

private def query (pending : PendingTurn) (allowance : Nat := 28000) (empty : Bool := false) : IO (Option Json × Nat × Bool) := do
  let started ← IO.monoMsNow
  let pending := if empty then {pending with projection := .none} else pending
  let request : Worker.Search := {
    pending,state := {profile := pending.profile},work := pending.prompt,enforce := false,
    deadline := started+allowance}
  let ready ← IO.mkRef false
  let semantic := pending.semanticMatcher.isSome
  let policy : Worker.SearchPolicy := {
    identity := request.identity,finishReady := semantic,onReady := fun _ => ready.set true}
  let cutoff := if semantic then semanticSearchDeadline started request.deadline else request.deadline
  let result ← Worker.exchange pending.sessionId "search" (toJson request) cutoff (some policy)
  return (result,(← IO.monoMsNow)-started,← ready.get)

private def checkBody (result : Option Json) : IO Unit := do
  let some value := result | throw (IO.userError "logical client got no search response")
  let some handoff ← IO.ofExcept (fromJson? value : Except String (Option Handoff)) |
    throw (IO.userError "logical client got an empty handoff")
  check (handoff.reason != "search-incomplete" && handoff.text.contains "\"OLD_ID_ALPHA\"" &&
    handoff.text.contains "\"OLD_ID_ALPHA_TAIL\"" && !handoff.text.contains "NEW_ID_BETA")
    "shared worker lost original evidence or read a newer foreign snapshot"

/-- Exercise the product's semantic-first, lexical-fallback and final offer
path. A transport-only semantic phase is not the full hook outcome. -/
private def hookQuery (pending : PendingTurn) : IO (Option Json × Nat × Bool) := do
  let started ← IO.monoMsNow
  let input := Json.mkObj [("_eggshell_deadline",toJson (started+28000)),
    ("_eggshell_receipt",toJson (← Receipt.fresh))]
  let result ← deliverForWork input pending pending.prompt false
  let semantic := result.any fun handoff => handoff.search.any fun trace =>
    match trace.semantic with | .completed => true | _ => false
  return (result.map toJson,(← IO.monoMsNow)-started,semantic)

private def saveDuring (pending : PendingTurn) (index : Nat) : IO Nat := do
  let started ← IO.monoMsNow
  let files ← sessionFiles pending.sessionId
  let domain := Sha256.hex "shared-execution-fixture".toUTF8
  let clock := fun time => Json.mkObj [("_eggshell_synapse_clock",toJson domain),("_eggshell_synapse_nanos",toJson time)]
  let tool : ToolEvent := {
    name := "mcp__fixture__inspect",useId := s!"saved-{index}",input := "{}",
    response := (Json.mkObj [("evidence",toJson s!"CONCURRENT_ORIGINAL_{index}")]).compress}
  try Synapses.Live.start (clock (index*2+1)) files pending {profile := pending.profile} tool
  catch error => throw (IO.userError s!"save {index}, start ingress: {error}")
  try Synapses.Live.finish (clock (index*2+2)) pending tool
  catch error => throw (IO.userError s!"save {index}, finish ingress: {error}")
  let closed := {pending with tools := [tool],finalMessage := some s!"Recorded `CONCURRENT_ORIGINAL_{index}`.",closed := true}
  let path := files.directory/"deferred"/"controlled-save.json"
  try FileSystem.privateDirectory path.parent.get!
  catch error => throw (IO.userError s!"save {index}, deferred directory {path}: {error}")
  try writeJson path closed
  catch error => throw (IO.userError s!"save {index}, deferred body {path}: {error}")
  let exchange := Worker.exchange pending.sessionId "save"
    (Json.mkObj [("session",toJson pending.sessionId),("path",toJson path.toString)]) ((← IO.monoMsNow)+60000)
  let reply ← try exchange
    catch error => throw (IO.userError s!"save {index}, publisher exchange {path}: {error}")
  let some reply := reply |
    throw (IO.userError "shared save did not reply")
  let .published saved ← IO.ofExcept (NativePublication.SaveReply.check? reply) |
    throw (IO.userError "shared save did not publish")
  check (saved.publication.accounted && saved.publication.awaiting == 0) "shared save lost its durable source ACK"
  return (← IO.monoMsNow)-started

private def searchPids (value : Json) : IO (Array Nat) := do
  let pipes ← IO.ofExcept (value.getObjValAs? (Array Json) "workerPipes")
  return pipes.filterMap fun entry => do
    let key ← (entry.getObjValAs? String "key").toOption
    if !key.startsWith "shared-operation-" || !key.contains ":search-" then none
    else (entry.getObjValAs? Nat "pid").toOption

private def signal (pids : Array Nat) (kind : String) : IO Unit := do
  for pid in pids do
    let _ ← IO.Process.output {cmd := "/bin/kill",args := #[kind,toString pid]}
    pure ()

private def cancellation (original : PendingTurn) : IO Json := do
  let sessions ← (List.range 4).toArray.mapM fun index => prepareSession original s!"queue-client-{index}" none
  let pids ← searchPids (← serverStats)
  check (pids.size == OperationPlan.searchWorkers) "load did not establish all bounded search workers"
  signal pids "-STOP"
  try
    let held ← (sessions.extract 0 pids.size).mapM fun pending => IO.asTask (query pending 10000) .dedicated
    let deadline := (← IO.monoMsNow)+5000
    repeat
      if natural (operations (← serverStats)) "active" ≥ pids.size then break
      check ((← IO.monoMsNow) < deadline) "paused workers did not hold their global slots"
      IO.sleep 5
    let some last := sessions[pids.size]? | throw (IO.userError "no client for queued expiry")
    let expired ← IO.asTask (query last 1000) .dedicated
    repeat
      if natural (operations (← serverStats)) "pending" > 0 then break
      check ((← IO.monoMsNow) < deadline) "short request did not enter the actual queue"
      IO.sleep 5
    let (reply,_,_) ← IO.ofExcept (← IO.wait expired)
    check reply.isNone "queued request executed after its cutoff"
    let some first := sessions[0]? | throw (IO.userError "missing cancelled client")
    Worker.cancel first.sessionId "search"
    let some firstTask := held[0]? | throw (IO.userError "missing cancelled request task")
    let (cancelled,_,_) ← IO.ofExcept (← IO.wait firstTask)
    check cancelled.isNone "cancelled client received a result"
    signal pids "-CONT"
    for task in held.extract 1 held.size do
      let (reply,_,_) ← IO.ofExcept (← IO.wait task)
      checkBody reply
    let _ ← idle ((← IO.monoMsNow)+15000)
    let next ← prepareSession original "after-cancel-client" none
    let (reply,_,_) ← query next
    checkBody reply
    return Json.mkObj [("queuedExpiry",toJson true),("cancelledOnlyItsClient",toJson true),
      ("otherClientsCompleted",toJson true),("reusedServiceAfterCancellation",toJson true)]
  finally signal pids "-CONT"

def exercise (root : System.FilePath) (numerical : Bool)
    (inspectPreparation : PendingTurn → IO Json := fun _ => pure Json.null) : IO Unit := do
  model
  let original ← IO.ofExcept (Json.parse (← IO.FS.readFile (root/"captured-turn.json")) >>= fromJson? (α := PendingTurn))
  let command ← if numerical then MiniLM.command (← Paths.installRoot) else pure none
  if numerical then check command.isSome "actual MiniLM runtime required"
  let some _context ← ProjectContext.open? original ((← IO.monoMsNow)+20000) |
    throw (IO.userError "complete original project scope missing")
  let clients ← (List.range 80).toArray.mapM fun index =>
    prepareSession original s!"load-{if numerical then "numeric" else "lexical"}-{index}" command
  let saves ← (List.range 80).toArray.mapM fun index => prepareSession original s!"save-client-{index}" command
  let mut writers : Std.HashMap String Nat := {}
  for pending in saves do
    let selected ← ProjectAccess.resolve pending.sessionId (pendingSelection pending)
    let some write := selected.write | throw (IO.userError "mixed save client has no configured project writer")
    writers := writers.insert write.original.identity (writers[write.original.identity]?.getD 0+1)
  check (writers.size > 1) "load did not exercise independently owned original streams"
  let _ ← Publication.Client.resolve
  try
    let started ← IO.monoMsNow
    let requests ← clients.mapM fun pending =>
      IO.asTask (if numerical then hookQuery pending else query pending) .dedicated
    let publications ← saves.zipIdx |>.mapM fun (pending,index) => IO.asTask (saveDuring pending index) .dedicated
    let mut times := #[]
    let mut ready := 0
    let mut queries := #[]
    let mut failures := #[]
    for task in requests do
      match ← IO.wait task with
      | .error error => failures := failures.push error.toString
      | .ok (reply,elapsed,announced) =>
        let passed ← try checkBody reply; pure true catch error =>
          failures := failures.push error.toString
          pure false
        let body := reply.bind fun value =>
          ((fromJson? value : Except String (Option Handoff)).toOption.join).map (·.text)
        if let some body := body then
          let sample := root/(if announced then "semantic-body.txt" else "fallback-body.txt")
          unless ← sample.pathExists do IO.FS.writeFile sample body
        queries := queries.push (Json.mkObj [("evidencePassed",toJson passed),
          ("elapsedMs",toJson elapsed),("ready",toJson announced),("replyPresent",toJson reply.isSome),
          ("bodySha256",toJson (body.map (fun text => Sha256.hex text.toUTF8)))])
        times := times.push elapsed
        if announced then ready := ready+1
    let mut durableSaves := 0
    let mut saveTimes := #[]
    for task in publications do
      match ← IO.wait task with
      | .error error => failures := failures.push error.toString
      | .ok elapsed =>
        durableSaves := durableSaves+1
        saveTimes := saveTimes.push elapsed
    let loadState ← serverStats
    let outcomes := Json.mkObj [("queries",toJson queries),("durableSaves",toJson durableSaves),
      ("writerClients",toJson writers.toArray),("errors",toJson failures),("server",loadState),
      ("saveMs",toJson saveTimes)]
    IO.FS.writeFile (root/"load-outcomes.json") (outcomes.pretty++"\n")
    check failures.isEmpty s!"mixed load failed: {failures.size}; see load-outcomes.json"
    if numerical then check (ready > 0) "no numeric query completed its semantic path"
    let drained ← idle ((← IO.monoMsNow)+60000)
    let pids ← searchPids drained
    check (pids.size ≤ OperationPlan.searchWorkers) "global search process bound overflowed"
    let some firstClient := clients[0]? | throw (IO.userError "missing empty-result client")
    let (empty,_,_) ← query firstClient 5000 true
    check (empty == some Json.null) "completed empty search became unavailable"
    let rejected ← Worker.exchange "foreign-save" "save" (Json.mkObj [
      ("session",toJson "foreign-save"),("path",toJson (root/"captured-turn.json").toString)]) ((← IO.monoMsNow)+2000)
    check rejected.isNone "foreign private save path was accepted"
    let cancelled ← cancellation original
    let preparationAudit ← inspectPreparation original
    let final ← idle ((← IO.monoMsNow)+15000)
    let ordered := times.qsort (· < ·)
    let orderedSaves := saveTimes.qsort (· < ·)
    let report := Json.mkObj [("allPassed",toJson true),("logicalSessionClients",toJson clients.size),
      ("concurrentSaves",toJson saves.size),("actualMiniLM",toJson numerical),("semanticReadyReplies",toJson ready),
      ("normalDeliveryFunction",toJson numerical),
      ("numericPreparationOnSaves",toJson numerical),
      ("lexicalFallbackReplies",toJson (if numerical then clients.size-ready else 0)),
      ("writerClients",toJson writers.toArray),("independentOriginalStreams",toJson writers.size),
      ("elapsedMs",toJson ((← IO.monoMsNow)-started)),("p50Ms",toJson (ordered[39]?)),
      ("p95Ms",toJson (ordered[75]?)),("maxMs",toJson (ordered[79]?)),("queryMs",toJson times),
      ("saveMs",toJson saveTimes),("saveP50Ms",toJson (orderedSaves[39]?)),
      ("saveP95Ms",toJson (orderedSaves[75]?)),("saveMaxMs",toJson (orderedSaves[79]?)),
      ("afterLoad",drained),("afterCancellation",final),("cancellation",cancelled),
      ("preparationAudit",preparationAudit),
      ("twoOriginalEvidenceItemsPerQuery",toJson true),("newerForeignOriginalAbsent",toJson true),
      ("completedEmptyPreserved",toJson true),("foreignSavePathRejected",toJson true),
      ("answeringModelCalls",toJson (0 : Nat)),("eightyPeopleEightHours",toJson false),
      ("requiredEvidence98Percent",toJson false),("productionAdoption",toJson false)]
    let name := if numerical then "numeric-execution-report.json" else "execution-report.json"
    IO.FS.writeFile (root/name) (report.pretty++"\n")
    IO.println report.compress
  finally
    Worker.shutdown
    try let _ ← Publication.Client.control "shutdown" catch _ => pure ()

end Eggshell.Research.ConcurrentHookChecks
