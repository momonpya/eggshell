import tools.research.SharedProjectLifecycle
import tools.research.RegisteredHook

open Lean Eggshell Eggshell.Plugin
open Eggshell.Research
namespace Eggshell.Research.SharedTrafficChecks
open SharedProjectLifecycle

structure Topic where
  number : Nat
  prompt : String
  required : Json
  source : Json
  frozen : Json
  deriving Inhabited

structure Input where
  installation : StudySeedChecks.Input
  original : String
  originalFiles : Array (String × String)
  workspace : String
  definitions : Json
  preparedReference : Option String := none
  activeReaders : Nat := 6
  llvmReaders : Nat := 6
  registered : Bool := false
  observeMaintenance : Bool := false
  deriving FromJson

def route (item : Case) (slot : Nat) : IO Case := do
  for suffix in [:1024] do
    let session := item.session++s!"-{suffix}"
    if ProjectStore.routeSlot session 4 == slot then return {item with session}
  throw (IO.userError "cannot route mixed writer to its declared source")

def activeCase (wave slot : Nat) : IO Case := route {
  session := s!"traffic-{wave}-{slot}",path := s!"src/traffic_{wave}_{slot}.cpp",
  symbol := s!"TRAFFIC_{wave}_{slot}_BASE",
  first := s!"int TRAFFIC_{wave}_{slot}_BASE = {100+wave*10+slot};",
  second := s!"int TRAFFIC_{wave}_{slot}_DETAIL = {900+wave*10+slot};"} slot

def config (runtime : String) (database : System.FilePath) (write : Bool) : String :=
  "default = \"work\"\nsemantic_matcher = "++(toJson #[runtime,"search-provider"]).compress++
  "\n[eggs]\nwork = "++(toJson database.toString).compress++
  "\n[profiles.work]\nread = [\"work\"]\nhandoff_chars = 500000\n"++
  (if write then "write = \"work\"\n" else "")

def beginWriter (plan : StudySeedChecks.Input) (root data configuration : System.FilePath)
    (item : Case) (registered : Bool := false) : IO Unit := do
  let invoke := fun session label event fields =>
    if registered then RegisteredHook.invoke plan root root data configuration session label event fields
    else hook plan root data configuration session label event fields
  discard <| invoke item.session "start" "SessionStart" []
  discard <| invoke item.session "prompt" "UserPromptSubmit"
    [("prompt",toJson "Inspect this new source investigation and record its evidence.")]

def settle (tasks : Array (Task (Except IO.Error Json))) : IO (Array Json × Bool) := do
  let settled := tasks.map (·.get)
  let rows := settled.map fun result => match result with
    | .ok value => value
    | .error error => Json.mkObj [("error",toJson error.toString)]
  return (rows,settled.all (·.isOk))

def readerHook (plan : StudySeedChecks.Input) (root workspace data configuration : System.FilePath)
    (session label event : String) (prompt : String := "") (registered : Bool := false) : IO StudyCommand.Result := do
  if registered then
    return ← RegisteredHook.invoke plan root workspace data configuration session label event [("prompt",toJson prompt)]
  let environment := replaceEnv plan.environment #[("EGGSHELL_DATA_ROOT",some data.toString),
    ("EGGSHELL_CONFIG",some configuration.toString),("EGGSHELL_PROFILE",some "work"),
    ("CODEX_THREAD_ID",some session),("CODEX_TURN_ID",some "recorded-turn"),
    ("TMPDIR",some (root/"tmp"/session).toString)]
  let directory := root/"calls"/session
  IO.FS.createDirAll directory
  let request := Json.mkObj [("hook_event_name",toJson event),("session_id",toJson session),
    ("turn_id",toJson "recorded-turn"),("cwd",toJson workspace.toString),
    ("_eggshell_config",toJson configuration.toString),("prompt",toJson prompt)]
  let output ← StudyCommand.run plan.runtime.path #["codex-hook"] environment workspace.toString
    (request.compress++"\n") (directory/label) 35000
  check (output.exitCode == 0 && output.elapsedMs < 30000) "mixed reader hook failed or exceeded its deadline"
  return output

