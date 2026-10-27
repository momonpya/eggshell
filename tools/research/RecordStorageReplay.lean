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
  for name in ["input.json","staged-rows.json","result.json"] do
    IO.FS.writeBinFile (target / name) (← IO.FS.readBinFile (active / ("row-replay-" ++ label) / name))
  for name in ["build.json","digest.json"] do
    IO.FS.writeBinFile (target / name) (← IO.FS.readBinFile (active / ("storage-" ++ label) / name))
  if label == "baseline" then
    let original := target / "core"
    IO.FS.createDirAll original
    for entry in ← (active / "storage-source-before").readDir do
      unless (← entry.path.symlinkMetadata).type == .file do throw (IO.userError "source files only")
      IO.FS.writeBinFile (original / entry.fileName) (← IO.FS.readBinFile entry.path)
