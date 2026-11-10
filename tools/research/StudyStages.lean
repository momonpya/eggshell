import tools.research.StudyHistory
import tools.research.StudyAcquire
import tools.research.StudyPrepare

open Lean Eggshell Eggshell.Research

namespace Eggshell.Research.StudyStages

inductive Arm | fresh | current | candidate
  deriving BEq, DecidableEq, Repr

inductive Block | first | second | third
  deriving DecidableEq

def order : Block → List Arm
  | .first => [.fresh,.current,.candidate]
  | .second => [.current,.candidate,.fresh]
  | .third => [.candidate,.fresh,.current]

theorem order_contains_each (block : Block) (arm : Arm) : arm ∈ order block := by
  cases block <;> cases arm <;> simp [order]

theorem order_distinct (block : Block) : (order block).Pairwise (· ≠ ·) := by
  cases block <;> simp [order]

def Arm.label : Arm → String
  | .fresh => "fresh" | .current => "current" | .candidate => "candidate"

structure Input where
  block : Nat
  stage : Nat
  purpose : String
  history : StudyAdmission.Artifact
  sourceAudit : StudyAdmission.Artifact
  readCoverage : StudyAdmission.Artifact
  initialSeedAudits : Array StudyAdmission.Artifact
  definitions : StudyAdmission.Artifact
  currentTemplate : StudyAdmission.Artifact
  candidateTemplate : StudyAdmission.Artifact
  controllerSeedPlan : StudyAdmission.Artifact
  limits : StudyAdmission.Artifact
  previousStage : Option StudyAdmission.Artifact := none
  output : String
  deriving FromJson, ToJson

private def check (condition : Bool) (message : String) : IO Unit :=
  unless condition do throw (IO.userError message)

private def save (path : System.FilePath) (value : Json) : IO StudyAdmission.Artifact := do
  check (!(← path.pathExists)) "keep the existing stage evidence"
  IO.FS.writeFile path (value.compress ++ "\n")
  StudyPrepare.artifact path

private def env (base updates : Array (String × Option String)) :=
  base.filter (fun row => !updates.any (·.1 == row.1)) ++ updates

private def prefixOf (runtime : StudyAdmission.Artifact) : System.FilePath :=
  ((System.FilePath.mk runtime.path).parent.getD "").parent.getD ""

private def profile (runtime database : String) (chars : Nat) : IO String := do
  return StudyProfile.render runtime database (← IO.ofExcept (StudyProfile.checked chars))

private def sourceReport (artifact : StudyAdmission.Artifact) (definitions : String) : IO Json := do
  StudyAdmission.verifyArtifact artifact
  let report ← StudyAdmission.readJson artifact.path
  check ((report.getObjValAs? String "taskDefinitionsSha256").toOption == some definitions &&
    (report.getObjValAs? Bool "sourceFactsUnchanged").toOption == some true &&
    (report.getObjValAs? Bool "nativeJournalComplete").toOption == some true &&
    (report.getObjValAs? Bool "portableOriginsComplete").toOption == some true &&
    (report.getObjValAs? Nat "handoffBodiesRead").toOption == some 0)
    "complete native source audit required before stage preparation"
  return report

