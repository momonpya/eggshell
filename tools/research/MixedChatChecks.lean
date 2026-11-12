import Main
import Eggshell.ContractAudit
import tools.research.SharedTrafficChecks
import tools.research.SourceBlocks
open Lean Eggshell Eggshell.Plugin Eggshell.Research
open Eggshell.Research.SharedProjectLifecycle
namespace MixedChatChecks

structure Turn where
  project : String
  id : String
  item : Case
  deriving ToJson
structure Reader where
  session : String
  groups : Array String
  config : System.FilePath
  visible : IO.Ref String
structure Needed where
  text : String
  path : String
  fingerprint : String
  deriving ToJson
structure Paused where
  turn : Turn
  output : Json
  detail : Json
  deriving ToJson

/-- Exercise the same lifecycle through either a directory or the project
service, without requiring a service-only field in older local runtimes. -/
def capturedWriter (pending : PendingTurn) (name : String) (directory : System.FilePath) : Bool :=
  if pending.projectInputs.isSome then toJson pending.write == toJson directory.toString
  else toJson pending.write == Json.mkObj [("project",toJson name)] && pending.read.isEmpty &&
    (toJson pending).getObjValD "remoteFrame" != Json.null
def remoteConfig (runtime : String) (command : Array String) (groups : Array String)
    (write : Option String) : String :=
  "default = \"work\"\nsemantic_matcher = "++(toJson #[runtime,"search-provider"]).compress++
  "\n[profiles.work]\nproject_service = "++(toJson command).compress++
  "\nread = "++(toJson groups).compress++"\nhandoff_chars = 500000\n"++
  (write.map (fun name => "write = "++(toJson name).compress++"\n")).getD ""

def invoke (plan : StudySeedChecks.Input) (root data config : System.FilePath)
    (session turn label event : String) (fields : List (String × Json) := []) : IO StudyCommand.Result := do
  let source := ((Json.mkObj fields).getObjValAs? String "source").toOption
  let command ← RegisteredHook.load plan event (source == some "compact")
  let environment := replaceEnv plan.environment #[("EGGSHELL_DATA_ROOT",some data.toString),
    ("EGGSHELL_CONFIG",some config.toString),("EGGSHELL_PROFILE",some "work"),
    ("PLUGIN_ROOT",some plan.pluginRoot),("CODEX_THREAD_ID",some session),("CODEX_TURN_ID",some turn),
    ("TMPDIR",some (root/"tmp"/session).toString)]
  let initial := Json.mkObj [("hook_event_name",toJson event),("session_id",toJson session),
    ("turn_id",toJson turn),("cwd",toJson root.toString),("_eggshell_config",toJson config.toString)]
  let fields := if event == "SessionStart" && source.isNone then ("source",toJson "startup")::fields else fields
  let request := fields.foldl (fun value (key,entry) => value.setObjVal! key entry) initial
  let directory := root/"calls"/session/(turn++"-"++label)
  IO.FS.createDirAll directory.parent.get!
  IO.FS.createDirAll (root/"tmp"/session)
  let result ← StudyCommand.run "/bin/sh" #["-c",command.text] environment root.toString
    (request.compress++"\n") directory command.timeoutMs
  save (directory/"registration.json") (Json.mkObj [("event",toJson event),("command",toJson command.text),
    ("timeoutMs",toJson command.timeoutMs),("matcher",toJson command.matcher)])
  check (result.exitCode == 0 && result.elapsedMs < command.timeoutMs &&
    !result.stdout.contains "Local memory search is busy or unavailable") "mixed client failed its registered hook contract"
  let reply ← IO.ofExcept (Json.parse result.stdout)
  if ["Stop","PostCompact","Interrupt","SessionEnd"].contains event then
    check (reply == Json.mkObj []) "mixed terminal event returned an incomplete notice"
  return result

def makeTurn (group session : String) (phase slot : Nat) : Turn :=
  let symbol := s!"{group}_SUPPORT_{phase}_{slot}"
  ⟨group,s!"turn-{phase}",⟨session,s!"src/{group}_{phase}_{slot}.cpp",symbol++"_BASE",
    s!"int {symbol}_BASE = {101+phase*10+slot};",s!"int {symbol}_DETAIL = {809+phase*10+slot};"⟩⟩
def configured (root : System.FilePath) (group : String) := root/(group++".toml")
def stage (plan : StudySeedChecks.Input) (root data config : System.FilePath) (turn : Turn)
    (start : Bool) : IO Unit := do
  if start then discard <| invoke plan root data config turn.item.session turn.id "start" "SessionStart"
  discard <| invoke plan root data config turn.item.session turn.id "prompt" "UserPromptSubmit"
    [("prompt",toJson "Inspect this source investigation and record the evidence for its two fields.")]
  let files ← sessionFiles turn.item.session
  let some pending ← readPendingBase? files | throw (IO.userError "writer prompt did not create a captured turn")
  let expected := root/(if turn.project == "ALPHA" then "alpha.egg" else "beta.egg")
  check (pending.turnId == turn.id && capturedWriter pending turn.project expected &&
    pending.projectInputs.all (·.size == 2)) "writer changed its selected project or turn identity"
def command (turn : Turn) (id : String) : String :=
  if id == "read" then s!"nl -ba {turn.item.path} | sed -n '1p'"
  else if id == "detail" then s!"nl -ba {turn.item.path} | sed -n '2p'"
  else s!"printf {turn.item.symbol}"
def toolFields (turn : Turn) (id : String) : List (String × Json) :=
  [("tool_name",toJson "shell"),("tool_use_id",toJson id),
    ("tool_input",Json.mkObj [("command",toJson (command turn id))])]
