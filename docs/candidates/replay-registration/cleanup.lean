import Lean.Data.Json.FromToJson
import Lean.Data.Json.Parser
open Lean
def base : System.FilePath := "/Users/ovm/.codex/experiments/eggshell/scope-token-study-20261028/fixed-frame-study"
def output : System.FilePath := "/Users/ovm/.codex/worktrees/hook-deadline-baseline/eggshell/docs/candidates/replay-registration"
def read (path : System.FilePath) : IO Json := do IO.ofExcept (Json.parse (← IO.FS.readFile path))
def hash (path : System.FilePath) : IO String := do
  let result ← IO.Process.output {cmd := "/usr/bin/shasum",args := #["-a","256",path.toString]}
  unless result.exitCode == 0 do throw (IO.userError "cannot validate retained source")
  return (result.stdout.splitOn " ").head!
partial def size (path : System.FilePath) : IO Nat := do
  let metadata ← path.symlinkMetadata
  if metadata.type != .dir then return metadata.byteSize.toNat
  let mut bytes := 0
  for entry in ← path.readDir do bytes := bytes+(← size entry.path)
  return bytes
def main : IO Unit := do
  unless (← (output/"evidence.json").pathExists) && !(← (output/"cleanup.json").pathExists) do
    throw (IO.userError "seal evidence before cleanup and preserve prior receipt")
  let evidence ← read (output/"evidence.json")
  let sources ← IO.ofExcept (evidence.getObjValAs? (Array (String × String × String)) "sourceHashes")
  for (name,before,after) in sources do
    unless (← hash (base/"replay-registration-baseline-core/Eggshell"/name)) == before &&
        (← hash (base/"interest-traffic-core/Eggshell"/name)) == after do
      throw (IO.userError "sealed source changed before cleanup")
  let mut recording := #[]
  for entry in ← base.readDir do
    if !entry.fileName.startsWith "replay-registration-records" || !entry.fileName.endsWith ".guard.json" then continue
    let guard ← read entry.path
    unless guard.getObjValD "state" == toJson "finished" && guard.getObjValD "ownedPids" == toJson (#[] : Array Nat) do
      throw (IO.userError "recording still owns work")
    recording := recording.push (entry.fileName,guard,← IO.FS.readFile (base/(entry.fileName.replace ".guard.json" ".log")))
  IO.FS.writeFile (output/"recording-guards.json") (toJson recording).pretty
  let guards ← IO.ofExcept (evidence.getObjValAs? (Array (String × Json × String)) "guards")
  let mut removed := #[]
  let mut bytes := 0
  for (name,guard,_) in guards do
    unless guard.getObjValD "state" == toJson "finished" && guard.getObjValD "ownedPids" == toJson (#[] : Array Nat) do
      throw (IO.userError "live work cannot be removed")
    let tag := name.replace ".guard.json" ""
    let path := base/(tag++"-result")
    if ← path.pathExists then
      unless path.parent == some base && (← path.symlinkMetadata).type == .dir do
        throw (IO.userError "cleanup escaped its exact ended fixture")
      let count ← size path
      IO.FS.removeDirAll path
      bytes := bytes+count
      removed := removed.push (path.toString,count)
    for suffix in [".log",".guard-settings.json",".guard.json"] do
      let path := base/(tag++suffix)
      if ← path.pathExists then
        let count ← size path
        IO.FS.removeFile path
        bytes := bytes+count
        removed := removed.push (path.toString,count)
  -- The baseline diagnostic executable is no longer needed. Retain native
  -- build dependencies and the captured source needed for the next comparison.
  let executable := base/"replay-registration-baseline-build/StudyMain"
  if ← executable.pathExists then
    let count ← size executable
    IO.FS.removeFile executable
    bytes := bytes+count
    removed := removed.push (executable.toString,count)
  IO.FS.writeFile (output/"cleanup.json") (Json.mkObj [("removed",toJson removed),("apparentBytes",toJson bytes),
    ("archiveCreated",toJson false),("activeSourcesAndBuildDependenciesRetained",toJson true)]).pretty
  IO.println (Json.mkObj [("removedPaths",toJson removed.size),("apparentBytes",toJson bytes),
    ("archiveCreated",toJson false)]).compress
