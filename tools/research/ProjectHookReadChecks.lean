import tools.research.ProjectReadFixture
import Eggshell.ProjectHookRead
open Lean Eggshell Eggshell.Plugin Eggshell.Plugin.Publication Eggshell.Research
namespace ProjectHookReadChecks
open SharedProjectLifecycle
def config (runtime : String) (argv : Array String) (groups : Array String) : String :=
  "default = \"work\"\nsemantic_matcher = "++(toJson #[runtime,"search-provider"]).compress++
  "\n[profiles.work]\nread_service = "++(toJson argv).compress++
  "\nread = "++(toJson groups).compress++"\nhandoff_chars = 500000\n"
def invoke (plan : StudySeedChecks.Input) (root data configuration : System.FilePath)
    (session turn label event : String) (fields : List (String × Json) := []) : IO StudyCommand.Result := do
  let env := replaceEnv plan.environment #[("EGGSHELL_DATA_ROOT",some data.toString),
    ("EGGSHELL_CONFIG",some configuration.toString),("EGGSHELL_PROFILE",some "work"),
    ("CODEX_THREAD_ID",some session),("CODEX_TURN_ID",some turn),("TMPDIR",some (root/"tmp"/session).toString)]
  let input := Json.mkObj ([
    ("hook_event_name",toJson event),("session_id",toJson session),("turn_id",toJson turn),
    ("cwd",toJson root.toString),("_eggshell_config",toJson configuration.toString)]++fields)
  IO.FS.createDirAll (root/"hook-calls"/session)
  let result ← StudyCommand.run plan.runtime.path #["codex-hook"] env root.toString (input.compress++"\n")
    (root/"hook-calls"/session/label) 35000
  check (result.exitCode == 0 && result.elapsedMs < 30000 && result.stderr.isEmpty &&
    !result.stdout.contains "Local memory search is busy or unavailable") s!"remote native callback failed: {session}/{label} {result.stderr}"
  return result
def cancellation (root : System.FilePath) : IO Unit := do
  let marker := root/"cancel-started"
  let pending : PendingTurn := {
    sessionId := "cancel-one",turnId := "cancel-turn",cwd := root.toString,prompt := "cancel read pin",
    profile := "work",semanticMatcher := none,read := [],write := none,handoffChars := 500000,
    projection := .automatic,remoteRead := some ⟨[(← IO.appPath).toString,"hang",marker.toString],["ALPHA"]⟩ }
  let task ← IO.asTask (ProjectHookRead.capture pending ((← IO.monoMsNow)+10000)) .dedicated
  let deadline := (← IO.monoMsNow)+3000
  while !(← marker.pathExists) do
    check ((← IO.monoMsNow) < deadline && !(← IO.hasFinished task)) "cancel target never started its actual connection"
    IO.sleep 2
  let started ← IO.monoMsNow
  Worker.cancel pending.sessionId "search"
  let result ← IO.ofExcept ((← IO.wait task).mapError IO.Error.toString)
  let elapsed := (← IO.monoMsNow)-started
  check (result.isNone && elapsed < 1000) "cancelled pin returned a captured remote scope or did not join promptly"
  save (root/"cancellation.json") (Json.mkObj [("elapsedMs",toJson elapsed),("captureAbsent",toJson result.isNone)])
