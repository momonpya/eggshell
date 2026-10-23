import tools.research.NativeTrialAudit
import tools.research.StudyRuntime
import tools.research.StudyTransport
import tools.research.StudyCommand
import tools.research.ArtifactHash

open Lean Eggshell

namespace Eggshell.Research.StudyAdmission

structure Artifact where
  path : String
  sha256 : String
  deriving FromJson, ToJson

structure Preparation where
  input : Artifact
  stdout : Artifact
  timing : Artifact
  body : Artifact
  state : Artifact
  shutdown : Artifact
  search : Artifact
  numerical : Array Artifact
  auditInput : Artifact
  auditReport : Artifact
  session : String
  deriving FromJson, ToJson

structure Plan where
  label : String
  purpose : String
  topic : Nat
  stage : Nat
  repetition : Nat
  model : String
  effort : String
  workspace : String
  sourceCommit : String
  prompt : Artifact
  runner : Artifact
  cliWrapper : Artifact
  nativeCli : Artifact
  runtime : Artifact
  accountConfiguration : Artifact
  configuration : Artifact
  harness : Array Artifact
  pluginRoot : String
  pluginFiles : Array Artifact
  sourceSnapshot : String
  sourceFiles : Array (String × String)
  database : String
  databaseFiles : Array (String × String)
  dataRoot : String
  privateFiles : Array (String × String)
  environment : Array (String × Option String)
  preparation : Preparation
  output : String
  guardRecord : String
  deriving FromJson, ToJson

structure Admitted where
  private mk ::
  plan : Plan
  prompt : String
  bodySha256 : String
  audit : Json
  liveDoctor : Json
  knownOmissions : Array String
  modelExact : plan.model = "gpt-5.6-luna"
  effortExact : plan.effort = "xhigh"

private def check (condition : Bool) (message : String) : IO Unit :=
  unless condition do throw (IO.userError message)

def readJson (path : String) : IO Json := do
  IO.ofExcept (Json.parse (← IO.FS.readFile (.mk path)))

/-- The opened file's identity/version and its resolved path must remain stable
across hashing. Credentials are not experiment artifacts. -/
def verifyArtifact (artifact : Artifact) : IO Unit := do
  let path := System.FilePath.mk artifact.path
  check (path.isAbsolute && path.fileName != some "auth.json") "invalid experiment artifact path"
  check ((← ArtifactHash.hex path) == artifact.sha256) s!"sealed artifact changed: {path}"

private def sorted (files : Array (String × String)) := files.qsort (fun a b => a.1 < b.1)

partial def tree (root : System.FilePath) (relative : String := "") : IO (Array (String × String)) := do
  let mut result := #[]
  for entry in ← (root / relative).readDir do
    let name := if relative.isEmpty then entry.fileName else relative ++ "/" ++ entry.fileName
    let metadata ← entry.path.symlinkMetadata
    if metadata.type == .dir then result := result ++ (← tree root name)
    else
      check (metadata.type == .file && entry.fileName != "daemon.json") "private preparation has a symlink or live daemon"
      result := result.push (name,← ArtifactHash.hex entry.path)
  return sorted result

def env (plan : Plan) (name : String) : Option String :=
  (plan.environment.find? (·.1 == name)).bind (·.2)

private def requireEnv (plan : Plan) (key value : String) : IO Unit :=
  check (env plan key == some value) s!"prepared environment differs: {key}"

private def datum (artifact : Artifact) : IO Json := do
  let json ← readJson artifact.path
  IO.ofExcept (json.getObjVal? "data")

/-- Stored receipts do not imply that cache files still exist. Inspect the
current DB through the frozen runtime, without starting an encoder. -/
def verifyLiveWarm (plan : Plan) : IO Json := do
  let directory := System.FilePath.mk (plan.output ++ s!".warm-check-{← IO.Process.getPID}-{← IO.monoNanosNow}")
  let result ← StudyCommand.run plan.runtime.path #["egg","doctor"] plan.environment plan.workspace "" directory 60000
  check (result.exitCode == 0) "current native cache inspection failed"
  let doctor ← IO.ofExcept (Json.parse result.stdout)
  let databases ← IO.ofExcept (doctor.getObjValAs? (Array Json) "databases")
  check (databases.size == 1) "current cache inspection selected another database set"
  let database := databases[0]!
  check ((database.getObjValAs? String "path").toOption == some plan.database &&
    (database.getObjValAs? String "state").toOption == some "warm") "current database is cold"
  let coverage ← IO.ofExcept (database.getObjVal? "coverage")
  for lane in #[coverage,← IO.ofExcept (coverage.getObjVal? "discovery"),← IO.ofExcept (coverage.getObjVal? "focus")] do
    let windows ← IO.ofExcept (lane.getObjValAs? Nat "windows")
    check (windows > 0 && (lane.getObjValAs? Nat "valid").toOption == some windows &&
      (lane.getObjValAs? Nat "missing").toOption == some 0 &&
      (lane.getObjValAs? Nat "invalid").toOption == some 0) "current source windows are missing or invalid"
  return Json.mkObj [("directory",toJson directory.toString),("report",doctor)]

