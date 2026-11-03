import tools.research.ProjectExecutionChecks

open Lean Eggshell Eggshell.Plugin

namespace Eggshell.Research.PreparationDrainChecks

private def check (value : Bool) (message : String) : IO Unit :=
  unless value do throw (IO.userError message)

private def natural (value : Json) (key : String) : Nat :=
  (value.getObjValAs? Nat key).toOption.getD 0

private def stats : IO Json := do IO.ofExcept (Json.parse (← Publication.Client.control "stats"))

private partial def hasAtom (value : Value) (bytes : ByteArray) : Bool :=
  match value with
  | .atom original => original == bytes
  | .apply _ children => children.toList.any (fun (_,child) => hasAtom child bytes)

private def waitPrepared (root : System.FilePath) : IO Json := do
  let started ← IO.monoMsNow
  let mut samples := #[]
  let mut last := ""
  repeat
    let value := (← stats).getObjValD "preparation"
    let key := (toJson (natural value "pending",natural value "active",natural value "retries",
      natural value "finishedAttempts")).compress
    if key != last then
      samples := samples.push (Json.mkObj [("elapsedMs",toJson ((← IO.monoMsNow)-started)),("state",value)])
      last := key
    let complete := natural value "pending" == 0 && natural value "active" == 0
    let elapsed := (← IO.monoMsNow)-started
    if complete || elapsed ≥ 120000 then
      let result := Json.mkObj [("complete",toJson complete),("elapsedMs",toJson elapsed),
        ("samples",toJson samples),("foregroundDeadlineChanged",toJson false)]
      IO.FS.writeFile (root/"drain-observation.json") (result.pretty++"\n")
      check complete "normal preparation did not drain within its observation window"
      return result
    IO.sleep 100
  throw (IO.userError "unreachable preparation observation")

private def freshQuery (original : PendingTurn) (name : String) (command : List String)
    (marker : String := "CONCURRENT_ORIGINAL_79") (recordRoot : Option System.FilePath := none) : IO Json := do
  let started ← IO.monoMsNow
  let draft := {original with
    sessionId := name,turnId := "after-drain",projectInputs := none,
    prompt := s!"Find the stored {marker} original observation.",
    semanticMatcher := some command,tools := [],inFlight := [],finalMessage := none,closed := false}
  let pending ← ProjectContext.capture draft (started+20000)
  let files ← sessionFiles name
  writeJson files.state ({profile := pending.profile} : ThreadState)
  writeJson files.pending pending
  let input := Json.mkObj [("_eggshell_deadline",toJson (started+28000)),
    ("_eggshell_receipt",toJson (← Receipt.fresh))]
  let handoff ← deliverForWork input pending pending.prompt false
  let evidence := handoff.any (fun value => value.reason != "search-incomplete" &&
    value.text.contains ("\""++marker++"\""))
  if let some recordRoot := recordRoot then
    IO.FS.writeFile (recordRoot/(name++"-body.txt")) (handoff.map (·.text) |>.getD "")
  let semantic := handoff.any fun value => value.search.any fun trace =>
    match trace.semantic with | .completed => true | _ => false
  return Json.mkObj [("evidence",toJson evidence),("semantic",toJson semantic),
    ("elapsedMs",toJson ((← IO.monoMsNow)-started)),("trace",toJson (handoff.bind (·.search))),
    ("bodySha256",toJson (handoff.map fun value => Sha256.hex value.text.toUTF8))]

private def inspect (root : System.FilePath) (original : PendingTurn) : IO Json := do
  let some context ← ProjectContext.open? original ((← IO.monoMsNow)+20000) |
    throw (IO.userError "drain audit lost its captured original context")
  let some write := context.selection.write | throw (IO.userError "no selected write project")
  let before ← ProjectStore.pin write.project ((← IO.monoMsNow)+20000)
  let drained ← waitPrepared root
  let mut values := []
  for source in before.sources do values := values++(← Persistence.Store.materialize source).values
  for index in [:80] do
    let expected := (Json.mkObj [("evidence",toJson s!"CONCURRENT_ORIGINAL_{index}")]).compress.toUTF8
    check (values.any (hasAtom · expected)) s!"durable original {index} was not materialized exactly"
  let some command ← MiniLM.command (← Paths.installRoot) | throw (IO.userError "actual MiniLM required")
  let sources := write.project.manifest.owners.map (·.identity)
  let targets := (← registeredIndexTargets (some sources)).filter fun (_,target) => target.command == command
  check (targets.length == sources.size) "current numerical targets omitted an original stream"
  let mut inspections := #[]
  for (_,target) in targets do
    let source ← target.owner.pin
    let job ← PreparationRegistry.request "index" target.key
    let done ← PreparationRegistry.drained job
    let conservative ← PreparationRegistry.complete job
    let options ← Warm.options source command target.storage
    let inspected ← Warm.inspect source options
    inspections := inspections.push (Json.mkObj [("source",toJson source.head),
      ("drained",toJson done),("conservativeComplete",toJson conservative),
      ("coverage",toJson inspected.coverage),("needed",toJson inspected.needed.length)])
    IO.FS.writeFile (root/"coverage-audit.json") ((toJson inspections).pretty++"\n")
    check (done && inspected.needed.isEmpty && inspected.coverage.missing == 0 &&
      inspected.coverage.invalid == 0) "idle preparation left a cold or invalid numerical source"
  let after ← ProjectStore.pin write.project ((← IO.monoMsNow)+20000)
  check (before.cut == after.cut) "derived preparation changed authoritative original heads"
  let query ← freshQuery original "drain-new-reader" command
  IO.FS.writeFile (root/"new-query.json") (query.pretty++"\n")
  check (query.getObjValD "evidence" == toJson true) "newly stored original did not reach a new native query"
  let some endpoint ← Publication.Client.endpoint? | throw (IO.userError "no service to restart")
  let _ ← Publication.Client.control "shutdown"
  check (!(← Numerical.alive endpoint.pid)) "shutdown reply preceded actual service exit"
  let recovered ← freshQuery original "drain-restarted-reader" command
  IO.FS.writeFile (root/"restart-query.json") (recovered.pretty++"\n")
  check (recovered.getObjValD "evidence" == toJson true) "service restart lost the newly stored original"
  let result := Json.mkObj [("originalResponses",toJson (80 : Nat)),("originalHeadsUnchanged",toJson true),
    ("drain",drained),("inspections",toJson inspections),("newQuery",query),("restartQuery",recovered),
    ("serviceRestarted",toJson true),("answeringModelCalls",toJson (0 : Nat)),
    ("eightHourCapacity",toJson false),("productionAdoption",toJson false)]
  IO.FS.writeFile (root/"drain-audit.json") (result.pretty++"\n")
  return result

