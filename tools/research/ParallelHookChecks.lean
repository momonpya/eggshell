import tools.research.StudyPrepare
import Eggshell.SynapseLive

open Lean Eggshell Eggshell.Synapses Eggshell.Research

private structure Calls where
  sequential : Array Plugin.ToolEvent
  parallel : Array Plugin.ToolEvent
  deriving FromJson

private def check (condition : Bool) (message : String) : IO Unit :=
  unless condition do throw (IO.userError message)

private def replaceEnv (original updates : Array (String × Option String)) :=
  original.filter (fun row => !updates.any (·.1 == row.1)) ++ updates

private def saved (database : System.FilePath) (count : Nat) : IO Unit := do
  let deadline := (← IO.monoMsNow)+30000
  repeat
    let source ← DB.PageMap.pin database
    if (← Provenance.records source).size == count then return
    check ((← IO.monoMsNow) < deadline) "native observations did not finish publication"
    IO.sleep 25

/-- Replay the failed seed's two saved terminal results, then execute its
three concurrent calls as read-only shell operations. All five calls pass
through real native hooks. The real App Server stays alive
for representative resource accounting; its typed inspection client cannot
start a thread or a model turn. No relations are inserted by the fixture. -/
def main (args : List String) : IO Unit := do
  let [template,fixture,directory] := args |
    throw (IO.userError "ParallelHookChecks TEMPLATE CALLS NEW-DIRECTORY")
  let plan ← IO.ofExcept (fromJson? (α := StudyAdmission.Plan) (← StudyAdmission.readJson template))
  let calls ← IO.ofExcept (fromJson? (α := Calls) (← StudyAdmission.readJson fixture))
  let root := System.FilePath.mk directory
  check (root.isAbsolute && !(← root.pathExists)) "new absolute native fixture directory required"
  check ((← IO.getEnv "EGGSHELL_DATA_ROOT") == some (root / "data").toString) "isolated private root required"
  check (calls.sequential.size == 2 && calls.parallel.size == 3) "expected frozen two-plus-three call trajectory"
  StudyAdmission.verifyArtifact plan.runtime
  StudyAdmission.verifyArtifact plan.cliWrapper
  StudyAdmission.verifyArtifact plan.nativeCli
  StudyAdmission.verifyArtifact plan.prompt
  for artifact in plan.pluginFiles do StudyAdmission.verifyArtifact artifact
  let commit ← IO.Process.output {cmd := "git",args := #["rev-parse","HEAD"],cwd := some (.mk plan.workspace)}
  check (commit.exitCode == 0 && commit.stdout.trimAscii.toString == plan.sourceCommit) "fixture source commit changed"
  IO.FS.createDir root
  IO.FS.createDir (root / "data")
  let database := root / "work.egg"
  let _ ← DB.PageMap.create database (Persistence.valueToJson (.text "parallel-native-hook-fixture")).compress
  let config := root / "config.toml"
  IO.FS.writeFile config ("default = \"work\"\nsemantic_matcher = " ++
    (toJson #[plan.runtime.path,"search-provider"]).compress ++ "\n[eggs]\nwork = " ++
    (toJson database.toString).compress ++
    "\n[profiles.work]\nread = [\"work\"]\nwrite = \"work\"\nhandoff_chars = 120000\n")
  let session := "native-parallel-hooks"
  let turn := "parallel-turn"
  let environment := replaceEnv plan.environment #[
    ("EGGSHELL_DATA_ROOT",some (root / "data").toString),("EGGSHELL_CONFIG",some config.toString),
    ("PLUGIN_ROOT",some plan.pluginRoot),("CODEX_THREAD_ID",some session),("CODEX_TURN_ID",some turn)]
  let settings : StudyTransport.Settings := {
    command := #[plan.cliWrapper.path,"--strict-config","-c","features.remote_plugin=false","app-server","--listen","stdio://"]
    cwd := plan.workspace,environment,output := (root / "rpc").toString,timeoutMs := 180000
    responseBytes := 32*1024*1024,transcriptBytes := 256*1024*1024 }
  StudyTransport.withClient .inspect settings fun client => do
    let initialized ← StudyTransport.handshake client "0.145.0"
    IO.FS.writeFile (root / "initialize.json") (initialized.compress ++ "\n")
    check ((← StudyTransport.executables client).contains (← IO.FS.realPath (.mk plan.nativeCli.path)).toString)
      "fixture App Server is another native executable"
    let endpoint := root / "data/sessions" / session / "daemon.json"
    let managed ← StudyRuntime.startManaged (.mk plan.runtime.path) (.mk plan.pluginRoot) session endpoint environment
    let hook := fun label fields => do
      let request := Json.mkObj ([("session_id",toJson session),("turn_id",toJson turn),
        ("cwd",toJson plan.workspace),("_eggshell_config",toJson config.toString)] ++ fields)
      let result ← StudyCommand.run plan.runtime.path #["codex-hook"] environment plan.workspace
        (request.compress ++ "\n") (root / label) 35000
      check (result.exitCode == 0 && result.elapsedMs < 30000) s!"native hook failed or expired: {label}: {result.stderr}"
      let _ ← IO.ofExcept (Json.parse result.stdout)
      pure ()
    let operation := fun (tool : Plugin.ToolEvent) (replay : Bool) => do
      let input ← IO.ofExcept (Json.parse tool.input)
      let command ← IO.ofExcept (input.getObjValAs? String "command")
      let fields := [("tool_name",toJson tool.name),("tool_use_id",toJson tool.useId),("tool_input",input)]
      hook (tool.useId ++ "-Pre") (fields ++ [("hook_event_name",toJson "PreToolUse")])
      let response ← if replay then IO.ofExcept (Json.parse tool.response) else do
        let actual ← StudyCommand.run "/bin/sh" #["-c",command] environment plan.workspace ""
          (root / (tool.useId ++ "-actual")) 10000
        check (actual.exitCode == 0) "read-only parallel fixture command failed"
        pure (toJson actual.stdout)
      hook (tool.useId ++ "-Post") (fields ++ [("hook_event_name",toJson "PostToolUse"),
        ("tool_response",response)])
    try
      hook "SessionStart" [("hook_event_name",toJson "SessionStart")]
      hook "UserPromptSubmit" [("hook_event_name",toJson "UserPromptSubmit"),
        ("prompt",toJson (← IO.FS.readFile (.mk plan.prompt.path)))]
      for tool in calls.sequential do operation tool true
      saved database calls.sequential.size
      let ready ← IO.mkRef (0 : Nat)
      let release ← IO.mkRef false
      let mut tasks : Array (Task (Except IO.Error Unit)) := #[]
      for tool in calls.parallel do
        let task ← IO.asTask (do
          ready.modify (·+1)
          while !(← release.get) do IO.sleep 1
          operation tool false) .dedicated
        tasks := tasks.push task
      let deadline := (← IO.monoMsNow)+5000
      while (← ready.get) < calls.parallel.size do
        check ((← IO.monoMsNow) < deadline) "parallel native launch barrier expired"
        IO.sleep 1
      release.set true
      let mut failures := #[]
      for task in tasks do
        if let .error error ← IO.wait task then failures := failures.push error.toString
      check failures.isEmpty ("parallel native hook failures: " ++ "; ".intercalate failures.toList)
      hook "Stop" [("hook_event_name",toJson "Stop"),
        ("last_assistant_message",toJson "The native fixture inspected the recorded Clang driver sources.")]
      let kept ← StudyCommand.run plan.runtime.path #["egg","keep"] environment plan.workspace "" (root / "keep") 35000
      check (kept.exitCode == 0) "parallel fixture save failed"
      saved database (calls.sequential.size+calls.parallel.size)
      let source ← DB.PageMap.pin database
      let journal ← Journal.prepare source
      let entries ← Journal.turnEntries journal ⟨session,turn⟩
      check (entries.size == 11) "parallel native Pre/Post/Stop journal is incomplete"
      IO.FS.writeFile (root / "result.json") ((Json.mkObj [
        ("runtime",toJson plan.runtime),("sequentialCalls",toJson calls.sequential.size),
        ("replayedTerminalPrefix",toJson calls.sequential.size),("actualShellCalls",toJson calls.parallel.size),
        ("parallelCalls",toJson calls.parallel.size),("nativeJournalEvents",toJson entries.size),
        ("portableOrigins",toJson (← Provenance.records source).size),
        ("realAppServerAliveDuringHooks",toJson true),("answeringModelCalls",toJson (0 : Nat)),
        ("directRelationInsertions",toJson (0 : Nat))]).compress ++ "\n")
    finally StudyRuntime.stopManaged managed (root / "shutdown.json")
