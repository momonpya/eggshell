import Lean.Data.Json.Parser
import Lean.Data.Json.FromToJson
open Lean

private def root : System.FilePath := "/Users/ovm/.codex/experiments/eggshell/scope-token-study-20261028"
private def controller := (root / "controller-build/StudyMain").toString
private def project := "/Users/ovm/.codex/worktrees/hook-deadline-baseline/eggshell"
private def lean := "/Users/ovm/.elan/toolchains/leanprover--lean4---v4.33.0/bin/lean"

private def announce (text : String) : IO Unit := do
  (← IO.getStdout).putStrLn text
  (← IO.getStdout).flush

private def run (label cmd : String) (args : Array String)
    (env : Array (String × Option String) := #[]) : IO Unit := do
  let logs := root / "driver"
  IO.FS.createDirAll logs
  unless !(← (logs / (label ++ ".json")).pathExists) do throw (IO.userError "preserve the previous driver call")
  announce s!"starting {label}"
  let start ← IO.monoMsNow
  let result ← IO.Process.output {cmd,args,env,cwd := some project}
  IO.FS.writeFile (logs / (label ++ ".stdout")) result.stdout
  IO.FS.writeFile (logs / (label ++ ".stderr")) result.stderr
  IO.FS.writeFile (logs / (label ++ ".json")) (Json.mkObj [
    ("exitCode",toJson result.exitCode.toNat),("elapsedMs",toJson ((← IO.monoMsNow)-start)),
    ("command",toJson (#[cmd] ++ args))]).pretty
  announce s!"finished {label}: exit {result.exitCode}"
  unless result.exitCode == 0 do throw (IO.userError s!"{label} failed; inspect its retained logs")

private def stageHelper (label : String) (args : Array String) : IO Unit :=
  run label lean (#["--run",project ++ "/tools/research/ScopeTokenStages.lean"] ++ args)

def main (args : List String) : IO Unit := do
  let gate ← IO.ofExcept (Json.parse (← IO.FS.readFile (root / "native-gate.guard.json")))
  unless (gate.getObjValAs? Nat "exitCode").toOption == some 0 &&
      (gate.getObjValAs? (Array Nat) "ownedPids").toOption == some #[] do
    throw (IO.userError "successful completed native gate required")
  let attempt := if args == ["replacement-seed"] then "2" else "1"
  let acquisition := root / ("study/seed-" ++ attempt)
  let env : Array (String × Option String) := #[
    ("EGGSHELL_DATA_ROOT",some (acquisition / "data").toString),
    ("LEAN_NUM_THREADS",some "1"),("OMP_NUM_THREADS",some "1"),("OPENBLAS_NUM_THREADS",some "1"),
    ("MKL_NUM_THREADS",some "1"),("TOKENIZERS_PARALLELISM",some "false"),("HF_HUB_OFFLINE",some "1")]
  if attempt == "1" then
    run "seal-seed" controller #["bootstrap","seal-seed",root.toString] env
  run ("seed-" ++ attempt) controller #["guard",(root / ("seed-" ++ attempt ++ ".settings.json")).toString] env
  let finalize := Json.mkObj [
    ("record",toJson (root / "finalize.guard.json").toString),("cwd",toJson project),
    ("ownedPrefixes",toJson #[root.toString]),("limitRssKiB",toJson (3670016 : Nat)),("minFreeKiB",toJson (2097152 : Nat)),
    ("command",toJson #[controller,"seed-finalize",acquisition.toString,(root / "seed-ready").toString])]
  IO.FS.writeFile (root / "finalize.settings.json") finalize.pretty
  run "finalize" controller #["guard",(root / "finalize.settings.json").toString] env
  run "seed-audit" controller #["seed-audit",acquisition.toString,
    (root / "task-definitions.json").toString,(root / "seed-ready/ready.egg").toString,(root / "source-audit.json").toString] env
  run "freeze-seed" controller #["history","freeze",(root / "seed-ready/ready.egg").toString,
    (acquisition / "data").toString,(root / "initial-history").toString] env
  for rep in [0:2] do
    stageHelper s!"fork-r{rep}" #["fork",toString rep]
    for stage in [1:7] do
      stageHelper s!"draft-r{rep}-stage{stage}" #["stage",toString rep,toString stage]
      let directory := root / s!"r{rep}/stage{stage}"
      run s!"prepare-r{rep}-stage{stage}" controller #["guard",(directory / "prepare.settings.json").toString] env
      stageHelper s!"seal-r{rep}-stage{stage}" #["seal-trial",toString rep,toString stage]
      -- Charged failure is terminal for the chain; no retry or discarded usage.
      run s!"trial-r{rep}-stage{stage}" controller #["guard",(directory / "trial.settings.json").toString] env
      stageHelper s!"collect-r{rep}-stage{stage}" #["collect",toString rep,toString stage]
  announce "all twelve predeclared memory cells completed"