def read (plan : StudySeedChecks.Input) (root workspace data configuration : System.FilePath)
    (session prompt : String) (required : Array String) (registered : Bool := false) : IO Json := do
  let started ← IO.monoMsNow
  let output ← readerHook plan root workspace data configuration session "prompt" "UserPromptSubmit" prompt registered
  let finished ← IO.monoMsNow
  let parsed ← IO.ofExcept (Json.parse output.stdout)
  let body ← IO.ofExcept ((parsed.getObjValD "hookSpecificOutput").getObjValAs? String "additionalContext")
  let path := root/"calls"/session/"body.txt"
  IO.FS.writeFile path body
  let state ← (readJson? (data/"sessions"/session/"state.json") stateJsonDefaults : IO (Option ThreadState))
  let missing := required.filter (!body.contains ·)
  return Json.mkObj [("session",toJson session),("startedMs",toJson started),("finishedMs",toJson finished),
    ("elapsedMs",toJson output.elapsedMs),("body",toJson path.toString),
    ("bodySha256",toJson (Sha256.hex body.toUTF8)),("missing",toJson missing),
    ("search",toJson (state.bind (·.lastSearch))),("completeBody",toJson (!body.contains "EGGSHELL SEARCH INCOMPLETE"))]

def auditTopic (topic : Topic) (database root : System.FilePath) (row : Json) : IO Json := do
  let session ← IO.ofExcept (row.getObjValAs? String "session")
  let calls := root/"calls"/session
  let input := root/(session++"-audit-input.json")
  save input (Json.mkObj [("source",topic.source),("database",toJson database.toString),
    ("request",toJson (calls/"prompt/stdin").toString),("stdout",toJson (calls/"prompt/stdout").toString),
    ("timing",toJson (calls/"prompt/record.json").toString),("body",row.getObjValD "body")])
  let audit ← NativeTrialAudit.inspect input.toString
  check (audit.getObjValD "availableEvidence" == topic.frozen) "mixed-load denominator changed after delivery"
  return Json.mkObj [("topic",toJson topic.number),("delivery",row),
    ("requiredDelivery",audit.getObjValD "requiredDelivery"),("availableDelivery",audit.getObjValD "availableDelivery")]

def waitAnswers (project : ProjectStore.Project) (items : Array Case) : IO Json := do
  let started ← IO.monoMsNow
  let wanted := items.map answer
  repeat
    let mut present : Array String := #[]
    for slot in [:project.manifest.owners.size] do
      let source ← project.current slot
      let reader ← Persistence.Store.NodeReader.new source
      for candidate in ← Persistence.Store.searchDocuments source do
        let doc ← Synapses.Build.document reader candidate.owner
        for message in wanted do
          if doc.source.any (·.contains message) then present := present.push message
    let missing := wanted.filter (!present.contains ·)
    if missing.isEmpty then return Json.mkObj [("expected",toJson wanted.size),
      ("persisted",toJson wanted.size),("elapsedMs",toJson ((← IO.monoMsNow)-started)),("manualKeepUsed",toJson false)]
    check ((← IO.monoMsNow) < started+20000) "automatic Stop checkpoint did not publish every final answer"
    IO.sleep 25
  throw (IO.userError "unreachable automatic answer wait")

def extraEvents (plan : StudySeedChecks.Input) (root workspace data config : System.FilePath)
    (session : String) : IO Json := do
  let mut rows := #[]
  for (label,event,fields) in [
      ("compact-start","SessionStart",[("source",toJson "compact")]),
      ("post-compact","PostCompact",[]),("interrupt","Interrupt",[]),("end","SessionEnd",[])] do
    let result ← RegisteredHook.invoke plan root workspace data config session label event fields
    rows := rows.push (Json.mkObj [("event",toJson event),("elapsedMs",toJson result.elapsedMs)])
  return Json.mkObj [("session",toJson session),("events",toJson rows)]

