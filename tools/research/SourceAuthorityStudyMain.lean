import Lean.Data.Json.Parser
import Lean.Data.Json.FromToJson
open Lean

def main (args : List String) : IO Unit := do
  let [label,mode] := args | throw (IO.userError "SourceAuthorityStudyMain LABEL MODE")
  let root := System.FilePath.mk "/Users/ovm/.codex/experiments/eggshell/source-authority-20261026"
  let parent := System.FilePath.mk "/Users/ovm/.codex/experiments/eggshell/publication-service-20261026"
  let project := System.FilePath.mk "/Users/ovm/.codex/worktrees/hook-deadline-baseline/eggshell"
  let toolchain := "/Users/ovm/.elan/toolchains/leanprover--lean4---v4.33.0"
  let record := root / (label ++ ".guard.json")
  unless !(← record.pathExists) do throw (IO.userError "keep existing source-authority evidence")
  let mut settings ← IO.ofExcept (Json.parse (← IO.FS.readFile (root / "build.settings.json")))
  -- These model-free fixtures allocate only small journals/DBs. Reserve 2 GiB
  -- of disk; the independent 3.5 GiB aggregate-RSS stop remains unchanged.
  settings := settings.setObjVal! "record" (toJson record.toString)
    |>.setObjVal! "minFreeKiB" (toJson (2097152 : Nat))
  let command ← match mode with
    | "build" | "checks-build" | "baseline-build" | "native-build" => do
      let mut plan ← IO.ofExcept (Json.parse (← IO.FS.readFile (root / "build-plan.json")))
      if mode != "build" then
        plan := plan.setObjVal! "mainModule" (toJson (if mode == "native-build" then
          "tools.research.NativePublicationNativeMain" else "tools.research.SourceAuthorityChecksMain"))
          |>.setObjVal! "force" (toJson (#[] : Array String))
      if mode == "baseline-build" then
        plan := plan.setObjVal! "core" (toJson (parent / "checkout").toString)
          |>.setObjVal! "output" (toJson (root / "baseline-build").toString)
      let path := root / (label ++ ".plan.json")
      IO.FS.writeFile path plan.pretty
      pure #["/usr/bin/env","LEAN_PATH=" ++ toolchain ++ "/lib/lean",toolchain ++ "/bin/lean",
        "-j1","-M1536","--run",(project / "tools/research/StudyBuildMain.lean").toString,path.toString]
    | "baseline" | "checks" =>
      let arm := if mode == "baseline" then "baseline" else "candidate"
      pure #["/usr/bin/env","EGGSHELL_DATA_ROOT=" ++ (root / (arm ++ "-data")).toString,
        "LEAN_NUM_THREADS=1",(root / (if mode == "baseline" then "baseline-build/StudyMain" else
          "build/StudyMain")).toString,(root / (label ++ "-fixtures")).toString,arm]
    | "native" => pure #["/usr/bin/env","EGGSHELL_DATA_ROOT=" ++ (root / "native/data").toString,
        "LEAN_NUM_THREADS=1",(root / "build/StudyMain").toString,root.toString,"publisher"]
    | "contract" | "boundary" | "source-contract" =>
      pure #["/usr/bin/env","LEAN_PATH=" ++ (root / "build/lib").toString ++ ":" ++
          (root / "checkout/.lake/build/lib/lean").toString ++ ":" ++ toolchain ++ "/lib/lean",
        toolchain ++ "/bin/lean","--root=" ++ (if mode == "contract" then
          (root / "checkout").toString else project.toString),"-j1","-M1536","-DwarningAsError=true",
        (if mode == "contract" then root / "checkout/Eggshell/ContractAudit.lean" else
          project / "tools/research" / (if mode == "boundary" then "NativePublicationContract.lean" else
          "SourceAuthorityContract.lean")).toString]
    | _ => throw (IO.userError "unknown source-authority mode")
  settings := settings.setObjVal! "command" (toJson command)
  IO.FS.writeFile (root / (label ++ ".settings.json")) settings.pretty
