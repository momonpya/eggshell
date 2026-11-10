import tools.research.StudyAcquire

open Lean Eggshell Eggshell.Research
namespace Eggshell.Research.StudyRecordedRun

inductive Kind | seed | memory
  deriving BEq,ToJson

/-- Paths come from the actual recorded plan. A memory trial's DB and private
history belong to its arm, rather than its nested transcript directory. -/
structure Completed where
  kind : Kind
  root : System.FilePath
  database : System.FilePath
  data : System.FilePath
  configuration : System.FilePath
  runtime : StudyAdmission.Artifact
  runner : StudyAdmission.Artifact
  pluginRoot : String
  pluginFiles : Array StudyAdmission.Artifact
  environment : Array (String × Option String)
  workspace : String
  model : String
  effort : String
  provider : String

private def check (valid : Bool) (message : String) : IO Unit :=
  unless valid do throw (IO.userError message)

def read (kind : Kind) (root : System.FilePath) : IO Completed := do
  check root.isAbsolute "absolute recorded run required"
  let json ← StudyAdmission.readJson (root/"plan.json").toString
  let result ← StudyAdmission.readJson (root/"result.json").toString
  check (result.getObjValD "completed" == toJson true &&
    (result.getObjValD "usage").getObjValD "protocolPassed" == toJson true)
    "a completed recorded generation is required; failed usage remains separate"
  let run : Completed ← match kind with
    | .seed => do
      let plan ← IO.ofExcept (fromJson? (α := StudyAcquire.Plan) json)
      check (plan.kind == "seed" && plan.output == root.toString) "record is not the actual seed acquisition"
      pure {
        kind,root,database := root/"work.egg",data := root/"data",configuration := root/"config.toml"
        runtime := plan.runtime,runner := plan.runner,pluginRoot := plan.pluginRoot,pluginFiles := plan.pluginFiles,
        environment := plan.environment,workspace := plan.workspace,model := plan.model,effort := plan.effort,provider := plan.provider}
    | .memory => do
      let plan ← IO.ofExcept (fromJson? (α := StudyAdmission.Plan) json)
      check (plan.output == root.toString) "record is not the actual memory trial"
      StudyAdmission.verifyArtifact plan.configuration
      pure {
        kind,root,database := .mk plan.database,data := .mk plan.dataRoot,configuration := .mk plan.configuration.path
        runtime := plan.runtime,runner := plan.runner,pluginRoot := plan.pluginRoot,pluginFiles := plan.pluginFiles,
        environment := plan.environment,workspace := plan.workspace,model := plan.model,effort := plan.effort,provider := "openai"}
  StudyAdmission.verifyArtifact run.runtime
  StudyAdmission.verifyArtifact run.runner
  let thread ← StudyAdmission.readJson (root/"thread.json").toString
  check (thread.getObjValD "model" == toJson run.model && thread.getObjValD "modelProvider" == toJson run.provider &&
    thread.getObjValD "reasoningEffort" == toJson run.effort) "actual generation model, provider or effort differs"
  check (run.database.isAbsolute && run.data.isAbsolute && run.configuration.isAbsolute)
    "recorded publication and private paths must be absolute"
  return run

end Eggshell.Research.StudyRecordedRun
