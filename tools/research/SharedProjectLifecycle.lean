import tools.research.StudySeedChecks
import Eggshell.ProjectStore

open Lean Eggshell Eggshell.Plugin
namespace Eggshell.Research.SharedProjectLifecycle

def check (ok : Bool) (message : String) : IO Unit :=
  unless ok do throw (IO.userError message)

def save (path : System.FilePath) (value : Json) : IO Unit :=
  IO.FS.writeFile path value.pretty

def replaceEnv (env updates : Array (String × Option String)) :=
  env.filter (fun row => !updates.any (·.1 == row.1)) ++ updates

structure Case where
  session : String
  path : String
  symbol : String
  first : String
  second : String
  deriving Inhabited, ToJson

def answer (item : Case) : String :=
  s!"The two fields are supported by [base]({item.path}:1) and [detail]({item.path}:2)."

def cases : Array Case := #[
  ⟨"reference-writer","src/reference.cpp","REFERENCE_BASE","int REFERENCE_BASE = 731;","int REFERENCE_DETAIL = 947;"⟩] ++
  (List.range 4).toArray.map (fun i => ⟨s!"project-writer-{i}",s!"src/shared_{i}.cpp",
    s!"SHARED_{i}_BASE",s!"int SHARED_{i}_BASE = {101+i};",s!"int SHARED_{i}_DETAIL = {809+i};"⟩)

def renderConfig (runtime : String) (active reference : System.FilePath) (write : Option String) : String :=
  "default = \"work\"\nsemantic_matcher = " ++ (toJson #[runtime,"search-provider"]).compress ++
  "\n[eggs]\nactive = " ++ (toJson active.toString).compress ++
  "\nreference = " ++ (toJson reference.toString).compress ++
  "\n[profiles.work]\nread = [\"active\",\"reference\"]\nhandoff_chars = 500000\n" ++
  (write.map (fun name => "write = " ++ (toJson name).compress ++ "\n") |>.getD "")

def originals (project : ProjectStore.Project) : IO Json := do
  let mut rows := #[]
  for slot in [:project.manifest.owners.size] do
    let source ← project.current slot
    rows := rows.push (Json.mkObj [("slot",toJson slot),("head",toJson source.head),
      ("files",toJson (← StudyRuntime.files source.directory))])
  return Json.mkObj [("manifest",toJson project.manifest),("sources",toJson rows)]

def census (project : ProjectStore.Project) (expected : Nat)
    (observe : Nat → Array Json → IO Unit := fun _ _ => pure ()) : IO Json := do
  let deadline := (← IO.monoMsNow)+20000
  repeat
    let mut rows := #[]
    let mut count := 0
    for slot in [:project.manifest.owners.size] do
      let source ← project.current slot
      let records ← Synapses.Provenance.records source
      count := count+records.size
      check (records.all (·.origin.valid)) "stored observation has invalid temporal/source provenance"
      rows := rows.push (Json.mkObj [("slot",toJson slot),("head",toJson source.head),
        ("origins",toJson (records.map (·.origin)))])
    observe count rows
    if count == expected then return Json.mkObj [("count",toJson count),("sources",toJson rows)]
    check (count < expected && (← IO.monoMsNow) < deadline) "source publication lost or duplicated observations"
    IO.sleep 25
  throw (IO.userError "unreachable census")

def call (plan : StudySeedChecks.Input) (root data config : System.FilePath)
    (session label : String) (args : Array String) (input : String := "") : IO StudyCommand.Result := do
  let env := replaceEnv plan.environment #[
    ("EGGSHELL_DATA_ROOT",some data.toString),("EGGSHELL_CONFIG",some config.toString),
    ("EGGSHELL_PROFILE",some "work"),("CODEX_THREAD_ID",some session),
    ("CODEX_TURN_ID",some "recorded-turn"),("TMPDIR",some (root/"tmp"/session).toString)]
  let directory := root/"calls"/session
  IO.FS.createDirAll directory
  let result ← StudyCommand.run plan.runtime.path args env root.toString input (directory/label) 35000
  check (result.exitCode == 0 && result.elapsedMs < 30000)
    s!"{session}/{label} failed or exceeded hook bound: {result.stderr}"
  return result

