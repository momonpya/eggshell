import Lean.Data.Json.Parser
import Lean.Data.Json.FromToJson
import tools.research.NativeTrialAudit

open Lean

private def root := System.FilePath.mk "/Users/ovm/.codex/experiments/eggshell/study-services-20261026"
private def runner := root / "assessed-controller"

private def read (path : System.FilePath) : IO Json := do
  IO.ofExcept (Json.parse (← IO.FS.readFile path))

private def save (path : System.FilePath) (json : Json) : IO Unit := do
  unless !(← path.pathExists) do throw (IO.userError "keep previous pilot evidence")
  IO.FS.writeFile path (json.pretty ++ "\n")

private def call (args : Array String) : IO Unit := do
  let result ← IO.Process.output {cmd := runner.toString,args}
  unless result.exitCode == 0 do throw (IO.userError result.stderr)

private def artifact (path : System.FilePath) : IO Json := do
  let result ← IO.Process.output {cmd := runner.toString,args := #["artifacts",path.toString]}
  unless result.exitCode == 0 do throw (IO.userError "pilot artifact hashing failed")
  let rows ← IO.ofExcept (Json.parse result.stdout >>= Json.getArr?)
  let some row := rows[0]? | throw (IO.userError "missing pilot artifact")
  return row

private def environment (base : Json) (updates : Array (String × Option String)) : IO Json := do
  let entries ← IO.ofExcept (fromJson? (α := Array (String × Option String)) base)
  return toJson (entries.filter (fun entry => !updates.any (·.1 == entry.1)) ++ updates)

private def settings (record : System.FilePath) (command : Array String) : Json :=
  Json.mkObj [("record",toJson record.toString),("cwd",toJson root.toString),
    ("ownedPrefixes",toJson #[root.toString]),("limitRssKiB",toJson (3670016 : Nat)),
    ("minFreeKiB",toJson (524288 : Nat)),("command",toJson command)]

/-- One exploratory candidate/fresh pair. This never invokes an answering
model and is not the three-repetition current/candidate adoption experiment.
The full DB-present reference set is frozen before either native preflight. -/
def main (args : List String) : IO Unit := do
  let seed ← read (root / "study/seed-1/plan.json")
  let audit ← read (root / "seed-1-complete-audit.json")
  unless (audit.getObjValAs? Bool "seedAccepted").toOption == some true &&
      (audit.getObjValAs? Nat "handoffBodiesRead").toOption == some 0 &&
      audit.getObjValD "runtime" == seed.getObjValD "runtime" do
    throw (IO.userError "complete same-runtime source-only audit required")
  let common := root / "common-seed-1"
  match args with
  | ["freeze"] =>
    call #["history","freeze",(root / "study/seed-1-ready/ready.egg").toString,
      (root / "study/seed-1/data").toString,common.toString]
    save (root / "assessment-amendment.json") (Json.mkObj [
      ("seed",← artifact (root / "study/seed-1/plan.json")),
      ("sourceAudit",← artifact (root / "seed-1-complete-audit.json")),
      ("runner",← artifact runner),("runtime",seed.getObjValD "runtime"),
      ("reason",toJson "Bind DB-present original-output intervals in the evaluator; add a history CLI. Product runtime, seed bytes, model accounting and hook prompts are unchanged."),
      ("answeringModelCalls",toJson (0 : Nat)),("productionAdoption",toJson false)])
  | ["draft"] =>
    let stage := root / "pilot-stage-1"
    let manifest ← artifact (common / "history.json")
    let digest ← IO.ofExcept (manifest.getObjValAs? String "sha256")
    call #["history","fork",(common / "history.json").toString,digest,stage.toString]
    let history ← read (common / "history.json")
    unless history.getObjValD "sourceFiles" == audit.getObjValD "sourceFiles" do
      throw (IO.userError "common history differs from frozen source audit")
    let definitions ← IO.ofExcept ((← read (root / "task-definitions.json")).getArr?)
    let some topic := definitions.find? (fun row => (row.getObjValAs? Nat "topic").toOption == some 1) |
      throw (IO.userError "topic 1 definition missing")
    let availability ← IO.ofExcept (audit.getObjValAs? (Array Json) "availability")
    let some sourceTopic := availability.find? (fun row => (row.getObjValAs? Nat "topic").toOption == some 1) |
      throw (IO.userError "topic 1 source availability missing")
    save (stage / "frozen-evidence.json") (sourceTopic.getObjValD "frozenEvidence")
    let prototype := stage / "audit-prototype.json"
    save prototype (Json.mkObj [("source",Json.mkObj [("required",topic.getObjValD "referenceRanges")])])
    let promptPath ← IO.ofExcept ((topic.getObjValD "prompt").getObjValAs? String "path")
    let availabilitySource := Json.mkObj [("source",toJson (common / "source.egg").toString),
      ("workspace",seed.getObjValD "workspace"),("prompt",toJson (← IO.FS.readFile (.mk promptPath))),
      ("files",history.getObjValD "sourceFiles"),("required",topic.getObjValD "referenceRanges")]
    let frozen ← Eggshell.Research.NativeTrialAudit.freezeAvailable availabilitySource
    save (stage / "available-evidence.json") (toJson frozen)
    let placeholder ← artifact prototype
    let config := stage / "config.toml"
    let runtime ← IO.ofExcept ((seed.getObjValD "runtime").getObjValAs? String "path")
    IO.FS.writeFile config ("default = \"work\"\nsemantic_matcher = " ++
      (toJson #[runtime,"search-provider"]).compress ++ "\n[eggs]\nwork = " ++
      (toJson (stage / "work.egg").toString).compress ++
      "\n[profiles.work]\nread = [\"work\"]\nwrite = \"work\"\nhandoff_chars = 120000\n")
    let mut harness := #[]
    for item in ← IO.ofExcept (seed.getObjValAs? (Array Json) "harness") do
      harness := harness.push (← artifact (.mk (← IO.ofExcept (item.getObjValAs? String "path"))))
    let project := System.FilePath.mk "/Users/ovm/.codex/worktrees/hook-deadline-baseline/eggshell/tools/research"
    for name in #["OriginalEvidence.lean","NativeTrialAudit.lean","AvailableDelivery.lean","NativeSeedAudit.lean","PrepareMemoryPilot.lean"] do
      harness := harness.push (← artifact (project / name))
    let pluginRoot ← IO.ofExcept (seed.getObjValAs? String "pluginRoot")
    let env ← environment (seed.getObjValD "environment") #[
      ("EGGSHELL_DATA_ROOT",some (stage / "data").toString),
      ("EGGSHELL_CONFIG",some config.toString),("EGGSHELL_PROFILE",some "work"),
      ("PLUGIN_ROOT",some pluginRoot),("CODEX_THREAD_ID",none),("CODEX_TURN_ID",none)]
    let preparation := Json.mkObj ((#["input","stdout","timing","body","state","shutdown","search",
      "auditInput","auditReport"]).toList.map (fun key => (key,placeholder)) ++
      [("numerical",toJson (#[] : Array Json)),("session",toJson "unprepared")])
    let copied := #["model","effort","workspace","sourceCommit","cliWrapper","nativeCli",
      "runtime","accountConfiguration","pluginRoot","pluginFiles"]
    let plan := Json.mkObj (copied.toList.map (fun key => (key,seed.getObjValD key)) ++ [
      ("label",toJson "pilot-stage-1"),("purpose",toJson "pilot"),("stage",toJson (1 : Nat)),
      ("topic",toJson (1 : Nat)),("repetition",toJson (0 : Nat)),("prompt",topic.getObjValD "prompt"),
      ("runner",← artifact runner),("harness",toJson harness),("configuration",← artifact config),
      ("sourceSnapshot",toJson (common / "source.egg").toString),("sourceFiles",history.getObjValD "sourceFiles"),
      ("database",toJson (stage / "work.egg").toString),("databaseFiles",history.getObjValD "sourceFiles"),
      ("dataRoot",toJson (stage / "data").toString),("privateFiles",toJson (#[] : Array Json)),
      ("environment",env),("preparation",preparation),("output",toJson (stage / "trial").toString),
      ("guardRecord",toJson (stage / "trial.guard.json").toString)])
    save (stage / "draft.json") plan
    save (stage / "preparation.settings.json") (settings (stage / "preparation.guard.json")
      #[runner.toString,"prepare-live",(stage / "draft.json").toString,(stage / "preparation").toString])
  | ["qualify"] =>
    let stage := root / "pilot-stage-1"
    let report ← read (stage / "preparation/audit-report.json")
    unless report.getObjValD "frozenEvidence" == (← read (stage / "frozen-evidence.json")) do
      throw (IO.userError "delivery denominator changed after viewing the handoff")
    unless ((report.getObjValD "requiredDelivery").getObjValAs? Bool "targetMet").toOption == some true do
      throw (IO.userError "actual preflight misses frozen required original evidence; no answering model admitted")
    unless report.getObjValD "availableEvidence" == (← read (stage / "available-evidence.json")) &&
        ((report.getObjValD "availableDelivery").getObjValAs? Bool "targetMet").toOption == some true do
      throw (IO.userError "actual preflight misses frozen fully or partially stored evidence; no answering model admitted")
    let planFile := stage / "preparation/plan.json"
    let digest ← IO.ofExcept ((← artifact planFile).getObjValAs? String "sha256")
    save (stage / "trial.settings.json") (settings (stage / "trial.guard.json")
      #[runner.toString,"trial",planFile.toString,digest])
  | _ => throw (IO.userError "PrepareMemoryPilot freeze|draft|qualify")