def beginTool (plan : StudySeedChecks.Input) (root data config : System.FilePath) (turn : Turn)
    (id : String) : IO Json := do
  let result ← invoke plan root data config turn.item.session turn.id (id++"-pre") "PreToolUse" (toolFields turn id)
  let parsed ← IO.ofExcept (Json.parse result.stdout)
  check ((parsed.getObjValD "hookSpecificOutput").getObjValD "permissionDecision" != toJson "deny")
    "the fixture must not execute a tool that the real Pre hook stopped"
  let actual ← StudyCommand.run "/bin/sh" #["-c",command turn id] #[] root.toString ""
    (root/"calls"/turn.item.session/(turn.id++"-"++id++"-actual")) 5000
  check (actual.exitCode == 0) "real mixed-client source command failed"
  return Json.mkObj [("output",toJson actual.stdout),("exitCode",toJson actual.exitCode)]
def postTool (plan : StudySeedChecks.Input) (root data config : System.FilePath) (turn : Turn)
    (id label : String) (output : Json) : IO Unit := do
  discard <| invoke plan root data config turn.item.session turn.id label "PostToolUse"
    (toolFields turn id++[("tool_response",output)])
def tool (plan : StudySeedChecks.Input) (root data config : System.FilePath) (turn : Turn) (id : String) : IO Unit := do
  let output ← beginTool plan root data config turn id
  postTool plan root data config turn id (id++"-post") output
def finish (plan : StudySeedChecks.Input) (root data config : System.FilePath) (turn : Turn)
    (label : String := "stop") : IO Unit := do
  discard <| invoke plan root data config turn.item.session turn.id label "Stop"
    [("last_assistant_message",toJson (answer turn.item))]
def writer (plan : StudySeedChecks.Input) (root data : System.FilePath) (turn : Turn)
    (first pause : Bool) : IO (Option Paused) := do
  let config := configured root turn.project
  stage plan root data config turn first
  tool plan root data config turn "read"
  if pause then
    let output ← beginTool plan root data config turn "consume"
    let detail ← beginTool plan root data config turn "detail"
    discard <| invoke plan root data config turn.item.session turn.id "interrupt" "Interrupt"
    discard <| invoke plan root data config turn.item.session turn.id "end-interrupted" "SessionEnd"
    return some ⟨turn,output,detail⟩
  tool plan root data config turn "consume"
  tool plan root data config turn "detail"
  finish plan root data config turn
  return none

def inventory (alpha beta : ProjectStore.Project) (turns : Array Turn) : IO Json := do
  let mut records := #[]
  let mut native : Array (Synapses.Occurrence × String) := #[]
  let mut answers : Array String := #[]
  for (name,project) in [("ALPHA",alpha),("BETA",beta)] do
    for slot in [:project.manifest.owners.size] do
      let source ← project.current slot
      let reader ← Persistence.Store.NodeReader.new source
      for record in ← Synapses.Provenance.records source do
        let occurrence := record.origin.occurrence
        let some expected := turns.find? (fun turn => turn.item.session == occurrence.session && turn.id == occurrence.turn) |
          throw (IO.userError "unexpected original session/turn in the mixed projects")
        check (expected.project == name) "a late result or selected-project switch wrote into the wrong DB"
        discard <| Synapses.Provenance.checkedDocument reader record.origin
        records := records.push (Json.mkObj [("project",toJson name),("slot",toJson slot),("origin",toJson record.origin)])
      for candidate in ← Persistence.Store.searchDocuments source do
        let doc ← Synapses.Build.document reader candidate.owner
        if doc.native then
          for occurrence in doc.occurrences do
            let some expected := turns.find? (fun turn => turn.item.session == occurrence.session && turn.id == occurrence.turn) |
              throw (IO.userError "native observation has an unexpected session/turn")
            check (expected.project == name) "native observation escaped its captured project"
            check (["read","consume","detail"].contains occurrence.useId) "unexpected native tool identity"
            let files ← sessionFiles occurrence.session
            let some receipt ← (readJson? (toolReceiptPath files occurrence.turn occurrence.useId) [] : IO (Option ToolEvent)) |
              throw (IO.userError "published native observation has no immutable receipt")
            check (receipt.useId == occurrence.useId && doc.workText == some (canonicalToolWork receipt) &&
              doc.source == some (canonicalJson receipt.response))
              "native publication disagrees with its complete original tool receipt"
            check (!native.any (·.1 == occurrence)) "duplicated native occurrence in project publications"
            native := native.push (occurrence,doc.owner)
        for turn in turns do
          if doc.source.any (·.contains (answer turn.item)) then
            check (turn.project == name) "final answer was published in the wrong selected project"
            let key := turn.item.session++":"++turn.id
            if !answers.contains key then answers := answers.push key
  let timed := records.filterMap fun record =>
    (fromJson? (α := Synapses.Provenance.Origin) (record.getObjValD "origin")).toOption.map (·.occurrence)
  check (timed.all (fun occurrence => native.any (·.1 == occurrence))) "timed provenance has no native original"
  return Json.mkObj [("observations",toJson native.size),("native",toJson native),
    ("timedObservations",toJson records.size),("withoutVerifiedInterval",toJson (native.filter (!timed.contains ·.1))),
    ("answers",toJson answers),("records",toJson records)]
