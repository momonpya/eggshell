import Lean.Data.Json.Parser
import Lean.Data.Json.FromToJson
open Lean

/-- Replay archived observation checkpoints with the already built native source
compiler. This verifies storage, not journal recovery, indexing or delivery. -/
def main (args : List String) : IO Unit := do
  let [planPath,checkpointPath,appPath,outputPath] := args |
    throw (IO.userError "PLAN CHECKPOINT-DIRECTORY NATIVE-REPLAY NEW-OUTPUT")
  let plan ← IO.ofExcept (Json.parse (← IO.FS.readFile planPath))
  let environment ← IO.ofExcept (plan.getObjValAs? (Array (String × Option String)) "environment")
  let directory := System.FilePath.mk outputPath
  unless directory.isAbsolute && !(← directory.pathExists) do
    throw (IO.userError "preserve previous storage batch")
  let checkpoints ← (System.FilePath.mk checkpointPath).readDir
  let checkpoints := checkpoints.qsort (fun a b => a.fileName < b.fileName)
  IO.FS.createDirAll directory
  let mut results := #[]
  for entry in checkpoints do
    unless entry.path.extension == some "json" &&
        (← entry.path.symlinkMetadata).type == .file do continue
    let original ← IO.FS.readBinFile entry.path
    let output := (directory / (entry.fileName.dropEnd 5).toString).toString
    let run ← IO.Process.output {
      cmd := appPath
      args := #[planPath,entry.path.toString,output]
      env := environment}
    IO.FS.writeFile (directory / (entry.fileName ++ ".stdout")) run.stdout
    IO.FS.writeFile (directory / (entry.fileName ++ ".stderr")) run.stderr
    unless original == (← IO.FS.readBinFile entry.path) do
      throw (IO.userError "a source checkpoint changed during replay")
    unless run.exitCode == 0 do throw (IO.userError s!"native replay failed: {entry.fileName}: {run.stderr}")
    let report ← IO.ofExcept (Json.parse (← IO.FS.readFile ((System.FilePath.mk output) / "result.json")))
    unless report.getObjValD "error" == .null &&
        (report.getObjValD "receipt").getObjValD "awaiting" == toJson (0 : Nat) do
      throw (IO.userError s!"source replay was not acknowledged: {entry.fileName}: {report.compress}")
    let records ← IO.ofExcept (Json.parse (← IO.FS.readFile ((System.FilePath.mk output) / "readback.json")))
    let rows ← IO.ofExcept (Json.parse (← IO.FS.readFile ((System.FilePath.mk output) / "staged-rows.json")))
    unless rows.getObjValD "oversized" == toJson (#[] : Array Json) do
      throw (IO.userError "a source row still exceeds its leaf budget")
    let row := Json.mkObj [("checkpoint",toJson entry.fileName),
      ("elapsedMs",report.getObjValD "elapsedMs"),("receipt",report.getObjValD "receipt"),
      ("originalReadback",records),("checkpointBytesUnchanged",toJson true),
      ("oversizedRows",toJson (0 : Nat)),("publishedHeadUnchanged",report.getObjValD "publishedHeadUnchanged")]
    results := results.push row
    IO.println (Json.mkObj [("completed",toJson results.size),("checkpoint",toJson entry.fileName),
      ("elapsedMs",report.getObjValD "elapsedMs")]).compress
  unless !results.isEmpty do throw (IO.userError "no real checkpoints to replay")
  IO.FS.writeFile (directory / "result.json") (Json.mkObj [
    ("checkpoints",toJson results),("allSourceAcknowledged",toJson true),
    ("allOriginalReadbacksExact",toJson true),("journalRecoveryTested",toJson false),
    ("indexReadinessTested",toJson false),("answeringModelCalls",toJson (0 : Nat))]).compress
