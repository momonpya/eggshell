import Lean.Data.Json.Parser
import Lean.Data.Json.FromToJson
open Lean

def main (args : List String) : IO Unit := do
  let [label,mode] := args | throw (IO.userError "PrepareNativePublicationChecks LABEL build|contract|boundary|create|copy|native|ingress")
  let root := System.FilePath.mk "/Users/ovm/.codex/experiments/eggshell/native-publication-20261025"
  let project := System.FilePath.mk "/Users/ovm/.codex/worktrees/hook-deadline-baseline/eggshell"
  let toolchain := "/Users/ovm/.elan/toolchains/leanprover--lean4---v4.33.0"
  let mut settings ← IO.ofExcept (Json.parse (← IO.FS.readFile (root / "build-root.settings.json")))
  settings := settings.setObjVal! "record" (toJson (root / (label ++ ".guard.json")).toString)
  let command ← match mode with
    | "build" | "native" => do
      let plan ← IO.ofExcept (Json.parse (← IO.FS.readFile (root / "build-plan.json")))
      let main := if mode == "build" then "tools.research.NativePublicationMain" else "tools.research.NativePublicationNativeMain"
      let plan := plan.setObjVal! "mainModule" (toJson main) |>.setObjVal! "force" (toJson (#[] : Array String))
      let path := root / (label ++ ".plan.json")
      IO.FS.writeFile path (plan.pretty ++ "\n")
      pure #["/usr/bin/env","LEAN_PATH=" ++ toolchain ++ "/lib/lean",toolchain ++ "/bin/lean","-j1","-M1536",
        "--run",(project / "tools/research/StudyBuildMain.lean").toString,path.toString]
    | "contract" => pure #["/usr/bin/env","LEAN_PATH=" ++ (root / "build/lib").toString ++ ":" ++ toolchain ++ "/lib/lean",
        toolchain ++ "/bin/lean","--root=" ++ (root / "checkout").toString,"-j1","-M3072","-DwarningAsError=true",
        (root / "checkout/Eggshell/ContractAudit.lean").toString]
    | "boundary" => pure #["/usr/bin/env","LEAN_PATH=" ++ (root / "build/lib").toString ++ ":" ++ toolchain ++ "/lib/lean",
        toolchain ++ "/bin/lean","--root=" ++ project.toString,"-j1","-M1536","-DwarningAsError=true",
        (project / "tools/research/NativePublicationContract.lean").toString]
    | "create" | "copy" => pure #["/usr/bin/env",
        "EGGSHELL_DATA_ROOT=" ++ (root / (if mode == "create" then "test-data" else "test-data-fresh")).toString,
        "LEAN_NUM_THREADS=1",(root / "build/StudyMain").toString,mode,(root / "checks").toString]
    | "ingress" => pure #["/usr/bin/env","EGGSHELL_DATA_ROOT=" ++ (root / "native/data").toString,
        "LEAN_NUM_THREADS=1",(root / "build/StudyMain").toString]
    | _ => throw (IO.userError "invalid native publication check mode")
  settings := settings.setObjVal! "command" (toJson command)
  IO.FS.writeFile (root / (label ++ ".settings.json")) (settings.pretty ++ "\n")
