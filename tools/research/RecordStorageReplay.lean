import Lean.Data.Json.Parser
import Lean.Data.Json.FromToJson
open Lean
def main (args : List String) : IO Unit := do
  let [label] := args | throw (IO.userError "baseline | payload")
  unless ["baseline","payload"].contains label do throw (IO.userError "known replay arm only")
  let active : System.FilePath := "/Users/ovm/.codex/experiments/eggshell/feedback-pilot-20261028"
  let target : System.FilePath := System.FilePath.mk
    ("/Users/ovm/.codex/worktrees/hook-deadline-baseline/eggshell/docs/candidates/storage-row/" ++ label)
  unless !(← target.pathExists) do throw (IO.userError "preserve captured replay")
  let raw ← IO.FS.readFile (active / ("row-replay-" ++ label ++ ".guard.json"))
  let guard ← IO.ofExcept (Json.parse raw)
  unless guard.getObjValD "state" == toJson "finished" &&
      guard.getObjValD "ownedPids" == toJson (#[] : Array Nat) do
    throw (IO.userError "preserve any live storage replay")
  IO.FS.createDirAll target
  IO.FS.writeFile (target / "guard.json") raw
  for name in ["input.json","staged-rows.json","result.json",
      "correspondence-validation.json","readback.json"] do
    if !(← (active / ("row-replay-" ++ label) / name).pathExists) then continue
    IO.FS.writeBinFile (target / name) (← IO.FS.readBinFile (active / ("row-replay-" ++ label) / name))
  for name in ["build.json","digest.json"] do
    IO.FS.writeBinFile (target / name) (← IO.FS.readBinFile (active / ("storage-" ++ label) / name))
  if label == "baseline" then
    let original := target / "core"
    IO.FS.createDirAll original
    for entry in ← (active / "storage-source-before").readDir do
      unless (← entry.path.symlinkMetadata).type == .file do throw (IO.userError "source files only")
      IO.FS.writeBinFile (original / entry.fileName) (← IO.FS.readBinFile entry.path)
  else
    let current : System.FilePath := "/Users/ovm/.codex/experiments/eggshell/verified-winner-20261027/checkout/Eggshell"
    let original := target / "core"
    IO.FS.createDirAll original
    let files := #["GraphStore.lean","ContentMetadata.lean","ObservedRecords.lean",
      "SynapseIndex.lean","MetadataBytes.lean"]
    for file in files do
      IO.FS.writeBinFile (original / file) (← IO.FS.readBinFile (current / file))
    let hashes ← IO.Process.output {
      cmd := (active / "controller/StudyMain").toString
      args := #["artifacts"] ++ files.map (fun (file : String) => (current / file).toString)}
    unless hashes.exitCode == 0 do throw (IO.userError hashes.stderr)
    IO.FS.writeFile (original / "digests.json") hashes.stdout