def admit (path expectedSha256 : String) : IO Admitted := do
  verifyArtifact ⟨path,expectedSha256⟩
  let plan ← IO.ofExcept (fromJson? (α := Plan) (← readJson path))
  let modelExact : PLift (plan.model = "gpt-5.6-luna") ←
    if h : plan.model = "gpt-5.6-luna" then pure ⟨h⟩ else throw (IO.userError "model substitution is not permitted")
  let effortExact : PLift (plan.effort = "xhigh") ←
    if h : plan.effort = "xhigh" then pure ⟨h⟩ else throw (IO.userError "reasoning effort differs from the study")
  check (!plan.label.isEmpty && plan.label.toList.all (fun c => c.isAlphanum || c == '-' || c == '_' || c == '.'))
    "invalid trial label"
  check (1 ≤ plan.stage && plan.stage ≤ 6 && plan.topic == (plan.stage-1)%3+1 &&
      #["pilot","comparison"].contains plan.purpose) "trial is outside the frozen six-stage design"
  check ((System.FilePath.mk plan.workspace).isAbsolute && (System.FilePath.mk plan.output).isAbsolute &&
    !(← (System.FilePath.mk plan.output).pathExists)) "trial workspace/output is invalid or already used"
  let p := plan.preparation
  let artifacts := #[plan.prompt,plan.runner,plan.cliWrapper,plan.nativeCli,plan.runtime,
    plan.accountConfiguration,plan.configuration,p.input,p.stdout,p.timing,p.body,p.state,p.shutdown,
    p.search,p.auditInput,p.auditReport] ++ plan.harness ++ plan.pluginFiles ++ p.numerical
  for artifact in artifacts do verifyArtifact artifact
  check (!plan.harness.isEmpty && !plan.pluginFiles.isEmpty &&
    plan.pluginFiles.any (·.path == plan.pluginRoot ++ "/bin/eggshelld")) "unsealed harness or plugin launcher"
  let environmentNames := (plan.environment.map (·.1)).toList
  check (environmentNames.eraseDups.length == plan.environment.size) "duplicate environment setting"
  requireEnv plan "EGGSHELL_DATA_ROOT" plan.dataRoot
  requireEnv plan "EGGSHELL_CONFIG" plan.configuration.path
  requireEnv plan "CODEX_HOME" ((System.FilePath.mk plan.accountConfiguration.path).parent.getD (.mk "")).toString
  requireEnv plan "EGGSHELL_PROFILE" "work"
  check ((env plan "EGGSHELL_PREFIX").any (fun root => root ++ "/libexec/eggshell" == plan.runtime.path))
    "prepared runtime prefix differs"
  check ((env plan "EGGSHELL_TARGET").isNone && (env plan "EGGSHELL_HANDOFF_BYTES").isNone)
    "unsealed target/budget override"
  let commit ← IO.Process.output {cmd := "/usr/bin/git",args := #["rev-parse","HEAD"],cwd := some (.mk plan.workspace)}
  let clean ← IO.Process.output {cmd := "/usr/bin/git",args := #["status","--porcelain"],cwd := some (.mk plan.workspace)}
  check (commit.exitCode == 0 && commit.stdout.trimAscii.copy == plan.sourceCommit &&
    clean.exitCode == 0 && clean.stdout.trimAscii.isEmpty) "source checkout changed"
  check (sorted plan.sourceFiles == (← StudyRuntime.files (.mk plan.sourceSnapshot)) &&
    sorted plan.databaseFiles == (← StudyRuntime.files (.mk plan.database))) "saved publication changed"
  FileSystem.rejectSymlinkAncestors (.mk plan.dataRoot)
  check ((← tree (.mk plan.dataRoot)) == sorted plan.privateFiles) "private preparation changed"
  let config ← Config.parseFile (.mk plan.configuration.path)
  let selected ← IO.ofExcept (Config.resolve config "work")
  check (config.defaultProfile == "work" && selected.read.map (·.path.toString) == [plan.database] &&
    selected.write.map (·.path.toString) == some plan.database && selected.handoffChars == 120000 &&
    selected.semanticMatcher == some [plan.runtime.path,"search-provider"])
    "prepared profile, database, provider or budget differs"
  let prompt ← IO.FS.readFile (.mk plan.prompt.path)
  let request ← readJson p.input.path
  check ((request.getObjValAs? String "_eggshell_config").toOption == some plan.configuration.path &&
    (request.getObjValAs? String "session_id").toOption == some p.session)
    "preflight used another config or session"
  let auditInput ← readJson p.auditInput.path
  let source ← IO.ofExcept (auditInput.getObjVal? "source")
  check ((auditInput.getObjValAs? String "database").toOption == some plan.database &&
    (source.getObjValAs? String "source").toOption == some plan.sourceSnapshot &&
    (source.getObjValAs? String "workspace").toOption == some plan.workspace &&
    (source.getObjValAs? String "prompt").toOption == some prompt &&
    (source.getObjValAs? (Array (String × String)) "files").toOption.map sorted == some (sorted plan.sourceFiles))
    "audit is bound to a different publication or question"
  for (key,artifact) in #[("request",p.input),("stdout",p.stdout),("timing",p.timing),("body",p.body)] do
    check ((auditInput.getObjValAs? String key).toOption == some artifact.path) s!"audit references another {key}"
  let audit ← NativeTrialAudit.inspect p.auditInput.path
  check (audit == (← readJson p.auditReport.path)) "native source/code audit is stale"
  check ((audit.getObjValAs? Nat "originalRows").toOption.any (· > 0)) "no original memory observations"
  let body ← IO.FS.readFile (.mk p.body.path)
  check (!body.trimAscii.isEmpty && !(body.contains "EGGSHELL SEARCH INCOMPLETE")) "preflight did not deliver a memory body"
  let state ← readJson p.state.path
  check ((state.getObjValAs? String "lastHandoff").toOption == some body &&
    (state.getObjValAs? (Array String) "deliveredGraphs").toOption.any (! ·.isEmpty)) "preflight was not acknowledged"
  let shutdown ← readJson p.shutdown.path
  check ((shutdown.getObjValAs? String "phase").toOption == some "stopped" &&
    (shutdown.getObjValAs? Bool "acknowledged").toOption == some true &&
    (shutdown.getObjValAs? Nat "daemonExitCode").toOption == some 0 &&
    (shutdown.getObjValAs? Bool "endpointRemoved").toOption == some true) "preparation daemon did not close cleanly"
  let search ← datum p.search
  let trace ← IO.ofExcept (search.getObjVal? "trace")
  check ((trace.getObjValAs? String "semantic").toOption == some "completed") "warm semantic preflight did not complete"
  let mut purposes : Std.HashSet String := {}
  for numerical in p.numerical do
    let receipt ← datum numerical
    let corpus ← IO.ofExcept (receipt.getObjVal? "corpus")
    purposes := purposes.insert (← IO.ofExcept (corpus.getObjValAs? String "purpose"))
    let counters ← IO.ofExcept (receipt.getObjVal? "counters")
    let sources ← IO.ofExcept (counters.getObjVal? "source")
    let encoder ← IO.ofExcept (counters.getObjVal? "encoder")
    check ((receipt.getObjValAs? String "status").toOption == some "completed" &&
      (sources.getObjValAs? Nat "hit").toOption.any (· > 0) &&
      (sources.getObjValAs? Nat "absent").toOption == some 0 &&
      (sources.getObjValAs? Nat "unusable").toOption == some 0 &&
      (encoder.getObjValAs? Nat "sourceEncodeUs").toOption == some 0)
      "preflight has cold/invalid source vectors or encoded source windows inside the hook"
  check (purposes.size == 2 && purposes.contains "discovery" && purposes.contains "focus")
    "both warm numerical lanes are required"
  let requirements ← IO.ofExcept (audit.getObjValAs? (Array Json) "requirements")
  let knownOmissions ← (requirements.filter fun row =>
    (row.getObjValAs? Bool "stored").toOption == some true &&
    (row.getObjValAs? Bool "bodyDelivered").toOption != some true).mapM fun row =>
      IO.ofExcept (row.getObjValAs? String "name")
  check (plan.purpose == "pilot" || knownOmissions.isEmpty) "comparison preflight omits known required source code"
  let liveDoctor ← verifyLiveWarm plan
  return {
    plan,prompt,bodySha256 := p.body.sha256,audit,liveDoctor,knownOmissions
    modelExact := modelExact.down,effortExact := effortExact.down}

end Eggshell.Research.StudyAdmission