/-- Prepare matched arms from one source/private-history checkpoint. The
frozen StudyMain performs warm, real hook preflight and model admission;
this program never dispatches an answering turn. Reference code is used only
by the post-handoff auditor, never as an input to the selector. -/
def run (input digest : String) (preparationRunner : Option String := none) : IO Unit := do
  StudyAdmission.verifyArtifact ⟨input,digest⟩
  let request ← IO.ofExcept (fromJson? (α := Input) (← StudyAdmission.readJson input))
  StudyAdmission.verifyArtifact request.limits
  let _ ← IO.ofExcept (fromJson? (α := StudyTrial.Limits) (← StudyAdmission.readJson request.limits.path))
  let block ← match request.block with
    | 1 => pure Block.first | 2 => pure .second | 3 => pure .third
    | _ => throw (IO.userError "exactly three predeclared seed blocks required")
  check (1 ≤ request.stage && request.stage ≤ 6 &&
    #["pilot","comparison"].contains request.purpose) "invalid six-stage preparation"
  let pilot := request.purpose == "pilot"
  let initialCount := if pilot then 1 else 3
  check ((!pilot || request.block == 1) && request.initialSeedAudits.size == initialCount &&
    (request.initialSeedAudits.map (·.sha256)).toList.eraseDups.length == initialCount)
    "pilot requires one audited seed in block one; adoption comparison requires three distinct audited seeds"
  StudyAdmission.verifyArtifact request.definitions
  let mut seedReports := #[]
  for artifact in request.initialSeedAudits do
    let report ← sourceReport artifact request.definitions.sha256
    check ((report.getObjValAs? Bool "seedAccepted").toOption == some true)
      "an initial seed is incomplete"
    seedReports := seedReports.push report
  let sourceAudit ← sourceReport request.sourceAudit request.definitions.sha256
  let (historyRoot,history) ← StudyHistory.verify request.history
  check ((sourceAudit.getObjValAs? (Array (String × String)) "sourceFiles").toOption == some history.sourceFiles)
    "stage audit and common source publication differ"
  if request.stage == 1 then
    let some initial := request.initialSeedAudits[request.block-1]? |
      throw (IO.userError "missing independent seed block")
    check (request.previousStage.isNone &&
      toJson request.sourceAudit == toJson initial)
      "first stage must use its own independent seed"
  else
    let some previous := request.previousStage | throw (IO.userError "previous completed stage required")
    StudyAdmission.verifyArtifact previous
    let closed ← StudyAdmission.readJson previous.path
    check ((closed.getObjValAs? Bool "completed").toOption == some true &&
      (closed.getObjValAs? Nat "block").toOption == some request.block &&
      (closed.getObjValAs? Nat "stage").toOption == some (request.stage-1) &&
      (closed.getObjVal? "nextHistory").toOption == some (toJson request.history) &&
      (closed.getObjVal? "sourceAudit").toOption == some (toJson request.sourceAudit))
      "stage history must advance from the fixed candidate's completed measured output"
  StudyAdmission.verifyArtifact request.readCoverage
  let coverage ← StudyAdmission.readJson request.readCoverage.path
  let coverageDatabase ← IO.ofExcept (coverage.getObjValAs? String "database")
  check ((coverage.getObjValAs? Bool "publicationUnchanged").toOption == some true &&
    (coverage.getObjValAs? String "taskDefinitionsSha256").toOption == some request.definitions.sha256 &&
    (coverage.getObjValAs? Nat "handoffBodiesRead").toOption == some 0 &&
    (coverage.getObjValAs? Nat "conflictingCanonicalRows").toOption == some 0 &&
    (coverage.getObjValAs? (Array Json) "payloadMismatches").toOption == some #[] &&
    (← StudyRuntime.files (.mk coverageDatabase)) == history.sourceFiles)
    "raw stored code availability must be audited before delivery"
  for artifact in #[request.currentTemplate,request.candidateTemplate,request.controllerSeedPlan] do
    StudyAdmission.verifyArtifact artifact
  let controller ← IO.ofExcept (fromJson? (α := StudyAcquire.Plan)
    (← StudyAdmission.readJson request.controllerSeedPlan.path))
  StudyAdmission.verifyArtifact controller.runner
  check (controller.model == "gpt-5.6-luna" && controller.effort == "xhigh" && controller.provider == "openai")
    "fixed Luna/xhigh and provider required"
  for report in seedReports.push sourceAudit do
    check ((report.getObjVal? "runtime").toOption == some (toJson controller.runtime) &&
      (report.getObjValAs? String "model").toOption == some controller.model &&
      (report.getObjValAs? String "effort").toOption == some controller.effort &&
      (report.getObjValAs? String "provider").toOption == some controller.provider)
      "seed sources changed runtime, model, effort or provider"
  let root := System.FilePath.mk request.output
  check (root.isAbsolute && !(← root.pathExists) && !StudyRuntime.inside historyRoot root &&
    !StudyRuntime.inside root historyRoot) "new stage output must not overlap protected history"
  let topic := (request.stage-1)%3+1
  let definitions ← IO.ofExcept ((← StudyAdmission.readJson request.definitions.path).getArr?)
  let some definition := definitions.find? (fun row =>
    (row.getObjValAs? Nat "topic").toOption == some topic) | throw (IO.userError "missing frozen topic")
  let prompt ← IO.ofExcept (definition.getObjValAs? StudyAdmission.Artifact "prompt")
  StudyAdmission.verifyArtifact prompt
  let required ← IO.ofExcept (definition.getObjVal? "referenceRanges")
  FileSystem.privateDirectory root
  let prototype ← save (root / "audit-prototype.json") (Json.mkObj [
    ("source",Json.mkObj [("required",required)])])
  let mut arms := #[]
  let mut accountSettings : Option String := none
  let templates := if pilot then #[(Arm.candidate,request.candidateTemplate)]
    else #[(Arm.current,request.currentTemplate),(Arm.candidate,request.candidateTemplate)]
  for (arm,artifact) in templates do
    let template ← IO.ofExcept (fromJson? (α := StudyAdmission.Plan) (← StudyAdmission.readJson artifact.path))
    let template : StudyAdmission.Plan := if arm == .candidate then
      {template with
        accountConfiguration := controller.accountConfiguration
        pluginRoot := controller.pluginRoot}
      else template
    StudyAdmission.verifyArtifact template.runtime
    StudyAdmission.verifyArtifact template.accountConfiguration
    StudyAdmission.verifyPluginRuntime template.runtime template.pluginRoot
    let normalized := (← IO.FS.readFile (.mk template.accountConfiguration.path)).replace
      (prefixOf template.runtime).toString "<MEMORY_RUNTIME>"
    if let some previous := accountSettings then
      check (normalized == previous) "model account settings differ beyond the memory runtime path"
    else accountSettings := some normalized
    if arm == .candidate then
      check (toJson template.runtime == toJson controller.runtime) "candidate runtime differs from seed acquisition"
    let armRoot := root / arm.label
    let _ ← StudyHistory.fork request.history armRoot
    let database := armRoot / "work.egg"
    let config := armRoot / "config.toml"
    IO.FS.writeFile config (← profile template.runtime.path database.toString template.handoffChars)
    let account := (System.FilePath.mk template.accountConfiguration.path).parent.getD ""
    let environment := env controller.environment #[
      ("CODEX_HOME",some account.toString),("EGGSHELL_PREFIX",some (prefixOf template.runtime).toString),
      ("PLUGIN_ROOT",some template.pluginRoot),("EGGSHELL_CONFIG",some config.toString),
      ("EGGSHELL_DATA_ROOT",some (armRoot / "data").toString)]
    let draft : StudyAdmission.Plan := {template with
      arm := if arm == .candidate then .candidate else .reference
      label := s!"seed-{request.block}-stage-{request.stage}-{arm.label}"
      purpose := request.purpose,stage := request.stage,topic,repetition := request.block-1
      model := controller.model,effort := controller.effort,workspace := controller.workspace
      sourceCommit := controller.sourceCommit,prompt,runner := controller.runner
      cliWrapper := controller.cliWrapper,nativeCli := controller.nativeCli,harness := controller.harness
      sourceSnapshot := (historyRoot / "source.egg").toString,sourceFiles := history.sourceFiles
      database := database.toString,databaseFiles := history.sourceFiles,dataRoot := (armRoot / "data").toString
      configuration := ← StudyPrepare.artifact config,environment
      preparation := {template.preparation with auditInput := prototype}
      output := (armRoot / "trial").toString,guardRecord := (armRoot / "trial.guard.json").toString}
    let draftFile ← save (armRoot / "draft.json") (toJson draft)
    let preparationGuard := armRoot / "preparation.guard.json"
    let preparationSettings ← save (armRoot / "preparation.settings.json") (toJson ({
      record := preparationGuard.toString,cwd := controller.workspace
      command := #[preparationRunner.getD controller.runner.path,"prepare-live",draftFile.path,(armRoot / "preparation").toString]
      ownedPrefixes := #[armRoot.toString,(prefixOf template.runtime).toString,controller.runner.path]
      limitRssKiB := ResourceGuard.maximumStopRssKiB,minFreeKiB := 2097152} : ResourceGuard.Settings))
    let prepared ← IO.Process.output {cmd := controller.runner.path,args := #["guard",preparationSettings.path]}
    IO.FS.writeFile (armRoot / "preparation.stdout") prepared.stdout
    IO.FS.writeFile (armRoot / "preparation.stderr") prepared.stderr
    let report ← StudyAdmission.readJson preparationGuard.toString
    check (prepared.exitCode == 0 && (report.getObjValAs? Nat "exitCode").toOption == some 0 &&
      (report.getObjValAs? (Array Nat) "ownedPids").toOption == some #[]) "native matched-arm preparation failed"
    let plan ← StudyPrepare.artifact (armRoot / "preparation/plan.json")
    let settings ← save (armRoot / "trial.settings.json") (toJson ({
      record := draft.guardRecord,cwd := controller.workspace
      command := #[controller.runner.path,"trial-bounded",plan.path,plan.sha256,request.limits.path,request.limits.sha256]
      ownedPrefixes := #[armRoot.toString,(prefixOf template.runtime).toString,controller.runner.path]
      limitRssKiB := ResourceGuard.maximumStopRssKiB,minFreeKiB := 2097152} : ResourceGuard.Settings))
    arms := arms.push (Json.mkObj [("arm",toJson arm.label),("plan",toJson plan),("settings",toJson settings)])
  let freshRoot := root / "fresh"
  FileSystem.privateDirectory freshRoot
  let fresh : StudyAcquire.Plan := {controller with
    kind := "fresh",label := s!"seed-{request.block}-stage-{request.stage}-fresh",prompt
    output := (freshRoot / "trial").toString,guardRecord := (freshRoot / "trial.guard.json").toString}
  let freshPlan ← save (freshRoot / "plan.json") (toJson fresh)
  let freshSettings ← save (freshRoot / "trial.settings.json") (toJson ({
    record := fresh.guardRecord,cwd := controller.workspace
    command := #[controller.runner.path,"acquire-bounded",freshPlan.path,freshPlan.sha256,request.limits.path,request.limits.sha256]
    ownedPrefixes := #[freshRoot.toString,controller.runner.path]
    limitRssKiB := ResourceGuard.maximumStopRssKiB,minFreeKiB := 2097152} : ResourceGuard.Settings))
  arms := arms.push (Json.mkObj [("arm",toJson "fresh"),("plan",toJson freshPlan),("settings",toJson freshSettings)])
  let _ ← StudyHistory.verify request.history
  let _ ← save (root / "stage.json") (Json.mkObj [
    ("block",toJson request.block),("stage",toJson request.stage),("topic",toJson topic),
    ("input",toJson (← StudyPrepare.artifact (.mk input))),("history",toJson request.history),
    ("sourceAudit",toJson request.sourceAudit),("readCoverage",toJson request.readCoverage),
    ("order",toJson (if pilot then ["fresh","candidate"] else (order block).map Arm.label)),("arms",toJson arms),
    ("forkedFromCommonSourceAndPrivateHistory",toJson true),("answeringModelCalls",toJson (0 : Nat)),
    ("productionAdoption",toJson false)])
  pure ()

end Eggshell.Research.StudyStages
