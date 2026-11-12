import Main
import Eggshell.ContractAudit
import tools.research.SharedProjectLifecycle
import tools.research.SourceBlocks
open Lean Eggshell Eggshell.Plugin Eggshell.Plugin.Publication Eggshell.Research
namespace ProjectHookWriteChecks
open SharedProjectLifecycle
structure Required where
  project : String
  path : String
  fingerprint : String
  text : String
  deriving ToJson, FromJson
def cases : Array Case := #[
  ⟨"project-alpha-writer","src/alpha.cpp","ALPHA_NATIVE_BASE","int ALPHA_NATIVE_BASE = 731;","int ALPHA_NATIVE_DETAIL = 947;"⟩,
  ⟨"project-beta-writer","src/beta.cpp","BETA_NATIVE_BASE","int BETA_NATIVE_BASE = 613;","int BETA_NATIVE_DETAIL = 829;"⟩]
def render (runtime : String) (command : Array String) (groups : Array String) (write : Option String) : String :=
  "default = \"work\"\nsemantic_matcher = "++(toJson #[runtime,"search-provider"]).compress++
  "\n[profiles.work]\nproject_service = "++(toJson command).compress++
  "\nread = "++(toJson groups).compress++"\nhandoff_chars = 500000\n"++
  (write.map (fun name => "write = "++(toJson name).compress++"\n")).getD ""
def invoke (plan : StudySeedChecks.Input) (root data configuration : System.FilePath)
    (session turn label event : String) (fields : List (String × Json) := []) : IO StudyCommand.Result := do
  let env := replaceEnv plan.environment #[("EGGSHELL_DATA_ROOT",some data.toString),
    ("EGGSHELL_CONFIG",some configuration.toString),("EGGSHELL_PROFILE",some "work"),
    ("CODEX_THREAD_ID",some session),("CODEX_TURN_ID",some turn),("TMPDIR",some (root/"tmp"/session).toString)]
  IO.FS.createDirAll (root/"calls"/session)
  let input := Json.mkObj ([("hook_event_name",toJson event),("session_id",toJson session),
    ("turn_id",toJson turn),("cwd",toJson root.toString),("_eggshell_config",toJson configuration.toString)]++fields)
  let result ← StudyCommand.run plan.runtime.path #["codex-hook"] env root.toString (input.compress++"\n")
    (root/"calls"/session/label) 35000
  check (result.exitCode == 0 && result.elapsedMs < 30000 && result.stderr.isEmpty &&
    !result.stdout.contains "Local memory search is busy or unavailable") s!"shared native hook failed: {session}/{label}: {result.stderr}"
  return result
def inventory (projects : Array (String × ProjectStore.Project)) : IO (String × Json) := do
  let mut body := ""
  let mut heads := #[]
  for (name,project) in projects do
    for slot in [:project.manifest.owners.size] do
      let source ← project.current slot
      let reader ← Persistence.Store.NodeReader.new source
      for item in ← Persistence.Store.searchDocuments source do
        let document ← Synapses.Build.document reader item.owner
        body := body++"\n"++document.source.getD ""
      heads := heads.push (name,source.head,← StudyRuntime.files source.directory)
  return (body,toJson heads)
def awaitAnswers (projects : Array (String × ProjectStore.Project)) : IO String := do
  let deadline := (← IO.monoMsNow)+30000
  repeat
    let (body,_) ← inventory projects
    if cases.all (fun item => body.contains (answer item)) then return body
    check ((← IO.monoMsNow) < deadline) "native final answer did not reach its shared project"
    IO.sleep 20
  throw (IO.userError "unreachable publication wait")
def awaitReady (projects : Array (String × ProjectStore.Project)) : IO Unit := do
  let deadline := (← IO.monoMsNow)+30000
  repeat
    let mut ready := true
    for (_,project) in projects do
      for slot in [:project.manifest.owners.size] do
        let source ← project.current slot
        if (← PreparedInputs.loadStored? source .database MiniLM.model SearchProvider.encoderContract).isNone then ready := false
        if (← OwnerViews.loadStored? source .database).isNone then ready := false
    if ready then return
    check ((← IO.monoMsNow) < deadline) "service-owned preparation did not catch up with publication"
    IO.sleep 20
  throw (IO.userError "unreachable readiness wait")
