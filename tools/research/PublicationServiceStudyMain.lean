import Lean.Data.Json.Parser
import Lean.Data.Json.FromToJson
open Lean

/-- Prepare uniquely named resource-guarded build/run records. Never overwrite
an earlier guard or relink an executable while a trial is using it. -/
def main (args : List String) : IO Unit := do
  let [label,mode] := args | throw (IO.userError "PublicationServiceStudyMain LABEL MODE")
  let root := System.FilePath.mk "/Users/ovm/.codex/experiments/eggshell/publication-service-20261026"
  let project := System.FilePath.mk "/Users/ovm/.codex/worktrees/hook-deadline-baseline/eggshell"
  let toolchain := "/Users/ovm/.elan/toolchains/leanprover--lean4---v4.33.0"
  let record := root / (label ++ ".guard.json")
  unless !(← record.pathExists) do throw (IO.userError "keep the existing guard record")
  let mut settings ← IO.ofExcept (Json.parse (← IO.FS.readFile (root / "build.settings.json")))
  settings := settings.setObjVal! "record" (toJson record.toString)
  let command ← match mode with
    | "build" | "trial-build" | "native-build" | "lifecycle-build" => do
      let plan ← IO.ofExcept (Json.parse (← IO.FS.readFile (root / "build-plan.json")))
      let plan := if mode == "build" then plan else
        plan.setObjVal! "mainModule" (toJson (if mode == "native-build" then
          "tools.research.NativePublicationNativeMain" else if mode == "lifecycle-build" then
          "tools.research.PublicationServiceLifecycleMain" else "tools.research.PublicationServiceTrialMain"))
          |>.setObjVal! "force" (toJson (#[] : Array String))
      let path := root / (label ++ ".plan.json")
      IO.FS.writeFile path plan.pretty
      pure #["/usr/bin/env","LEAN_PATH=" ++ toolchain ++ "/lib/lean",toolchain ++ "/bin/lean",
        "-j1","-M1536","--run",(project / "tools/research/StudyBuildMain.lean").toString,path.toString]
    | "trial" => pure #["/usr/bin/env","EGGSHELL_DATA_ROOT=" ++ (root / "trial-data").toString,
        "LEAN_NUM_THREADS=1",(root / "build/StudyMain").toString,root.toString,label]
    | "native" => pure #["/usr/bin/env","EGGSHELL_DATA_ROOT=" ++ (root / "native/data").toString,
        "LEAN_NUM_THREADS=1",(root / "build/StudyMain").toString,
        root.toString,"publisher"]
    | "lifecycle" => pure #["/usr/bin/env","EGGSHELL_DATA_ROOT=" ++ (root / "lifecycle-data").toString,
        "LEAN_NUM_THREADS=1",(root / "build/StudyMain").toString,root.toString,label]
    | "contract" | "boundary" => pure #["/usr/bin/env",
        "LEAN_PATH=" ++ (root / "build/lib").toString ++ ":" ++
          (root / "checkout/.lake/build/lib/lean").toString ++ ":" ++ toolchain ++ "/lib/lean",
        toolchain ++ "/bin/lean","--root=" ++ (if mode == "contract" then
          (root / "checkout").toString else project.toString),"-j1","-M1536","-DwarningAsError=true",
        (if mode == "contract" then root / "checkout/Eggshell/ContractAudit.lean" else
          project / "tools/research/NativePublicationContract.lean").toString]
    | _ => throw (IO.userError "invalid publication study mode")
  settings := settings.setObjVal! "command" (toJson command)
  IO.FS.writeFile (root / (label ++ ".settings.json")) settings.pretty
