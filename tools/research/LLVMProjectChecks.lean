import Main
import Eggshell.ContractAudit
import tools.research.RegisteredHook
import tools.research.NativeTrialAudit
import tools.research.StudyRuntime
import tools.research.StudyLaunchers

open Lean Eggshell Eggshell.Plugin Eggshell.Research
namespace LLVMProjectChecks
structure Plan where
  installation : StudySeedChecks.Input
  original : String
  originalFiles : Array (String × String)
  definitions : String
  workspace : String
  root : String
  records : String
  project : Option String := none
  deriving FromJson, ToJson
def Plan.projectPath (plan : Plan) : System.FilePath :=
  plan.project.map System.FilePath.mk |>.getD (System.FilePath.mk plan.root/"llvm.egg")
structure Definition where
  topic : Nat
  prompt : StudyAdmission.Artifact
  referenceRanges : Array OriginalEvidence.Reference
  deriving FromJson
def check (condition : Bool) (message : String) : IO Unit :=
  unless condition do throw (IO.userError message)
def read (path : System.FilePath) : IO Json := do
  IO.ofExcept (Json.parse (← IO.FS.readFile path))
def write (path : System.FilePath) (value : Json) : IO Unit := IO.FS.writeFile path value.compress
def replace (environment updates : Array (String × Option String)) :=
  environment.filter (fun row => !updates.any (·.1 == row.1))++updates
def environment (plan : Plan) (data : System.FilePath) :=
  replace plan.installation.environment #[("EGGSHELL_DATA_ROOT",some data.toString),
    ("EGGSHELL_CONFIG",some (System.FilePath.mk plan.root/"host.toml").toString),
    ("TMPDIR",some (System.FilePath.mk plan.root/"tmp").toString),
    ("CODEX_THREAD_ID",none),("CODEX_TURN_ID",none)]
def load (input : String) : IO Plan := do
  let plan ← IO.ofExcept (fromJson? (α := Plan) (← read (.mk input)))
  check (plan.installation.handoffChars == 120000) "retain the ordinary character budget"
  StudyAdmission.verifyArtifact plan.installation.runtime
  for file in plan.installation.pluginFiles do StudyAdmission.verifyArtifact file
  StudySeedChecks.requireNumericalSupport plan.installation
  for (name,expected) in plan.originalFiles do
    check ((← ArtifactHash.hex (System.FilePath.mk plan.original/name)) == expected) "protected native LLVM source changed"
  return plan