def hook (plan : StudySeedChecks.Input) (root data config : System.FilePath)
    (session label event : String) (fields : List (String × Json) := []) : IO StudyCommand.Result := do
  let input := Json.mkObj ([
    ("hook_event_name",toJson event),("session_id",toJson session),
    ("turn_id",toJson "recorded-turn"),("cwd",toJson root.toString),
    ("_eggshell_config",toJson config.toString)] ++ fields)
  call plan root data config session label #["codex-hook"] (input.compress++"\n")

def writer (plan : StudySeedChecks.Input) (root data config target : System.FilePath)
    (item : Case) (begin : Bool := true) (projects : Nat := 2)
    (invoke : String → String → String → List (String × Json) → IO StudyCommand.Result :=
      fun session label event fields => hook plan root data config session label event fields)
    (keep : Bool := true) : IO Json := do
  if begin then
    discard <| invoke item.session "start" "SessionStart" []
    discard <| invoke item.session "prompt" "UserPromptSubmit"
      [("prompt",toJson "Inspect the shared source evidence and explain its two recorded fields.")]
  let pendingPath := data/"sessions"/item.session/"pending.json"
  let some pending ← (readJson? pendingPath pendingJsonDefaults : IO (Option PendingTurn)) |
    throw (IO.userError "normal hook did not stage the configured project")
  check (pending.write == some target.toString && pending.projectInputs.any (·.size == projects))
    "native hook changed its write target or omitted a configured project"
  for (id,command) in #[
      ("read",s!"nl -ba {item.path} | sed -n '1p'"),
      ("consume",s!"printf {item.symbol}"),
      ("detail",s!"nl -ba {item.path} | sed -n '2p'")] do
    let input := Json.mkObj [("command",toJson command)]
    let fields := [("tool_name",toJson "shell"),("tool_use_id",toJson id),("tool_input",input)]
    discard <| invoke item.session (id++"-pre") "PreToolUse" fields
    let directory := root/"calls"/item.session/(id++"-actual")
    let actual ← StudyCommand.run "/bin/sh" #["-c",command] #[] root.toString "" directory 5000
    check (actual.exitCode == 0) "actual source operation failed"
    discard <| invoke item.session (id++"-post") "PostToolUse"
      (fields++[("tool_response",Json.mkObj [("output",toJson actual.stdout),("exitCode",toJson actual.exitCode)])])
  discard <| invoke item.session "stop" "Stop" [
    ("last_assistant_message",toJson (answer item))]
  if keep then discard <| call plan root data config item.session "keep" #["egg","keep"]
  return Json.mkObj [("session",toJson item.session),("target",toJson target.toString),
    ("capturedInputs",toJson pending.projectInputs),("toolCalls",toJson (3 : Nat))]

def warm (plan : StudySeedChecks.Input) (root data config : System.FilePath) (label : String) : IO Json := do
  let env := replaceEnv plan.environment #[
    ("EGGSHELL_DATA_ROOT",some data.toString),("EGGSHELL_CONFIG",some config.toString),
    ("CODEX_THREAD_ID",none),("CODEX_TURN_ID",none)]
  let result ← StudyCommand.run plan.runtime.path #["egg","warm"] env root.toString "" (root/label) 180000
  check (result.exitCode == 0) s!"shared project warm failed: {result.stderr}"
  let parsed ← IO.ofExcept (Json.parse result.stdout)
  for database in ← IO.ofExcept ((parsed.getObjValD "databases").getArr?) do
    for source in ← IO.ofExcept ((database.getObjValD "sources").getArr?) do
      let after := source.getObjValD "after"
      check (after.getObjValD "missing" == toJson (0 : Nat) && after.getObjValD "invalid" == toJson (0 : Nat))
        "warm acknowledged incomplete numerical coverage"
  return parsed

