import tools.research.StudyPrepare

open Lean Eggshell Eggshell.Research

private def check (condition : Bool) (message : String) : IO Unit :=
  unless condition do throw (IO.userError message)

private def save (path : System.FilePath) (value : Json) : IO Unit :=
  IO.FS.writeFile path (value.compress ++ "\n")

/-- Freeze stored-source availability before the first diagnostic handoff.
Stage zero and purpose compatibility cannot pass model-trial admission. -/
def main (args : List String) : IO Unit := do
  let [templatePath,auditPath,definitions,output,currentPrefix,candidatePrefix] := args |
    throw (IO.userError "PrepareMatchedSource TEMPLATE NATIVE-SOURCE-AUDIT DEFINITIONS NEW-DIRECTORY CURRENT-PREFIX CANDIDATE-PREFIX")
  let root := System.FilePath.mk output
  check root.isAbsolute "absolute comparison directory required"
  for name in #["source-oracle.json","audit-prototype.json","current-template.json","candidate-template.json"] do
    check (!(← (root / name).pathExists)) "keep the existing comparison records"
  let template ← IO.ofExcept (fromJson? (α := StudyAdmission.Plan) (← StudyAdmission.readJson templatePath))
  let audit ← StudyAdmission.readJson auditPath
  let publication ← IO.ofExcept (audit.getObjValAs? String "publication")
  let files ← IO.ofExcept (audit.getObjValAs? (Array (String × String)) "sourceFiles")
  check ((← StudyRuntime.files (.mk publication)) == files &&
    (audit.getObjValAs? Bool "sourceFactsUnchanged").toOption == some true &&
    (audit.getObjValAs? Bool "nativeJournalComplete").toOption == some true &&
    (audit.getObjValAs? Nat "handoffBodiesRead").toOption == some 0)
    "source publication or native audit is incomplete"
  check ((audit.getObjValAs? String "taskDefinitionsSha256").toOption == some (← ArtifactHash.hex (.mk definitions)))
    "task definitions differ from source audit"
  let availability ← IO.ofExcept (audit.getObjValAs? (Array Json) "availability")
  let topics ← IO.ofExcept ((← StudyAdmission.readJson definitions).getArr?)
  let some topic := topics[0]? | throw (IO.userError "no defined topic")
  let number ← IO.ofExcept (topic.getObjValAs? Nat "topic")
  let some sourceTopic := availability.find? (fun row =>
    (row.getObjValAs? Nat "topic").toOption == some number) | throw (IO.userError "no stored-source availability")
  let requirements ← IO.ofExcept (sourceTopic.getObjValAs? (Array Json) "requirements")
  let required ← (requirements.filter fun row =>
    (row.getObjValAs? Bool "storedOriginal").toOption == some true).mapM fun row => IO.ofExcept (row.getObjVal? "reference")
  let prompt ← IO.ofExcept (topic.getObjValAs? StudyAdmission.Artifact "prompt")
  StudyAdmission.verifyArtifact prompt
  IO.FS.createDirAll root
  save (root / "source-oracle.json") (Json.mkObj [
    ("source",toJson publication),("files",toJson files),("availability",toJson availability),
    ("sourceAudit",toJson (← StudyPrepare.artifact (.mk auditPath))),
    ("definitions",toJson (← StudyPrepare.artifact (.mk definitions))),
    ("handoffBodiesRead",toJson (0 : Nat)),("answeringModelCalls",toJson (0 : Nat)),
    ("diagnosticOnly",toJson true),("generationAllowed",toJson false)])
  let prototype := root / "audit-prototype.json"
  save prototype (Json.mkObj [("source",Json.mkObj [("required",toJson required)])])
  for (label,prefixPath) in #[ ("current",currentPrefix),("candidate",candidatePrefix)] do
    let installRoot := System.FilePath.mk prefixPath
    let account := root / label / "account"
    let plugin := account / "plugins/cache/eggshell/eggshell/0.1.0"
    let runtime ← StudyPrepare.artifact (installRoot / "libexec/eggshell")
    StudyAdmission.verifyPluginRuntime runtime plugin.toString
    let artifacts ← template.pluginFiles.mapM fun file => do
      check (file.path.startsWith (template.pluginRoot ++ "/")) "prototype plugin artifact escaped its root"
      StudyPrepare.artifact (.mk (file.path.replace template.pluginRoot plugin.toString))
    let updates : Array (String × Option String) := #[
      ("EGGSHELL_PREFIX",some installRoot.toString),("CODEX_HOME",some account.toString),("PLUGIN_ROOT",some plugin.toString)]
    let plan : StudyAdmission.Plan := {template with
      label := "compatibility-" ++ label,purpose := "compatibility",stage := 0,topic := number,prompt
      runtime,accountConfiguration := ← StudyPrepare.artifact (account / "config.toml")
      runner := ← StudyPrepare.artifact ((← IO.appPath).parent.getD "" / "StudyMain")
      pluginRoot := plugin.toString,pluginFiles := artifacts
      sourceSnapshot := publication,sourceFiles := files,database := (root / label / "work.egg").toString
      environment := template.environment.filter (fun row => !updates.any (·.1 == row.1)) ++ updates
      preparation := {template.preparation with auditInput := ← StudyPrepare.artifact prototype}}
    save (root / (label ++ "-template.json")) (toJson plan)
