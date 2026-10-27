import Lean.Data.Json.Parser
import Lean.Data.Json.FromToJson
open Lean
private def read (path : System.FilePath) : IO Json :=
  IO.FS.readFile path >>= fun text => IO.ofExcept (Json.parse text)
private partial def copyTree (source target : System.FilePath) : IO Unit := do
  match (← source.symlinkMetadata).type with
  | .dir =>
      IO.FS.createDirAll target
      for entry in ← source.readDir do copyTree entry.path (target / entry.fileName)
  | .file => IO.FS.writeBinFile target (← IO.FS.readBinFile source)
  | _ => throw (IO.userError "receipt capture must contain plain records only")
private partial def remove (path : System.FilePath) : IO Nat := do
  let metadata ← path.symlinkMetadata
  if metadata.type == .dir then
    let mut total := 0
    for entry in ← path.readDir do total := total+(← remove entry.path)
    IO.FS.removeDir path
    return total
  IO.FS.removeFile path
  return if metadata.type == .file then metadata.byteSize.toNat else 0

def main : IO Unit := do
  let root := System.FilePath.mk "/Users/ovm/.codex/experiments/eggshell/range-postings-20261027"
  let output := System.FilePath.mk "/Users/ovm/.codex/worktrees/hook-deadline-baseline/eggshell/docs/candidates/range-postings"
  unless !(← (output / "retired-trials.json").pathExists) do throw (IO.userError "already retired")
  for entry in ← root.readDir do
    if entry.fileName.endsWith ".guard.json" then
      let guard ← read entry.path
      unless guard.getObjValD "state" == toJson "finished" &&
          guard.getObjValD "ownedPids" == toJson (#[] : Array Nat) do
        throw (IO.userError "a guarded operation is still live")
  let processes ← IO.Process.output {cmd := "/bin/ps",args := #["-axo","command="]}
  unless processes.exitCode == 0 && (processes.stdout.splitOn root.toString).length == 1 do
    throw (IO.userError "a range trial or build remains in use")
  for (label,record) in [("actual-range-native-hook","final"),("profile-range-hook","profile")] do
    unless (← IO.FS.readBinFile (root / label / "body.txt")) ==
        (← IO.FS.readBinFile (output / "final/hook/body.txt")) do
      throw (IO.userError "captured body differs from ended trial")
    let target := output / record / "full-receipts"
    unless !(← target.pathExists) do throw (IO.userError "preserve copied receipts")
    copyTree (root / label / "data/receipts") target
    if record == "profile" then
      for file in ["audit.json","changed-views.json","shutdown.json","publisher-shutdown.json"] do
        IO.FS.writeBinFile (output / record / file) (← IO.FS.readBinFile (root / label / file))
  let mut deleted : Array (String × Nat) := #[]
  for name in ["actual-range-native-hook","profile-range-hook","actual-range-interface-hook",
      "hook-build","driver-interfaces"] do
    let path := root / name
    if ← path.pathExists then deleted := deleted.push (path.toString,← remove path)
  IO.FS.writeFile (output / "retired-trials.json") (Json.mkObj [
    ("targets",toJson deleted),("archiveCreated",toJson false),("fullReceiptsCaptured",toJson true),
    ("currentProductAndPreparedDatabaseKept",toJson true)]).pretty