def graphFacts (project : ProjectStore.Project) : IO Json := do
  let mut rows := #[]
  for slot in [:project.manifest.owners.size] do
    let source ← project.current slot
    let records ← Synapses.Provenance.records source
    if records.isEmpty then continue
    let some reader ← Synapses.Index.open? source .database .shared |
      throw (IO.userError "published source has no prepared synaptic index")
    let facts ← Synapses.Index.allFacts reader.index
    let consumed := (facts.filter fun fact => match fact with | .consumed _ => true | _ => false).size
    let supported := (facts.filter fun fact => match fact with | .supports _ => true | _ => false).size
    let coquoted := (facts.filter fun fact => match fact with | .coquoted _ _ => true | _ => false).size
    check (consumed > 0 && supported ≥ 2 && coquoted > 0) "normal hooks did not persist all three advisory edge types"
    rows := rows.push (Json.mkObj [("slot",toJson slot),("consumed",toJson consumed),
      ("supports",toJson supported),("coquoted",toJson coquoted)])
  return toJson rows

def checkSharedVectors (data : System.FilePath) (projects : List ProjectStore.Project) : IO Json := do
  let mut privateRows := 0
  let mut rows := #[]
  for project in projects do
    let root := data/"read-cache"/project.manifest.identity/"semantic"
    let privateMatrix ← VectorMatrix.open? root MiniLM.model SearchProvider.encoderContract
    let sharedRoot := project.directory/"derived"/project.manifest.identity/"semantic"
    let sharedMatrix ← VectorMatrix.open? sharedRoot MiniLM.model SearchProvider.encoderContract
    let count := privateMatrix.map (·.metadata.rows) |>.getD 0
    privateRows := privateRows+count
    rows := rows.push (Json.mkObj [("project",toJson project.directory.toString),
      ("privateRows",toJson count),("sharedRows",toJson (sharedMatrix.map (·.metadata.rows) |>.getD 0)),
      ("privateHead",toJson (privateMatrix.map (·.snapshot.head))),
      ("sharedHead",toJson (sharedMatrix.map (·.snapshot.head)))])
  return Json.mkObj [("privateProjectedRows",toJson privateRows),
    ("noPrivateProjection",toJson (privateRows == 0)),("projects",toJson rows)]

def readiness (runtime root report : String) : IO Unit := do
  let mut rows := #[]
  for name in ["active.egg","reference.egg"] do
    let project ← ProjectStore.openProject (System.FilePath.mk root/name)
    for slot in [:project.manifest.owners.size] do
      let source ← project.current slot
      let target : IndexTarget := {
        owner := DB.Sidecar.Owner.ofSnapshot source
        command := [runtime,"search-provider"]
        storage := .database
        sourceHead := some source.head }
      let inputs ← PreparedInputs.loadStored? source .database MiniLM.model SearchProvider.encoderContract
      rows := rows.push (Json.mkObj [("project",toJson name),("source",toJson source.head.identity),
        ("synapsesRequired",toJson (← Synapses.Build.required source .database)),
        ("canonicalReady",toJson (← Synapses.CanonicalSource.Cache.ready source)),
        ("windowsReady",toJson (← WindowOwners.openShared? source).isSome),
        ("lexicalReady",toJson (← RetrievalResearch.Index.ready source)),
        ("sharedInput",toJson inputs.isSome),("ownerRequired",toJson (← OwnerViews.requiredFor source)),
        ("sharedRequired",toJson (← Warm.storedRequired target source)),
        ("readOnlyRequired",toJson (← Warm.required {target with storage := .user} source)),
        ("latestSharedRequired",toJson (← Warm.required {target with sourceHead := none} source)),
        ("latestReadOnlyRequired",toJson (← Warm.required {target with storage := .user,sourceHead := none} source))])
  save (.mk report) (toJson rows)

