import Lean.Data.Json.Parser
import Lean.Data.Json.FromToJson
open Lean

def main (args : List String) : IO Unit := do
  let [label,mode] := args | throw (IO.userError "PrepareSharedPublicationTrialMain LABEL build|run|coverage-build|coverage")
  let root := System.FilePath.mk "/Users/ovm/.codex/experiments/eggshell/shared-publication-20261025"
  let candidate := System.FilePath.mk "/Users/ovm/.codex/experiments/eggshell/native-publication-20261025"
  let project := System.FilePath.mk "/Users/ovm/.codex/worktrees/hook-deadline-baseline/eggshell"
  let toolchain := "/Users/ovm/.elan/toolchains/leanprover--lean4---v4.33.0"
  IO.FS.createDirAll root
  let mut settings ← IO.ofExcept (Json.parse (← IO.FS.readFile (candidate / "build-root.settings.json")))
  settings := settings.setObjVal! "record" (toJson (root / (label ++ ".guard.json")).toString)
    |>.setObjVal! "ownedPrefixes" (toJson #[root.toString,candidate.toString])
    |>.setObjVal! "minFreeKiB" (toJson (4194304 : Nat))
  let command ← match mode with
    | "build" | "coverage-build" => do
      let plan ← IO.ofExcept (Json.parse (← IO.FS.readFile (candidate / "build-plan.json")))
      let plan := plan.setObjVal! "mainModule" (toJson (if mode == "build" then
          "tools.research.SharedPublicationTrialMain" else "tools.research.RequiredDeliveryChecks"))
        |>.setObjVal! "force" (toJson (#[] : Array String))
      let path := root / (label ++ ".plan.json")
      IO.FS.writeFile path (plan.pretty ++ "\n")
      pure #["/usr/bin/env","LEAN_PATH=" ++ toolchain ++ "/lib/lean",toolchain ++ "/bin/lean","-j1","-M1536",
        "--run",(project / "tools/research/StudyBuildMain.lean").toString,path.toString]
    | "run" => pure #["/usr/bin/env","EGGSHELL_DATA_ROOT=" ++ (root / "data").toString,
        "LEAN_NUM_THREADS=1",(candidate / "build/StudyMain").toString,(root / "fixtures").toString]
    | "coverage" => pure #["/usr/bin/env","LEAN_NUM_THREADS=1",(candidate / "build/StudyMain").toString]
    | _ => throw (IO.userError "invalid shared publication trial mode")
  settings := settings.setObjVal! "command" (toJson command)
  IO.FS.writeFile (root / (label ++ ".settings.json")) (settings.pretty ++ "\n")
