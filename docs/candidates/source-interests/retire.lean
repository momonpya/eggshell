import Lean.Data.Json.FromToJson
import Lean.Data.Json.Parser
open Lean
def main : IO Unit := do
  let base : System.FilePath := "/Users/ovm/.codex/experiments/eggshell/scope-token-study-20261028/fixed-frame-study"
  let report : System.FilePath := "/Users/ovm/.codex/worktrees/hook-deadline-baseline/eggshell/docs/candidates/source-interests/retired-helpers.json"
  unless !(← report.pathExists) do throw (IO.userError "retain existing deletion accounting")
  let stopped ← IO.Process.output {cmd := "/bin/ps",args := #["-axo","command="]}
  unless stopped.exitCode == 0 do throw (IO.userError "process inventory unavailable")
  let names := ["prepared-basis-runtime-build","prepared-query-runtime-build","lexical-delta-runtime-build",
    "prepared-progress-runtime-build","empty-routing-runtime-build","owned-project-access-build",
    "lexical-delta-study-build","prepared-progress-study-build","empty-routing-study-build"]
  let mut rows := #[]
  let mut total := 0
  for name in names do
    let path := base/name/"StudyMain"
    unless (← path.symlinkMetadata).type == .file && !stopped.stdout.contains path.toString do
      throw (IO.userError "retired helper is not a stopped regular file")
    let hash ← IO.Process.output {cmd := "/usr/bin/shasum",args := #["-a","256",path.toString]}
    unless hash.exitCode == 0 do throw (IO.userError hash.stderr)
    let size := (← path.metadata).byteSize.toNat
    total := total+size
    rows := rows.push (Json.mkObj [("path",toJson path.toString),("bytes",toJson size),
      ("sha256",toJson ((hash.stdout.take 64).toString))])
  IO.FS.createDirAll report.parent.get!
  IO.FS.writeFile report (Json.mkObj [("removed",Json.arr rows),("bytes",toJson total),
    ("reason",toJson "superseded stopped research executables; current/protected helpers and all build inputs retained"),
    ("archiveCreated",toJson false),("completed",toJson false)]).pretty
  for name in names do IO.FS.removeFile (base/name/"StudyMain")
  let saved ← IO.ofExcept (Json.parse (← IO.FS.readFile report))
  IO.FS.writeFile report ((saved.setObjVal! "completed" (toJson true)).pretty++"\n")
  IO.println (Json.mkObj [("removedBytes",toJson total),("archiveCreated",toJson false)]).compress
