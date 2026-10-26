import Lean.Data.Json.Parser
import Lean.Data.Json.FromToJson
open Lean

private partial def bytes (path : System.FilePath) : IO Nat := do
  let metadata ← path.symlinkMetadata
  if metadata.type == .dir then
    let mut total := 0
    for entry in ← path.readDir do total := total + (← bytes entry.path)
    return total
  return if metadata.type == .file then metadata.byteSize.toNat else 0

private partial def remove (path : System.FilePath) : IO Unit := do
  if (← path.symlinkMetadata).type == .dir then
    for entry in ← path.readDir do remove entry.path
    IO.FS.removeDir path
  else IO.FS.removeFile path

/-- Retire only superseded topology images and completed synthetic fixtures.
The original seed, actual graph input and verified integration images stay. -/
def main (args : List String) : IO Unit := do
  let [destination] := args | throw (IO.userError "RetireRoutingStoreTrials NEW-REPORT")
  let output := System.FilePath.mk destination
  unless output.isAbsolute && !(← output.pathExists) do
    throw (IO.userError "absolute unused cleanup report required")
  let root := System.FilePath.mk
    "/Users/ovm/.codex/experiments/eggshell/synaptic-routing-store-20261026"
  for label in ["build","build-bounded","build-causes","build-order",
      "run","run-causes","run-order"] do
    let record ← IO.ofExcept (Json.parse (← IO.FS.readFile (root / (label ++ ".guard.json"))))
    unless (record.getObjValAs? String "state").toOption == some "finished" &&
        (record.getObjValAs? (Array Nat) "ownedPids").toOption == some #[] &&
        (record.getObjValAs? Nat "exitCode").toOption == some 0 do
      throw (IO.userError "trial guard is not successfully finished")
  for relative in ["with-order/shared-view","with-order/usage-view",
      "build/StudyMain","checkout/Eggshell/SynapticRoutingStore.lean"] do
    unless ← (root / relative).pathExists do throw (IO.userError "active integration input missing")
  let processes ← IO.Process.output {cmd := "/bin/ps",args := #["-axo","pid=,command="]}
  unless processes.exitCode == 0 do throw (IO.userError "cannot inspect trial processes")
  let response ← IO.FS.readFile (root / "build/runtime.rsp")
  let mut records := #[]
  let mut total := 0
  let targets := ["shared-view","usage-view","unsealed-view","with-causes",
    "with-order/unsealed-view","with-order/fixture-usage-index","with-order/fixture-usage-view"]
  for relative in targets do
    let path := root / relative
    unless (processes.stdout.splitOn path.toString).length == 1 &&
        (response.splitOn path.toString).length == 1 do
      throw (IO.userError "trial image still has an active process or link dependency")
    unless (← path.symlinkMetadata).type == .dir do
      throw (IO.userError "expected an existing trial directory")
    let size ← bytes path
    total := total + size
    records := records.push (Json.mkObj [("path",toJson path.toString),("logicalBytes",toJson size)])
  IO.FS.writeFile output (Json.mkObj [("targets",toJson records),("logicalBytes",toJson total),
    ("archiveCreated",toJson false),("followsSymlinks",toJson false),
    ("verifiedIntegrationImagesRetained",toJson true),("originalSeedRetained",toJson true)]).pretty
  for relative in targets do remove (root / relative)
  for relative in targets do
    if ← (root / relative).pathExists then throw (IO.userError "trial image survived cleanup")
  let result := Json.mkObj [("removed",toJson targets.length),("logicalBytes",toJson total),
    ("archiveCreated",toJson false)]
  IO.FS.writeFile (.mk (destination ++ ".result.json")) result.pretty
  IO.println result.compress
