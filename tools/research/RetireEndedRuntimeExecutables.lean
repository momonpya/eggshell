import Lean.Data.Json.Parser
import Lean.Data.Json.FromToJson
open Lean

/-- Remove completed trial executables, retaining the checked comparison and
current candidate. Native objects, sealed inputs, interfaces, models and DBs
remain available; no archive is created. -/
def main : IO Unit := do
  let root : System.FilePath := "/Users/ovm/.codex/experiments/eggshell/scope-token-study-20261028/shared-snapshot"
  let report : System.FilePath := "/Users/ovm/.codex/worktrees/hook-deadline-baseline/eggshell/docs/candidates/runtime-integration/retired-executables.json"
  unless !(← report.pathExists) do throw (IO.userError "preserve previous retirement")
  let names := #["contract", "historical", "historical-evidence", "historical-read",
    "hook", "optionalchecks", "pages", "product", "recipes", "scan", "service", "write"]
  let processes ← IO.Process.output {cmd := "/bin/ps", args := #["-axo", "command="]}
  unless processes.exitCode == 0 do throw (IO.userError "process inspection failed")
  let mut targets : Array Json := #[]
  let mut paths : Array System.FilePath := #[]
  let mut total := 0
  for name in names do
    let directory := root / System.FilePath.mk (name ++ "-build")
    let executable := directory / "StudyMain"
    if !(← executable.pathExists) then continue
    unless (← directory.symlinkMetadata).type == .dir &&
        (← executable.symlinkMetadata).type == .file do
      throw (IO.userError "retirement target must be a direct regular file")
    unless (processes.stdout.splitOn executable.toString).length == 1 do
      throw (IO.userError "completed executable is still running")
    unless (← (directory / "build.json").pathExists) &&
        (← (directory / "runtime.rsp").pathExists) do
      throw (IO.userError "retirement lost native rebuild evidence")
    let digest ← IO.Process.output {cmd := "/usr/bin/shasum", args := #["-a", "256", executable.toString]}
    unless digest.exitCode == 0 do throw (IO.userError "executable digest failed")
    let size := (← executable.symlinkMetadata).byteSize.toNat
    targets := targets.push (Json.mkObj [("path", toJson executable.toString),
      ("sha256", toJson ((digest.stdout.splitOn " ").head!)), ("bytes", toJson size)])
    paths := paths.push executable
    total := total + size
  IO.FS.createDirAll report.parent.get!
  let evidence := Json.mkObj [("targets", Json.arr targets), ("logicalBytes", toJson total),
    ("retainedRuntimes", toJson #["dependency-checked-runtime-build", "maintenance-runtime-build"]),
    ("objectsSourcesDependenciesInterfacesDatabasesAndModelsRetained", toJson true),
    ("archiveCreated", toJson false)]
  IO.FS.writeFile report (evidence.setObjVal! "completed" (toJson false)).pretty
  for path in paths do IO.FS.removeFile path
  IO.FS.writeFile report (evidence.setObjVal! "completed" (toJson true)).pretty
  IO.println s!"Deleted {paths.size} completed executables, {total} logical bytes; no DB or archive changes"
