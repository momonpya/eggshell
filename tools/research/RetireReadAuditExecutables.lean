import Lean.Data.Json.FromToJson
import Lean.Data.Json.Parser

open Lean

/-- Completed audit executables are not build inputs: their native objects,
interfaces, source stamps and reports remain. Delete no source DB or cache. -/
def main (args : List String) : IO Unit := do
  let root : System.FilePath := "/Users/ovm/.codex/experiments/eggshell/scope-token-study-20261028/fixed-frame-study"
  let (reportName,names) ← match args with
    | [] => pure ("read-audit-executable-cleanup.json",
        ["read-audit-build/StudyMain","storage-audit-build/StudyMain","replay-audit-build/StudyMain"])
    | ["catalog"] => pure ("read-catalog-helper-cleanup.json",
        ["read-catalog-checks-build/StudyMain","read-catalog-collect-build/StudyMain"])
    | _ => throw (IO.userError "[catalog]")
  let report := root / reportName
  unless !(← report.pathExists) do throw (IO.userError "cleanup already recorded")
  let processes ← IO.Process.output {cmd := "/bin/ps",args := #["-axo","command="]}
  unless processes.exitCode == 0 do throw (IO.userError "cannot inspect native readers")
  let mut deleted := #[]
  for name in names do
    let path := root / name
    unless (← path.pathExists) && !(processes.stdout.splitOn "\n").any (·.startsWith path.toString) do
      throw (IO.userError "ended audit executable is absent or active")
    let sha ← IO.Process.output {cmd := "/usr/bin/shasum",args := #["-a","256",path.toString]}
    unless sha.exitCode == 0 do throw (IO.userError "cannot seal the retired helper")
    let size := (← path.metadata).byteSize
    deleted := deleted.push (Json.mkObj [("path",toJson path.toString),("bytes",toJson size),
      ("sha256",toJson (sha.stdout.splitOn " ").head!)])
  IO.FS.writeFile report (Json.mkObj [("executables",toJson deleted),("completed",toJson false)]).pretty
  for name in names do
    IO.FS.removeFile (root / name)
  let receipt := Json.mkObj [("executables",toJson deleted),("completed",toJson true),
    ("nativeObjectsAndInterfacesPreserved",toJson true),("sourceDatabasesUnchanged",toJson true),
    ("archiveCreated",toJson false)]
  IO.FS.writeFile report receipt.pretty
  if args == ["catalog"] then
    let target : System.FilePath := "/Users/ovm/.codex/worktrees/hook-deadline-baseline/eggshell/docs/candidates/read-catalog/retired-helpers.json"
    unless !(← target.pathExists) do throw (IO.userError "preserve retired helper receipt")
    IO.FS.writeFile target receipt.pretty
    for suffix in ["stdout","stderr"] do
      for name in ["read-catalog-collect","read-catalog-collect-compile","read-catalog-collect-compile2"] do
        let path := root / (name ++ "." ++ suffix)
        if ← path.pathExists then IO.FS.removeFile path
  IO.println s!"Deleted {names.length} ended native audit executables; build objects and original DBs retained."