def runHooks (installation directory phase : String) : IO Unit := do
  let plan ← IO.ofExcept (fromJson? (α := StudySeedChecks.Input) (← StudyAdmission.readJson installation))
  let root := System.FilePath.mk directory
  let data := root/(phase++"-client-data")
  let host := root/(phase++"-host-data")
  check (!(← data.pathExists) && !(← host.pathExists)) "fresh hook service/client data roots required"
  let runtime := System.FilePath.mk plan.runtime.path
  let envHost := replaceEnv plan.environment #[("EGGSHELL_DATA_ROOT",some host.toString)]
  let envClient := replaceEnv plan.environment #[("EGGSHELL_DATA_ROOT",some data.toString)]
  IO.FS.createDirAll host
  IO.FS.createDirAll data
  let publisher ← StudyRuntime.startPublisher runtime host envHost
  let frontend ← try StudyRuntime.startManaged runtime (.mk plan.pluginRoot) "hook-remote-read" (data/"daemon.json") envClient
    catch error => StudyRuntime.stopManaged publisher (root/(phase++"-startup-publisher-stop.json")); throw error
  try
    let required ← IO.ofExcept (fromJson? (α := Array ProjectReadChecks.Required)
      (← StudyAdmission.readJson (root/"required-before-delivery.json").toString))
    let argv := #["/usr/bin/env","EGGSHELL_DATA_ROOT="++host.toString,
      "EGGSHELL_PREFIX="++(← Paths.installRoot).toString,runtime.toString,"project-gateway",(root/"catalog.json").toString]
    let configs ← ProjectReadChecks.queries.mapM fun (groups,_) => do
      let path := root/(phase++"-remote-"++toString groups.size++"-"++groups[0]!++".toml")
      IO.FS.writeFile path (config runtime.toString argv groups)
      let parsed ← Config.parseFile path
      let selected ← IO.ofExcept (Config.resolve parsed "work")
      check (selected.read.isEmpty && selected.write.isNone && selected.remoteRead.isSome)
        "remote profile resolved into local DB paths"
      check (!(Config.admitProject parsed).isOk) "repository config can execute a remote service command"
      return path
    IO.FS.createDirAll (root/phase)
    cancellation (root/phase)
    let mut visible := Array.replicate 10 ""
    let mut results := #[]
    for wave in [:3] do
      let started ← IO.monoMsNow
      let previous := visible
      let tasks ← (List.range 10).toArray.mapM fun index => IO.asTask (do
        let ordinal := index%ProjectReadChecks.queries.size
        let some (groups,question) := ProjectReadChecks.queries[ordinal]? | throw (IO.userError "missing normal hook query")
        let configuration := configs[ordinal]!
        let session := s!"{phase}-reader-{index}"
        let turn := s!"turn-{wave}"
        let reset := wave == 0 || (wave == 2 && index%3 != 0)
        let source := if wave == 0 then "startup" else if wave == 1 then "resume"
          else if index%3 == 1 then "clear" else if index%3 == 2 then "compact" else "resume"
        discard <| invoke plan root data configuration session turn s!"start-{wave}" "SessionStart" [("source",toJson source)]
        let reply ← invoke plan root data configuration session turn s!"prompt-{wave}" "UserPromptSubmit" [("prompt",toJson question)]
        let json ← IO.ofExcept (Json.parse reply.stdout)
        let body := ((json.getObjValD "hookSpecificOutput").getObjValAs? String "additionalContext").toOption.getD ""
        let actual := (if reset then "" else previous[index]!)++body
        for item in required do
          if groups.contains item.project then
            check (SourceBlocks.contains actual item.path item.fingerprint item.text) s!"remote hook omitted a frozen source field in wave {wave}"
          else check (!actual.contains item.text) "remote hook leaked a different project's original"
        check (!reply.stdout.contains (root/"alpha.egg").toString && !reply.stdout.contains (root/"beta.egg").toString)
          "remote body disclosed an internal project directory"
        let some pending ← (readJson? (data/"sessions"/session/"pending.json") pendingJsonDefaults : IO (Option PendingTurn)) |
          throw (IO.userError "normal remote hook omitted pending turn")
        let some state ← (readJson? (data/"sessions"/session/"state.json") stateJsonDefaults : IO (Option ThreadState)) |
          throw (IO.userError "normal remote hook omitted state")
        check (pending.remoteFrame.isSome && pending.projectInputs.isNone && pending.inputBoundary.isNone && pending.read.isEmpty &&
          pending.write.isNone && state.offers.isEmpty && state.confirmedDelivery.isSome)
          "normal remote hook bypassed capture/ACK or opened a local project boundary"
        discard <| invoke plan root data configuration session turn s!"stop-{wave}" "Stop" [("final_message",toJson "Recorded source evidence received.")]
        return (actual,Json.mkObj [("wave",toJson wave),("client",toJson index),("source",toJson source),
          ("body",toJson body),("elapsedMs",toJson reply.elapsedMs),
          ("required",toJson (required.filter fun item => groups.contains item.project).size),
          ("pending",toJson pending),("state",toJson state)])) .dedicated
      let completed : Array (Except IO.Error (String × Json)) ← tasks.mapM fun task => do
        return ← IO.wait task
      for index in [:completed.size] do
        let (actual,result) ← IO.ofExcept (completed[index]!.mapError IO.Error.toString)
        visible := visible.set! index actual
        results := results.push result
      let elapsed := (← IO.monoMsNow)-started
      save (root/s!"{phase}-wave-{wave}.json") (Json.mkObj [("wholeGateMs",toJson elapsed),("clients",toJson (10 : Nat))])
      check (elapsed < 10000) "ten-client normal-hook wave exceeded the temporary local gate"
    save (root/(phase++"-results.json")) (toJson results)
    let alpha ← ProjectStore.openProject (root/"alpha.egg")
    let beta ← ProjectStore.openProject (root/"beta.egg")
    check ((← ProjectReadChecks.originals #[("ALPHA",alpha),("BETA",beta)]) ==
      (← StudyAdmission.readJson (root/"originals-before.json").toString)) "remote normal hooks mutated original project files"
  finally
    let errors ← IO.mkRef (#[] : Array String)
    try StudyRuntime.stopManaged frontend (root/(phase++"-frontend-stop.json"))
    catch error => errors.modify (·.push error.toString); StudyRuntime.abort frontend
    try StudyRuntime.stopManaged publisher (root/(phase++"-publisher-stop.json"))
    catch error => errors.modify (·.push error.toString); StudyRuntime.abort publisher
    check (← errors.get).isEmpty "normal-hook services failed supervised shutdown"
def run (installation directory : String) : IO Unit := do
  ProjectReadChecks.run installation directory
  runHooks installation directory "hook"
end ProjectHookReadChecks
def main : List String → IO UInt32
  | ["checks",installation,root] => do ProjectHookReadChecks.run installation root; return 0
  | ["hooks",installation,root,phase] => do ProjectHookReadChecks.runHooks installation root phase; return 0
  | ["hang",marker] => do IO.FS.writeFile marker "connected"; IO.sleep 60000; return 0
  | args => sourceRouteEngine args
