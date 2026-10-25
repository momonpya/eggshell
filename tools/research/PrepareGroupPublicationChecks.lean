import Lean.Data.Json.Parser
import Lean.Data.Json.FromToJson
open Lean

def main (args : List String) : IO Unit := do
  let [label,mode] := args | throw (IO.userError "PrepareGroupPublicationChecks LABEL MODE")
  let root := System.FilePath.mk "/Users/ovm/.codex/experiments/eggshell/group-publication-20261025"
  let project := System.FilePath.mk "/Users/ovm/.codex/worktrees/hook-deadline-baseline/eggshell"
  let toolchain := "/Users/ovm/.elan/toolchains/leanprover--lean4---v4.33.0"
  let mut settings ← IO.ofExcept (Json.parse (← IO.FS.readFile (root / "build.settings.json")))
  settings := settings.setObjVal! "record" (toJson (root / (label ++ ".guard.json")).toString)
  let command ← match mode with
    | "batch-build" | "atomic-build" | "native-build" | "bounds-build" | "seal-build" => do
      let name := if mode == "batch-build" then "tools.research.SharedPublicationBatchMain"
        else if mode == "atomic-build" then "tools.research.NativePublicationMain"
        else if mode == "native-build" then "tools.research.NativePublicationNativeMain"
        else if mode == "bounds-build" then "tools.research.GroupPublicationBoundsMain"
        else "tools.research.SealGroupPublicationMain"
      let plan ← IO.ofExcept (Json.parse (← IO.FS.readFile (root / "build-plan.json")))
      let plan := plan.setObjVal! "mainModule" (toJson name) |>.setObjVal! "force" (toJson (#[] : Array String))
      let path := root / (label ++ ".plan.json")
      IO.FS.writeFile path plan.pretty
      pure #["/usr/bin/env","LEAN_PATH=" ++ toolchain ++ "/lib/lean",toolchain ++ "/bin/lean","-j1","-M1536",
        "--run",(project / "tools/research/StudyBuildMain.lean").toString,path.toString]
    | "batch-run" => pure #["/usr/bin/env","EGGSHELL_DATA_ROOT=" ++ (root / "batch-data").toString,
        "LEAN_NUM_THREADS=1",(root / "build/StudyMain").toString,
        "/Users/ovm/.codex/experiments/eggshell/shared-publication-20261025/fixtures",(root / "fixtures").toString]
    | "create" | "copy" => pure #["/usr/bin/env","EGGSHELL_DATA_ROOT=" ++
        (root / (if mode == "create" then "check-data" else "check-data-fresh")).toString,
        "LEAN_NUM_THREADS=1",(root / "build/StudyMain").toString,mode,(root / "checks").toString]
    | "native-run" => pure #["/usr/bin/env","EGGSHELL_DATA_ROOT=" ++ (root / "native/data").toString,
        "LEAN_NUM_THREADS=1",(root / "build/StudyMain").toString,root.toString]
    | "bounds-run" => pure #["/usr/bin/env","EGGSHELL_DATA_ROOT=" ++ (root / "bounds-data").toString,
        "LEAN_NUM_THREADS=1",(root / "build/StudyMain").toString,(root / "bounds").toString]
    | "contract" | "boundary" =>
      let base := if mode == "contract" then root / "checkout" else project
      let file := if mode == "contract" then base / "Eggshell/ContractAudit.lean"
        else base / "tools/research/NativePublicationContract.lean"
      pure #["/usr/bin/env","LEAN_PATH=" ++ (root / "build/lib").toString ++ ":" ++ toolchain ++ "/lib/lean",
        toolchain ++ "/bin/lean","--root=" ++ base.toString,"-j1","-M3072","-DwarningAsError=true",file.toString]
    | _ => throw (IO.userError "unknown group publication check mode")
  settings := settings.setObjVal! "command" (toJson command)
  IO.FS.writeFile (root / (label ++ ".settings.json")) settings.pretty
