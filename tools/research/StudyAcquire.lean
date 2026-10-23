import tools.research.StudyTrial

open Lean Eggshell

namespace Eggshell.Research.StudyAcquire

structure Gate where
  report : StudyAdmission.Artifact
  guard : StudyAdmission.Artifact
  shutdown : StudyAdmission.Artifact
  recovery : StudyAdmission.Artifact
  deriving FromJson, ToJson

structure Plan where
  kind : String
  label : String
  model : String
  effort : String
  provider : String
  workspace : String
  sourceCommit : String
  output : String
  guardRecord : String
  runtime : StudyAdmission.Artifact
  runner : StudyAdmission.Artifact
  cliWrapper : StudyAdmission.Artifact
  nativeCli : StudyAdmission.Artifact
  accountConfiguration : StudyAdmission.Artifact
  prompt : StudyAdmission.Artifact
  pluginRoot : String
  pluginFiles : Array StudyAdmission.Artifact
  harness : Array StudyAdmission.Artifact
  gate : Gate
  environment : Array (String × Option String)
  deriving FromJson, ToJson

private def check (condition : Bool) (message : String) : IO Unit :=
  unless condition do throw (IO.userError message)

private def save (directory : System.FilePath) (name : String) (value : Json) : IO Unit := do
  let path := directory / name
  check (!(← path.pathExists)) "keep previous acquisition evidence"
  IO.FS.writeFile path (value.compress ++ "\n")

private def replaceEnv (original updates : Array (String × Option String)) :=
  original.filter (fun row => !updates.any (·.1 == row.1)) ++ updates

