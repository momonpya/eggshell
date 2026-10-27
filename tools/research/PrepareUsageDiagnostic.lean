import Lean.Data.Json.Parser
import Lean.Data.Json.FromToJson
open Lean

private def root : System.FilePath := "/Users/ovm/.codex/experiments/eggshell/feedback-pilot-20261028"
private def study : System.FilePath := "/Users/ovm/.codex/experiments/eggshell/study-services-20261026"
private def project : System.FilePath := "/Users/ovm/.codex/worktrees/hook-deadline-baseline/eggshell"
private def controller : System.FilePath := root / "controller/StudyMain"

private def read (path : System.FilePath) : IO Json :=
  IO.FS.readFile path >>= fun value => IO.ofExcept (Json.parse value)

private def save (path : System.FilePath) (value : Json) : IO Unit := do
  unless !(← path.pathExists) do throw (IO.userError "keep the previous diagnostic evidence")
  IO.FS.writeFile path (value.compress ++ "\n")

private def invoke (args : Array String) : IO Json := do
  let result ← IO.Process.output {cmd := controller.toString,args}
  unless result.exitCode == 0 do throw (IO.userError result.stderr)
  if result.stdout.trimAscii.isEmpty then return .null
  IO.ofExcept (Json.parse result.stdout)

private def artifact (path : System.FilePath) : IO Json := do
  let result ← invoke #["artifacts",path.toString]
  let rows ← IO.ofExcept result.getArr?
  let some found := rows[0]? | throw (IO.userError "missing native digest")
  return found

private def env (base updates : Array (String × Option String)) :=
  base.filter (fun row => !updates.any (·.1 == row.1)) ++ updates