def run (inputPath directory : String) : IO Unit := do
  let plan ← IO.ofExcept (fromJson? (α := StudySeedChecks.Input) (← StudyAdmission.readJson inputPath))
  StudyAdmission.verifyArtifact plan.runtime
  for file in plan.pluginFiles do StudyAdmission.verifyArtifact file
  StudySeedChecks.requireNumericalSupport plan
  let root := System.FilePath.mk directory
  check (root.isAbsolute && !(← root.pathExists)) "fresh shared-project fixture required"
  IO.FS.createDirAll (root/"src")
  for item in cases do IO.FS.writeFile (root/item.path) (item.first++"\n"++item.second++"\n")
  let active ← ProjectStore.create (root/"active.egg") 4
  let reference ← ProjectStore.create (root/"reference.egg") 2
  let mut chosen := #[cases[0]!]
  for i in [:4] do
    let mut selected : Option String := none
    for suffix in [:1024] do
      let name := s!"project-writer-{i}-{suffix}"
      if ProjectStore.routeSlot name 4 == i then
        selected := some name
        break
    let some session := selected | throw (IO.userError "could not route a distinct test owner")
    chosen := chosen.push {cases[i+1]! with session}
  let initialActive ← originals active
  let activeConfig := root/"active.toml"
  let referenceConfig := root/"reference.toml"
  let readerConfig := root/"reader.toml"
  IO.FS.writeFile activeConfig (renderConfig plan.runtime.path active.directory reference.directory (some "active"))
  IO.FS.writeFile referenceConfig (renderConfig plan.runtime.path active.directory reference.directory (some "reference"))
  IO.FS.writeFile readerConfig (renderConfig plan.runtime.path active.directory reference.directory none)
  let data := root/"writer-data"
  IO.FS.createDir data
  let env := replaceEnv plan.environment #[("EGGSHELL_DATA_ROOT",some data.toString),
    ("CODEX_THREAD_ID",none),("CODEX_TURN_ID",none)]
  let publisher ← StudyRuntime.startPublisher (.mk plan.runtime.path) data env
  let frontend ← try
      StudyRuntime.startManaged (.mk plan.runtime.path) (.mk plan.pluginRoot)
        "shared-project-writers" (data/"daemon.json") env
    catch error =>
      StudyRuntime.stopManaged publisher (root/"writer-publisher-startup-stop.json")
      throw error
  try
    discard <| writer plan root data referenceConfig reference.directory chosen[0]!
    let referenceBefore ← originals reference
    check ((← originals active) == initialActive) "reference-only writer changed the other project"
    discard <| warm plan root data referenceConfig "reference-ready"
    let mut tasks := #[]
    let mut slots : Std.HashSet Nat := {}
    for item in chosen.extract 1 chosen.size do
      let slot := ProjectStore.routeSlot item.session 4
      slots := slots.insert slot
      tasks := tasks.push (← IO.asTask (writer plan root data activeConfig active.directory item) .dedicated)
    let settled := tasks.map (·.get)
    save (root/"writer-attempts.json") (toJson (settled.map fun result => match result with
      | .ok value => value | .error error => Json.mkObj [("error",toJson error.toString)]))
    let mut writers := #[]
    for result in settled do writers := writers.push (← IO.ofExcept (result.mapError IO.Error.toString))
    save (root/"writers.json") (toJson writers)
    save (root/"active-census.json") (← census active 12)
    save (root/"reference-census.json") (← census reference 3)
    check ((← originals reference) == referenceBefore) "active project writers changed their read-only reference DB"
    save (root/"writer-warm.json") (← warm plan root data activeConfig "writers-ready")
    save (root/"synapses.json") (Json.mkObj [
      ("active",← graphFacts active),("reference",← graphFacts reference)])
    save (root/"write-routing.json") (Json.mkObj [("parallelWriterChats",toJson writers.size),
      ("physicalOwnersUsed",toJson slots.size),("referenceUnchanged",toJson true)])
    check (slots.size == 4) "parallel writes did not use all four independent source owners"
  finally
    try StudyRuntime.stopManaged frontend (root/"writer-frontend-stop.json")
    finally StudyRuntime.stopManaged publisher (root/"writer-publisher-stop.json")
  let before := Json.mkObj [("active",← originals active),("reference",← originals reference)]
  let required := cases.flatMap fun item => #[item.first,item.second]
  let mut stored := #[]
  for project in [active,reference] do
    for slot in [:project.manifest.owners.size] do
      let source ← project.current slot
      let reader ← Persistence.Store.NodeReader.new source
      for record in ← Synapses.Provenance.records source do
        let document ← Synapses.Provenance.checkedDocument reader record.origin
        if let some text := document.source then stored := stored.push text
  check (required.all (fun wanted => stored.any (·.contains wanted)))
    "required evidence was not actually persisted before freezing the delivery denominator"
  save (root/"required-before-delivery.json") (Json.mkObj [
    ("originals",before),("required",toJson required),("cases",toJson chosen),
    ("allRequiredPresentInOriginals",toJson true)])
  let privateData := root/"reader-data"
  IO.FS.createDir privateData
  let readerEnv := replaceEnv plan.environment #[("EGGSHELL_DATA_ROOT",some privateData.toString),
    ("CODEX_THREAD_ID",none),("CODEX_TURN_ID",none)]
  let readPublisher ← StudyRuntime.startPublisher (.mk plan.runtime.path) privateData readerEnv
  let readFrontend ← try
      StudyRuntime.startManaged (.mk plan.runtime.path) (.mk plan.pluginRoot)
        "shared-project-readers" (privateData/"daemon.json") readerEnv
    catch error =>
      StudyRuntime.stopManaged readPublisher (root/"reader-publisher-startup-stop.json")
      throw error
  let mut replies := #[]
  let mut first : Option String := none
  try
    save (root/"reader-warm.json") (← warm plan root privateData readerConfig "reader-ready")
    let cache ← checkSharedVectors privateData [active,reference]
    save (root/"reader-cache.json") cache
    for repetition in [:2] do
      let session := s!"independent-reader-{repetition}"
      discard <| hook plan root privateData readerConfig session "start" "SessionStart"
      let output ← hook plan root privateData readerConfig session "prompt" "UserPromptSubmit" [
        ("prompt",toJson "Show the original BASE and DETAIL source definitions for the shared investigations and the reference investigation.")]
      let reply ← IO.ofExcept (Json.parse output.stdout)
      let body ← IO.ofExcept ((reply.getObjValD "hookSpecificOutput").getObjValAs? String "additionalContext")
      let some state ← (readJson? (privateData/"sessions"/session/"state.json") stateJsonDefaults :
          IO (Option ThreadState)) | throw (IO.userError "reader has no post-delivery state")
      check (state.lastSearch.any fun trace => match trace.semantic with
        | .completed => true | _ => false) "new reader did not complete semantic retrieval"
      IO.FS.writeFile (root/s!"reader-{repetition}-body.txt") body
      let missing := required.filter (!body.contains ·)
      replies := replies.push (Json.mkObj [("session",toJson session),("elapsedMs",toJson output.elapsedMs),
        ("required",toJson required.size),("delivered",toJson (required.size-missing.size)),
        ("missing",toJson missing),("sha256",toJson (Sha256.hex body.toUTF8)),
        ("search",toJson state.lastSearch),
        ("sameAsFirst",toJson (first.all (· == body)))])
      save (root/"delivery.json") (toJson replies)
      check missing.isEmpty "new read-only chat omitted DB-present required original definitions"
      check (first.all (· == body)) "identical new-chat query changed its delivered body"
      first := some body
    check (cache.getObjValD "noPrivateProjection" == toJson true)
      "read-only warm created a private matrix despite shared preparation"
  finally
    try StudyRuntime.stopManaged readFrontend (root/"reader-frontend-stop.json")
    finally StudyRuntime.stopManaged readPublisher (root/"reader-publisher-stop.json")
  check ((Json.mkObj [("active",← originals active),("reference",← originals reference)]) == before)
    "read-only recovery or delivery changed an original publication"
  save (root/"result.json") (Json.mkObj [("runtime",toJson plan.runtime),("delivery",toJson replies),
    ("projectOriginalsUnchangedByReader",toJson true),("separatePrivateRoots",toJson true),
    ("answeringModelCalls",toJson (0 : Nat)),("realMcpServerUsed",toJson false),("adopted",toJson false)])

