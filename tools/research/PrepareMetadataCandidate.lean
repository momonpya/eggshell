import Lean.Data.Json.Parser
import Lean.Data.Json.FromToJson
open Lean
def main (args : List String) : IO Unit := do
  let [mode] := args | throw (IO.userError "backup | restore")
  let active : System.FilePath := "/Users/ovm/.codex/experiments/eggshell/verified-winner-20261027/checkout/Eggshell"
  let saved : System.FilePath := "/Users/ovm/.codex/experiments/eggshell/feedback-pilot-20261028/storage-source-before"
  let files := #["GraphStore.lean","ContentMetadata.lean","ObservedRecords.lean","SynapseIndex.lean"]
  if mode == "backup" then
    unless !(← saved.pathExists) do throw (IO.userError "preserve original core sources")
    IO.FS.createDirAll saved
    for file in files do IO.FS.writeBinFile (saved / file) (← IO.FS.readBinFile (active / file))
    let hashes ← IO.Process.output {
      cmd := "/Users/ovm/.codex/experiments/eggshell/feedback-pilot-20261028/controller/StudyMain"
      args := #["artifacts"] ++ files.map (fun (file : String) => (active / file).toString)}
    unless hashes.exitCode == 0 do throw (IO.userError hashes.stderr)
    IO.FS.writeFile (saved / "digests.json") hashes.stdout
  else if mode == "restore" then
    for file in files do IO.FS.writeBinFile (active / file) (← IO.FS.readBinFile (saved / file))
    let added := active / "MetadataBytes.lean"
    if ← added.pathExists then IO.FS.removeFile added
  else throw (IO.userError "known preparation mode required")
