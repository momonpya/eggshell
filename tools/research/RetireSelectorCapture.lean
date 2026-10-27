import Lean.Data.Json.Parser
import Lean.Data.Json.FromToJson
open Lean
private def read (path : System.FilePath) : IO Json :=
  IO.FS.readFile path >>= fun text => IO.ofExcept (Json.parse text)
private partial def referenced (path : System.FilePath) (seen : IO.Ref (Std.HashSet String)) : IO Unit := do
  let actual ← IO.FS.realPath path
  if (← seen.get).contains actual.toString then return
  seen.modify (·.insert actual.toString)
  if (← actual.metadata).type == .dir then
    for entry in ← actual.readDir do referenced entry.path seen
private partial def remove (path : System.FilePath) : IO Nat := do
  let metadata ← path.symlinkMetadata
  if metadata.type == .dir then
    let mut bytes := 0
    for entry in ← path.readDir do bytes := bytes+(← remove entry.path)
    IO.FS.removeDir path
    return bytes
  IO.FS.removeFile path
  return if metadata.type == .file then metadata.byteSize.toNat else 0

def main : IO Unit := do
  let root := System.FilePath.mk "/Users/ovm/.codex/experiments/eggshell/selector-input-20261027"
  let output := System.FilePath.mk "/Users/ovm/.codex/worktrees/hook-deadline-baseline/eggshell/docs/candidates/selector-input"
  unless !(← (output / "retired-capture.json").pathExists) do throw (IO.userError "capture was already retired")
  unless (← read (output / "native/status.json")).getObjValD "sameActualInputSelectionSequence" == toJson true do
    throw (IO.userError "native evidence is missing")
  unless (← IO.FS.readBinFile (root / "selector-input.json")) == (← IO.FS.readBinFile (output / "capture/input.json")) do
    throw (IO.userError "recorded selector input differs")
  for entry in ← root.readDir do
    if entry.fileName.endsWith ".guard.json" then
      let guard ← read entry.path
      unless guard.getObjValD "state" == toJson "finished" &&
          guard.getObjValD "ownedPids" == toJson (#[] : Array Nat) do throw (IO.userError "a guard remains live")
  let process ← IO.Process.output {cmd := "/bin/ps",args := #["-axo","command="]}
  unless process.exitCode == 0 && (process.stdout.splitOn root.toString).length == 1 do
    throw (IO.userError "a selector process remains in use")
  let targets := [root / "capture-actual-selector-input",root / "controller-build",
    root / "replay-build",root / "product-build/StudyMain"]
  let seen ← IO.mkRef ({} : Std.HashSet String)
  referenced (root / "changed-build/lib") seen
  referenced (root / "product-build/lib") seen
  for line in (← IO.FS.readFile (root / "changed-build/runtime.rsp")).splitOn "\n" do
    if line.trimAscii.isEmpty then continue
    let path := System.FilePath.mk (← IO.ofExcept (Json.parse line >>= Json.getStr?))
    if path.isAbsolute then referenced path seen
  for name in ← seen.get do
    unless !(targets.any fun target => name == target.toString || name.startsWith (target.toString ++ "/")) do
      throw (IO.userError "ended capture still owns an active selector dependency")
  let receipts := root / "capture-actual-selector-input/data/receipts"
  for entry in ← receipts.readDir do
    let target := output / "capture/receipts" / entry.fileName
    IO.FS.createDirAll target
    for item in ← entry.path.readDir do
      unless (← item.path.symlinkMetadata).type == .file do throw (IO.userError "receipt is not a plain file")
      if item.fileName == "selection-plan.json" then
        let record ← read item.path
        let data ← IO.ofExcept ((record.getObjValD "data").getObj?)
        let extracted := record.setObjVal! "data" (Json.obj (data.erase "selectorInput"))
          |>.setObjVal! "selectorInputReference" (toJson "capture/input.json")
          |>.setObjVal! "extractedMetadataNotOriginalReceiptBytes" (toJson true)
        IO.FS.writeFile (target / "selection-plan-metadata.json") extracted.pretty
      else IO.FS.writeBinFile (target / item.fileName) (← IO.FS.readBinFile item.path)
  let mut removed : Array (String × Nat) := #[]
  for path in targets do removed := removed.push (path.toString,← remove path)
  IO.FS.writeFile (output / "retired-capture.json") (Json.mkObj [
    ("targets",toJson removed),("archiveCreated",toJson false),
    ("originalSeedAndOnePreparedDatabaseKept",toJson true),
    ("currentSelectorSourceObjectsInterfacesAndNativeComparisonKept",toJson true)]).pretty