private def guarded (label : String) (command : Array String)
    (environment : Array (String × Option String) := #[]) : IO Unit := do
  let unset := environment.filterMap fun row => if row.2.isNone then some #["-u",row.1] else none
  let variables := environment.filterMap fun row => row.2.map (fun value => row.1 ++ "=" ++ value)
  let command := if environment.isEmpty then command else
    #["/usr/bin/env"] ++ unset.flatten ++ variables ++ command
  save (root / (label ++ ".settings.json")) (Json.mkObj [
    ("command",toJson command),("cwd",toJson project.toString),
    ("ownedPrefixes",toJson #[root.toString]),("limitRssKiB",toJson (3670016 : Nat)),
    ("minFreeKiB",toJson (2097152 : Nat)),("record",toJson (root / (label ++ ".guard.json")).toString)])

def main (args : List String) : IO Unit := do
  match args with
  | ["transport"] =>
    guarded "usage-transport-checks" #[controller.toString,"test-transport",
      "/Users/ovm/.codex/experiments/eggshell/verified-winner-20261027/transport-build/StudyMain",
      (root / "usage-transport-checks").toString]
  | ["close"] =>
    guarded "usage-close" #[
      "/Users/ovm/.codex/experiments/eggshell/verified-winner-20261027/close-build/StudyMain",
      (root / "usage-prepared/plan.json").toString,(root / "usage-closed").toString]
  | ["audit-usage"] =>
    guarded "usage-evidence" #[
      "/Users/ovm/.codex/experiments/eggshell/verified-winner-20261027/usage-build/StudyMain",
      (study / "common-seed-1").toString,(root / "usage-history-start/work.egg").toString,
      (root / "usage-history-start/data").toString,(study / "prompts/topic-2.txt").toString,
      (root / "usage-run").toString,(root / "usage-evidence.json").toString]
  | ["init"] =>
    unless !(← (root / "usage-template.json").pathExists) && !(← (root / "usage-run").pathExists) do
      throw (IO.userError "one diagnostic answer only")
    let input ← read (root / "native-gate-input.json")
    let runtime := input.getObjValD "runtime"
    unless runtime.getObjValD "sha256" ==
        toJson "3551bb5ad8df6ce3387e237e80f5c27f6f5149762edb0c70b75de893ce82687c" do
      throw (IO.userError "fixed product runtime required")
    let actualRuntime ← artifact (.mk (← IO.ofExcept (runtime.getObjValAs? String "path")))
    unless actualRuntime == runtime do throw (IO.userError "product runtime changed")
    let historyPath := study / "common-seed-1/history.json"
    let history := (← read historyPath)
    let historyDigest ← artifact historyPath
    let branch := root / "usage-history-start"
    let _ ← invoke #["history","fork",historyPath.toString,
      ← IO.ofExcept (historyDigest.getObjValAs? String "sha256"),branch.toString]
    let definitions ← IO.ofExcept ((← read (study / "task-definitions.json")).getArr?)
    let some definition := definitions.find? (fun row => row.getObjValD "topic" == toJson (2 : Nat)) |
      throw (IO.userError "missing predeclared topic two")
    let prompt := definition.getObjValD "prompt"
    unless (← artifact (.mk (← IO.ofExcept (prompt.getObjValAs? String "path")))) == prompt do
      throw (IO.userError "fixed question changed")
    let prototype := root / "usage-audit-prototype.json"
    save prototype (Json.mkObj [("source",Json.mkObj [("required",definition.getObjValD "referenceRanges")])])
    let placeholder ← artifact prototype
    let pluginRoot ← IO.ofExcept (input.getObjValAs? String "pluginRoot")
    let database := branch / "work.egg"
    let data := branch / "data"
    let config := branch / "config.toml"
    let binary ← IO.ofExcept (runtime.getObjValAs? String "path")
    IO.FS.writeFile config ("default = \"work\"\nsemantic_matcher = " ++
      (toJson #[binary,"search-provider"]).compress ++ "\n[eggs]\nwork = " ++
      (toJson database.toString).compress ++
      "\n[profiles.work]\nread = [\"work\"]\nwrite = \"work\"\nhandoff_chars = 120000\n")
    let originalEnv ← IO.ofExcept (input.getObjValAs? (Array (String × Option String)) "environment")
    let environment := env originalEnv #[
      ("EGGSHELL_CONFIG",some config.toString),("EGGSHELL_PROFILE",some "work"),
      ("EGGSHELL_DATA_ROOT",some data.toString),("PLUGIN_ROOT",some pluginRoot)]
    let build ← read (root / "controller/build.json")
    let modules ← IO.ofExcept (build.getObjValAs? (Array Json) "modules")
    let mut sourcePaths := #[]
    for moduleRow in modules do
      sourcePaths := sourcePaths.push (← IO.ofExcept (moduleRow.getObjValAs? String "source"))
    for relative in #["tools/research/PrepareUsageDiagnostic.lean","tools/research/StudyBuildMain.lean",
        "docs/astra-progress-review.md","docs/usage-feedback-diagnostic.md"] do
      sourcePaths := sourcePaths.push (project / relative).toString
    let harness ← invoke (#["artifacts"] ++ sourcePaths)
    let plan := Json.mkObj [
      ("label",toJson "usage-feedback-topic2"),("purpose",toJson "pilot"),
      ("topic",toJson (2 : Nat)),("stage",toJson (2 : Nat)),("repetition",toJson (0 : Nat)),
      ("model",toJson "gpt-5.6-luna"),("effort",toJson "xhigh"),
      ("workspace",toJson "/Users/ovm/Code/eggshell-benchmarks/aamas-2027/sources/llvm-project"),
      ("sourceCommit",toJson "6dfe1677ab8dffbc6ec13d53a1e0215d75147689"),
      ("prompt",prompt),("runner",← artifact controller),
      ("cliWrapper",← artifact "/Users/ovm/.nodebrew/current/bin/codex"),
      ("nativeCli",← artifact "/Users/ovm/.nodebrew/current/lib/node_modules/@openai/codex/node_modules/@openai/codex-darwin-arm64/vendor/aarch64-apple-darwin/bin/codex"),
      ("runtime",runtime),("accountConfiguration",← artifact (root / "account/config.toml")),
      ("configuration",← artifact config),("harness",harness),
      ("pluginRoot",toJson pluginRoot),("pluginFiles",input.getObjValD "pluginFiles"),
      ("sourceSnapshot",toJson (study / "common-seed-1/source.egg").toString),
      ("sourceFiles",history.getObjValD "sourceFiles"),
      ("database",toJson database.toString),("databaseFiles",history.getObjValD "sourceFiles"),
      ("dataRoot",toJson data.toString),("privateFiles",toJson (#[] : Array (String × String))),
      ("environment",toJson environment),
      ("preparation",Json.mkObj ([("session",toJson "unprepared-template"),("numerical",toJson (#[] : Array Json))] ++
        (["input","stdout","timing","body","state","shutdown","search","auditInput","auditReport"].map
          fun key => (key,placeholder)))),
      ("output",toJson (root / "usage-run").toString),
      ("guardRecord",toJson (root / "usage-run.guard.json").toString)]
    save (root / "usage-template.json") plan
    save (root / "usage-limits.json") (Json.mkObj [
      ("inclusiveTokens",toJson (1000000 : Nat)),("answerMs",toJson (900000 : Nat))])
    save (root / "usage-input.json") (Json.mkObj [("history",historyDigest),
      ("question",prompt),("taskDefinitions",← artifact (study / "task-definitions.json")),
      ("runtime",runtime),("newSeed",toJson false),("freshCalls",toJson (0 : Nat)),
      ("maximumAnsweringCalls",toJson (1 : Nat)),("productionAdoption",toJson false)])
    guarded "usage-prepare" #[controller.toString,"prepare-live",(root / "usage-template.json").toString,
      (root / "usage-prepared").toString] environment
  | ["refresh-plan"] =>
    unless !(← (root / "usage-run").pathExists) && !(← (root / "usage-run.guard.json").pathExists) do
      throw (IO.userError "cannot refresh after an answering call starts")
    let plan ← read (root / "usage-closed/plan.json")
    let harness ← IO.ofExcept (plan.getObjValAs? (Array Json) "harness")
    let mut paths := #[]
    for entry in harness do paths := paths.push (← IO.ofExcept (entry.getObjValAs? String "path"))
    paths := paths.push (project / "tools/research/StudyClosePrepared.lean").toString
    let rebound := plan.setObjVal! "runner" (← artifact controller)
      |>.setObjVal! "harness" (← invoke (#["artifacts"] ++ paths))
    save (root / "usage-sealed-plan.json") rebound
    save (root / "usage-reseal.json") (Json.mkObj [
      ("reason",toJson "admit the existing product keyed-discovery lane before any model call"),
      ("originalPlan",← artifact (root / "usage-prepared/plan.json")),
      ("sealedPlan",← artifact (root / "usage-sealed-plan.json")),
      ("productRuntimeChanged",toJson false),("answeringCalls",toJson (0 : Nat)),
      ("preparedBodyChanged",toJson false),("requiredCriteriaRelaxed",toJson false)])
  | ["seal-run"] =>
    unless !(← (root / "usage-run").pathExists) do throw (IO.userError "never retry an answering call")
    let qualification ← read (root / "usage-prepare.guard.json")
    let transport ← read (root / "usage-transport-checks.guard.json")
    for guard in #[qualification,transport] do
      unless guard.getObjValD "state" == toJson "finished" && guard.getObjValD "exitCode" == toJson (0 : Nat) &&
          guard.getObjValD "ownedPids" == toJson (#[] : Array Nat) do
        throw (IO.userError "native qualification must be complete")
    let path := root / "usage-sealed-plan.json"
    let plan ← read path
    let environment ← IO.ofExcept (plan.getObjValAs? (Array (String × Option String)) "environment")
    let bound ← artifact (root / "usage-limits.json")
    let sealedPlan ← artifact path
    let _ ← invoke #["admit",path.toString,← IO.ofExcept (sealedPlan.getObjValAs? String "sha256"),
      (root / "usage-admission.json").toString]
    guarded "usage-run" #[controller.toString,"trial-bounded",path.toString,
      ← IO.ofExcept (sealedPlan.getObjValAs? String "sha256"),
      (root / "usage-limits.json").toString,← IO.ofExcept (bound.getObjValAs? String "sha256")] environment
  | _ => throw (IO.userError "transport | init | close | refresh-plan | seal-run | audit-usage")
