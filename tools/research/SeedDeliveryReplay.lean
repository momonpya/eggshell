import tools.research.StudyAdmission
import tools.research.StudyCommand
import tools.research.StudyRuntime
import Eggshell.Warm

open Lean Eggshell Eggshell.Research

/-- Three first-hook measurements on the acquired live seed. No warm, restore,
answering model, label-derived recommendation, or source publication. -/
def main (args : List String) : IO Unit := do
  let (rootPath,outputPath,firstTopic,lastTopic,candidate) ← match args with
    | [rootPath,outputPath] => pure (rootPath,outputPath,1,4,none)
    | [rootPath,outputPath,"continue-2"] => pure (rootPath,outputPath,2,4,none)
    | [rootPath,outputPath,"topic-1",plan] => pure (rootPath,outputPath,1,2,some plan)
    | _ => throw (IO.userError "SEED-ROOT OUTPUT [continue-2 | topic-1 PLAN]")
  let root := System.FilePath.mk rootPath
  let output := System.FilePath.mk outputPath
  unless root.isAbsolute && output.isAbsolute &&
      ((firstTopic == 1 && !(← output.pathExists)) ||
       (firstTopic == 2 && (← (output / "topic-1/result.json").pathExists) &&
        !(← (output / "topic-2").pathExists))) do
    throw (IO.userError "absolute existing seed and new output required")
  let read := fun (path : System.FilePath) => StudyAdmission.readJson path.toString
  let acquisition := root / "study/seed-1"
  let data := acquisition / "data"
  let database := acquisition / "work.egg"
  let snapshot := root / "seed-ready/ready.egg"
  let config := acquisition / "config.toml"
  let seedPlan ← read (acquisition / "plan.json")
  let plan ← match candidate with
    | none => pure seedPlan
    | some path => read (.mk path)
  let runtime ← IO.ofExcept (plan.getObjValAs? StudyAdmission.Artifact "runtime")
  let seedRuntime ← IO.ofExcept (seedPlan.getObjValAs? StudyAdmission.Artifact "runtime")
  StudyAdmission.verifyArtifact runtime
  StudyAdmission.verifyArtifact seedRuntime
  unless candidate.isSome || runtime.sha256 == "c255d23527bc4aba06c9fd38932f5cab446dd4d1c775472064e0c16d9a913860" do
    throw (IO.userError "the frozen seed runtime changed")
  let plugin ← IO.ofExcept (plan.getObjValAs? String "pluginRoot")
  StudyAdmission.verifyPluginRuntime runtime plugin
  for artifact in ← IO.ofExcept (plan.getObjValAs? (Array StudyAdmission.Artifact) "pluginFiles") do
    StudyAdmission.verifyArtifact artifact
  let workspace ← IO.ofExcept (plan.getObjValAs? String "workspace")
  let original ← IO.ofExcept ((← read (root / "seed-ready/result.json")).getObjValAs?
    (Array (String × String)) "sourceFiles")
  let frozenSource ← DB.PageMap.pin snapshot
  let liveSource ← DB.PageMap.pin database
  unless (← StudyRuntime.files snapshot) == original &&
      (← Synapses.Index.sameSources liveSource frozenSource.head
        (liveSource.head.revision-frozenSource.head.revision+1)) &&
      (← IO.getEnv "EGGSHELL_DATA_ROOT") == some data.toString do
    throw (IO.userError "live seed, frozen snapshot or actual private root changed")
  let originalEnv ← IO.ofExcept (plan.getObjValAs? (Array (String × Option String)) "environment")
  let updates := #[("EGGSHELL_CONFIG",some config.toString),("EGGSHELL_DATA_ROOT",some data.toString),
    ("EGGSHELL_PROFILE",some "work"),("PLUGIN_ROOT",some plugin),
    ("CODEX_THREAD_ID",none),("CODEX_TURN_ID",none)]
  let environment := originalEnv.filter (fun row => !updates.any (·.1 == row.1)) ++ updates
  let prepared ← DB.PageMap.pin database
  let target : Eggshell.Plugin.IndexTarget := {
    owner := DB.Sidecar.Owner.ofSnapshot prepared, command := [seedRuntime.path,"search-provider"], storage := .database}
  unless !(← Warm.required target prepared) && !(← Synapses.Build.required prepared .database) &&
      (← Synapses.Journal.open? prepared).isSome && !(← Synapses.Journal.required prepared .database) do
    throw (IO.userError "live preparation debt remains; replay does not repair it")
  let availability ← IO.ofExcept ((← read (root / "seed-audit.json")).getObjValAs? (Array Json) "availability")
  let definitions ← IO.ofExcept ((← read (root / "task-definitions.json")).getArr?)
  IO.FS.createDirAll output
  let mut results := #[]
  if firstTopic == 2 then results := results.push (← read (output / "topic-1/result.json"))
  let publisher ← if candidate.isSome then
      some <$> StudyRuntime.startPublisher (.mk runtime.path) data environment (recoverDead := true)
    else pure none
  try
    for topic in [firstTopic:lastTopic] do
      let directory := output / s!"topic-{topic}"
      IO.FS.createDir directory
      let session := if candidate.isSome then s!"source-replay-{(runtime.sha256.take 16).toString}-topic-{topic}"
        else s!"seed-initial-replay-topic-{topic}"
      let prompt ← IO.FS.readFile (root / s!"prompts/topic-{topic}.txt")
      let managed ← StudyRuntime.startManaged (.mk runtime.path) (.mk plugin) session
        (data / "sessions" / session / "daemon.json") environment
      try
        for event in #["SessionStart","UserPromptSubmit"] do
          let fields := [("hook_event_name",toJson event),("session_id",toJson session),
            ("turn_id",toJson "first"),("cwd",toJson workspace),("_eggshell_config",toJson config.toString)]
          let request := Json.mkObj (if event == "UserPromptSubmit" then fields ++ [("prompt",toJson prompt)] else fields)
          let result ← StudyCommand.run runtime.path #["codex-hook"] environment workspace
            (request.compress ++ "\n") (directory / event) 35000
          unless result.exitCode == 0 do throw (IO.userError s!"native {event} failed")
          if event == "UserPromptSubmit" then
            let reply ← IO.ofExcept (Json.parse result.stdout)
            let body := (reply.getObjVal? "hookSpecificOutput" >>= (·.getObjValAs? String "additionalContext")).toOption.getD ""
            IO.FS.writeFile (directory / "body.txt") body
      finally
        StudyRuntime.stopManaged managed (directory / "shutdown.json")
      let some definition := definitions.find? (fun row => row.getObjValD "topic" == toJson topic) |
        throw (IO.userError "missing previously sealed topic definition")
      let some frozen := availability.find? (fun row => row.getObjValD "topic" == toJson topic) |
        throw (IO.userError "missing pre-delivery denominator")
      let hook := directory / "UserPromptSubmit"
      let auditInput := directory / "audit-input.json"
      IO.FS.writeFile auditInput (Json.mkObj [
        ("source",Json.mkObj [("source",toJson snapshot.toString),("workspace",toJson workspace),
          ("prompt",toJson prompt),("files",toJson original),("required",definition.getObjValD "referenceRanges")]),
        ("database",toJson database.toString),("request",toJson (hook / "stdin").toString),
        ("stdout",toJson (hook / "stdout").toString),("timing",toJson (hook / "record.json").toString),
        ("body",toJson (directory / "body.txt").toString)]).compress
      let audited ← NativeTrialAudit.inspect auditInput.toString
      IO.FS.writeFile (directory / "audit-report.json") audited.compress
      unless audited.getObjValD "frozenEvidence" == frozen.getObjValD "frozenEvidence" do
        throw (IO.userError "the original pre-delivery denominator changed")
      let timing ← read (hook / "record.json")
      let result := Json.mkObj [("topic",toJson topic),("elapsedMs",timing.getObjValD "elapsedMs"),
        ("requiredDelivery",audited.getObjValD "requiredDelivery"),("bodySha256",audited.getObjValD "bodySha256"),
        ("requirements",audited.getObjValD "requirements")]
      IO.FS.writeFile (directory / "result.json") result.compress
      IO.println result.compress
      results := results.push result
      unless audited.getObjValD "sameSourceFacts" == toJson true &&
          audited.getObjValD "samePublishedPagePrefix" == toJson true do
        throw (IO.userError "a replay changed the frozen original facts or published page prefix")
  finally
    if let some publisher := publisher then
      StudyRuntime.stopManaged publisher (output / "publisher-shutdown.json")
  StudyAdmission.verifyArtifact runtime
  IO.FS.writeFile (output / "result.json") (Json.mkObj [("runtime",toJson runtime),("numericalRuntime",toJson seedRuntime),
    ("sourceFactsUnchanged",toJson true),("originalPagePrefixUnchanged",toJson true),
    ("restoredDatabase",toJson false),("explicitWarmCalls",toJson (0 : Nat)),
    ("answeringModelCalls",toJson (0 : Nat)),("topics",toJson results),("productionAdoption",toJson false)]).compress