def waitStored (alpha beta : ProjectStore.Project) (turns : Array Turn) (observations answers : Nat) : IO Json := do
  let deadline := (← IO.monoMsNow)+30000
  repeat
    let found ← inventory alpha beta turns
    let count : Nat ← IO.ofExcept (found.getObjValAs? _ "observations")
    let messages : Array String ← IO.ofExcept (found.getObjValAs? _ "answers")
    check (count ≤ observations && messages.size ≤ answers) "mixed resume duplicated an observation or answer"
    if count == observations && messages.size == answers then return found
    check ((← IO.monoMsNow) < deadline) "mixed-client automatic publication did not catch up"
    IO.sleep 50
  throw (IO.userError "unreachable publication wait")
def awaitReady (alpha beta : ProjectStore.Project) (runtime : String) : IO Json := do
  let deadline := (← IO.monoMsNow)+30000
  repeat
    let mut rows := #[]
    for (name,project) in [("ALPHA",alpha),("BETA",beta)] do
      for slot in [:project.manifest.owners.size] do
        let source ← project.current slot
        let target : IndexTarget := {
          owner := DB.Sidecar.Owner.ofSnapshot source
          command := [runtime,"search-provider"]
          storage := .database
          sourceHead := some source.head }
        let reference ← PreparedInputs.loadStored? source .database MiniLM.model SearchProvider.encoderContract
        let count ← Persistence.Store.getNat source.get "candidates"
        let required ← if count == 0 then pure false else Warm.storedRequired target source
        let ownerReady ← OwnerViews.loadStored? source .database
        rows := rows.push (Json.mkObj [("project",toJson name),("slot",toJson slot),("head",toJson source.head),
          ("ready",toJson (!required && reference.isSome && ownerReady.isSome))])
    if rows.all (·.getObjValD "ready" == toJson true) then return toJson rows
    check ((← IO.monoMsNow) < deadline) "automatic mixed-project preparation did not catch up"
    IO.sleep 100
  throw (IO.userError "unreachable preparation wait")

def freeze (alpha beta : ProjectStore.Project) (root : System.FilePath) (turns : Array Turn) : IO (Array (String × Needed)) := do
  let mut found := #[]
  for turn in turns do
    let project := if turn.project == "ALPHA" then alpha else beta
    let mut raw := ""
    for slot in [:project.manifest.owners.size] do
      let source ← project.current slot
      let reader ← Persistence.Store.NodeReader.new source
      for candidate in ← Persistence.Store.searchDocuments source do
        let doc ← Synapses.Build.document reader candidate.owner
        if !doc.native then continue
        raw := raw++"\n"++doc.source.getD ""
    let some (content,_) ← SourceEvidence.fingerprint (root/turn.item.path) ((← IO.monoMsNow)+3000) |
      throw (IO.userError "mixed fixture source fingerprint unavailable")
    for text in [turn.item.first,turn.item.second] do
      check (raw.contains text) "required mixed-client field was not actually stored before delivery"
      found := found.push (turn.project,⟨text,turn.item.path,content.root⟩)
  return found

def read (plan : StudySeedChecks.Input) (root data : System.FilePath) (client : Reader)
    (turn : String) (needed : Array (String × Needed)) : IO Json := do
  let prompt := "Show the original BASE and DETAIL source definitions from the recorded "++
    " and ".intercalate (client.groups.map (·++"_SUPPORT")).toList++" investigations, retaining their versions and source locations."
  let before ← client.visible.get
  let result ← invoke plan root data client.config client.session turn "prompt" "UserPromptSubmit" [("prompt",toJson prompt)]
  let reply ← IO.ofExcept (Json.parse result.stdout)
  let body := ((reply.getObjValD "hookSpecificOutput").getObjValAs? String "additionalContext").toOption.getD ""
  check (!body.contains "EGGSHELL SEARCH INCOMPLETE") "mixed reader received an incomplete notice"
  let visible := before++"\n"++body
  let wanted := needed.filter (fun row => client.groups.contains row.1) |>.map (·.2)
  let missing := wanted.filter fun item => !SourceBlocks.contains visible item.path item.fingerprint item.text
  let foreign := needed.filter (fun row => !client.groups.contains row.1) |>.map (·.2)
  check (!foreign.any (fun item => body.contains item.text)) "single-project reader received another project's original fields"
  save (root/"calls"/client.session/(turn++"-body.json")) (Json.mkObj [("body",toJson body),
    ("previousVisibleSha256",toJson (Sha256.hex before.toUTF8)),("visibleSha256",toJson (Sha256.hex visible.toUTF8))])
  client.visible.set visible
  let files ← sessionFiles client.session
  let some pending ← readPendingBase? files | throw (IO.userError "read-only prompt omitted its captured turn")
  let remote := (toJson pending).getObjValD "remoteFrame"
  let payload := if remote.getObjValD "payload" == Json.null then remote else remote.getObjValD "payload"
  let remoteGroups := ((payload.getObjValD "descriptor").getObjValD "projects").getArr?.toOption.getD #[]
    |>.map (fun item => item.getObjValD "name")
  let completeScope := match pending.projectInputs with
    | some inputs => inputs.size == client.groups.size
    | none => pending.read.isEmpty && remoteGroups == client.groups.map toJson
  check (pending.turnId == turn && pending.write.isNone && completeScope)
    "reader acquired a writer or lost its complete selected project inventory"
  let some state ← readState? files | throw (IO.userError "reader state unavailable")
  let fresh := before.isEmpty
  let semantic := state.lastSearch.map (·.semantic) |>.getD .notRequested
  check (!fresh || semantic == .completed) "fresh mixed reader did not complete semantic retrieval"
  discard <| invoke plan root data client.config client.session turn "stop" "Stop"
    [("last_assistant_message",toJson "Read-only client consumed the delivered original evidence.")]
  return Json.mkObj [("session",toJson client.session),("turn",toJson turn),("groups",toJson client.groups),
    ("freshContext",toJson fresh),("required",toJson wanted),("missing",toJson missing),
    ("delivered",toJson (wanted.size-missing.size)),("semantic",toJson semantic),
    ("search",toJson state.lastSearch),("elapsedMs",toJson result.elapsedMs),
    ("bodySha256",toJson (Sha256.hex body.toUTF8)),("capturedInputs",toJson pending.projectInputs)]

