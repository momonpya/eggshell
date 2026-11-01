import tools.research.StudySeedChecks
open Lean Eggshell
namespace Eggshell.Research.StudyPreparationChecks
def run (directory : String) : IO Unit := do
  let root := System.FilePath.mk directory
  let input ← IO.ofExcept (fromJson? (α := StudySeedChecks.Input)
    (← StudyAdmission.readJson (root / "native-gate-input.json").toString))
  let test := root / "preparation-check"
  unless !(← test.pathExists) do throw (IO.userError "preserve native preparation check")
  IO.FS.createDir test
  let frozen ← StudyAdmission.readJson (root / "native-gate/recall-required-before-delivery.json").toString
  let prompt ← IO.ofExcept (frozen.getObjValAs? String "prompt")
  IO.FS.writeFile (test / "prompt.txt") prompt
  let source := root / "native-gate/recall-source.egg"
  let files ← StudyRuntime.files source
  let unused : StudyAdmission.Artifact := ⟨"/unused-no-model-artifact","unused"⟩
  let preparation : StudyAdmission.Preparation := {
    input := unused,stdout := unused,timing := unused,body := unused,state := unused,
    shutdown := unused,search := unused,numerical := #[],
    auditInput := ← StudyPrepare.artifact (root / "native-gate/recall-audit-input.json"),
    auditReport := unused,session := "unused"}
  let template : StudyAdmission.Plan := {
    label := "native-preparation-check",arm := .candidate,purpose := "pilot",topic := 1,stage := 1,repetition := 0,
    model := "gpt-5.6-luna",effort := "xhigh",handoffChars := input.handoffChars,
    workspace := (root / "native-gate").toString,sourceCommit := "fixture-no-model",
    prompt := ← StudyPrepare.artifact (test / "prompt.txt"),runner := unused,cliWrapper := unused,nativeCli := unused,
    runtime := input.runtime,accountConfiguration := ← StudyPrepare.artifact (root / "account/config.toml"),
    configuration := unused,harness := #[],pluginRoot := input.pluginRoot,pluginFiles := input.pluginFiles,
    sourceSnapshot := source.toString,sourceFiles := files,database := (test / "work.egg").toString,
    databaseFiles := files,dataRoot := "unused",privateFiles := #[],environment := input.environment,
    preparation,output := "unused",guardRecord := "unused"}
  let path := test / "template.json"
  IO.FS.writeFile path (toJson template).pretty
  let prepared ← StudyPrepare.prepare path.toString (test / "prepared").toString
  let config ← Config.parseFile (.mk prepared.configuration.path)
  let selected ← IO.ofExcept (Config.resolve config "work")
  unless selected.handoffChars == input.handoffChars do throw (IO.userError "preparation reset the sealed envelope")
  let audit ← StudyAdmission.readJson prepared.preparation.auditReport.path
  unless StudyAdmission.deliveryTargetMet audit do throw (IO.userError "prepared fixture lost original evidence")
  let ending ← StudyAdmission.readJson (test / "prepared/publisher-shutdown.json").toString
  unless ["acknowledged","processExited","endpointRemoved"].all (fun key => ending.getObjValD key == toJson true) do
    throw (IO.userError "prepared publisher remains live")
  IO.FS.writeFile (test / "result.json") (Json.mkObj [
    ("budget",toJson selected.handoffChars),("twoNativeChatBodiesEqual",toJson true),
    ("availableDelivery",audit.getObjValD "availableDelivery"),("publisherShutdown",ending),
    ("modelCalls",toJson (0 : Nat))]).pretty
end Eggshell.Research.StudyPreparationChecks