private def signal (pids : Array Nat) (kind : String) : IO Unit := do
  for pid in pids do
    let _ ← IO.Process.output {cmd := "/bin/kill",args := #[kind,toString pid]}
    pure ()

private def interruptedSave (original : PendingTurn) (command : List String) (index : Nat) : IO Unit := do
  let pending := {original with
    sessionId := s!"paused-save-{index}",turnId := "after-drain-source",semanticMatcher := some command,
    tools := [],inFlight := [],finalMessage := none,closed := false}
  let files ← sessionFiles pending.sessionId
  writeJson files.state ({profile := pending.profile} : ThreadState)
  writeJson files.pending pending
  let tool : ToolEvent := {
    name := "mcp__fixture__inspect",useId := s!"after-drain-{index}",
    input := (Json.mkObj [("case",toJson index)]).compress,
    response := (Json.mkObj [("evidence",toJson s!"INTERRUPTED_ORIGINAL_{index}")]).compress}
  let domain := Sha256.hex "interrupted-preparation-fixture".toUTF8
  let clock := fun time => Json.mkObj [("_eggshell_synapse_clock",toJson domain),
    ("_eggshell_synapse_nanos",toJson time)]
  Synapses.Live.start (clock (index*2+1)) files pending {profile := pending.profile} tool
  Synapses.Live.finish (clock (index*2+2)) pending tool
  let closed := {pending with tools := [tool],finalMessage := some s!"Recorded `INTERRUPTED_ORIGINAL_{index}`.",closed := true}
  let path := files.directory/"deferred"/"interrupted-save.json"
  FileSystem.privateDirectory path.parent.get!
  writeJson path closed
  let some reply ← Worker.exchange pending.sessionId "save" (Json.mkObj [
      ("session",toJson pending.sessionId),("path",toJson path.toString)]) ((← IO.monoMsNow)+60000) |
    throw (IO.userError "paused preparation prevented a source save reply")
  let .published saved ← IO.ofExcept (NativePublication.SaveReply.check? reply) |
    throw (IO.userError "paused preparation prevented original publication")
  check (saved.publication.accounted && saved.publication.awaiting == 0) "paused save lost its durable original ACK"

private def interrupt (root : System.FilePath) (retry : Bool := false) : IO Unit := do
  let original ← IO.ofExcept (Json.parse (← IO.FS.readFile (root/"captured-turn.json")) >>= fromJson? (α := PendingTurn))
  let directory := root/(if retry then "interruption-retry" else "interruption")
  FileSystem.privateDirectory directory
  let some command ← MiniLM.command (← Paths.installRoot) | throw (IO.userError "actual MiniLM required")
  let some context ← ProjectContext.open? original ((← IO.monoMsNow)+20000) | throw (IO.userError "no captured context")
  let some write := context.selection.write | throw (IO.userError "no selected project")
  let targets := (← registeredIndexTargets (some (write.project.manifest.owners.map (·.identity)))).filter
    fun (_,target) => target.command == command
  let some (_,target) := targets.head? | throw (IO.userError "no numerical preparation target")
  let accepted ← Publication.Client.enqueuePreparation "index" target.key ((← IO.monoMsNow)+5000)
  check accepted "could not establish preparation worker"
  let _ ← waitPrepared directory
  let before ← stats
  let pipes ← IO.ofExcept (before.getObjValAs? (Array Json) "workerPipes")
  let pids := pipes.filterMap fun entry => do
    let key ← (entry.getObjValAs? String "key").toOption
    if !key.startsWith "project-preparation-" || !key.endsWith ":index" then none
    else (entry.getObjValAs? Nat "pid").toOption
  check (!pids.isEmpty) "no owned idle index worker to pause"
  let paused ← IO.mkRef pids
  signal pids "-STOP"
  try
    try
      let started ← IO.monoMsNow
      let previous ← ProjectStore.pin write.project ((← IO.monoMsNow)+20000)
      let saves ← (List.range 24).toArray.mapM fun index => IO.asTask (interruptedSave original command index) .dedicated
      for task in saves do IO.ofExcept (← IO.wait task)
      let stopped := (← stats).getObjValD "preparation"
      let mut tickets := 0
      for (_,target) in targets do
        let source ← target.owner.pin
        let path ← target.indexes source
        for entry in ← path.readDir do if entry.fileName.endsWith ".json" then tickets := tickets+1
      let source ← ProjectStore.pin write.project ((← IO.monoMsNow)+20000)
      check ((source.cut == previous.cut) == retry) "original publication did not match the new/retry scenario"
      let pending := Json.mkObj [("durableSaves",toJson (24 : Nat)),("saveBatchMs",toJson ((← IO.monoMsNow)-started)),
        ("idempotentRetry",toJson retry),
        ("pausedWorkers",toJson pids.size),("tickets",toJson tickets),("state",stopped),("sourceCut",toJson source.cut)]
      IO.FS.writeFile (directory/"before-stop.json") (pending.pretty++"\n")
      check (tickets > 0 && natural stopped "active" > 0) "test did not retain genuine interrupted preparation debt"
      let some endpoint ← Publication.Client.endpoint? | throw (IO.userError "no interrupted service")
      let _ ← Publication.Client.control "shutdown"
      check (!(← Numerical.alive endpoint.pid)) "interrupted service still owns its sources"
      for pid in pids do check (!(← Numerical.alive pid)) "stopped index worker survived service shutdown"
      -- No resume may address retired PIDs after the long recovery phase.
      paused.set #[]
      let _ ← Publication.Client.resolve
      let discovered ← flushIndexesResult original.sessionId ((← IO.monoMsNow)+20000)
      check discovered "normal manager recovery did not admit durable preparation"
      let drained ← waitPrepared directory
      let after ← ProjectStore.pin write.project ((← IO.monoMsNow)+20000)
      check (after.cut == source.cut) "interrupted preparation recovery changed original heads"
      let mut values := []
      for source in after.sources do values := values++(← Persistence.Store.materialize source).values
      for index in [:24] do
        let expected := (Json.mkObj [("evidence",toJson s!"INTERRUPTED_ORIGINAL_{index}")]).compress.toUTF8
        check (values.any (hasAtom · expected)) "recovery lost an acknowledged original response"
      let mut windows := 0
      for (_,target) in targets do
        let source ← target.owner.pin
        let job ← PreparationRegistry.request "index" target.key
        check (← PreparationRegistry.drained job) "restarted worker retained original preparation debt"
        let inspected ← Warm.inspect source (← Warm.options source command target.storage)
        check inspected.needed.isEmpty "restarted source has missing or invalid vectors"
        windows := windows+inspected.coverage.windows
      let query ← freshQuery original "interrupted-new-reader" command "INTERRUPTED_ORIGINAL_23" (some directory)
      IO.FS.writeFile (directory/"new-query.json") (query.pretty++"\n")
      check (query.getObjValD "evidence" == toJson true) "interrupted original did not reach the new native query"
      let result := Json.mkObj [("allPassed",toJson true),("beforeStop",pending),("recoveryDrain",drained),
        ("windows",toJson windows),("allCurrentVectorsValid",toJson true),("originalHeadsUnchanged",toJson true),
        ("originalResponses",toJson (24 : Nat)),("normalManagerRecovery",toJson true),("newQuery",query),
        ("answeringModelCalls",toJson (0 : Nat)),("eightHourCapacity",toJson false),("productionAdoption",toJson false)]
      IO.FS.writeFile (directory/"report.json") (result.pretty++"\n")
      IO.println result.compress
    finally signal (← paused.get) "-CONT"
  finally
    Worker.shutdown
    try let _ ← Publication.Client.control "shutdown" catch _ => pure ()

end Eggshell.Research.PreparationDrainChecks

def main (args : List String) : IO UInt32 := do
  match args with
  | ["drain",root] =>
    Numerical.withDefaultKeeper (do
      let path : System.FilePath := .mk root
      Eggshell.Research.ProjectExecutionChecks.exercise path true
        (Eggshell.Research.PreparationDrainChecks.inspect path)
      return 0) (drainMs := 1000)
  | ["interrupt-preparation",root] =>
    Numerical.withDefaultKeeper (do
      Eggshell.Research.PreparationDrainChecks.interrupt (.mk root)
      return 0) (drainMs := 1000)
  | ["interrupt-retry",root] =>
    Numerical.withDefaultKeeper (do
      Eggshell.Research.PreparationDrainChecks.interrupt (.mk root) true
      return 0) (drainMs := 1000)
  | other => projectExecutionMain other