def startReader (plan : StudySeedChecks.Input) (root data : System.FilePath) (client : Reader)
    (turn source : String) : IO Unit := do
  let files ← sessionFiles client.session
  let before ← readState? files
  discard <| invoke plan root data client.config client.session turn ("start-"++source) "SessionStart" [("source",toJson source)]
  if source == "compact" then
    discard <| invoke plan root data client.config client.session turn "post-compact" "PostCompact"
  if source == "compact" || source == "clear" then
    client.visible.set ""
    let some state ← readState? files | throw (IO.userError "reset reader lost its private state")
    check (state.confirmedDelivery.isNone) "new model context retained a prior confirmed delivery head"
    if source == "clear" then
      check (state.deliveredGraphs.isEmpty && state.offers.isEmpty && state.lastHandoff.isEmpty)
        "clear retained a claim about discarded context"
  if source == "resume" then
    let some before := before | throw (IO.userError "resume fixture has no preceding context")
    let some state ← readState? files | throw (IO.userError "resume lost its delivery state")
    check (state.confirmedDelivery == before.confirmedDelivery && state.deliveredGraphs == before.deliveredGraphs)
      "resume discarded context that is still visible to the model"
def makeReader (root : System.FilePath) (name : String) (groups : Array String) : IO Reader := do
  return ⟨name,groups,root/(if groups.size == 2 then "read-both.toml" else "read-"++groups[0]!++".toml"),← IO.mkRef ""⟩
