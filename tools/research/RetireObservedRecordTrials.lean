import Eggshell.Paths
import Lean.Data.Json.Parser
import Lean.Data.Json.FromToJson
open Lean Eggshell

private def base := System.FilePath.mk "/Users/ovm/.codex/experiments/eggshell"

private partial def size (path : System.FilePath) : IO Nat := do
  let info ← path.symlinkMetadata
  if info.type == .dir then
    let mut total := 0
    for entry in ← path.readDir do total := total+(← size entry.path)
    return total
  return if info.type == .file then info.byteSize.toNat else 0

private partial def remove (path : System.FilePath) : IO Unit := do
  if (← path.symlinkMetadata).type == .dir then
    for entry in ← path.readDir do remove entry.path
    IO.FS.removeDir path
  else IO.FS.removeFile path

private def pathPresent (path : System.FilePath) : IO Bool :=
  try let _ ← path.symlinkMetadata; pure true catch _ => pure false

def main (args : List String) : IO Unit := do
  let [destination] := args | throw (IO.userError "RetireObservedRecordTrials UNUSED-REPORT")
  let report := System.FilePath.mk destination
  unless report.isAbsolute && !(← report.pathExists) do throw (IO.userError "keep previous retirement evidence")
  let parent := base / "record-publication-20261026"
  let candidate := base / "literal-support-20261026"
  for root in [parent,candidate] do
    for entry in ← root.readDir do
      if !entry.fileName.endsWith ".guard.json" then continue
      let record ← IO.ofExcept (Json.parse (← IO.FS.readFile entry.path))
      unless (record.getObjValAs? String "state").toOption == some "finished" &&
          (record.getObjValAs? (Array Nat) "ownedPids").toOption == some #[] do
        throw (IO.userError "trial guard has not terminated cleanly")
  let mut targets : Array System.FilePath := #[]
  for relative in ["checks","copy-private","prefix","product","lifecycle","paired","final-pair",
      "native-build","literal-native-build","final-native-build","fixture-core","contract/lib",
      "probe-tools_research_ObservedRecordPublicationChecks",
      "probe-tools_research_ObservedRecordRuntimeAudit","probe-tools_research_NativePublicationNativeMain"] do
    targets := targets.push (parent / relative)
  for relative in ["paired","bounded","native-build","bounded-native-build","fixture-core",
      "replay","replay-build","checks","contract/lib","probe-tools_research_ObservedRecordPublicationChecks"] do
    targets := targets.push (candidate / relative)
  -- The first fixture used the default data root. Retire only identities whose
  -- every registered owner belongs to that exact disposable fixture directory.
  for name in ["source.egg","delayed.egg","absent.egg"] do
    let head ← IO.ofExcept (Json.parse (← IO.FS.readFile (parent / "checks" / name / "head")))
    let identity ← IO.ofExcept (head.getObjValAs? String "identity")
    let cache := (← Paths.dataRoot) / "read-cache" / identity
    if !(← pathPresent cache) then continue
    unless (← cache.symlinkMetadata).type == .dir do throw (IO.userError "refuse a linked private cache")
    let owners := cache / "owners"
    unless ← owners.pathExists do throw (IO.userError "fixture cache has no ownership evidence")
    let entries ← owners.readDir
    unless !entries.isEmpty do throw (IO.userError "fixture cache has no registered owner")
    for entry in entries do
      let owner ← IO.ofExcept (Json.parse (← IO.FS.readFile entry.path))
      let directory ← IO.ofExcept (owner.getObjValAs? String "directory")
      unless (System.FilePath.mk directory).normalize.toString.startsWith ((parent / "checks").toString ++ "/") &&
          (owner.getObjValAs? String "database").toOption == some identity do
        throw (IO.userError "private cache belongs to another source")
    targets := targets.push cache
  let processes ← IO.Process.output {cmd := "/bin/ps",args := #["-axo","pid=,command="]}
  unless processes.exitCode == 0 do throw (IO.userError "cannot check active trial processes")
  let response ← IO.FS.readFile (candidate / "build/runtime.rsp")
  let mut records := #[]
  let mut present := #[]
  let mut total := 0
  for target in targets do
    unless (processes.stdout.splitOn target.toString).length == 1 &&
        (response.splitOn target.toString).length == 1 do
      throw (IO.userError "trial still has a live process or active link dependency")
    if !(← pathPresent target) then continue
    let bytes ← size target
    present := present.push target
    records := records.push (Json.mkObj [("path",toJson target.toString),("logicalBytes",toJson bytes)])
    total := total+bytes
  IO.FS.writeFile report (Json.mkObj [("targets",toJson records),("logicalBytes",toJson total),
    ("followsSymlinks",toJson false),("archiveCreated",toJson false),
    ("currentSeedRetained",toJson true),("candidateBuildDependenciesRetained",toJson true)]).pretty
  for target in present do remove target
  for target in present do
    if ← pathPresent target then throw (IO.userError "trial retirement left an artifact")
  IO.FS.writeFile (report.toString ++ ".result.json") (Json.mkObj [
    ("removed",toJson present.size),("logicalBytes",toJson total),("archiveCreated",toJson false)]).pretty