/-- Read-only frontend statistics and one bounded native stack sample when
publication has not caught up. The original census deadline is not extended. -/
def observedCensus (root : System.FilePath) (wave : Nat) (project : ProjectStore.Project)
    (expected : Nat) : IO Json := do
  let directory := root/"maintenance"/s!"wave-{wave}"
  IO.FS.createDirAll directory
  let started ← IO.monoMsNow
  let next ← IO.mkRef started
  let sampled ← IO.mkRef false
  let history ← IO.mkRef (#[] : Array Json)
  let observe : Nat → Array Json → IO Unit := fun count rows => do
    let now ← IO.monoMsNow
    if now < (← next.get) && count != expected then return
    next.set (now+1000)
    let stats ← try
        let endpoint ← Daemon.loadEndpoint "shared-traffic"
        let raw ← Daemon.exchangeBefore endpoint "stats" (Json.mkObj []) (now+1000)
        IO.ofExcept (Json.parse raw)
      catch error => pure (Json.mkObj [("error",toJson error.toString)])
    history.modify (·.push (Json.mkObj [("elapsedMs",toJson (now-started)),("count",toJson count),
      ("expected",toJson expected),("frontend",stats)]))
    save (directory/"progress.json") (toJson (← history.get))
    save (directory/"latest-source.json") (Json.mkObj [("count",toJson count),("sources",toJson rows)])
    if count < expected && now ≥ started+3000 && !(← sampled.get) then
      sampled.set true
      let endpoint ← Daemon.loadEndpoint "shared-traffic"
      let result ← StudyCommand.run "/usr/bin/sample" #[toString endpoint.pid,"1","1","-file",(directory/"frontend.sample").toString]
        #[] root.toString "" (directory/"sample-command") 4000
      check (result.exitCode == 0) "bounded native maintenance sample failed"
  census project expected observe

/-- Read-only postmortem of the actual project. It never resumes publishing,
warms an index, or turns a failed timed census into a passing traffic run. -/
def inspect (directory report : String) : IO Unit := do
  let root := System.FilePath.mk directory
  let project ← ProjectStore.openProject (root/"active.egg")
  let mut wanted : Array Case := #[]
  for wave in [:3] do
    for slot in [:4] do wanted := wanted.push (← activeCase wave slot)
  let mut sources := #[]
  let mut count := 0
  let mut answers : Array String := #[]
  for slot in [:project.manifest.owners.size] do
    let source ← project.current slot
    let before ← StudyRuntime.files source.directory
    let records ← Synapses.Provenance.records source
    count := count+records.size
    let reader ← Persistence.Store.NodeReader.new source
    for candidate in ← Persistence.Store.searchDocuments source do
      let document ← Synapses.Build.document reader candidate.owner
      for item in wanted do
        if document.source.any (·.contains (answer item)) && !answers.contains item.session then
          answers := answers.push item.session
    check ((← StudyRuntime.files source.directory) == before) "inspection changed the saved project"
    sources := sources.push (Json.mkObj [("slot",toJson slot),("head",toJson source.head),
      ("origins",toJson (records.map (·.origin))),("files",toJson before)])
  check (!(← (System.FilePath.mk report).pathExists)) "preserve previous native inspection"
  save (.mk report) (Json.mkObj [("observations",toJson count),("sources",toJson sources),
    ("answerSessions",toJson answers),("readOnly",toJson true),("warmOrSaveResumed",toJson false)])

/-- Resume durable work after the failed traffic run, without replaying a hook,
issuing keep/warm, or relabeling the original timeout as success. -/
def resume (inputPath directory report : String) : IO Unit := do
  let input ← IO.ofExcept (fromJson? (α := Input) (← StudyAdmission.readJson inputPath))
  let plan := input.installation
  StudyAdmission.verifyArtifact plan.runtime
  let root := System.FilePath.mk directory
  let data := root/"data"
  let mut waiting : Array String := #[]
  for entry in ← (data/"sessions").readDir do
    let queue := entry.path/"checkpoints"
    if !(← queue.pathExists) then continue
    if (← queue.readDir).any (·.fileName.endsWith ".json") then
      waiting := waiting.push entry.fileName
  check (!waiting.isEmpty) "recovery must start with actual retained work"
  let project ← ProjectStore.openProject (root/"active.egg")
  let before ← originals project
  let publisher ← StudyRuntime.startPublisher (.mk plan.runtime.path) data plan.environment
  let frontend ← try
      StudyRuntime.startManaged (.mk plan.runtime.path) (.mk plan.pluginRoot) waiting[0]! (data/"daemon.json") plan.environment
    catch error =>
      StudyRuntime.stopManaged publisher (root/"resume-publisher-startup-stop.json")
      throw error
  let started ← IO.monoMsNow
  let result ← try
      let endpoint ← Daemon.loadEndpoint waiting[0]!
      for session in waiting do
        discard <| Daemon.exchangeBefore endpoint "register" (Json.mkObj [("session_id",toJson session)]) ((← IO.monoMsNow)+2000)
      let observed ← census project 36
      let items ← (List.range 4).toArray.mapM (activeCase 2)
      let answers ← waitAnswers project items
      pure (Json.mkObj [("census",observed),("answers",answers),
        ("elapsedMs",toJson ((← IO.monoMsNow)-started)),("success",toJson true)])
    catch error => pure (Json.mkObj [("error",toJson error.toString),
      ("elapsedMs",toJson ((← IO.monoMsNow)-started)),("success",toJson false)])
    finally
      try StudyRuntime.stopManaged frontend (root/"resume-frontend-stop.json")
      finally StudyRuntime.stopManaged publisher (root/"resume-publisher-stop.json")
  save (.mk report) (Json.mkObj [("result",result),("waitingSessions",toJson waiting),("before",before),
    ("after",← originals project),("manualKeepOrWarmUsed",toJson false),
    ("originalTrafficPassed",toJson false),("product",toJson plan.runtime)])
  check (result.getObjValD "success" == toJson true) "retained work did not resume within its original census bounds"

def run (inputPath directory : String) : IO Unit := do
  let input ← IO.ofExcept (fromJson? (α := Input) (← StudyAdmission.readJson inputPath))
  let plan := input.installation
  let readerCount := input.activeReaders+input.llvmReaders
  check (input.activeReaders > 0 && (input.llvmReaders == 3 || input.llvmReaders == 6) &&
    10 ≤ readerCount+4 && readerCount+4 ≤ 16) "mixed profile must respect the local 10-to-16-client bound"
  StudyAdmission.verifyArtifact plan.runtime
  for file in plan.pluginFiles do StudyAdmission.verifyArtifact file
  StudySeedChecks.requireNumericalSupport plan
  let original := System.FilePath.mk input.original
  check ((← StudyRuntime.files original) == input.originalFiles) "protected LLVM source changed"
  let root := System.FilePath.mk directory
  check (root.isAbsolute && !(← root.pathExists)) "fresh mixed-traffic directory required"
  IO.FS.createDirAll (root/"src")
  let database := input.preparedReference.map System.FilePath.mk |>.getD (root/"llvm.egg")
  if input.preparedReference.isSome then
    check ((← StudyRuntime.files database) == input.originalFiles) "prepared reference changed its original snapshot"
  else
    StudyRuntime.restore original database
    let originalSnapshot ← DB.PageMap.pin original
    let copySnapshot ← DB.PageMap.pin database
    let hints ← DB.Sidecar.locate originalSnapshot .database
    let destination ← DB.Sidecar.locate copySnapshot .database
    check ((← VectorMatrix.open? hints.semantic MiniLM.model SearchProvider.encoderContract).isSome)
      "the fixed real source has no reusable committed numerical preparation"
    IO.FS.createDirAll destination.semantic.parent.get!
    let copied ← IO.Process.output {cmd := "/bin/cp",args := #["-cR",hints.semantic.toString,destination.semantic.toString]}
    check (copied.exitCode == 0) "could not clone existing source-only numerical hints"
  let active ← ProjectStore.create (root/"active.egg") 4
  let mut topics := #[]
  for definition in ← IO.ofExcept input.definitions.getArr? do
    let number ← IO.ofExcept (definition.getObjValAs? Nat "topic")
    let promptPath ← IO.ofExcept ((definition.getObjValD "prompt").getObjValAs? String "path")
    let expected ← IO.ofExcept ((definition.getObjValD "prompt").getObjValAs? String "sha256")
    check ((← ArtifactHash.hex (.mk promptPath)) == expected) "LLVM question changed"
    let prompt ← IO.FS.readFile (.mk promptPath)
    let source := Json.mkObj [("source",toJson input.original),("files",toJson input.originalFiles),
      ("workspace",toJson input.workspace),("prompt",toJson prompt),("required",definition.getObjValD "referenceRanges")]
    let frozen ← NativeTrialAudit.freezeAvailable source
    topics := topics.push ({number,prompt,required := definition.getObjValD "referenceRanges",source,frozen := toJson frozen} : Topic)
  check (topics.size == 3) "all three LLVM topics required"
  save (root/"frozen-before-delivery.json") (toJson (topics.map fun topic =>
    Json.mkObj [("topic",toJson topic.number),("source",topic.source),("frozen",topic.frozen)]))
  let data := root/"data"
  IO.FS.createDir data
  let writerConfig := root/"active.toml"
  let readerConfig := root/"active-read.toml"
  let llvmWarm := root/"llvm-warm.toml"
  let llvmRead := root/"llvm-read.toml"
  let invokeWriter := fun session label event fields =>
    if input.registered then RegisteredHook.invoke plan root root data writerConfig session label event fields
    else hook plan root data writerConfig session label event fields
  for (path,db,writable) in [(writerConfig,active.directory,true),(readerConfig,active.directory,false),
      (llvmWarm,database,true),(llvmRead,database,false)] do
    IO.FS.writeFile path (config plan.runtime.path db writable)
  let environment := replaceEnv plan.environment #[("EGGSHELL_DATA_ROOT",some data.toString),
    ("CODEX_THREAD_ID",none),("CODEX_TURN_ID",none)]
  let publisher ← StudyRuntime.startPublisher (.mk plan.runtime.path) data environment
  let frontend ← try
      StudyRuntime.startManaged (.mk plan.runtime.path) (.mk plan.pluginRoot)
        "shared-traffic" (data/"daemon.json") environment
    catch error =>
      StudyRuntime.stopManaged publisher (root/"publisher-startup-stop.json")
      throw error
  let mut waves := #[]
  try
    save (root/"llvm-warm.json") (← warm plan root data llvmWarm "llvm-ready")
    let baseline ← (List.range 4).toArray.mapM (activeCase 0)
    for item in baseline do IO.FS.writeFile (root/item.path) (item.first++"\n"++item.second++"\n")
    let tasks ← baseline.mapM fun item => IO.asTask
      (writer plan root data writerConfig active.directory item true 1 invokeWriter (!input.registered)) .dedicated
    let (recorded,ok) ← settle tasks
    save (root/"baseline-writers.json") (toJson recorded)
    check ok "baseline actual writer failed"
    if input.registered then
      save (root/"baseline-auto-answers.json") (← waitAnswers active baseline)
    save (root/"baseline-warm.json") (← warm plan root data writerConfig "baseline-ready")
    if input.registered then save (root/"baseline-facts.json") (← graphFacts active)
    let required := baseline.flatMap fun item => #[item.first,item.second]
    save (root/"active-before-delivery.json") (Json.mkObj [("originals",← originals active),
      ("census",← census active 12),("required",toJson required)])
    let llvmBefore ← StudyRuntime.files database
    for wave in [1:4] do
      let writers ← (List.range 4).toArray.mapM (activeCase wave)
      let mut beginTasks := #[]
      for item in writers do
        IO.FS.writeFile (root/item.path) (item.first++"\n"++item.second++"\n")
        beginTasks := beginTasks.push (← IO.asTask (beginWriter plan root data writerConfig item input.registered) .dedicated)
      for result in beginTasks.map (·.get) do discard <| IO.ofExcept (result.mapError IO.Error.toString)
      for index in [:readerCount] do
        let configuration := if index < input.activeReaders then readerConfig else llvmRead
        let workspace := if index < input.activeReaders then root else .mk input.workspace
        discard <| readerHook plan root workspace data configuration s!"reader-{wave}-{index}" "start" "SessionStart" "" input.registered
      let gate ← IO.mkRef false
      let started ← IO.monoMsNow
      let mut tasks := #[]
      for item in writers do
        tasks := tasks.push (← IO.asTask (do
          while !(← gate.get) do IO.sleep 1
          let begin ← IO.monoMsNow
          let output ← writer plan root data writerConfig active.directory item false 1 invokeWriter (!input.registered)
          return Json.mkObj [("kind",toJson "writer"),("startedMs",toJson begin),
            ("finishedMs",toJson (← IO.monoMsNow)),("output",output)]) .dedicated)
      for index in [:readerCount] do
        tasks := tasks.push (← IO.asTask (do
          while !(← gate.get) do IO.sleep 1
          let session := s!"reader-{wave}-{index}"
          if index < input.activeReaders then
            return Json.mkObj [("kind",toJson "active-reader"),("delivery",← read plan root root data readerConfig session
              "Show the original TRAFFIC_0 BASE and DETAIL source definitions from the baseline shared investigations." required input.registered)]
          let topic := topics[(index-input.activeReaders)%3]!
          return Json.mkObj [("kind",toJson "llvm-reader"),("topic",toJson topic.number),
            ("delivery",← read plan root (.mk input.workspace) data llvmRead session topic.prompt #[] input.registered)]) .dedicated)
      gate.set true
      let (outcomes,ok) ← settle tasks
      let elapsed := (← IO.monoMsNow)-started
      save (root/s!"wave-{wave}-outcomes.json") (Json.mkObj [("elapsedMs",toJson elapsed),
        ("outcomes",toJson outcomes),("allProcessesSucceeded",toJson ok)])
      check ok "mixed traffic had an actual hook/save failure; see settled outcomes"
      for outcome in outcomes do
        let kind := outcome.getObjValD "kind"
        if kind == toJson "writer" then continue
        let delivery := outcome.getObjValD "delivery"
        check (delivery.getObjValD "completeBody" == toJson true) "mixed reader returned incomplete notification"
        if kind == toJson "active-reader" then
          check (delivery.getObjValD "missing" == toJson (#[] : Array String) &&
            delivery.getObjValD "completeBody" == toJson true) "active publication caused lost baseline evidence"
      save (root/s!"wave-{wave}-census.json") (← if input.observeMaintenance then
        observedCensus root wave active (12+wave*12) else census active (12+wave*12))
      if input.registered then
        save (root/s!"wave-{wave}-auto-answers.json") (← waitAnswers active writers)
      save (root/s!"wave-{wave}-drain.json") (← warm plan root data writerConfig s!"wave-{wave}-ready")
      if input.registered then
        save (root/s!"wave-{wave}-facts.json") (← graphFacts active)
        let mut fast := #[]
        for index in [:readerCount] do
          let configuration := if index < input.activeReaders then readerConfig else llvmRead
          let workspace := if index < input.activeReaders then root else .mk input.workspace
          fast := fast.push (← IO.asTask (extraEvents plan root workspace data configuration s!"reader-{wave}-{index}") .dedicated)
        let (events,ok) ← settle fast
        save (root/s!"wave-{wave}-fast-events.json") (toJson events)
        check ok "a registered fast lifecycle event failed"
      check ((← StudyRuntime.files database) == llvmBefore) "active project wrote into the LLVM reference DB"
      waves := waves.push (Json.mkObj [("wave",toJson wave),("elapsedMs",toJson elapsed),
        ("outcomes",toJson outcomes)])
      save (root/"waves.json") (toJson waves)
  catch error =>
    save (root/"failure.json") (Json.mkObj [("error",toJson error.toString),("observedMs",toJson (← IO.monoMsNow)),
      ("completedWaves",toJson waves.size),("observeMaintenance",toJson input.observeMaintenance)])
    throw error
  finally
    try StudyRuntime.stopManaged frontend (root/"frontend-stop.json")
    finally StudyRuntime.stopManaged publisher (root/"publisher-stop.json")
  -- Full original-prefix audits read large immutable snapshots. Keep this
  -- independent verification out of the live service's traffic/RSS interval.
  let mut checkedWaves := #[]
  for wave in waves do
    let mut audits := #[]
    for outcome in ← IO.ofExcept ((wave.getObjValD "outcomes").getArr?) do
      if outcome.getObjValD "kind" != toJson "llvm-reader" then continue
      let number ← IO.ofExcept (outcome.getObjValAs? Nat "topic")
      let some topic := topics.find? (·.number == number) | throw (IO.userError "unknown LLVM topic")
      audits := audits.push (← auditTopic topic database root (outcome.getObjValD "delivery"))
    let number ← IO.ofExcept (wave.getObjValAs? Nat "wave")
    save (root/s!"wave-{number}-audits.json") (toJson audits)
    check (audits.all fun audit => (audit.getObjValD "requiredDelivery").getObjValD "targetMet" == toJson true &&
      (audit.getObjValD "availableDelivery").getObjValD "targetMet" == toJson true) "LLVM original evidence was omitted under mixed traffic"
    checkedWaves := checkedWaves.push (wave.setObjVal! "llvmAudits" (toJson audits))
  check ((← StudyRuntime.files original) == input.originalFiles) "protected original changed"
  save (root/"result.json") (Json.mkObj [("runtime",toJson plan.runtime),("waves",toJson checkedWaves),
    ("clientsPerWave",toJson (readerCount+4)),("answeringModelCalls",toJson (0 : Nat)),
    ("fullOriginalAuditAfterServicesStopped",toJson true),
    ("registeredCommands",toJson input.registered),("explicitKeepUsed",toJson (!input.registered)),
    ("seedAccepted",toJson false),("adopted",toJson false)])

end Eggshell.Research.SharedTrafficChecks