def auditPreparation (directory : String) : IO Unit := do
  let root := System.FilePath.mk directory
  let mut rows := #[]
  for (name,path) in [("ALPHA","alpha.egg"),("BETA","beta.egg")] do
    let project ← ProjectStore.openProject (root/path)
    for slot in [:project.manifest.owners.size] do
      let source ← project.current slot
      rows := rows.push (Json.mkObj [("project",toJson name),("slot",toJson slot),("head",toJson source.head),
        ("candidates",toJson (← Persistence.Store.getNat source.get "candidates")),
        ("preparedInputs",toJson (← PreparedInputs.loadStored? source .database MiniLM.model SearchProvider.encoderContract).isSome),
        ("ownerInputs",toJson (← OwnerViews.loadStored? source .database).isSome)])
  save (root/"preparation-postmortem.json") (toJson rows)
def write (plan : StudySeedChecks.Input) (root data configuration : System.FilePath) (project : String) (item : Case) : IO Unit := do
  discard <| invoke plan root data configuration item.session "seed" "start" "SessionStart"
  discard <| invoke plan root data configuration item.session "seed" "prompt" "UserPromptSubmit"
    [("prompt",toJson "Inspect the original source and explain both recorded fields.")]
  let some pending ← (readJson? (data/"sessions"/item.session/"pending.json") pendingJsonDefaults : IO (Option PendingTurn)) |
    throw (IO.userError "native writer has no staged turn")
  check (pending.write == some (.project project) && pending.localWrite.isNone && pending.remoteFrame.isSome &&
    pending.projectInputs.isNone && pending.read.isEmpty) "native writer changed its selected project or used local project paths"
  for (id,command) in #[
      ("read",s!"nl -ba {item.path} | sed -n '1p'"),
      ("consume",s!"printf {item.symbol}"),
      ("detail",s!"nl -ba {item.path} | sed -n '2p'")] do
    let fields := [("tool_name",toJson "shell"),("tool_use_id",toJson id),("tool_input",Json.mkObj [("command",toJson command)])]
    discard <| invoke plan root data configuration item.session "seed" (id++"-pre") "PreToolUse" fields
    let actual ← StudyCommand.run "/bin/sh" #["-c",command] #[] root.toString "" (root/"calls"/item.session/(id++"-actual")) 5000
    check (actual.exitCode == 0) "actual native source operation failed"
    discard <| invoke plan root data configuration item.session "seed" (id++"-post") "PostToolUse"
      (fields++[("tool_response",Json.mkObj [("output",toJson actual.stdout),("exitCode",toJson actual.exitCode)])])
  discard <| invoke plan root data configuration item.session "seed" "stop" "Stop" [("last_assistant_message",toJson (answer item))]