private def verifySource (plan : Plan) : IO Unit := do
  let commit ← IO.Process.output {cmd := "git",args := #["rev-parse","HEAD"],cwd := some (.mk plan.workspace)}
  let status ← IO.Process.output {cmd := "git",args := #["status","--porcelain"],cwd := some (.mk plan.workspace)}
  check (commit.exitCode == 0 && commit.stdout.trimAscii.toString == plan.sourceCommit &&
    status.exitCode == 0 && status.stdout.trimAscii.isEmpty) "source commit or clean workspace changed"

private def verify (plan : Plan) : IO StudyAccounting.Acquisition := do
  check (plan.model == "gpt-5.6-luna" && plan.effort == "xhigh") "fixed Luna/xhigh required"
  check (plan.provider == "openai" || plan.provider == "synthetic") "explicit acquisition provider required"
  let kind ← match plan.kind with
    | "seed" => pure StudyAccounting.Acquisition.seed
    | "fresh" => pure .fresh
    | _ => throw (IO.userError "acquisition kind must be seed or fresh")
  for artifact in #[plan.runtime,plan.runner,plan.cliWrapper,plan.nativeCli,plan.accountConfiguration,plan.prompt,
      plan.gate.report,plan.gate.guard,plan.gate.shutdown,plan.gate.recovery] ++ plan.pluginFiles ++ plan.harness do
    StudyAdmission.verifyArtifact artifact
  let gate ← StudyAdmission.readJson plan.gate.report.path
  let guard ← StudyAdmission.readJson plan.gate.guard.path
  let shutdown ← StudyAdmission.readJson plan.gate.shutdown.path
  let recovered ← StudyAdmission.readJson plan.gate.recovery.path
  check ((gate.getObjVal? "runtime").toOption == some (toJson plan.runtime) &&
    (gate.getObjValAs? Bool "emptyInitialDatabase").toOption == some true &&
    (gate.getObjValAs? Nat "answeringModelCalls").toOption == some 0 &&
    (gate.getObjValAs? Nat "directRelationInsertions").toOption == some 0 &&
    (gate.getObjValAs? Nat "consumptionWitnesses").toOption.any (· > 0) &&
    (gate.getObjValAs? Nat "actualToolCalls").toOption == (gate.getObjValAs? Nat "portableOrigins").toOption)
    "native empty-DB provenance gate is absent or belongs to another runtime"
  check ((guard.getObjValAs? Nat "exitCode").toOption == some 0 &&
    (guard.getObjValAs? (Array Nat) "ownedPids").toOption == some #[] &&
    (shutdown.getObjValAs? Nat "daemonExitCode").toOption == some 0 &&
    (shutdown.getObjValAs? Bool "endpointRemoved").toOption == some true &&
    (recovered.getObjValAs? Bool "sourceOnlyCheckpoint").toOption == some true &&
    (recovered.getObjValAs? Bool "publicationUnchanged").toOption == some true &&
    (recovered.getObjValAs? Nat "consumptionWitnesses").toOption.any (· > 0))
    "native gate cleanup or portable source-only recovery failed"
  check ((← IO.FS.realPath (← IO.appPath)) == (← IO.FS.realPath (.mk plan.runner.path)))
    "running acquisition controller differs from frozen harness"
  verifySource plan
  return kind

private def observedPromptHook (scope : StudyAccounting.Scope) (path : System.FilePath) : IO Bool := do
  let input ← IO.FS.Handle.mk path .read
  let mut found := false
  repeat
    let line ← input.getLine
    if line.isEmpty then break
    let .ok row := Json.parse line | continue
    if (row.getObjValAs? String "direction").toOption != some "server" then continue
    let .ok message := row.getObjVal? "message" | continue
    if (message.getObjValAs? String "method").toOption != some "hook/completed" then continue
    let .ok params := message.getObjVal? "params" | continue
    if (params.getObjValAs? String "threadId").toOption != some scope.threadId ||
        (params.getObjValAs? String "turnId").toOption != some scope.turnId then continue
    let .ok run := params.getObjVal? "run" | continue
    found := found || (run.getObjValAs? String "eventName").toOption == some "userPromptSubmit"
  return found

private def report (kind : StudyAccounting.Acquisition) (scope : StudyAccounting.Scope)
    (path : System.FilePath) : IO (StudyAccounting.State × Json) := do
  let state ← StudyAccounting.replay scope path
  return (state,StudyAccounting.acquisitionReport scope state kind (← observedPromptHook scope path))

/-- Acquire an independent seed or a contemporaneous fresh control. Empty
database creation and absence of initial memory are checked separately from
the normal memory-trial body/ACK admission, which remains mandatory there. -/
def run (input digest : String) : IO UInt32 := do
  StudyAdmission.verifyArtifact ⟨input,digest⟩
  let plan ← IO.ofExcept (fromJson? (α := Plan) (← StudyAdmission.readJson input))
  let kind ← verify plan
  let guard ← StudyTrial.guard plan.runner plan.guardRecord ((← IO.monoMsNow)+3000)
  let root := System.FilePath.mk plan.output
  check (root.isAbsolute && !(← root.pathExists)) "new absolute acquisition directory required"
  Persistence.rejectSymlinkAncestors root
  IO.FS.createDir root
  save root "plan.json" (toJson plan)
  save root "guard-admission.json" guard
  let prompt ← IO.FS.readFile (.mk plan.prompt.path)
  IO.FS.writeFile (root / "prompt.txt") prompt
  let data := root / "data"
  let config := root / "config.toml"
  let database := root / "work.egg"
  IO.FS.createDir data
  if kind == .seed then
    let empty ← DB.PageMap.create database (Persistence.valueToJson (.text plan.label)).compress
    check ((← Synapses.Build.entries empty).isEmpty) "seed database is not empty"
    save root "input-files.json" (toJson (← StudyRuntime.checkpoint database (root / "input.egg")))
    IO.FS.writeFile config ("default = \"work\"\nsemantic_matcher = " ++
      (toJson #[plan.runtime.path,"search-provider"]).compress ++ "\n[eggs]\nwork = " ++
      (toJson database.toString).compress ++
      "\n[profiles.work]\nread = [\"work\"]\nwrite = \"work\"\nhandoff_chars = 120000\n")
  let environment := replaceEnv plan.environment #[
    ("EGGSHELL_DATA_ROOT",some data.toString),("EGGSHELL_CONFIG",some config.toString),
    ("EGGSHELL_PROFILE",some "work"),("PLUGIN_ROOT",some plan.pluginRoot),
    ("CODEX_THREAD_ID",none),("CODEX_TURN_ID",none)]
  let flags := if kind == .seed then #[] else #["-c","features.plugins=false","-c","features.hooks=false"]
  let settings : StudyTransport.Settings := {
    command := #[plan.cliWrapper.path,"--strict-config","-c","features.remote_plugin=false"] ++
      flags ++ #["app-server","--listen","stdio://"]
    cwd := plan.workspace,environment,output := (root / "rpc").toString,
    timeoutMs := 900000,responseBytes := 32*1024*1024,transcriptBytes := 256*1024*1024 }
  let manager ← IO.mkRef (none : Option StudyRuntime.Managed)
  let identity ← IO.mkRef (none : Option StudyAccounting.Scope)
  let mut runError : Option String := none
  let mut cleanupError : Option String := none
  try
    StudyTransport.withClient .generate settings fun client => do
      save root "initialize.json" (← StudyTransport.handshake client "0.145.0")
      save root "models.json" (← StudyTransport.request client (.read .models) (Json.mkObj [("includeHidden",toJson true)]))
      let hooks ← StudyTransport.request client (.read .hooks) (Json.mkObj [("cwds",toJson #[plan.workspace])])
      save root "hooks.json" hooks
      let mut active := 0
      for group in ← IO.ofExcept (hooks.getObjValAs? (Array Json) "data") do
        for field in #["errors","warnings"] do
          check ((group.getObjValAs? (Array Json) field).toOption.any (·.isEmpty)) "hook discovery warning or error"
        for hook in ← IO.ofExcept (group.getObjValAs? (Array Json) "hooks") do
          if (hook.getObjValAs? Bool "enabled").toOption == some false then continue
          active := active+1
          check (kind == .seed && (hook.getObjValAs? String "trustStatus").toOption == some "trusted" &&
            (hook.getObjValAs? String "sourcePath").toOption == some (plan.pluginRoot ++ "/hooks/hooks.json"))
            "unexpected active hook in acquisition"
      check (if kind == .seed then active == 8 else active == 0) "wrong acquisition hook count"
      check ((← StudyTransport.executables client).contains (← IO.FS.realPath (.mk plan.nativeCli.path)).toString)
        "actual CLI differs from sealed native executable"
      let thread ← StudyTransport.request client (.run .threadStart) (Json.mkObj [
        ("cwd",toJson plan.workspace),("model",toJson plan.model),("permissions",toJson "pilot"),
        ("approvalPolicy",toJson "never"),("ephemeral",toJson true),("allowProviderModelFallback",toJson false)])
      save root "thread.json" thread
      check ((thread.getObjValAs? String "model").toOption == some plan.model &&
        (thread.getObjValAs? String "modelProvider").toOption == some plan.provider &&
        (thread.getObjValAs? String "reasoningEffort").toOption == some plan.effort &&
        (thread.getObjValAs? (Array Json) "instructionSources").toOption == some #[])
        "actual model/effort or disabled AGENTS requirement differs"
      let id ← IO.ofExcept ((← IO.ofExcept (thread.getObjVal? "thread")).getObjValAs? String "id")
      if kind == .seed then
        let managed ← StudyRuntime.startManaged (.mk plan.runtime.path) (.mk plan.pluginRoot) id
          (data / "sessions" / id / "daemon.json") environment
        manager.set (some managed)
        save root "manager.json" (Json.mkObj [("session",toJson id),("pid",toJson (StudyRuntime.pid managed))])
      let turn ← StudyTransport.request client (.run .turnStart) (Json.mkObj [
        ("threadId",toJson id),("model",toJson plan.model),("effort",toJson plan.effort),
        ("input",toJson #[Json.mkObj [("type",toJson "text"),("text",toJson prompt)]])])
      save root "turn-start.json" turn
      let turnId ← IO.ofExcept ((← IO.ofExcept (turn.getObjVal? "turn")).getObjValAs? String "id")
      let scope : StudyAccounting.Scope := ⟨id,turnId,Sha256.hex ByteArray.empty⟩
      identity.set (some scope)
      let completed ← StudyTransport.waitNotification client "turn/completed" fun params =>
        (params.getObjValAs? String "threadId").toOption == some id &&
        ((params.getObjVal? "turn").bind (·.getObjValAs? String "id")).toOption == some turnId
      save root "completed.json" completed
      let (_,usage) ← report kind scope (root / "rpc/exchange.jsonl")
      check ((usage.getObjValAs? Bool "protocolPassed").toOption == some true) "acquisition generation or empty-context gate failed; retain cost"
      if kind == .seed then
        let kept ← StudyCommand.run plan.runtime.path #["egg","keep"]
          (replaceEnv environment #[("CODEX_THREAD_ID",some id)]) plan.workspace "" (root / "keep") 35000
        check (kept.exitCode == 0) "seed keep failed"
      let _ ← StudyTransport.request client (.run .unsubscribe) (Json.mkObj [("threadId",toJson id)])
      pure ()
  catch error => runError := some error.toString
  if let some managed ← manager.get then
    try StudyRuntime.stopManaged managed (root / "shutdown.json")
    catch error => cleanupError := some error.toString
  let mut captureError : Option String := none
  let mut usage := Json.mkObj [("unknownFinalUsage",toJson true),("observedInclusiveTokens",.null)]
  try
    let exchange := root / "rpc/exchange.jsonl"
    let scopes ← StudyAccounting.discover exchange
    let scope := (← identity.get).orElse fun _ =>
      if scopes.size == 1 then some ⟨scopes[0]!.1,scopes[0]!.2,Sha256.hex ByteArray.empty⟩ else none
    if let some scope := scope then
      let (state,captured) ← report kind scope exchange
      usage := captured
      StudyAccounting.savePackets scope exchange root
      if let some answer := state.answer then IO.FS.writeFile (root / "answer.txt") answer
    save root "usage.json" usage
  catch error => captureError := some error.toString
  let mut checkpointError : Option String := none
  try
    if kind == .seed then
      save root "output-files.json" (toJson (← StudyRuntime.checkpoint database (root / "output.egg")))
    verifySource plan
    StudyAdmission.verifyArtifact plan.runtime
  catch error => checkpointError := some error.toString
  let passed := runError.isNone && cleanupError.isNone && captureError.isNone && checkpointError.isNone &&
    (usage.getObjValAs? Bool "protocolPassed").toOption == some true
  save root (if passed then "result.json" else "failure.json") (Json.mkObj [
    ("completed",toJson passed),("kind",toJson plan.kind),("label",toJson plan.label),
    ("usage",usage),("runtime",toJson plan.runtime),("runError",toJson runError),
    ("cleanupError",toJson cleanupError),("captureError",toJson captureError),
    ("checkpointError",toJson checkpointError),("productionAdoption",toJson false)])
  return if passed then 0 else 1

end Eggshell.Research.StudyAcquire
