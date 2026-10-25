import tools.research.StudyPrepare
import Eggshell.SynapseLive

open Lean Eggshell Eggshell.Synapses
open Eggshell.Research

namespace Eggshell.Research.StudySeedChecks

structure Input where
  runtime : StudyAdmission.Artifact
  pluginRoot : String
  pluginFiles : Array StudyAdmission.Artifact
  environment : Array (String × Option String)
  deriving FromJson, ToJson

private def check (condition : Bool) (message : String) : IO Unit :=
  unless condition do throw (IO.userError message)

private def replaceEnv (original updates : Array (String × Option String)) :=
  original.filter (fun row => !updates.any (·.1 == row.1)) ++ updates

private def save (path : System.FilePath) (value : Json) : IO Unit :=
  IO.FS.writeFile path (value.compress ++ "\n")

private def config (binary database : String) : String :=
  "default = \"work\"\nsemantic_matcher = " ++
  (toJson #[binary,"search-provider"]).compress ++ "\n[eggs]\nwork = " ++
  (toJson database).compress ++ "\n[profiles.work]\nread = [\"work\"]\nwrite = \"work\"\nhandoff_chars = 120000\n"

private def origins (database : System.FilePath) (count : Nat) : IO Unit := do
  let deadline := (← IO.monoMsNow)+20000
  repeat
    let snapshot ← DB.PageMap.pin database
    if (← Provenance.records snapshot).size == count then return
    check ((← IO.monoMsNow) < deadline) "actual save worker did not publish every tool origin"
    IO.sleep 25

private def facts (database : System.FilePath) (ready : Array Fact → Bool) : IO (Array Fact) := do
  let deadline := (← IO.monoMsNow)+20000
  repeat
    let snapshot ← DB.PageMap.pin database
    if let some reader ← Index.open? snapshot .database .shared then
      let all ← Index.allFacts reader.index
      if ready all then return all
    check ((← IO.monoMsNow) < deadline) "actual index worker did not publish the expected synaptic facts"
    IO.sleep 25

private def isConsumption : Fact → Bool
  | .consumed edge => edge.consumer.useId == "consume" && edge.producer.useId == "read" &&
      edge.rows.any (·.first == 11)
  | _ => false

private def supported : Fact → Bool
  | .supports _ => true
  | _ => false

private def coquoted : Fact → Bool
  | .coquoted _ _ => true
  | _ => false

/-- The fixture writes no relations. Only real hooks, a real shell, the save
worker and the index worker may create its observations and consumption. -/
def run (templatePath directory : String) : IO Unit := do
  let plan ← IO.ofExcept (fromJson? (α := Input) (← StudyAdmission.readJson templatePath))
  StudyAdmission.verifyArtifact plan.runtime
  for artifact in plan.pluginFiles do StudyAdmission.verifyArtifact artifact
  let root := System.FilePath.mk directory
  check (root.isAbsolute && !(← root.pathExists)) "a new absolute fixture directory is required"
  check ((← IO.getEnv "EGGSHELL_DATA_ROOT") == some (root / "data").toString)
    "fixture observer and native hooks need the same isolated private data root"
  Persistence.rejectSymlinkAncestors root
  IO.FS.createDir root
  IO.FS.createDir (root / "data")
  IO.FS.createDir (root / "src")
  let lines := (List.range 10).map (fun i => s!"prefix_{i+1}") ++
    ["NEEDED_SYMBOL", "alpha", "beta", "OTHER_SYMBOL", "omega"]
  IO.FS.writeFile (root / "src/source.cpp") ("\n".intercalate lines ++ "\n")
  let database := root / "work.egg"
  let initial ← DB.PageMap.create database (Persistence.valueToJson (.text "native-seed-fixture")).compress
  check ((← Build.entries initial).isEmpty) "synthetic seed did not start with an empty database"
  let configuration := root / "config.toml"
  IO.FS.writeFile configuration (config plan.runtime.path database.toString)
  let session := "native-empty-seed"
  let turn := "seed-turn"
  let environment := replaceEnv plan.environment #[
    ("EGGSHELL_DATA_ROOT",some (root / "data").toString),
    ("EGGSHELL_CONFIG",some configuration.toString),("EGGSHELL_PROFILE",some "work"),
    ("CODEX_THREAD_ID",some session),("CODEX_TURN_ID",some turn)]
  let call := fun label args input => do
    let result ← StudyCommand.run plan.runtime.path args environment root.toString input (root / label) 35000
    check (result.exitCode == 0 && result.elapsedMs < 30000) s!"native {label} failed or expired: {result.stderr}"
    return result
  let hook := fun label fields => do
    let input := Json.mkObj ([("session_id",toJson session),("turn_id",toJson turn),
      ("cwd",toJson root.toString),("_eggshell_config",toJson configuration.toString)] ++ fields)
    let result ← call label #["codex-hook"] (input.compress ++ "\n")
    let _ ← IO.ofExcept (Json.parse result.stdout)
    pure ()
  let endpoint := root / "data/sessions" / session / "daemon.json"
  let managed ← StudyRuntime.startManaged (.mk plan.runtime.path) (.mk plan.pluginRoot) session endpoint environment
  try
    hook "SessionStart" [("hook_event_name",toJson "SessionStart")]
    hook "UserPromptSubmit" [("hook_event_name",toJson "UserPromptSubmit"),
      ("prompt",toJson "inspect the source symbols and their recorded evidence")]
    let commands := #[
      ("read", "nl -ba src/source.cpp | sed -n '10p;11,12p' && nl -ba src/source.cpp | sed -n '14p'"),
      ("consume", "printf NEEDED_SYMBOL"),
      ("other", "nl -ba src/source.cpp | sed -n '13,15p'"),
      ("reread", "nl -ba src/source.cpp | sed -n '10,12p'")]
    for index in [:commands.size] do
      let (useId, command) := commands[index]!
      let input := Json.mkObj [("command",toJson command)]
      let fields := [("tool_name",toJson "shell"),("tool_use_id",toJson useId),("tool_input",input)]
      hook (useId ++ "-Pre") (fields ++ [("hook_event_name",toJson "PreToolUse")])
      let actual ← StudyCommand.run "/bin/sh" #["-c",command] environment root.toString ""
        (root / (useId ++ "-actual")) 5000
      check (actual.exitCode == 0) "fixture shell command failed"
      hook (useId ++ "-Post") (fields ++ [("hook_event_name",toJson "PostToolUse"),
        ("tool_response",Json.mkObj [("output",toJson actual.stdout),("exitCode",toJson actual.exitCode)])])
      origins database (index+1)
    hook "Stop" [("hook_event_name",toJson "Stop"),
      ("last_assistant_message",toJson "The symbols are supported by [first](src/source.cpp:11) and [second](src/source.cpp:14).")]
    let _ ← call "keep" #["egg","keep"] ""
    let all ← facts database fun all => all.any isConsumption && all.any supported && all.any coquoted
    let snapshot ← DB.PageMap.pin database
    let stored ← Provenance.records snapshot
    check (stored.size == commands.size && stored.all (fun row => row.origin.valid && row.origin.occurrence.session == session))
      "native origins lost their source or temporal binding"
    let sourceReader ← Persistence.Store.NodeReader.new snapshot
    let mut checkedRows := 0
    for origin in stored do
      if origin.origin.occurrence.useId != "read" then continue
      let document ← Provenance.checkedDocument sourceReader origin.origin
      let rows ← IO.ofExcept (Extraction.recordedRows snapshot.head.identity document)
      check (rows.map (·.source.first) == #[10,11,12,14])
        "actual conditional read lost coordinates or filled a gap"
      checkedRows := checkedRows+rows.size
    check (checkedRows == 4) "conditional read was not checked in the saved source"
    let journal ← Journal.prepare snapshot
    let entries ← Journal.turnEntries journal ⟨session,turn⟩
    check (entries.size == 9) "native Pre/Post/Stop journal is incomplete"
    let mut usage : Array Fact := #[]
    if let some reader ← Index.open? snapshot .user .usage then usage ← Index.allFacts reader.index
    save (root / "facts.json") (toJson all)
    save (root / "origins.json") (toJson (stored.map (·.origin)))
    save (root / "usage.json") (toJson usage)
    save (root / "result.json") (Json.mkObj [
      ("runtime",toJson plan.runtime),("emptyInitialDatabase",toJson true),
      ("actualToolCalls",toJson commands.size),("nativeJournalEvents",toJson entries.size),
      ("portableOrigins",toJson stored.size),("consumptionWitnesses",toJson (all.filter isConsumption).size),
      ("conditionalReadRows",toJson checkedRows),
      ("supports",toJson (all.filter supported).size),("coquoted",toJson (all.filter coquoted).size),
      ("privateUsage",toJson usage.size),("answeringModelCalls",toJson (0 : Nat)),
      ("directRelationInsertions",toJson (0 : Nat))])
  finally
    StudyRuntime.stopManaged managed (root / "shutdown.json")
  let copied := root / "output.egg"
  let publication ← StudyRuntime.checkpoint database copied
  save (root / "publication-files.json") (toJson publication)
  let recoveryData := root / "recovery-data"
  IO.FS.createDir recoveryData
  let recoveryConfig := root / "recovery-config.toml"
  IO.FS.writeFile recoveryConfig (config plan.runtime.path copied.toString)
  let recoveredEnvironment := replaceEnv environment #[
    ("EGGSHELL_DATA_ROOT",some recoveryData.toString),("EGGSHELL_CONFIG",some recoveryConfig.toString),
    ("CODEX_THREAD_ID",none),("CODEX_TURN_ID",none)]
  let warmed ← StudyCommand.run plan.runtime.path #["egg","warm","work"] recoveredEnvironment root.toString ""
    (root / "recover-warm") 60000
  check (warmed.exitCode == 0) "source-only seed could not be warmed without its old private state"
  let recovered ← facts copied fun all => all.any isConsumption && all.any supported && all.any coquoted
  check ((← StudyRuntime.files copied) == publication) "recovering derived synapses changed the source publication"
  save (root / "recovery.json") (Json.mkObj [
    ("runtime",toJson plan.runtime),("sourceOnlyCheckpoint",toJson true),
    ("newPrivateRoot",toJson true),("publicationUnchanged",toJson true),
    ("consumptionWitnesses",toJson (recovered.filter isConsumption).size),
    ("supports",toJson (recovered.filter supported).size),
    ("coquoted",toJson (recovered.filter coquoted).size)])

def cliMain (args : List String) : IO UInt32 := do
  try
    let [template,directory] := args | throw (IO.userError "StudySeedChecks TEMPLATE NEW-DIRECTORY")
    Eggshell.Research.StudySeedChecks.run template directory
    return 0
  catch error =>
    IO.eprintln error.toString
    return 1

end Eggshell.Research.StudySeedChecks