def readerBatch (plan : StudySeedChecks.Input) (root data : System.FilePath) (clients : Array Reader)
    (turn label : String) (needed : Array (String × Needed)) : IO (Array Json) := do
  let gate ← IO.mkRef false
  let tasks ← clients.mapM fun client => IO.asTask (do
    while !(← gate.get) do IO.sleep 1
    read plan root data client turn needed) .dedicated
  let began ← IO.monoMsNow
  gate.set true
  let (rows,ok) ← SharedTrafficChecks.settle tasks
  save (root/(label++".json")) (Json.mkObj [("elapsedMs",toJson ((← IO.monoMsNow)-began)),
    ("rows",toJson rows),("allProcessesSucceeded",toJson ok)])
  check (ok && rows.all (fun row => row.getObjValD "missing" == toJson (#[] : Array Needed)))
    "mixed reader batch omitted needed original rows"
  return rows

def run (inputPath directory : String) (sharedOwner : Bool := false) (remote : Bool := false) : IO Unit := do
  let plan ← IO.ofExcept (fromJson? (α := StudySeedChecks.Input) (← StudyAdmission.readJson inputPath))
  StudyAdmission.verifyArtifact plan.runtime
  for file in plan.pluginFiles do StudyAdmission.verifyArtifact file
  StudySeedChecks.requireNumericalSupport plan
  let root : System.FilePath := .mk directory
  let data := root/"data"
  let host := if remote then root/"host" else data
  check (root.isAbsolute && !(← root.pathExists) && (← Paths.dataRoot) == data) "fresh mixed lifecycle root required"
  IO.FS.createDirAll (root/"src")
  IO.FS.createDirAll (root/"tmp")
  IO.FS.createDirAll data
  IO.FS.createDirAll host
  let alpha ← ProjectStore.create (root/"alpha.egg") 4
  let beta ← ProjectStore.create (root/"beta.egg") 4
  IO.FS.writeFile (configured root "ALPHA") (renderConfig plan.runtime.path alpha.directory beta.directory (some "active"))
  IO.FS.writeFile (configured root "BETA") (renderConfig plan.runtime.path alpha.directory beta.directory (some "reference"))
  IO.FS.writeFile (root/"read-both.toml") (renderConfig plan.runtime.path alpha.directory beta.directory none)
  for (name,project) in [("ALPHA",alpha),("BETA",beta)] do
    IO.FS.writeFile (root/("read-"++name++".toml")) (SharedTrafficChecks.config plan.runtime.path project.directory false)
  if remote then
    let catalog := root/"catalog.json"
    let entries := (#[("ALPHA",alpha),("BETA",beta)]).map fun (name,project) =>
      Json.mkObj [("name",toJson name),("directory",toJson project.directory.toString),
        ("readable",toJson true),("writable",toJson true)]
    save catalog (Json.mkObj [("projects",toJson entries),
      ("policy",Json.mkObj [("chars",toJson (500000 : Nat)),("numeric",toJson true)])])
    let command := #["/usr/bin/env","EGGSHELL_DATA_ROOT="++host.toString,
      "EGGSHELL_PREFIX="++(← Paths.installRoot).toString,plan.runtime.path,"project-gateway",catalog.toString]
    for name in ["ALPHA","BETA"] do
      IO.FS.writeFile (configured root name) (remoteConfig plan.runtime.path command #["ALPHA","BETA"] (some name))
      IO.FS.writeFile (root/("read-"++name++".toml")) (remoteConfig plan.runtime.path command #[name] none)
    IO.FS.writeFile (root/"read-both.toml") (remoteConfig plan.runtime.path command #["ALPHA","BETA"] none)
  let mut sessions := #[]
  for (group,slot) in [("ALPHA",0),("ALPHA",1),("BETA",2),("BETA",3)] do
    let item ← SharedTrafficChecks.route ⟨s!"mixed-{group}-{slot}","","","",""⟩ (if sharedOwner then 0 else slot)
    sessions := sessions.push (group,slot,item.session)
  if sharedOwner then
    check (sessions.all (fun (_,_,session) => ProjectStore.routeSlot session 4 == 0))
      "shared-owner fixture did not force every writer onto the same physical owner"
  let first := sessions.map fun (group,slot,session) => makeTurn group session 0 slot
  let second := sessions.map fun (group,slot,session) => makeTurn group session 1 slot
  let switched := makeTurn "BETA" sessions[0]!.2.2 2 0
  let turns := first++second++#[switched]
  let growth := if sharedOwner then (Array.range 4).map fun phase =>
    sessions.map fun (group,slot,session) => makeTurn group session (phase+3) slot else #[]
  let declared := turns++growth.flatten
  for turn in declared do IO.FS.writeFile (root/turn.item.path) (turn.item.first++"\n"++turn.item.second++"\n")
  save (root/"declared-turns.json") (toJson declared)
  let environment := replaceEnv plan.environment #[("EGGSHELL_DATA_ROOT",some data.toString),
    ("TMPDIR",some (root/"tmp").toString),("CODEX_THREAD_ID",none),("CODEX_TURN_ID",none)]
  let services ← IO.mkRef (#[] : Array (StudyRuntime.Managed × String))
  let start := do
    check (← services.get).isEmpty "mixed services are already running"
    let hostEnvironment := replaceEnv environment #[("EGGSHELL_DATA_ROOT",some host.toString)]
    let publisher ← StudyRuntime.startPublisher (.mk plan.runtime.path) host hostEnvironment
    services.modify (·.push (publisher,"publisher"))
    if remote then
      let clientPublisher ← StudyRuntime.startPublisher (.mk plan.runtime.path) data environment
      services.modify (fun live => #[(clientPublisher,"client-publisher")]++live)
    let frontend ← StudyRuntime.startManaged (.mk plan.runtime.path) (.mk plan.pluginRoot)
      "mixed-chat-service" (data/"daemon.json") environment
    services.modify (fun live => #[(frontend,"frontend")]++live)
  let stop := fun label => do
    let mut failures : Array String := #[]
    for (service,name) in ← services.get do
      try StudyRuntime.stopManaged service (root/(label++"-"++name++"-stop.json"))
      catch error => failures := failures.push error.toString; StudyRuntime.abort service
    services.set #[]
    check failures.isEmpty "mixed services failed normal shutdown"
  try
    start
    let tasks ← first.mapM fun turn => IO.asTask (writer plan root data turn true false) .dedicated
    let settled := tasks.map (·.get)
    for result in settled do discard <| IO.ofExcept (result.mapError IO.Error.toString)
    save (root/"baseline-inventory.json") (← waitStored alpha beta declared 12 4)
    save (root/"baseline-ready.json") (← awaitReady alpha beta plan.runtime.path)
    let initialNeeded ← freeze alpha beta root first
    save (root/"baseline-required.json") (toJson initialNeeded)
    let a ← makeReader root "mixed-reader-a" #["ALPHA"]
    let b ← makeReader root "mixed-reader-b" #["BETA"]
    let both ← makeReader root "mixed-reader-both" #["ALPHA","BETA"]
    let clear ← makeReader root "mixed-reader-clear" #["ALPHA","BETA"]
    let existing := #[a,b,both,clear]
    for client in existing do startReader plan root data client "read-0" "startup"
    discard <| readerBatch plan root data existing "read-0" "baseline-readers" initialNeeded
    for client in #[a,b] do
      discard <| invoke plan root data client.config client.session "read-0" "end-before-resume" "SessionEnd"
    let mut newcomers := #[]
    for (index,groups) in #[(0,#["ALPHA"]),(1,#["BETA"]),(2,#["ALPHA","BETA"]),(3,#["ALPHA","BETA"])] do
      let client ← makeReader root s!"mixed-newcomer-{index}" groups
      startReader plan root data client "read-1" "startup"
      newcomers := newcomers.push client
    for client in #[a,b] do startReader plan root data client "read-1" "resume"
    let concurrentReaders := existing++newcomers
    let gate ← IO.mkRef false
    let writes ← (second.mapIdx fun index turn => (index,turn)).mapM fun (index,turn) => IO.asTask (do
      while !(← gate.get) do IO.sleep 1
      writer plan root data turn false (index == 0 || index == 3)) .dedicated
    let reads ← concurrentReaders.mapM fun client => IO.asTask (do
      while !(← gate.get) do IO.sleep 1
      read plan root data client "read-1" initialNeeded) .dedicated
    let began ← IO.monoMsNow
    gate.set true
    let written := writes.map (·.get)
    let (received,ok) ← SharedTrafficChecks.settle reads
    save (root/"mixed-wave.json") (Json.mkObj [("elapsedMs",toJson ((← IO.monoMsNow)-began)),
      ("readers",toJson received),("readerProcessesSucceeded",toJson ok),
      ("writers",toJson (written.map fun result => match result with
        | .ok paused => Json.mkObj [("paused",toJson paused)]
        | .error error => Json.mkObj [("error",toJson error.toString)]))])
    check (ok && received.all (fun row => row.getObjValD "missing" == toJson (#[] : Array Needed))) "mixed existing/fresh delivery failed"
    let mut paused := #[]
    for result in written do
      if let some value ← IO.ofExcept (result.mapError IO.Error.toString) then paused := paused.push value
    check (paused.size == 2) "both interrupted writers required"
    save (root/"paused.json") (toJson paused)
    save (root/"before-restart-inventory.json") (← waitStored alpha beta declared 20 6)
    stop "before-restart"
    let beforeRestart := Json.mkObj [("alpha",← originals alpha),("beta",← originals beta)]
    start
    check ((Json.mkObj [("alpha",← originals alpha),("beta",← originals beta)]) == beforeRestart)
      "service restart changed original publication bytes"
    for held in paused do
      let changing := held.turn.item.session == switched.item.session
      let config := configured root (if changing then "BETA" else held.turn.project)
      discard <| invoke plan root data config held.turn.item.session held.turn.id "start-resume" "SessionStart" [("source",toJson "resume")]
      if changing then stage plan root data config switched false
      postTool plan root data config held.turn "consume" "consume-late-post" held.output
      if changing then postTool plan root data config held.turn "consume" "consume-duplicate-post" held.output
      postTool plan root data config held.turn "detail" "detail-late-post" held.detail
      finish plan root data config held.turn
      if changing then
        let files ← sessionFiles switched.item.session
        let some pending ← readPendingBase? files | throw (IO.userError "older Stop removed the newer active turn")
        check (pending.turnId == switched.id && capturedWriter pending "BETA" beta.directory && !pending.closed)
          "older Stop changed the newer project/turn"
        for id in ["read","consume","detail"] do tool plan root data config switched id
        finish plan root data config switched
      else finish plan root data config held.turn "duplicate-stop"
    save (root/"final-inventory.json") (← waitStored alpha beta declared 27 9)
    save (root/"final-ready.json") (← awaitReady alpha beta plan.runtime.path)
    let finalNeeded ← freeze alpha beta root turns
    save (root/"final-required.json") (toJson finalNeeded)
    for client in existing++newcomers do
      startReader plan root data client "read-2" (if client.session == both.session then "compact" else if client.session == clear.session then "clear" else "resume")
    let freshA ← makeReader root "mixed-final-fresh-a" #["ALPHA"]
    let freshBoth ← makeReader root "mixed-final-fresh-both" #["ALPHA","BETA"]
    for client in #[freshA,freshBoth] do startReader plan root data client "read-2" "startup"
    let finalReaders := existing++newcomers++#[freshA,freshBoth]
    let final ← readerBatch plan root data finalReaders "read-2" "final-readers" finalNeeded
    let mut knownTurns := turns
    let mut knownNeeded := finalNeeded
    let mut growthWaves := #[]
    for phase in [:growth.size] do
      let readTurn := s!"read-growth-{phase}"
      for client in finalReaders do startReader plan root data client readTurn "resume"
      let gate ← IO.mkRef false
      let writers ← growth[phase]!.mapM fun turn => IO.asTask (do
        while !(← gate.get) do IO.sleep 1
        writer plan root data turn false false) .dedicated
      let readers ← finalReaders.mapM fun client => IO.asTask (do
        while !(← gate.get) do IO.sleep 1
        read plan root data client readTurn knownNeeded) .dedicated
      let began ← IO.monoMsNow
      gate.set true
      let written := writers.map (·.get)
      let (received,ok) ← SharedTrafficChecks.settle readers
      let traffic := Json.mkObj [("elapsedMs",toJson ((← IO.monoMsNow)-began)),("readers",toJson received),
        ("writerResults",toJson (written.map fun result => match result with
          | .ok _ => Json.mkObj [("ok",toJson true)]
          | .error error => Json.mkObj [("error",toJson error.toString)]))]
      save (root/s!"growth-traffic-{phase}.json") traffic
      check (ok && received.size == 10 && received.all (fun row => row.getObjValD "missing" == toJson (#[] : Array Needed)))
        "same-owner overlapping readers omitted previously committed originals"
      for value in written do discard <| IO.ofExcept (value.mapError IO.Error.toString)
      knownTurns := knownTurns++growth[phase]!
      let saved ← waitStored alpha beta declared (knownTurns.size*3) knownTurns.size
      save (root/s!"growth-inventory-{phase}.json") saved
      let ready ← awaitReady alpha beta plan.runtime.path
      save (root/s!"growth-ready-{phase}.json") ready
      knownNeeded ← freeze alpha beta root knownTurns
      save (root/s!"growth-required-{phase}.json") (toJson knownNeeded)
      growthWaves := growthWaves.push traffic
    if sharedOwner then
      discard <| readerBatch plan root data finalReaders "read-growth-final" "growth-final-readers" knownNeeded
    for client in finalReaders do
      discard <| invoke plan root data client.config client.session (if sharedOwner then "read-growth-final" else "read-2") "end" "SessionEnd"
    save (root/"facts.json") (Json.mkObj [("alpha",← graphFacts alpha),("beta",← graphFacts beta)])
    save (root/"result.json") (Json.mkObj [("runtime",toJson plan.runtime),("projects",toJson (2 : Nat)),
      ("writers",toJson turns),("readers",toJson final),("observations",toJson (27 : Nat)),("answers",toJson (9 : Nat)),
      ("manualWarmCalls",toJson (0 : Nat)),("manualKeepCalls",toJson (0 : Nat)),
      ("actualServiceRestart",toJson true),("interruptedWriters",toJson (2 : Nat)),
      ("projectService",toJson remote),
      ("samePhysicalOwner",toJson sharedOwner),("growthWaves",toJson growthWaves),
      ("finalWriterTurns",toJson knownTurns.size),("finalOriginalObservations",toJson (knownTurns.size*3)),
      ("maxSimultaneousClients",toJson (if sharedOwner then 14 else 12 : Nat)),
      ("answeringModelCalls",toJson (0 : Nat)),("adopted",toJson false)])
  catch error =>
    save (root/"failure.json") (Json.mkObj [("error",toJson error.toString),("runtime",toJson plan.runtime)])
    throw error
  finally stop "final"

def declaredTurns (root : System.FilePath) : IO (Array Turn) := do
  let values ← IO.ofExcept ((← StudyAdmission.readJson (root/"declared-turns.json").toString).getArr?)
  values.mapM fun value => do
    let project ← IO.ofExcept (value.getObjValAs? String "project")
    let id ← IO.ofExcept (value.getObjValAs? String "id")
    let item := value.getObjValD "item"
    let text := fun name => IO.ofExcept (item.getObjValAs? String name)
    let item : Case := ⟨← text "session",← text "path",← text "symbol",← text "first",← text "second"⟩
    return (⟨project,id,item⟩ : Turn)

/-- Query the completed growing DB from a distinct, initially empty client
data root. No earlier model context or client receipts can be reused. -/
def freshGrown (inputPath directory : String) : IO Unit := do
  let plan ← IO.ofExcept (fromJson? (α := StudySeedChecks.Input) (← StudyAdmission.readJson inputPath))
  StudyAdmission.verifyArtifact plan.runtime
  for file in plan.pluginFiles do StudyAdmission.verifyArtifact file
  let root : System.FilePath := .mk directory
  let data := root/"fresh-data"
  check (!(← data.pathExists) && (← Paths.dataRoot) == data) "fresh grown-DB reader root required"
  IO.FS.createDirAll data
  let turns ← declaredTurns root
  check (turns.size == 25) "the full predeclared growth workload must finish first"
  let alpha ← ProjectStore.openProject (root/"alpha.egg")
  let beta ← ProjectStore.openProject (root/"beta.egg")
  let before := Json.mkObj [("alpha",← originals alpha),("beta",← originals beta)]
  let needed ← freeze alpha beta root turns
  save (root/"fresh-grown-frozen.json") (toJson needed)
  let environment := replaceEnv plan.environment #[("EGGSHELL_DATA_ROOT",some data.toString),
    ("TMPDIR",some (root/"tmp").toString),("CODEX_THREAD_ID",none),("CODEX_TURN_ID",none)]
  let publisher ← StudyRuntime.startPublisher (.mk plan.runtime.path) data environment
  let frontend ← try
      StudyRuntime.startManaged (.mk plan.runtime.path) (.mk plan.pluginRoot)
        "grown-fresh-service" (data/"daemon.json") environment
    catch error => StudyRuntime.stopManaged publisher (root/"fresh-startup-publisher-stop.json"); throw error
  try
    let mut clients := #[]
    for index in [:10] do
      let groups := if index % 3 == 0 then #["ALPHA"] else if index % 3 == 1 then #["BETA"] else #["ALPHA","BETA"]
      let client ← makeReader root s!"grown-fresh-{index}" groups
      startReader plan root data client "fresh-grown" "startup"
      clients := clients.push client
    discard <| readerBatch plan root data clients "fresh-grown" "fresh-grown-readers" needed
    for client in clients do discard <| invoke plan root data client.config client.session "fresh-grown" "end" "SessionEnd"
    check ((Json.mkObj [("alpha",← originals alpha),("beta",← originals beta)]) == before)
      "fresh read-only clients changed original project publications"
    save (root/"fresh-grown-result.json") (Json.mkObj [("originalsUnchanged",toJson true),
      ("freshDataRoot",toJson data.toString),("manualWarmCalls",toJson (0 : Nat)),("answeringModelCalls",toJson (0 : Nat))])
  catch error =>
    save (root/"fresh-grown-failure.json") (Json.mkObj [("error",toJson error.toString)])
    throw error
  finally
    try StudyRuntime.stopManaged frontend (root/"fresh-frontend-stop.json")
    finally StudyRuntime.stopManaged publisher (root/"fresh-publisher-stop.json")

/-- Read-only postmortem. It neither registers a session nor resumes a save,
warms an index, repairs state, or changes the failed run's outcome. -/
def inspect (directory output : String) : IO Unit := do
  let root : System.FilePath := .mk directory
  check (!(← (System.FilePath.mk output).pathExists)) "retain the first mixed postmortem"
  let turns ← declaredTurns root
  let alpha ← ProjectStore.openProject (root/"alpha.egg")
  let beta ← ProjectStore.openProject (root/"beta.egg")
  let before := Json.mkObj [("alpha",← originals alpha),("beta",← originals beta)]
  let counts ← inventory alpha beta turns
  let mut fields := #[]
  let mut journals := #[]
  for (group,project) in [("ALPHA",alpha),("BETA",beta)] do
    let mut texts : Array (String × String) := #[]
    for slot in [:project.manifest.owners.size] do
      let source ← project.current slot
      let reader ← Persistence.Store.NodeReader.new source
      for candidate in ← Persistence.Store.searchDocuments source do
        let doc ← Synapses.Build.document reader candidate.owner
        if let some raw := doc.source then texts := texts.push (doc.owner,raw)
      if let some journal ← Synapses.Journal.open? source then
        for turn in turns do
          if turn.project != group || ProjectStore.routeSlot turn.item.session 4 != slot then continue
          let entries ← Synapses.Journal.turnEntries journal ⟨turn.item.session,turn.id⟩
          journals := journals.push (Json.mkObj [("project",toJson group),("slot",toJson slot),
            ("session",toJson turn.item.session),("turn",toJson turn.id),
            ("kinds",toJson (entries.map (·.payload.kind))),("entries",toJson entries)])
    for turn in turns do
      if turn.project != group then continue
      for text in [turn.item.first,turn.item.second] do
        let owners := texts.filterMap fun (owner,raw) => if raw.contains text then some owner else none
        fields := fields.push (Json.mkObj [("project",toJson group),("session",toJson turn.item.session),
          ("turn",toJson turn.id),("text",toJson text),("rawDocumentOwners",toJson owners),
          ("present",toJson (!owners.isEmpty))])
  let mut sessions := #[]
  for session in (turns.map (·.item.session)).toList.eraseDups do
    let files ← sessionFiles session
    let state ← StudyAdmission.readJson files.state.toString
    let mut privateRows := #[]
    for name in ["closed","checkpoints","deferred","terminal-intents","terminal-unresolved","terminal-done"] do
      let directory := files.directory/name
      if !(← directory.pathExists) then continue
      for entry in ← directory.readDir do
        if !entry.fileName.endsWith ".json" then continue
        privateRows := privateRows.push (Json.mkObj [("kind",toJson name),("file",toJson entry.fileName),
          ("value",← StudyAdmission.readJson entry.path.toString)])
    let mut receipts := #[]
    for turn in turns do
      if turn.item.session != session then continue
      let directory := toolDirectory files turn.id
      if !(← directory.pathExists) then continue
      for entry in ← directory.readDir do
        if !entry.fileName.endsWith ".json" then continue
        receipts := receipts.push (Json.mkObj [("turn",toJson turn.id),("file",toJson entry.fileName),
          ("value",← StudyAdmission.readJson entry.path.toString)])
    sessions := sessions.push (Json.mkObj [("session",toJson session),
      ("state",Json.mkObj [("epoch",state.getObjValD "epoch"),("enabled",state.getObjValD "enabled")]),
      ("privateMetadata",toJson privateRows),("nativeReceipts",toJson receipts)])
  check ((Json.mkObj [("alpha",← originals alpha),("beta",← originals beta)]) == before)
    "read-only mixed postmortem changed original publications"
  save (.mk output) (Json.mkObj [("inventory",counts),("rawFields",toJson fields),("journals",toJson journals),
    ("sessions",toJson sessions),("originalsUnchanged",toJson true),("readOnly",toJson true),
    ("servicesStarted",toJson (0 : Nat)),("hooksReplayed",toJson (0 : Nat)),("originalRunPassed",toJson false)])
def inspectPrepared (directory output : String) : IO Unit := do
  let root : System.FilePath := .mk directory
  let declared ← declaredTurns root
  let some first := declared[0]? | throw (IO.userError "missing declared mixed turn")
  let session := first.item.session
  let pending ← StudyAdmission.readJson (root/"data/sessions"/session/"pending.json").toString
  let frame := (pending.getObjValD "remoteFrame").getObjValD "payload"
  let cuts ← IO.ofExcept (((frame.getObjValD "boundary").getObjValD "projects").getArr?)
  let alpha ← ProjectStore.openProject (root/"alpha.egg")
  let beta ← ProjectStore.openProject (root/"beta.egg")
  let before := Json.mkObj [("alpha",← originals alpha),("beta",← originals beta)]
  let mut rows := #[]
  for selected in cuts do
    let name ← IO.ofExcept (selected.getObjValAs? String "name")
    let project := if name == "ALPHA" then alpha else beta
    let cut ← IO.ofExcept (fromJson? (α := ProjectStore.Cut) (selected.getObjValD "cut"))
    let view ← ProjectStore.openView project cut
    for index in [:view.sources.size] do
      let some source := view.sources[index]? | throw (IO.userError "captured view omitted an owner")
      let current ← project.current index
      rows := rows.push (Json.mkObj [("project",toJson name),("slot",toJson index),
        ("capturedHead",toJson source.head),("currentHead",toJson current.head),
        ("capturedQueryReady",toJson (← PreparedInputs.loadStored? source .database MiniLM.model SearchProvider.encoderContract).isSome),
        ("capturedOwnerReady",toJson (← OwnerViews.loadStored? source .database).isSome),
        ("currentQueryReady",toJson (← PreparedInputs.loadStored? current .database MiniLM.model SearchProvider.encoderContract).isSome),
        ("currentOwnerReady",toJson (← OwnerViews.loadStored? current .database).isSome)])
  check ((Json.mkObj [("alpha",← originals alpha),("beta",← originals beta)]) == before)
    "preparation postmortem changed original source files"
  save (.mk output) (Json.mkObj [("originalsUnchanged",toJson true),("rows",toJson rows),
    ("servicesStarted",toJson (0 : Nat)),("hooksReplayed",toJson (0 : Nat))])
end MixedChatChecks
def main (args : List String) : IO UInt32 := do
  match args with
  | ["check",input,directory] => MixedChatChecks.run input directory; return 0
  | ["shared-owner",input,directory] => MixedChatChecks.run input directory true; return 0
  | ["service",input,directory] => MixedChatChecks.run input directory false true; return 0
  | ["service-growth",input,directory] => MixedChatChecks.run input directory true true; return 0
  | ["fresh-grown",input,directory] => MixedChatChecks.freshGrown input directory; return 0
  | ["inspect",directory,output] => MixedChatChecks.inspect directory output; return 0
  | ["inspect-prepared",directory,output] => MixedChatChecks.inspectPrepared directory output; return 0
  | _ => sourceRouteEngine args