def run (installation directory : String) : IO Unit := do
  let plan ← IO.ofExcept (fromJson? (α := StudySeedChecks.Input) (← StudyAdmission.readJson installation))
  let root := System.FilePath.mk directory
  check (root.isAbsolute && !(← root.pathExists)) "fresh shared-writer workload required"
  IO.FS.createDirAll (root/"src")
  IO.FS.createDirAll (root/"tmp")
  for item in cases do IO.FS.writeFile (root/item.path) (item.first++"\n"++item.second++"\n")
  let alpha ← ProjectStore.create (root/"alpha.egg") 2
  let beta ← ProjectStore.create (root/"beta.egg") 2
  let projects := #[("ALPHA",alpha),("BETA",beta)]
  let host := root/"host"
  let client := root/"client"
  let runtime := System.FilePath.mk plan.runtime.path
  let hostEnv := replaceEnv plan.environment #[("EGGSHELL_DATA_ROOT",some host.toString)]
  let clientEnv := replaceEnv plan.environment #[("EGGSHELL_DATA_ROOT",some client.toString)]
  IO.FS.createDirAll host
  IO.FS.createDirAll client
  let services ← IO.mkRef (#[] : Array (StudyRuntime.Managed × String))
  let start := do
    check (← services.get).isEmpty "shared native services are already live"
    let backend ← StudyRuntime.startPublisher runtime host hostEnv
    services.modify (·.push (backend,"backend"))
    let localPublisher ← StudyRuntime.startPublisher runtime client clientEnv
    services.modify (fun live => #[(localPublisher,"local-publisher")]++live)
    let frontend ← StudyRuntime.startManaged runtime (.mk plan.pluginRoot) "shared-project-native" (client/"daemon.json") clientEnv
    services.modify (fun live => #[(frontend,"frontend")]++live)
  let stop := fun phase => do
    let failures ← IO.mkRef (#[] : Array String)
    for (managed,label) in ← services.get do
      try StudyRuntime.stopManaged managed (root/(phase++"-"++label++"-stop.json"))
      catch error => failures.modify (·.push error.toString); StudyRuntime.abort managed
    services.set #[]
    check (← failures.get).isEmpty "shared native services failed normal shutdown"
  try
    start
    let catalog := root/"catalog.json"
    save catalog (toJson (⟨#[⟨"ALPHA",alpha.directory.toString,true,true⟩,
      ⟨"BETA",beta.directory.toString,true,true⟩],⟨500000,true⟩⟩ : Gateway.Catalog))
    let command := #["/usr/bin/env","EGGSHELL_DATA_ROOT="++host.toString,
      "EGGSHELL_PREFIX="++(← Paths.installRoot).toString,runtime.toString,"project-gateway",catalog.toString]
    let mut configs := #[]
    for name in ["ALPHA","BETA"] do
      let config := root/(name++".toml")
      IO.FS.writeFile config (render runtime.toString command #["ALPHA","BETA"] (some name))
      configs := configs.push config
    let begun ← IO.monoMsNow
    let tasks ← (List.range 2).toArray.mapM fun index => IO.asTask (do
      write plan root client configs[index]! (if index == 0 then "ALPHA" else "BETA") cases[index]!) .dedicated
    let joined : Array (Except IO.Error Unit) ← tasks.mapM fun task => do return ← IO.wait task
    for result in joined do discard <| IO.ofExcept (result.mapError IO.Error.toString)
    let raw ← awaitAnswers projects
    for (_,project) in projects do discard <| census project 3
    let mut required : Array Required := #[]
    for index in [:cases.size] do
      let item := cases[index]!
      check (raw.contains (answer item)) "native final answer did not reach its shared project"
      let some (content,_) ← SourceEvidence.fingerprint (root/item.path) ((← IO.monoMsNow)+3000) |
        throw (IO.userError "cannot freeze original source fingerprint")
      for field in [item.first,item.second] do
        check (raw.contains field) "necessary original field is not present in the shared DB"
        required := required.push ⟨if index == 0 then "ALPHA" else "BETA",item.path,content.root,field⟩
    save (root/"required-before-delivery.json") (toJson required)
    awaitReady projects
    auditPreparation root.toString
    let ready ← IO.monoMsNow
    save (root/"publication.json") (Json.mkObj [("publicationAndPreparationMs",toJson (ready-begun)),
      ("observations",toJson (6 : Nat)),("answers",toJson (2 : Nat)),("manualWarmCalls",toJson (0 : Nat))])
    for (name,project) in projects do save (root/(name++"-synapses.json")) (← graphFacts project)
    let (_,originals) ← inventory projects
    save (root/"originals-before-queries.json") originals
    for item in cases do IO.FS.removeFile (root/item.path)
    let groups := #[#["ALPHA"],#["BETA"],#["ALPHA","BETA"]]
    let mut readers := #[]
    for selected in groups do
      let config := root/("reader-"++selected[0]!++toString selected.size++".toml")
      IO.FS.writeFile config (render runtime.toString command selected none)
      readers := readers.push config
    let mut replies := #[]
    let mut gates : Array Nat := #[]
    let mut visible := Array.replicate 10 ""
    for wave in [:4] do
      if wave == 2 then
        stop "restart"
        start
      let begun ← IO.monoMsNow
      let previous := visible
      let tasks ← (List.range 10).toArray.mapM fun index => IO.asTask (do
        let selected := groups[index%3]!
        let config := readers[index%3]!
        let fresh := wave == 3 && index%4 == 0
        let session := if fresh then s!"late-reader-{index}" else s!"native-reader-{index}"
        let turn := s!"read-{wave}"
        let mode := if wave == 2 then (index/3)%3 else index%4
        let source := if wave == 0 || fresh then "startup" else if wave == 1 then "resume"
          else if (wave == 2 && mode == 1) || (wave == 3 && mode == 2) then "clear"
          else if (wave == 2 && mode == 2) || (wave == 3 && mode == 3) then "compact" else "resume"
        let reset := ["startup","clear","compact"].contains source
        discard <| invoke plan root client config session turn s!"start-{wave}" "SessionStart" [("source",toJson source)]
        let reply ← invoke plan root client config session turn s!"prompt-{wave}" "UserPromptSubmit"
          [("prompt",toJson ("Explain the original source fields for "++String.intercalate " and " selected.toList))]
        let parsed ← IO.ofExcept (Json.parse reply.stdout)
        let body := ((parsed.getObjValD "hookSpecificOutput").getObjValAs? String "additionalContext").toOption.getD ""
        let actual := (if reset then "" else previous[index]!)++body
        for item in required do
          if selected.contains item.project then
            check (SourceBlocks.contains actual item.path item.fingerprint item.text) "native shared read omitted a frozen original field"
          else check (!actual.contains item.text) "native shared reader received an unselected project's original"
        let some state ← (readJson? (client/"sessions"/session/"state.json") stateJsonDefaults : IO (Option ThreadState)) |
          throw (IO.userError "native reader has no state")
        check (state.lastSearch.any (·.semantic == .completed) && state.confirmedDelivery.isSome && state.offers.isEmpty)
          "native reader fell back or did not ACK its exact delivery packet"
        discard <| invoke plan root client config session turn s!"stop-{wave}" "Stop" [("last_assistant_message",toJson "Original evidence received.")]
        return (actual,Json.mkObj [("wave",toJson wave),("client",toJson index),("source",toJson source),
          ("groups",toJson selected),("body",toJson body),("state",toJson state),
          ("required",toJson (required.filter fun item => selected.contains item.project).size)])) .dedicated
      let joined : Array (Except IO.Error (String × Json)) ← tasks.mapM fun task => do return ← IO.wait task
      for index in [:joined.size] do
        let (actual,result) ← IO.ofExcept (joined[index]!.mapError IO.Error.toString)
        visible := visible.set! index actual
        replies := replies.push result
      let elapsed := (← IO.monoMsNow)-begun
      gates := gates.push elapsed
      save (root/s!"wave-{wave}.json") (Json.mkObj [("readerGateMs",toJson elapsed),("readers",toJson (10 : Nat))])
      check (elapsed < 10000) "ten-reader native gate exceeded the temporary local limit"
    save (root/"replies.json") (toJson replies)
    check ((← inventory projects).2 == originals) "read-only native queries changed original shared DB files"
    save (root/"result.json") (Json.mkObj [("readerGatesMs",toJson gates),("readers",toJson (10 : Nat)),
      ("queries",toJson replies.size),
      ("requiredFields",toJson required.size),("adopted",toJson false),("answeringModelCalls",toJson (0 : Nat)),
      ("actualRemoteHostTested",toJson false)])
  finally
    stop "final"
end ProjectHookWriteChecks
def main : List String → IO UInt32
  | ["checks",installation,root] => do ProjectHookWriteChecks.run installation root; return 0
  | ["audit-preparation",_,root] => do ProjectHookWriteChecks.auditPreparation root; return 0
  | args => sourceRouteEngine args
