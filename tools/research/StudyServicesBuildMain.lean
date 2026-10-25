import Lean.Data.Json.Parser
import Lean.Data.Json.FromToJson
open Lean

def main (args : List String) : IO Unit := do
  let [label,mode] := args | throw (IO.userError "StudyServicesBuildMain LABEL MODE")
  let root := System.FilePath.mk "/Users/ovm/.codex/experiments/eggshell/study-services-20261026"
  let project := System.FilePath.mk "/Users/ovm/.codex/worktrees/hook-deadline-baseline/eggshell"
  let toolchain := "/Users/ovm/.elan/toolchains/leanprover--lean4---v4.33.0"
  let record := root / (label ++ ".guard.json")
  unless !(← record.pathExists) do throw (IO.userError "keep existing study-service guard")
  let mut settings ← IO.ofExcept (Json.parse (← IO.FS.readFile (root / "build.settings.json")))
  -- Small controller/fixture builds reserve 1 GiB of disk. Generation keeps
  -- its independent 2 GiB startup requirement; aggregate RSS still stops at 3.5 GiB.
  settings := settings.setObjVal! "record" (toJson record.toString)
    |>.setObjVal! "minFreeKiB" (toJson (1048576 : Nat))
  let command ← match mode with
    | "controller-build" | "checks-build" | "native-build" | "fixture-build" | "gate-build" => do
      let plan ← IO.ofExcept (Json.parse (← IO.FS.readFile (root / "build-plan.json")))
      let name := match mode with
        | "controller-build" => "StudyMain"
        | "checks-build" => "StudyServicesChecksMain"
        | "native-build" => "NativePublicationNativeMain"
        | "gate-build" => "StudyAcquisitionChecks"
        | _ => "StudyAcquisitionFixture"
      let plan := plan.setObjVal! "mainModule" (toJson ("tools.research." ++ name))
      let path := root / (label ++ ".plan.json")
      IO.FS.writeFile path plan.pretty
      pure #["/usr/bin/env","LEAN_PATH=" ++ toolchain ++ "/lib/lean",toolchain ++ "/bin/lean",
        "-j1","-M1536","--run",(project / "tools/research/StudyBuildMain.lean").toString,path.toString]
    | "checks" => pure #["/usr/bin/env","LEAN_NUM_THREADS=1",(root / "build/StudyMain").toString,
        "/Users/ovm/.codex/experiments/eggshell/source-authority-20261026/prefix/libexec/eggshell",
        (root / (label ++ "-fixtures")).toString]
    | "native" => pure #["/usr/bin/env","LEAN_NUM_THREADS=1",
        "EGGSHELL_DATA_ROOT=" ++ (root / "native/data").toString,
        (root / "build/StudyMain").toString,root.toString]
    | "gate" => pure #["/usr/bin/env","LEAN_NUM_THREADS=1",(root / "build/StudyMain").toString,
        "/Users/ovm/.codex/experiments/eggshell/source-authority-20261026"]
    | _ => throw (IO.userError "unknown study-service mode")
  settings := settings.setObjVal! "command" (toJson command)
  IO.FS.writeFile (root / (label ++ ".settings.json")) settings.pretty
