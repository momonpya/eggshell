import Main
import Eggshell.ContractAudit
import tools.research.SharedTrafficChecks

open Lean Eggshell Eggshell.Plugin Eggshell.Research
open Eggshell.Research.SharedProjectLifecycle
namespace Eggshell.Research.TenReaders

def run (inputPath databasePath frozenPath directory : String) : IO Unit := do
  let input ← IO.ofExcept (fromJson? (α := SharedTrafficChecks.Input) (← StudyAdmission.readJson inputPath))
  let plan := input.installation
  StudyAdmission.verifyArtifact plan.runtime
  for file in plan.pluginFiles do StudyAdmission.verifyArtifact file
  StudySeedChecks.requireNumericalSupport plan
  let database : System.FilePath := .mk databasePath
  let before ← StudyRuntime.files database
  check (before == input.originalFiles) "readonly concurrency source differs from the frozen original"
  let frozen ← IO.ofExcept ((← StudyAdmission.readJson frozenPath).getArr?)
  let mut topics := #[]
  for row in frozen do
    let source := row.getObjValD "source"
    topics := topics.push ({
      number := ← IO.ofExcept (row.getObjValAs? Nat "topic")
      prompt := ← IO.ofExcept (source.getObjValAs? String "prompt")
      required := source.getObjValD "required"
      source, frozen := row.getObjValD "frozen"} : SharedTrafficChecks.Topic)
  check (topics.size == 3) "all three original evidence questions required"
  let root : System.FilePath := .mk directory
  check (root.isAbsolute && !(← root.pathExists)) "fresh ten-reader directory required"
  IO.FS.createDirAll (root/"data")
  let data := root/"data"
  let configuration := root/"readonly.toml"
  IO.FS.writeFile configuration (SharedTrafficChecks.config plan.runtime.path database false)
  let environment := replaceEnv plan.environment #[("EGGSHELL_DATA_ROOT",some data.toString),
    ("CODEX_THREAD_ID",none),("CODEX_TURN_ID",none)]
  let publisher ← StudyRuntime.startPublisher (.mk plan.runtime.path) data environment
  let frontend ← try
      StudyRuntime.startManaged (.mk plan.runtime.path) (.mk plan.pluginRoot) "ten-readers"
        (data/"daemon.json") environment
    catch error =>
      StudyRuntime.stopManaged publisher (root/"publisher-startup-stop.json")
      throw error
  let mut waves := #[]
  try
    for wave in [1:4] do
      let sessions := (Array.range 10).map fun index => s!"ten-reader-{wave}-{index}"
      for session in sessions do
        discard <| SharedTrafficChecks.readerHook plan root (.mk input.workspace) data configuration session
          "start" "SessionStart" "" true
      let gate ← IO.mkRef false
      let started ← IO.monoMsNow
      let mut tasks := #[]
      for index in [:10] do
        tasks := tasks.push (← IO.asTask (do
          while !(← gate.get) do IO.sleep 1
          let topic := topics[index%3]!
          let delivery ← SharedTrafficChecks.read plan root (.mk input.workspace) data configuration
            sessions[index]! topic.prompt #[] true
          return Json.mkObj [("topic",toJson topic.number),("delivery",delivery)]) .dedicated)
      gate.set true
      let (outcomes,ok) ← SharedTrafficChecks.settle tasks
      let elapsed := (← IO.monoMsNow)-started
      save (root/s!"wave-{wave}-outcomes.json") (Json.mkObj [("elapsedMs",toJson elapsed),
        ("outcomes",toJson outcomes),("allProcessesSucceeded",toJson ok)])
      check ok "a simultaneous readonly hook failed"
      for outcome in outcomes do
        let delivered := outcome.getObjValD "delivery"
        check (delivered.getObjValD "completeBody" == toJson true &&
          (delivered.getObjValD "search").getObjValD "semantic" == toJson "completed")
          "simultaneous readonly request did not complete semantic delivery"
      let endings ← sessions.mapM fun session => IO.asTask
        (RegisteredHook.invoke plan root (.mk input.workspace) data configuration session "end" "SessionEnd") .dedicated
      for task in endings do discard <| IO.ofExcept (task.get.mapError IO.Error.toString)
      check ((← StudyRuntime.files database) == before) "readonly clients changed source publication bytes"
      waves := waves.push (Json.mkObj [("wave",toJson wave),("elapsedMs",toJson elapsed),("outcomes",toJson outcomes)])
      save (root/"waves.json") (toJson waves)
  finally
    try StudyRuntime.stopManaged frontend (root/"frontend-stop.json")
    finally StudyRuntime.stopManaged publisher (root/"publisher-stop.json")
  let mut checked := #[]
  for wave in waves do
    let mut audits := #[]
    for outcome in ← IO.ofExcept (wave.getObjValAs? (Array Json) "outcomes") do
      let number ← IO.ofExcept (outcome.getObjValAs? Nat "topic")
      let some topic := topics.find? (·.number == number) | throw (IO.userError "unknown frozen topic")
      let audit ← SharedTrafficChecks.auditTopic topic database root (outcome.getObjValD "delivery")
      check ((audit.getObjValD "requiredDelivery").getObjValD "targetMet" == toJson true &&
        (audit.getObjValD "availableDelivery").getObjValD "targetMet" == toJson true) "original evidence omitted under ten-query load"
      audits := audits.push audit
    checked := checked.push (wave.setObjVal! "audits" (toJson audits))
  check ((← StudyRuntime.files database) == before) "source changed during independent audit"
  save (root/"result.json") (Json.mkObj [("runtime",toJson plan.runtime),("waves",toJson checked),
    ("simultaneousQueries",toJson (10 : Nat)),("sourceFiles",toJson before),
    ("allRawSourceBytesUnchanged",toJson true),("answeringModelCalls",toJson (0 : Nat)),("adopted",toJson false)])

end Eggshell.Research.TenReaders
def main : List String → IO Unit
  | [input,database,frozen,directory] => Eggshell.Research.TenReaders.run input database frozen directory
  | _ => throw (IO.userError "TenReaders INPUT DB FROZEN OUTPUT")
