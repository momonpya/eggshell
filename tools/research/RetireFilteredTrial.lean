import Lean.Data.Json.Parser
import Lean.Data.Json.FromToJson
open Lean
private def read (path : System.FilePath) : IO Json :=
  IO.FS.readFile path >>= fun text => IO.ofExcept (Json.parse text)
private partial def remove (path : System.FilePath) : IO Unit := do
  if (← path.symlinkMetadata).type == .dir then
    for entry in ← path.readDir do remove entry.path
    IO.FS.removeDir path
  else IO.FS.removeFile path

def main : IO Unit := do
  let root := System.FilePath.mk "/Users/ovm/.codex/experiments/eggshell/filtered-postings-20261027"
  let trial := root / "actual-filtered-hook"
  let project := System.FilePath.mk "/Users/ovm/.codex/worktrees/hook-deadline-baseline/eggshell"
  let output := project / "docs/candidates/filtered-postings"
  unless !(← (output / "retired-trial.json").pathExists) do throw (IO.userError "preserve prior retirement")
  let guard ← read (root / "actual-filtered-hook.guard.json")
  unless guard.getObjValD "state" == toJson "finished" && guard.getObjValD "ownedPids" == toJson (#[] : Array Nat) do
    throw (IO.userError "actual hook remains live")
  unless (← read (trial / "result.json")) == (← read (output / "hook/result.json")) &&
      (← IO.FS.readBinFile (trial / "body.txt")) == (← IO.FS.readBinFile (output / "hook/body.txt")) do
    throw (IO.userError "capture the ended actual hook first")
  unless !(← (trial / "work.egg").pathExists) do throw (IO.userError "do not remove a source database")
  let processes ← IO.Process.output {cmd := "/bin/ps",args := #["-axo","command="]}
  let auditBinary := root / "audit-build/StudyMain"
  unless processes.exitCode == 0 && (processes.stdout.splitOn trial.toString).length == 1 &&
      (processes.stdout.splitOn auditBinary.toString).length == 1 do throw (IO.userError "trial or audit still referenced")
  for name in ["product-build/runtime.rsp","hook-build/runtime.rsp"] do
    unless ((← IO.FS.readFile (root / name)).splitOn trial.toString).length == 1 do
      throw (IO.userError "retained native build refers to ended trial")
  let mut guards := #[]
  let mut maximum := 0
  for entry in ← root.readDir do
    if entry.fileName.endsWith ".guard.json" then
      let value ← read entry.path
      unless value.getObjValD "state" == toJson "finished" && value.getObjValD "ownedPids" == toJson (#[] : Array Nat) do
        throw (IO.userError "a candidate operation is still live")
      maximum := max maximum ((value.getObjValAs? Nat "sampledPeakRssKiB").toOption.getD 0)
      guards := guards.push (entry.fileName,value)
  IO.FS.writeFile (output / "terminal-guards.json") (toJson guards).pretty
  IO.FS.writeFile (output / "retired-trial.json") (Json.mkObj [
    ("target",toJson trial.toString),("auditExecutable",toJson auditBinary.toString),
    ("sampledPeakRssKiB",toJson maximum),("activeCandidateAndBaselineRetained",toJson true),
    ("originalAndOnePreparedDatabaseRetained",toJson true),("archiveCreated",toJson false)]).pretty
  remove trial
  IO.FS.removeFile auditBinary
  IO.println "Deleted ended run/cache/runtime copy and audit executable; retained active candidate"
