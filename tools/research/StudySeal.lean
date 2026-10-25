import tools.research.StudyAcquire
import tools.research.StudyPrepare

open Lean Eggshell Eggshell.Research

namespace Eggshell.Research.StudySeal

private def check (condition : Bool) (message : String) : IO Unit :=
  unless condition do throw (IO.userError message)

private def save (path : System.FilePath) (json : Json) : IO StudyAdmission.Artifact := do
  check (!(← path.pathExists)) "keep the existing sealed artifact"
  IO.FS.writeFile path (json.compress ++ "\n")
  StudyPrepare.artifact path

private def setEnv (original updates : Array (String × Option String)) :=
  original.filter (fun row => !updates.any (·.1 == row.1)) ++ updates

/-- Resource-monitor amendments retain a completed seed's actual provenance.
They never relabel the interrupted seed, change the product runtime, or
resubmit into a used output directory. All later comparisons use this runner. -/
private def amendResources (args : List String) : IO Unit := do
  let [previousPath,newPath,checksPath] := args |
    throw (IO.userError "StudySeal resources PREVIOUS-STUDY NEW-STUDY CLEANUP-CHECKS")
  let previous := System.FilePath.mk previousPath
  let root := System.FilePath.mk newPath
  let checks := System.FilePath.mk checksPath
  check (previous.isAbsolute && root.isAbsolute && checks.isAbsolute && !(← root.pathExists))
    "new absolute resource amendment directory required"
  let seed := previous / "seed-1"
  let completed ← StudyAdmission.readJson (seed / "result.json").toString
  let audit ← StudyAdmission.readJson (previous / "seed-1-audit.json").toString
  let ready ← StudyAdmission.readJson (previous / "seed-1-ready/result.json").toString
  let guard ← StudyAdmission.readJson (previous / "seed-1.guard.json").toString
  let first ← IO.ofExcept (fromJson? (α := StudyAcquire.Plan)
    (← StudyAdmission.readJson (seed / "plan.json").toString))
  check ((completed.getObjValAs? Bool "completed").toOption == some true &&
    (audit.getObjValAs? Bool "seedAccepted").toOption == some true &&
    (audit.getObjValAs? Bool "nativeJournalComplete").toOption == some true &&
    (audit.getObjValAs? Bool "sourceFactsUnchanged").toOption == some true &&
    (guard.getObjValAs? Nat "exitCode").toOption == some 0 &&
    (guard.getObjValAs? (Array Nat) "ownedPids").toOption == some #[])
    "only the independently completed and fully audited seed1 may be retained"
  let coverage ← IO.ofExcept (ready.getObjVal? "coverage")
  check ((coverage.getObjValAs? Nat "missing").toOption == some 0 &&
    (coverage.getObjValAs? Nat "invalid").toOption == some 0 &&
    (ready.getObjVal? "runtime").toOption == some (toJson first.runtime)) "retained seed warm differs"
  StudyAdmission.verifyArtifact first.runtime
  let publication ← IO.ofExcept (ready.getObjValAs? String "publication")
  check ((ready.getObjValAs? (Array (String × String)) "sourceFiles").toOption ==
    some (← StudyRuntime.files (.mk publication))) "retained seed source changed"
  let runner ← StudyPrepare.artifact (← IO.appPath)
  for iteration in [:10] do
    let path := checks / s!"new-race-{iteration+1}" / "guard.json"
    let report ← StudyAdmission.readJson path.toString
    check ((report.getObjValAs? String "guardSha256").toOption == some runner.sha256 &&
      (report.getObjValAs? (Array Nat) "ownedPids").toOption == some #[] &&
      (report.getObjVal? "error").toOption == some .null)
      "new monitor has not closed ten actual late-child races"
  IO.FS.createDir root
  let source := (← IO.appPath).parent.getD root / "source"
  let mut plans := #[]
  for index in [2:4] do
    let original ← IO.ofExcept (fromJson? (α := StudyAcquire.Plan)
      (← StudyAdmission.readJson (previous / s!"seed-{index}.plan.json").toString))
    check (toJson original.runtime == toJson first.runtime && toJson original.prompt == toJson first.prompt &&
      original.model == first.model && original.effort == first.effort &&
      original.provider == first.provider && original.sourceCommit == first.sourceCommit &&
      original.environment == first.environment && toJson original.pluginFiles == toJson first.pluginFiles)
      "resource amendment changed frozen acquisition inputs"
    let harness ← original.harness.mapM fun artifact => do
      let some name := (System.FilePath.mk artifact.path).fileName |
        throw (IO.userError "unnamed harness artifact")
      StudyPrepare.artifact (source / name)
    let output := root / s!"seed-{index}"
    let plan : StudyAcquire.Plan := {original with
      runner := runner,harness := harness
      output := output.toString,guardRecord := output.toString ++ ".guard.json"}
    let artifact ← save (.mk (output.toString ++ ".plan.json")) (toJson plan)
    let installRoot := ((System.FilePath.mk plan.runtime.path).parent.getD "").parent.getD ""
    let settings : ResourceGuard.Settings := {
      record := plan.guardRecord,cwd := plan.workspace,
      command := #[runner.path,"acquire",artifact.path,artifact.sha256],
      ownedPrefixes := #[output.toString,installRoot.toString,runner.path],
      limitRssKiB := ResourceGuard.maximumStopRssKiB,minFreeKiB := 524288}
    let settings ← save (.mk (output.toString ++ ".settings.json")) (toJson settings)
    plans := plans.push (Json.mkObj [("plan",toJson artifact),("settings",toJson settings)])
  let _ ← save (root / "protocol.json") (Json.mkObj [
    ("runtime",toJson first.runtime),("runner",toJson runner),("guard",toJson runner),
    ("retainedSeed1",toJson (← StudyPrepare.artifact (seed / "plan.json"))),
    ("retainedSeed1Audit",toJson (← StudyPrepare.artifact (previous / "seed-1-audit.json"))),
    ("retainedSeed1Ready",toJson (← StudyPrepare.artifact (previous / "seed-1-ready/result.json"))),
    ("interruptedSeed2Guard",toJson (← StudyPrepare.artifact (previous / "seed-2.guard.json"))),
    ("seedPlans",toJson plans),("seedGenerationAllowed",toJson false),
    ("downstreamGenerationAllowed",toJson false),("noAutomaticResubmission",toJson true),
    ("stopRssKiB",toJson ResourceGuard.maximumStopRssKiB),("maxUserRssKiB",toJson (4194304 : Nat)),
    ("sameProductRuntime",toJson true),("allDownstreamArmsUseAmendedRunner",toJson true),
    ("state",toJson "resource amendment sealed; seed1 retained with stricter monitor; interrupted seed2 retained separately"),
    ("answeringModelCalls",toJson (0 : Nat)),("productionAdoption",toJson false)])
  pure ()

/-- Freeze independent empty-seed plans without starting a thread or a turn.
The acquisition controller still rechecks its native gate and actual model,
hooks, source, usage and process exits immediately before/after generation. -/
def cliMain (args : List String) : IO Unit := do
  if args.head? == some "resources" then
    amendResources (args.drop 1)
    return
  let [oldPlan,newTemplate,gateDirectory,studyDirectory,runnerPath,guardPath,repository] := args |
    throw (IO.userError "StudySeal OLD-PLAN QUALIFIED-TEMPLATE GATE STUDY RUNNER GUARD REPOSITORY")
  let old ← IO.ofExcept (fromJson? (α := StudyAcquire.Plan) (← StudyAdmission.readJson oldPlan))
  let template ← IO.ofExcept (fromJson? (α := StudyAdmission.Plan) (← StudyAdmission.readJson newTemplate))
  let study := System.FilePath.mk studyDirectory
  let gate := System.FilePath.mk gateDirectory
  let repo := System.FilePath.mk repository
  check (study.isAbsolute && gate.isAbsolute && repo.isAbsolute) "absolute freeze locations required"
  check (old.kind == "seed" && old.model == "gpt-5.6-luna" && old.effort == "xhigh" && old.provider == "openai")
    "original fixed acquisition conditions required"
  StudyAdmission.verifyArtifact template.runtime
  StudyAdmission.verifyArtifact old.prompt
  check (old.prompt.sha256 == "1c6b807d6fecb736b89c3270e019d09556e385ed18e256bac98a330f2e9a93c0")
    "original seed question changed"
  let some installDir := (template.environment.find? (·.1 == "EGGSHELL_PREFIX")).bind (·.2) |
    throw (IO.userError "qualified runtime prefix missing")
  let some accountDir := (template.environment.find? (·.1 == "CODEX_HOME")).bind (·.2) |
    throw (IO.userError "isolated study account missing")
  let source := study / "harness-source"
  check (!(← source.pathExists)) "keep the existing harness snapshot"
  IO.FS.createDirAll source
  let mut harness := #[]
  let extra : Array String := #["NativeSeedAudit.lean","NativeSeedFinalize.lean","StudySeal.lean","ArtifactHash.lean",
    "StudyEnvironment.lean","StudyEnvironmentChecks.lean","StudyCommandChecks.lean","PrepareMatchedSource.lean"]
  let previousNames ← old.harness.mapM fun artifact => do
    let some name := (System.FilePath.mk artifact.path).fileName |
      throw (IO.userError "harness source without a filename")
    return name
  for name in (previousNames ++ extra).toList.eraseDups do
    let path := repo / "tools/research" / name
    let target := source / name
    IO.FS.writeBinFile target (← IO.FS.readBinFile path)
    harness := harness.push (← StudyPrepare.artifact target)
  let prompt := study / "seed-question.txt"
  check (!(← prompt.pathExists)) "keep the frozen seed question"
  IO.FS.writeBinFile prompt (← IO.FS.readBinFile (.mk old.prompt.path))
  let runner ← StudyPrepare.artifact (.mk runnerPath)
  let resourceGuard ← StudyPrepare.artifact (.mk guardPath)
  check (runner.sha256 == resourceGuard.sha256) "acquisition must be monitored by its frozen unified runner"
  let account ← StudyPrepare.artifact (.mk accountDir / "config.toml")
  let gateArtifacts : StudyAcquire.Gate := {
    report := ← StudyPrepare.artifact (gate / "result.json")
    guard := ← StudyPrepare.artifact (.mk (gate.toString ++ ".guard.json"))
    shutdown := ← StudyPrepare.artifact (gate / "shutdown.json")
    recovery := ← StudyPrepare.artifact (gate / "recovery.json")
    publisherShutdown := ← StudyPrepare.artifact (gate / "publisher-shutdown.json") }
  let installation := System.FilePath.mk installDir
  let temporary := installation.parent.getD study / "tmp"
  let environment := setEnv old.environment #[
    ("EGGSHELL_PREFIX",some installDir),("CODEX_HOME",some accountDir),
    ("TMPDIR",some temporary.toString),
    ("PLUGIN_ROOT",some template.pluginRoot),("CODEX_THREAD_ID",none),("CODEX_TURN_ID",none),
    ("EGGSHELL_CONFIG",none),("EGGSHELL_DATA_ROOT",none)]
  StudyEnvironment.prepare environment
  let mut plans := #[]
  for index in [:3] do
    let label := s!"seed-{index+1}"
    let output := study / label
    let plan : StudyAcquire.Plan := {old with
      label,output := output.toString,guardRecord := output.toString ++ ".guard.json"
      runtime := template.runtime,runner,accountConfiguration := account
      prompt := ← StudyPrepare.artifact prompt,pluginRoot := template.pluginRoot
      pluginFiles := template.pluginFiles,harness,gate := gateArtifacts,environment}
    let artifact ← save (.mk (output.toString ++ ".plan.json")) (toJson plan)
    let settings : ResourceGuard.Settings := {
      record := plan.guardRecord,cwd := repo.toString
      command := #[runner.path,"acquire",artifact.path,artifact.sha256]
      ownedPrefixes := #[output.toString,installDir,runner.path]
      limitRssKiB := 3145728,minFreeKiB := 524288}
    let settings ← save (.mk (output.toString ++ ".settings.json")) (toJson settings)
    plans := plans.push (Json.mkObj [("plan",toJson artifact),("settings",toJson settings)])
  for fresh in #[false,true] do
    let output := study / (if fresh then "metadata-fresh" else "metadata-seed")
    let flags := if fresh then #["-c","features.plugins=false","-c","features.hooks=false"] else #[]
    let _ ← save (.mk (output.toString ++ ".settings.json")) (Json.mkObj [
      ("command",toJson (#[old.cliWrapper.path,"--strict-config","-c","features.remote_plugin=false"] ++
        flags ++ #["app-server","--listen","stdio://"])),
      ("cwd",toJson old.workspace),("environment",toJson environment),("output",toJson output.toString),
      ("timeoutMs",toJson (60000 : Nat)),("responseBytes",toJson (32*1024*1024 : Nat)),
      ("transcriptBytes",toJson (256*1024*1024 : Nat))])
    pure ()
  let _ ← save (study / "protocol.json") (Json.mkObj [
    ("runtime",toJson template.runtime),("runner",toJson runner),("guard",toJson resourceGuard),
    ("account",toJson account),("seedQuestion",toJson (← StudyPrepare.artifact prompt)),
    ("seedPlans",toJson plans),("model",toJson old.model),("effort",toJson old.effort),
    ("provider",toJson old.provider),("sourceCommit",toJson old.sourceCommit),
    ("seedGenerationAllowed",toJson false),("downstreamGenerationAllowed",toJson false),
    ("state",toJson "sealed plans; actual hook and fresh metadata qualification pending"),
    ("agentsEnabled",toJson false),("subagents",toJson false),("productionAdoption",toJson false),
    ("stopRssKiB",toJson (3145728 : Nat)),("maxUserRssKiB",toJson (4194304 : Nat)),
    ("historicalFreshReused",toJson false),("seedCostsSeparate",toJson true)])
  pure ()

end Eggshell.Research.StudySeal