/-- No query, warm, handoff body or answering model is opened before every
DB-present original-evidence obligation has been frozen independently. -/
def prepare (input : String) : IO Unit := do
  let plan ← load input
  let root : System.FilePath := .mk plan.root
  let records : System.FilePath := .mk plan.records
  check (!(← root.pathExists) && (← records.isDir)) "fresh LLVM project capture required"
  IO.FS.createDirAll (root/"commands")
  IO.FS.createDirAll (root/"tmp")
  let projectPath := plan.projectPath
  let runtime := plan.installation.runtime.path
  IO.FS.writeFile (root/"host.toml") ("default = \"work\"\nsemantic_matcher = "++
    (toJson #[runtime,"search-provider"]).compress++"\n[eggs]\nllvm = "++
    (toJson projectPath.toString).compress++"\n[profiles.work]\nread = [\"llvm\"]\nhandoff_chars = 120000\n")
  if plan.project.isNone then
    let captured ← StudyCommand.run (plan.installation.pluginRoot++"/bin/egg")
      #["snapshot",plan.original,projectPath.toString] (environment plan (root/"host")) plan.workspace ""
      (root/"commands/snapshot") 180000
    check (captured.exitCode == 0 && captured.stderr.isEmpty) ("actual egg snapshot failed: "++captured.stderr)
  let project ← ProjectStore.openProject projectPath
  let source ← project.current 0
  let original ← DB.PageMap.pin (.mk plan.original)
  check (source.head == original.head && !project.manifest.writable) "capture changed source identity or write authority"
  let sourceFiles ← StudyRuntime.files source.directory
  let definitions ← IO.ofExcept (fromJson? (α := Array Definition) (← read (.mk plan.definitions)))
  check (definitions.map (·.topic) == #[1,2,3]) "fixed three-topic definitions required"
  let mut topics := #[]
  for definition in definitions do
    StudyAdmission.verifyArtifact definition.prompt
    let specification := Json.mkObj [("source",toJson source.directory.toString),
      ("workspace",toJson plan.workspace),("prompt",toJson (← IO.FS.readFile (.mk definition.prompt.path))),
      ("files",toJson sourceFiles),("required",toJson definition.referenceRanges)]
    let frozen ← NativeTrialAudit.freezeAvailable specification
    topics := topics.push (Json.mkObj [("topic",toJson definition.topic),("specification",specification),
      ("frozen",toJson frozen),("eligible",toJson frozen.units.size),("absent",toJson frozen.absent)])
  write (records/"before-delivery.json") (Json.mkObj [("runtime",toJson plan.installation.runtime),
    ("originalHead",toJson original.head),("capturedHead",toJson source.head),
    ("manifest",toJson project.manifest),("sourceFiles",toJson sourceFiles),("topics",toJson topics),
    ("frozenBeforeAnyQueryOrWarm",toJson true),("acceptedSeed",toJson false),
    ("answeringModelCalls",toJson (0 : Nat)),("adopted",toJson false)])
  let connection := root/"connections/read-llvm.json"
  let catalog : Publication.Gateway.Catalog := ⟨#[⟨"LLVM",projectPath.toString,true,false⟩],⟨120000,true⟩⟩
  let delegation : Publication.Gateway.Delegation :=
    ⟨⟨#["LLVM"],none⟩,Blake3.hex (← IO.getRandomBytes 32),connection.toString⟩
  FileSystem.privateDirectory (root/"host/publisher")
  write (root/"host/publisher/project-access.json") (toJson (⟨catalog,#[delegation]⟩ : Publication.Gateway.Host))
  IO.FS.writeFile (root/"client.toml") ("default = \"work\"\nsemantic_matcher = "++
    (toJson #[runtime,"search-provider"]).compress++"\n[profiles.work]\nproject_service = "++
    (toJson connection.toString).compress++"\nread = [\"LLVM\"]\nhandoff_chars = 120000\n")

def run (input : String) : IO Unit := do
  let plan ← load input
  let root : System.FilePath := .mk plan.root
  let records : System.FilePath := .mk plan.records
  let frozen ← read (records/"before-delivery.json")
  check (frozen.getObjValD "frozenBeforeAnyQueryOrWarm" == toJson true) "evidence denominator was not frozen first"
  let topics ← IO.ofExcept ((frozen.getObjValD "topics").getArr?)
  let project ← ProjectStore.openProject plan.projectPath
  check (toJson (← project.current 0).head == frozen.getObjValD "capturedHead") "captured source head changed"
  let data := root/"client"
  check ((← Paths.dataRoot) == data && !(← (records/"result.json").pathExists)) "isolated fresh LLVM clients required"
  let services ← IO.mkRef (#[] : Array (StudyRuntime.Managed × String))
  let started ← IO.monoMsNow
  try
    let host ← StudyRuntime.startPublisher (.mk plan.installation.runtime.path) (root/"host")
      (environment plan (root/"host"))
    services.modify (·.push (host,"host"))
    let warm ← StudyCommand.run (plan.installation.pluginRoot++"/bin/egg")
      #["warm","--shared",project.directory.toString] (environment plan (root/"host")) plan.workspace ""
      (root/"commands/shared-warm") 190000
    write (records/"warm.json") (toJson warm)
    check (warm.exitCode == 0 && warm.stderr.isEmpty) ("actual host shared warm failed: "++warm.stderr)
    let clientEnvironment := replace (environment plan data) #[("EGGSHELL_CONFIG",some (root/"client.toml").toString)]
    let client ← StudyRuntime.startPublisher (.mk plan.installation.runtime.path) data clientEnvironment
    services.modify (·.push (client,"client-publisher"))
    let frontend ← StudyRuntime.startManaged (.mk plan.installation.runtime.path) (.mk plan.installation.pluginRoot)
      "llvm-project-service" (data/"daemon.json") clientEnvironment
    services.modify (·.push (frontend,"frontend"))
    let mut queries := #[]
    for pass in [:2] do
      for topic in topics do
        let number ← IO.ofExcept (topic.getObjValAs? Nat "topic")
        let specification := topic.getObjValD "specification"
        let prompt ← IO.ofExcept (specification.getObjValAs? String "prompt")
        let session := s!"llvm-pass-{pass}-topic-{number}"
        IO.FS.createDirAll (root/"tmp"/session)
        discard <| RegisteredHook.invoke plan.installation root (.mk plan.workspace) data (root/"client.toml")
          session "start" "SessionStart"
        let output ← RegisteredHook.invoke plan.installation root (.mk plan.workspace) data (root/"client.toml")
          session "prompt" "UserPromptSubmit" [("prompt",toJson prompt)]
        let reply ← IO.ofExcept (Json.parse output.stdout)
        let body := ((reply.getObjValD "hookSpecificOutput").getObjValAs? String "additionalContext").toOption.getD ""
        let bodyPath := records/s!"pass-{pass}-topic-{number}.txt"
        IO.FS.writeFile bodyPath body
        let assessed ← NativeTrialAudit.replayAvailable specification bodyPath.toString (Sha256.hex body.toUTF8)
        check (assessed.getObjValD "availableEvidence" == topic.getObjValD "frozen") "evidence denominator changed after delivery"
        let files ← sessionFiles session
        let some state ← readState? files | throw (IO.userError "actual registered hook omitted session state")
        let semantic := state.lastSearch.map (·.semantic) |>.getD .notRequested
        let result := Json.mkObj [("pass",toJson pass),("topic",toJson number),("session",toJson session),
          ("elapsedMs",toJson output.elapsedMs),("semantic",toJson semantic),("search",toJson state.lastSearch),
          ("bodyBytes",toJson body.utf8ByteSize),("bodySha256",toJson (Sha256.hex body.toUTF8)),
          ("incompleteNotice",toJson (body.contains "EGGSHELL SEARCH INCOMPLETE")),("assessment",assessed)]
        queries := queries.push result
        write (records/"queries.json") (toJson queries)
        discard <| RegisteredHook.invoke plan.installation root (.mk plan.workspace) data (root/"client.toml")
          session "stop" "Stop" [("last_assistant_message",toJson "Model-free original-evidence audit completed.")]
    let successful := queries.size == 6 && queries.all (fun row => row.getObjValD "semantic" == toJson "completed" &&
      row.getObjValD "incompleteNotice" == toJson false &&
      ((row.getObjValD "assessment").getObjValD "availableDelivery").getObjValD "targetMet" == toJson true)
    write (records/"result.json") (Json.mkObj [("queries",toJson queries),("allSixReachTarget",toJson successful),
      ("elapsedMs",toJson ((← IO.monoMsNow)-started)),("scope",toJson "six fresh-chat retrieval audits of one fixed incomplete native corpus; no answering rounds"),
      ("handoffChars",toJson plan.installation.handoffChars),("answeringModelCalls",toJson (0 : Nat)),
      ("acceptedSeed",toJson false),("adopted",toJson false)])
  finally
    let mut failures : Array String := #[]
    for (service,name) in (← services.get).reverse do
      try StudyRuntime.stopManaged service (records/(name++"-stop.json"))
      catch error => failures := failures.push error.toString; StudyRuntime.abort service
    check failures.isEmpty ("owned LLVM services did not drain: "++toString failures)

/-- Replay the product's read computation with its existing range receipt.
This is a diagnostic, not another hook latency sample. Reject it unless the
entire resulting body equals the earlier ordinary fresh-chat body. No frozen
requirement enters the product computation. -/
def diagnose (input : String) : IO Unit := do
  let plan ← load input
  let root : System.FilePath := .mk plan.root
  let records : System.FilePath := .mk plan.records
  let output := records/"diagnostic"
  check (!(← output.pathExists) && (← Paths.dataRoot) == root/"host") "fresh host-side range diagnostic required"
  IO.FS.createDirAll output
  let frozen ← read (records/"before-delivery.json")
  let topics ← IO.ofExcept ((frozen.getObjValD "topics").getArr?)
  let some topic := topics[0]? | throw (IO.userError "missing fixed first topic")
  let question ← IO.ofExcept ((topic.getObjValD "specification").getObjValAs? String "prompt")
  let project ← ProjectStore.openProject plan.projectPath
  let service ← StudyRuntime.startPublisher (.mk plan.installation.runtime.path) (root/"host") (environment plan (root/"host"))
  let coordinator ← SearchReaders.Coordinator.new
  try
    let pool ← Publication.Owned.Pool.new
    let grant ← pool.registerRead project.directory project.manifest.identity
    let deadline := (← IO.monoMsNow)+29000
    let (_,pins) ← Publication.Read.pin pool grant.manifest.identity grant.capability deadline
    let source ← project.current 0
    let some pin := pins[0]? | throw (IO.userError "missing captured preparation pin")
    let captured ← ProjectReadSnapshot.load source pin MiniLM.model SearchProvider.encoderContract
    let inputs := #[captured.input]
    let owners : OwnerViews.Reference := ⟨OwnerViews.implementation,#[source.head],#[captured.owner]⟩
    let frame ← PreparedReaders.Frame.capture #[source] inputs (some owners)
    let cancelled ← IO.mkRef false
    let session ← coordinator.borrow frame deadline cancelled
    let prepared ← session.pool.acquire session.sources inputs (some owners)
    let synaptic ← Synapses.Recommend.prepareMany session.sources (some inputs) deadline (some prepared)
    try
      check (synaptic.all (·.failure.isNone)) "diagnostic omitted a prepared synaptic input"
      let selection : Config.Selection := {
        label := "project-service",semanticMatcher := some [plan.installation.runtime.path,"search-provider"],
        read := [⟨project.manifest.identity++":0",source.directory⟩],write := none,
        handoffChars := 120000,localUnion := false }
      let receipt ← Receipt.fresh
      write (output/"request.json") (Json.mkObj [("receipt",toJson receipt),("question",toJson question),
        ("source",toJson source.head),("oraclePassedToProduct",toJson false),
        ("latencySample",toJson false),("productChanged",toJson false)])
      let handoff ← computeAutomaticHandoff selection (session.sources.toList.map some) question [] false
        (enableLocalUnion := false) (meaningQuery := some question) (receipt := some receipt)
        (synaptic := synaptic) (upstreamDeadline := some deadline) (queryInputs := some inputs)
        (queryOwners := some owners) (preparedReaders := some prepared)
      let some handoff := handoff | throw (IO.userError "diagnostic produced no handoff")
      let advice ← IO.ofExcept (Publication.Read.advice handoff)
      let ordinary ← IO.FS.readFile (records/"pass-0-topic-1.txt")
      IO.FS.writeFile (output/"body.txt") advice.text
      let same := ordinary == advice.text
      write (output/"validation.json") (Json.mkObj [("sameOrdinaryBody",toJson same),
        ("ordinarySha256",toJson (Sha256.hex ordinary.toUTF8)),("diagnosticSha256",toJson (Sha256.hex advice.text.toUTF8)),
        ("source",toJson source.head),("sourceOraclePassedToProduct",toJson false),
        ("newHookLatencySamples",toJson (0 : Nat)),("answeringModelCalls",toJson (0 : Nat))])
      check same "diagnostic body differs; its decisions cannot explain the ordinary hook"
      let directory := root/"host/receipts"/receipt
      write (output/"selection.json") (← Receipt.readSelection directory)
      write (output/"domain.json") ((← read (directory/"delivery-domain.json")).getObjValD "data")
    finally Synapses.Recommend.releaseMany synaptic ((← IO.monoMsNow)+1000)
  finally
    coordinator.close
    StudyRuntime.stopManaged service (output/"host-stop.json")
end LLVMProjectChecks

def main : List String → IO UInt32
  | ["bind",directory,inherited] => do
    let target : System.FilePath := .mk directory
    let parent : System.FilePath := .mk inherited
    unless target.isAbsolute && parent.isAbsolute && target != parent do
      throw (IO.userError "isolated launcher binding required")
    for name in ["egg","eggshelld"] do
      let relative := "plugins/eggshell/bin/"++name
      unless (← IO.FS.readFile (target/relative)) == (← IO.FS.readFile (parent/relative)) do
        throw (IO.userError "copied launcher changed before binding")
      Install.writeExecutable (target/relative) (Install.pluginLauncher target)
    StudyLaunchers.verify target
    return 0
  | ["prepare",input] => do LLVMProjectChecks.prepare input; return 0
  | ["run",input] => do LLVMProjectChecks.run input; return 0
  | ["diagnose",input] => do LLVMProjectChecks.diagnose input; return 0
  | _ => throw (IO.userError "LLVMProjectChecks prepare|run PLAN")
