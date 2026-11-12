import Main
import Eggshell.ContractAudit
import tools.research.SharedProjectLifecycle
import tools.research.SourceBlocks
open Lean Eggshell Eggshell.Plugin Eggshell.Plugin.Publication Eggshell.Research
namespace ProjectReadChecks
open SharedProjectLifecycle Gateway
structure Required where
  project : String
  path : String
  fingerprint : String
  text : String
  deriving ToJson, FromJson
def queries := #[
  (#["ALPHA"],"Explain ALPHA_CACHE_BASE and ALPHA_CACHE_DETAIL using the original source."),
  (#["BETA"],"Explain BETA_CACHE_BASE and BETA_CACHE_DETAIL using the original source."),
  (#["ALPHA","BETA"],"Compare ALPHA_CACHE_BASE/DETAIL and BETA_CACHE_BASE/DETAIL using both original sources.")]
def clients : Array Case := #[
  ⟨"read-service-alpha","src/alpha.cpp","ALPHA_CACHE_BASE","int ALPHA_CACHE_BASE = 731;","int ALPHA_CACHE_DETAIL = 947;"⟩,
  ⟨"read-service-beta","src/beta.cpp","BETA_CACHE_BASE","int BETA_CACHE_BASE = 613;","int BETA_CACHE_DETAIL = 829;"⟩]
def inventory (projects : Array (String × ProjectStore.Project)) : IO String := do
  let mut text := ""
  for (_,project) in projects do
    for slot in [:project.manifest.owners.size] do
      let source ← project.current slot
      let reader ← Persistence.Store.NodeReader.new source
      for item in ← Persistence.Store.searchDocuments source do
        let document ← Synapses.Build.document reader item.owner
        text := text++"\n"++document.source.getD ""
  return text
def originals (projects : Array (String × ProjectStore.Project)) : IO Json := do
  let mut heads := #[]
  for (name,project) in projects do
    for slot in [:project.manifest.owners.size] do
      let source ← project.current slot
      heads := heads.push (name,source.head,← StudyRuntime.files source.directory)
  return toJson heads
def rejectedQueries (argv : Array String) (policy : Read.Policy) : IO Unit := do
  let spawned ← IO.Process.spawn {
    cmd := argv[0]!,args := argv.extract 1 argv.size,
    stdin := .piped,stdout := .piped,stderr := .null,setsid := true }
  let (stdin,child) ← spawned.takeStdin
  let output := IO.FS.Stream.ofHandle stdin
  let input := IO.FS.Stream.ofHandle child.stdout
  let exchange := fun (id : String) (operation : Operation) => do
    writeFrame output (toJson (⟨id,Gateway.implementation,10000,operation⟩ : Request))
    let some bytes ← readFrame input | throw (IO.userError "raw query reply is absent")
    let some text := String.fromUTF8? bytes | throw (IO.userError "raw query reply is not UTF-8")
    let reply ← IO.ofExcept (Json.parse text >>= fromJson? (α := Reply))
    check (reply.id == id) "raw query reply changed its request identity"
    return reply
  try
    discard <| exchange "open" (.open ⟨#["ALPHA","BETA"],none⟩)
    let pinned ← exchange "pin" .pin
    let .value value := pinned.body | throw (IO.userError "raw read-only pin was rejected")
    let boundary ← IO.ofExcept (fromJson? (α := Boundary) value)
    let question : Read.Question := ⟨"Read the original fields.",[],policy⟩
    let cases : Array Operation := #[
      .query {boundary with projects := boundary.projects.extract 0 1} question,
      .query {boundary with scope := "foreign"} question,
      .query boundary {question with policy := {policy with numeric := false}},
      .query boundary {question with text := ""}]
    for index in [:cases.size] do
      let some operation := cases[index]? | throw (IO.userError "missing rejected query case")
      let reply ← exchange s!"deny-{index}" operation
      check (match reply.body with | .error _ => true | _ => false) "raw query bypassed its host scope or policy"
  finally
    Worker.killGroup child
    discard <| child.wait
def run (installation directory : String) : IO Unit := do
  let plan ← IO.ofExcept (fromJson? (α := StudySeedChecks.Input) (← StudyAdmission.readJson installation))
  let root := System.FilePath.mk directory
  check (root.isAbsolute && !(← root.pathExists) && (← Paths.dataRoot) == root/"client-data") "fresh isolated project read workload required"
  IO.FS.createDirAll (root/"src")
  IO.FS.createDirAll (root/"tmp")
  for item in clients do IO.FS.writeFile (root/item.path) (item.first++"\n"++item.second++"\n")
  let alpha ← ProjectStore.create (root/"alpha.egg") 2
  let beta ← ProjectStore.create (root/"beta.egg") 2
  let projects := #[("ALPHA",alpha),("BETA",beta)]
  let host := root/"host-data"
  IO.FS.createDirAll host
  let environment := replaceEnv plan.environment #[
    ("EGGSHELL_DATA_ROOT",some host.toString),("TMPDIR",some (root/"tmp").toString)]
  let runtime := System.FilePath.mk plan.runtime.path
  let publisher ← StudyRuntime.startPublisher runtime host environment
  let frontend ← try StudyRuntime.startManaged runtime (.mk plan.pluginRoot) "project-read" (host/"daemon.json") environment
    catch error => StudyRuntime.abort publisher; throw error
  try
    for index in [:clients.size] do
      let some item := clients[index]? | throw (IO.userError "missing native writer")
      let name := if index == 0 then "ALPHA" else "BETA"
      let config := root/(name++".toml")
      IO.FS.writeFile config (renderConfig plan.runtime.path alpha.directory beta.directory
        (some (if index == 0 then "active" else "reference")))
      discard <| writer plan root host config (if index == 0 then alpha.directory else beta.directory) item (keep := false)
    let cutoff := (← IO.monoMsNow)+20000
    repeat
      let raw ← inventory projects
      if clients.all (fun item => raw.contains (answer item)) then break
      check ((← IO.monoMsNow) < cutoff) "native final answers have not been published"
      IO.sleep 20
    for (_,project) in projects do discard <| census project 3
    let raw ← inventory projects
    let mut required : Array Required := #[]
    for index in [:clients.size] do
      let some item := clients[index]? | throw (IO.userError "missing frozen native original")
      let some (content,_) ← SourceEvidence.fingerprint (root/item.path) ((← IO.monoMsNow)+3000) |
        throw (IO.userError "cannot fingerprint original source")
      for text in [item.first,item.second] do
        check (raw.contains text) "required evidence is not actually present in the DB"
        required := required.push ⟨if index == 0 then "ALPHA" else "BETA",item.path,content.root,text⟩
    save (root/"required-before-delivery.json") (toJson required)
    discard <| warm plan root host (root/"ALPHA.toml") "explicit-warm"
    let frozen ← originals projects
    save (root/"originals-before.json") frozen
    -- Retrieval has to use stored originals; the host no longer has these files.
    IO.FS.removeDirAll (root/"src")
    let policy : Read.Policy := ⟨500000,true⟩
    let catalog : Catalog := ⟨#[⟨"ALPHA",alpha.directory.toString,true,true⟩,
      ⟨"BETA",beta.directory.toString,true,true⟩],policy⟩
    let profile := root/"catalog.json"
    save profile (toJson catalog)
    let argv := #["/usr/bin/env","EGGSHELL_DATA_ROOT="++host.toString,
      "EGGSHELL_PREFIX="++(← Paths.installRoot).toString,runtime.toString,"project-gateway",profile.toString]
    rejectedQueries argv policy
    let query := fun (id : String) (groups : Array String) (question : String) => do
      let started ← IO.monoMsNow
      withPeer argv ⟨groups,none⟩ (started+28000) fun peer => do
        let boundary ← peer.pin (started+28000)
        let response ← peer.query boundary question [] (started+28000)
        save (root/(id++".json")) (toJson response)
        let some advice := response.advice | throw (IO.userError "shared query returned no original evidence")
        let missing := required.filter fun item => groups.contains item.project &&
          !SourceBlocks.contains advice.text item.path item.fingerprint item.text
        check missing.isEmpty "shared query omitted DB-present source evidence"
        check (!(required.any fun item => !groups.contains item.project && advice.text.contains item.text))
          "shared query leaked an unselected project's original"
        check (advice.search.any (·.semantic == .completed) && advice.synapticComplete)
          "shared query fell back or did not complete its synaptic search"
        check (!advice.text.contains alpha.directory.toString && !advice.text.contains beta.directory.toString)
          "shared reply disclosed an internal DB directory"
        let elapsed := (← IO.monoMsNow)-started
        return Json.mkObj [("id",toJson id),("groups",toJson groups),
          ("boundary",toJson boundary),("elapsedMs",toJson elapsed),
          ("required",toJson (required.filter fun item => groups.contains item.project).size),
          ("response",toJson response)]
    let mut rows : Array Json := #[]
    for index in [:queries.size] do
      let some (groups,text) := queries[index]? | throw (IO.userError "missing project query")
      rows := rows.push (← query s!"initial-{index}" groups text)
    let start ← IO.monoMsNow
    let tasks ← (List.range 10).toArray.mapM fun index => IO.asTask (do
      let some (groups,text) := queries[index%queries.size]? | throw (IO.userError "missing parallel query")
      query s!"parallel-{index}" groups text) .dedicated
    for task in tasks do rows := rows.push (← IO.ofExcept ((← IO.wait task).mapError IO.Error.toString))
    let elapsed := (← IO.monoMsNow)-start
    check (frozen == (← originals projects)) "read-only service queries changed original publication bytes"
    save (root/"queries.json") (toJson rows)
    save (root/"result.json") (Json.mkObj [("queries",toJson rows.size),
      ("concurrentClients",toJson (10 : Nat)),("concurrentElapsedMs",toJson elapsed),
      ("originalsUnchanged",toJson true),("actualRemoteHostTested",toJson false),
      ("answeringModelCalls",toJson (0 : Nat)),("adopted",toJson false)])
  catch error =>
    save (root/"failure.json") (Json.mkObj [("error",toJson error.toString)])
    throw error
  finally
    let errors ← IO.mkRef (#[] : Array String)
    try StudyRuntime.stopManaged frontend (root/"frontend-stop.json")
    catch error => errors.modify (·.push error.toString); StudyRuntime.abort frontend
    try StudyRuntime.stopManaged publisher (root/"publisher-stop.json")
    catch error => errors.modify (·.push error.toString); StudyRuntime.abort publisher
    check (← errors.get).isEmpty "fixture services did not shut down normally"
def fresh (installation directory : String) : IO Unit := do
  let plan ← IO.ofExcept (fromJson? (α := StudySeedChecks.Input) (← StudyAdmission.readJson installation))
  let root := System.FilePath.mk directory
  let host := root/"fresh-host-data"
  check ((← root.pathExists) && !(← (root/"src").pathExists) && !(← host.pathExists) &&
    (← Paths.dataRoot) == root/"fresh-client-data") "fresh service/client roots and absent source files required"
  let alpha ← ProjectStore.openProject (root/"alpha.egg")
  let beta ← ProjectStore.openProject (root/"beta.egg")
  let projects := #[("ALPHA",alpha),("BETA",beta)]
  let frozen ← IO.ofExcept (Json.parse (← IO.FS.readFile (root/"originals-before.json")))
  check (frozen == (← originals projects)) "originals changed before the fresh-service test"
  let required ← IO.ofExcept (Json.parse (← IO.FS.readFile (root/"required-before-delivery.json")))
    >>= fun json => IO.ofExcept (fromJson? (α := Array Required) json)
  IO.FS.createDirAll host
  let runtime := System.FilePath.mk plan.runtime.path
  let environment := replaceEnv plan.environment #[("EGGSHELL_DATA_ROOT",some host.toString)]
  let publisher ← StudyRuntime.startPublisher runtime host environment
  try
    let argv := #["/usr/bin/env","EGGSHELL_DATA_ROOT="++host.toString,
      "EGGSHELL_PREFIX="++(← Paths.installRoot).toString,runtime.toString,"project-gateway",(root/"catalog.json").toString]
    let started ← IO.monoMsNow
    let tasks ← (List.range 10).toArray.mapM fun index => IO.asTask (do
      let ordinal := index%queries.size
      let some (groups,text) := queries[ordinal]? | throw (IO.userError "missing fresh-service query")
      withPeer argv ⟨groups,none⟩ (started+28000) fun peer => do
        let boundary ← peer.pin (started+28000)
        let response ← peer.query boundary text [] (started+28000)
        let some advice := response.advice | throw (IO.userError "fresh service did not return originals")
        let oldJson ← IO.ofExcept (Json.parse (← IO.FS.readFile (root/s!"initial-{ordinal}.json")))
        let previous ← IO.ofExcept (fromJson? (α := Read.Response) oldJson)
        check (previous.advice.any (·.text == advice.text)) "fresh service changed actual body on the same cut"
        check (advice.search.any (·.semantic == .completed) && advice.synapticComplete)
          "fresh service did not finish semantic/synaptic discovery"
        for item in required do
          if groups.contains item.project then
            check (SourceBlocks.contains advice.text item.path item.fingerprint item.text) "fresh service omitted a frozen source field"
          else check (!advice.text.contains item.text) "fresh service leaked another project"
        return Json.mkObj [("groups",toJson groups),("boundary",toJson boundary),
          ("required",toJson (required.filter fun item => groups.contains item.project).size),
          ("response",toJson response)]) .dedicated
    let mut rows := #[]
    for task in tasks do rows := rows.push (← IO.ofExcept ((← IO.wait task).mapError IO.Error.toString))
    let elapsed := (← IO.monoMsNow)-started
    check (frozen == (← originals projects)) "fresh-service queries changed original DB files"
    save (root/"fresh-queries.json") (toJson rows)
    save (root/"fresh-result.json") (Json.mkObj [("queries",toJson rows.size),("concurrentElapsedMs",toJson elapsed),
      ("manualWarmCalls",toJson (0 : Nat)),("actualBodiesMatchPrevious",toJson true),("originalsUnchanged",toJson true),
      ("actualRemoteHostTested",toJson false),("answeringModelCalls",toJson (0 : Nat))])
  finally
    try StudyRuntime.stopManaged publisher (root/"fresh-publisher-stop.json")
    catch error => StudyRuntime.abort publisher; throw error
end ProjectReadChecks