def repairReader (inputPath sourceDirectory outputDirectory : String) (repair := true) : IO Unit := do
  let plan ← IO.ofExcept (fromJson? (α := StudySeedChecks.Input) (← StudyAdmission.readJson inputPath))
  StudyAdmission.verifyArtifact plan.runtime
  for file in plan.pluginFiles do StudyAdmission.verifyArtifact file
  StudySeedChecks.requireNumericalSupport plan
  let original := System.FilePath.mk sourceDirectory
  let root := System.FilePath.mk outputDirectory
  check (root.isAbsolute && !(← root.pathExists)) "fresh namespace-repair output required"
  IO.FS.createDirAll root
  let active ← ProjectStore.openProject (original/"active.egg")
  let reference ← ProjectStore.openProject (original/"reference.egg")
  let frozen ← StudyAdmission.readJson (original/"required-before-delivery.json").toString
  let before := Json.mkObj [("active",← originals active),("reference",← originals reference)]
  check (before == frozen.getObjValD "originals") "original snapshot changed after failed delivery"
  let required ← IO.ofExcept (frozen.getObjValAs? (Array String) "required")
  save (root/"required-before-delivery.json") frozen
  let configA := root/"active.toml"
  let configB := root/"reference.toml"
  let configR := root/"read-only.toml"
  IO.FS.writeFile configA (renderConfig plan.runtime.path active.directory reference.directory (some "active"))
  IO.FS.writeFile configB (renderConfig plan.runtime.path active.directory reference.directory (some "reference"))
  IO.FS.writeFile configR (renderConfig plan.runtime.path active.directory reference.directory none)
  let repairData := root/"repair-data"
  IO.FS.createDir repairData
  let environment := fun (data : System.FilePath) => replaceEnv plan.environment #[
    ("EGGSHELL_DATA_ROOT",some data.toString),("CODEX_THREAD_ID",none),("CODEX_TURN_ID",none)]
  if repair then
    let publisher ← StudyRuntime.startPublisher (.mk plan.runtime.path) repairData (environment repairData)
    try
      save (root/"active-warm.json") (← warm plan root repairData configA "active-ready")
      save (root/"reference-warm.json") (← warm plan root repairData configB "reference-ready")
    finally StudyRuntime.stopManaged publisher (root/"repair-publisher-stop.json")
  do
    let mut scopes := #[]
    for project in [active,reference] do
      for slot in [:project.manifest.owners.size] do
        let source ← project.current slot
        let some prepared ← PreparedInputs.loadStored? source .database MiniLM.model SearchProvider.encoderContract |
          throw (IO.userError "shared source has no prepared frame after namespace repair")
        check prepared.sharedSafe "shared prepared frame still contains private roots"
        scopes := scopes.push (Json.mkObj [("source",toJson source.head),
          ("population",toJson prepared.population),("sharedSafe",toJson prepared.sharedSafe),
          ("rootStorages",toJson prepared.publicStorages)])
    save (root/"shared-scopes.json") (toJson scopes)
  let data := root/"fresh-reader-data"
  IO.FS.createDir data
  save (root/"cache-before-start.json") (← checkSharedVectors data [active,reference])
  readiness plan.runtime.path sourceDirectory (root/"readiness-before-start.json").toString
  let readPublisher ← StudyRuntime.startPublisher (.mk plan.runtime.path) data (environment data)
  let readFrontend ← try
      StudyRuntime.startManaged (.mk plan.runtime.path) (.mk plan.pluginRoot)
        "namespace-repaired-readers" (data/"daemon.json") (environment data)
    catch error =>
      StudyRuntime.stopManaged readPublisher (root/"reader-publisher-startup-stop.json")
      throw error
  let mut replies := #[]
  let mut first : Option String := none
  try
    readiness plan.runtime.path sourceDirectory (root/"readiness-after-start.json").toString
    save (root/"reader-warm.json") (← warm plan root data configR "reader-ready")
    save (root/"reader-cache.json") (← checkSharedVectors data [active,reference])
    readiness plan.runtime.path sourceDirectory (root/"readiness-after-warm.json").toString
    for repetition in [:2] do
      let session := s!"namespace-reader-{repetition}"
      let folder := root/session
      IO.FS.createDir folder
      let env := replaceEnv (environment data) #[
        ("EGGSHELL_CONFIG",some configR.toString),("CODEX_THREAD_ID",some session),
        ("CODEX_TURN_ID",some "read-only-turn")]
      for event in ["SessionStart","UserPromptSubmit"] do
        let input := Json.mkObj [
          ("hook_event_name",toJson event),("session_id",toJson session),
          ("turn_id",toJson "read-only-turn"),("cwd",toJson original.toString),
          ("_eggshell_config",toJson configR.toString),
          ("prompt",toJson "Show the original BASE and DETAIL source definitions for the shared investigations and the reference investigation.")]
        let result ← StudyCommand.run plan.runtime.path #["codex-hook"] env original.toString
          (input.compress++"\n") (folder/event) 35000
        check (result.exitCode == 0 && result.elapsedMs < 30000) "repaired reader hook failed"
        if event == "SessionStart" then continue
        let parsed ← IO.ofExcept (Json.parse result.stdout)
        let body ← IO.ofExcept ((parsed.getObjValD "hookSpecificOutput").getObjValAs? String "additionalContext")
        IO.FS.writeFile (folder/"body.txt") body
        let state ← (readJson? (data/"sessions"/session/"state.json") stateJsonDefaults : IO (Option ThreadState))
        let complete := state.any fun state => state.lastSearch.any fun trace => match trace.semantic with
          | .completed => true | _ => false
        let missing := required.filter (!body.contains ·)
        let row := Json.mkObj [("session",toJson session),("elapsedMs",toJson result.elapsedMs),
          ("required",toJson required.size),("delivered",toJson (required.size-missing.size)),
          ("missing",toJson missing),("semanticCompleted",toJson complete),
          ("search",toJson (state.bind (·.lastSearch))),("sha256",toJson (Sha256.hex body.toUTF8)),
          ("sameAsFirst",toJson (first.all (· == body)))]
        replies := replies.push row
        save (root/"delivery.json") (toJson replies)
        check (complete && missing.isEmpty && first.all (· == body))
          "repaired reader did not deliver the same complete semantic body"
        first := some body
  finally
    try StudyRuntime.stopManaged readFrontend (root/"reader-frontend-stop.json")
    finally StudyRuntime.stopManaged readPublisher (root/"reader-publisher-stop.json")
  check ((Json.mkObj [("active",← originals active),("reference",← originals reference)]) == before)
    "namespace repair or new-reader delivery changed original DB records"
  save (root/"result.json") (Json.mkObj [("runtime",toJson plan.runtime),("delivery",toJson replies),
    ("sameOriginalSnapshotAsFailure",toJson true),("originalsUnchanged",toJson true),
    ("newReaderDataRoot",toJson true),("answeringModelCalls",toJson (0 : Nat)),
    ("dtConverterImplemented",toJson false),("adopted",toJson false)])

end Eggshell.Research.SharedProjectLifecycle
