import Lean.Data.Json.Parser
import Lean.Data.Json.FromToJson
open Lean

private partial def bytes (path : System.FilePath) : IO Nat := do
  let metadata ← path.symlinkMetadata
  if metadata.type == .dir then
    let mut total := 0
    for entry in ← path.readDir do total := total+(← bytes entry.path)
    return total
  return if metadata.type == .file then metadata.byteSize.toNat else 0

private partial def remove (path : System.FilePath) : IO Unit := do
  if (← path.symlinkMetadata).type == .dir then
    for entry in ← path.readDir do remove entry.path
    IO.FS.removeDir path
  else IO.FS.removeFile path

private def present (path : System.FilePath) : IO Bool :=
  try let _ ← path.symlinkMetadata; pure true catch _ => pure false

/-- Explicitly scoped disposal, not an archive. Keep the original seed and
the topic-1 graph actively used for the next persisted-topology integration. -/
def main (args : List String) : IO Unit := do
  let [destination] := args | throw (IO.userError "RetireRequiredReplayTrials NEW-REPORT")
  let output := System.FilePath.mk destination
  unless output.isAbsolute && !(← output.pathExists) do throw (IO.userError "keep prior cleanup record")
  let base := System.FilePath.mk "/Users/ovm/.codex/experiments/eggshell"
  let parent := base / "literal-support-20261026"
  let candidate := base / "feedback-context-20261026"
  for root in [parent,candidate] do
    for entry in ← root.readDir do
      unless entry.fileName.endsWith ".guard.json" do continue
      let guardRecord ← IO.ofExcept (Json.parse (← IO.FS.readFile entry.path))
      unless (guardRecord.getObjValAs? String "state").toOption == some "finished" &&
          (guardRecord.getObjValAs? (Array Nat) "ownedPids").toOption == some #[] do
        throw (IO.userError "trial still has an unfinished guard")
  let processes ← IO.Process.output {cmd := "/bin/ps",args := #["-axo","pid=,command="]}
  unless processes.exitCode == 0 do throw (IO.userError "cannot inspect live trial processes")
  let responses ← #[candidate / "build/runtime.rsp",candidate / "routing-build/runtime.rsp"].mapM IO.FS.readFile
  let mut targets := #[parent / "required-replay/prefix",parent / "build/StudyMain"]
  for topic in [2,3] do
    targets := targets ++ #[parent / s!"required-replay/topic-{topic}/work.egg",
      parent / s!"required-replay/topic-{topic}/data"]
  for relative in ["native-fixture","fixture-build","fixture-core","contract/lib"] do
    targets := targets.push (candidate / relative)
  for entry in ← candidate.readDir do
    if entry.fileName.startsWith "probe-tools_research_" then targets := targets.push entry.path
  let mut records := #[]
  let mut total := 0
  let mut existing := #[]
  for target in targets do
    unless (processes.stdout.splitOn target.toString).length == 1 &&
        responses.all (fun response => (response.splitOn target.toString).length == 1) do
      throw (IO.userError "target still has an active process or link dependency")
    if !(← present target) then continue
    let count ← bytes target
    total := total+count
    existing := existing.push target
    records := records.push (Json.mkObj [("path",toJson target.toString),("logicalBytes",toJson count)])
  IO.FS.writeFile output (Json.mkObj [("targets",toJson records),("logicalBytes",toJson total),
    ("followsSymlinks",toJson false),("archiveCreated",toJson false),
    ("originalSeedRetained",toJson true),("activeTopicOneInputRetained",toJson true),
    ("candidateBuildDependenciesRetained",toJson true)]).pretty
  for target in existing do remove target
  for target in existing do
    if ← present target then throw (IO.userError "cleanup left a target behind")
  IO.FS.writeFile (.mk (destination ++ ".result.json")) (Json.mkObj [
    ("removed",toJson existing.size),("logicalBytes",toJson total),("archiveCreated",toJson false)]).pretty
  IO.println (Json.mkObj [("removed",toJson existing.size),("logicalBytes",toJson total)]).compress
