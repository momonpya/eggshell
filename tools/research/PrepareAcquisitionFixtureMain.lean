import Lean.Data.Json.Parser
import Lean.Data.Json.FromToJson
open Lean

private def root := System.FilePath.mk "/Users/ovm/.codex/experiments/eggshell/study-services-20261026"

private def read (path : System.FilePath) : IO Json := do
  IO.ofExcept (Json.parse (← IO.FS.readFile path))

private def artifact (path : System.FilePath) : IO Json := do
  let result ← IO.Process.output {cmd := (root / "controller").toString,args := #["artifacts",path.toString]}
  unless result.exitCode == 0 do throw (IO.userError "fixture artifact hashing failed")
  let rows ← IO.ofExcept (Json.parse result.stdout >>= Json.getArr?)
  let some item := rows[0]? | throw (IO.userError "missing fixture artifact")
  return item

/-- Prepare synthetic protocol checks only. Real hooks, publication and
source reads execute; the fixture emits a labelled 110-token counter. -/
def main : IO Unit := do
  let previous := System.FilePath.mk "/Users/ovm/.codex/experiments/eggshell/lean-study-20261025"
  let project := System.FilePath.mk "/Users/ovm/.codex/worktrees/hook-deadline-baseline/eggshell"
  let original ← read (previous / "seed-1.plan.json")
  let plugin := root / "prefix/share/eggshell/codex-plugin"
  let launcher := plugin / "bin/eggshelld"
  let egg := plugin / "bin/egg"
  unless !(← egg.pathExists) do throw (IO.userError "keep existing fixture launchers")
  let copied ← IO.Process.output {cmd := "/bin/cp",args := #["-p",launcher.toString,egg.toString]}
  unless copied.exitCode == 0 do throw (IO.userError "fixture launcher copy failed")
  let gate := root / "native"
  let facts ← read (gate / "result.json")
  let runtime ← IO.ofExcept (facts.getObjVal? "runtime")
  let producer ← artifact (root / "prefix/libexec/eggshell")
  unless producer == runtime do throw (IO.userError "fixture runtime differs from its actual native gate")
  let runner ← artifact (root / "controller")
  let fixture ← artifact (root / "acquisition-fixture")
  let gateFields := Json.mkObj [
    ("report",← artifact (gate / "result.json")),("guard",← artifact (root / "native-owned.guard.json")),
    ("shutdown",← artifact (gate / "shutdown.json")),("recovery",← artifact (gate / "recovery.json")),
    ("publisherShutdown",← artifact (gate / "publisher-shutdown.json"))]
  let pluginFiles ← #[egg,launcher].mapM artifact
  let mut harness := #[]
  for name in #["StudyRuntime.lean","StudyAcquire.lean","StudyTrial.lean","StudyAccounting.lean",
      "StudyAcquisitionFixture.lean","StudySeedChecks.lean","ResourceGuard.lean"] do
    harness := harness.push (← artifact (project / "tools/research" / name))
  let config ← artifact (previous / "account/config.toml")
  for kind in #["seed","fresh"] do
    let output := root / ("synthetic-" ++ kind)
    let planFile := root / ("synthetic-" ++ kind ++ ".plan.json")
    unless !(← planFile.pathExists) && !(← output.pathExists) do throw (IO.userError "keep existing acquisition fixture")
    let updates : Array (String × Option String) := #[
      ("CODEX_HOME",some (previous / "account").toString),("TMPDIR",some (root / "tmp").toString),
      ("EGGSHELL_PREFIX",some (root / "prefix").toString),("PLUGIN_ROOT",some plugin.toString),
      ("EGGSHELL_ACQUISITION_SCENARIO",some planFile.toString),("LEAN_NUM_THREADS",some "1"),
      ("OMP_NUM_THREADS",some "1"),("OPENBLAS_NUM_THREADS",some "1"),("MKL_NUM_THREADS",some "1"),
      ("HF_HUB_OFFLINE",some "1"),("TOKENIZERS_PARALLELISM",some "false"),
      ("CODEX_THREAD_ID",none),("CODEX_TURN_ID",none)]
    let plan := original.setObjVal! "kind" (toJson kind) |>.setObjVal! "provider" (toJson "synthetic")
      |>.setObjVal! "label" (toJson ("service-fixture-" ++ kind))
      |>.setObjVal! "runtime" runtime |>.setObjVal! "runner" runner
      |>.setObjVal! "cliWrapper" fixture |>.setObjVal! "nativeCli" fixture
      |>.setObjVal! "accountConfiguration" config |>.setObjVal! "pluginRoot" (toJson plugin.toString)
      |>.setObjVal! "pluginFiles" (toJson pluginFiles) |>.setObjVal! "gate" gateFields
      |>.setObjVal! "harness" (toJson harness) |>.setObjVal! "environment" (toJson updates)
      |>.setObjVal! "output" (toJson output.toString)
      |>.setObjVal! "guardRecord" (toJson (root / ("synthetic-" ++ kind ++ ".guard.json")).toString)
    IO.FS.writeFile planFile plan.pretty
    let sealedPlan ← artifact planFile
    let runnerPath ← IO.ofExcept (runner.getObjValAs? String "path")
    let digest ← IO.ofExcept (sealedPlan.getObjValAs? String "sha256")
    let settings := Json.mkObj [("record",plan.getObjValD "guardRecord"),("cwd",plan.getObjValD "workspace"),
      ("ownedPrefixes",toJson #[output.toString,(root / "prefix").toString,runnerPath,
        (root / "acquisition-fixture").toString]),("limitRssKiB",toJson (3670016 : Nat)),
      ("minFreeKiB",toJson (524288 : Nat)),
      ("command",toJson #[runnerPath,"acquire",planFile.toString,digest])]
    IO.FS.writeFile (root / ("synthetic-" ++ kind ++ ".settings.json")) settings.pretty
  IO.println "prepared synthetic seed and fresh checks; no answering model calls"
