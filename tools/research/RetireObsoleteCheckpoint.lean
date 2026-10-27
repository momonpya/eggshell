import Lean.Data.Json.Parser
import Lean.Data.Json.FromToJson
open Lean
private partial def remove (path : System.FilePath) : IO Nat := do
  let metadata ← path.symlinkMetadata
  if metadata.type == .dir then
    let mut bytes := 0
    for entry in ← path.readDir do bytes := bytes+(← remove entry.path)
    IO.FS.removeDir path
    return bytes
  else
    IO.FS.removeFile path
    return if metadata.type == .file then metadata.byteSize.toNat else 0

def main : IO Unit := do
  let base := System.FilePath.mk "/Users/ovm/.codex/experiments/eggshell"
  let root := base / "range-postings-20261027"
  let obsolete := base / "literal-support-20261026/required-replay/topic-1/work.egg"
  let seed := base / "study-services-20261026/common-seed-1/source.egg"
  let prepared := base / "packet-delivery-ledger-20261027/one-prepared-hook/work.egg"
  let output := root / "retired-obsolete-checkpoint.json"
  unless !(← output.pathExists) do throw (IO.userError "preserve prior deletion evidence")
  let head ← IO.FS.readBinFile (obsolete / "head")
  unless head == (← IO.FS.readBinFile (seed / "head")) && head == (← IO.FS.readBinFile (prepared / "head")) do
    throw (IO.userError "old checkpoint is not the retained identical publication")
  let pageName := "76352b67a9c35002bff67dc3d3c3a01b7bd194e43e09f5f54714dde75df5a8de.pages"
  unless (← (obsolete / pageName).metadata).byteSize.toNat ≤ 64*1024*1024 do
    throw (IO.userError "bounded equality check refuses unexpected source size")
  let bytes ← IO.FS.readBinFile (obsolete / pageName)
  unless bytes == (← IO.FS.readBinFile (seed / pageName)) && bytes == (← IO.FS.readBinFile (prepared / pageName)) do
    throw (IO.userError "old source bytes differ from either retained source")
  let settings ← IO.ofExcept (Json.parse (← IO.FS.readFile (root / "actual-range-hook-settings.json")))
  let command ← IO.ofExcept (settings.getObjValAs? (Array String) "command")
  unless command.back? == some prepared.parent.get!.toString do
    throw (IO.userError "current hook does not explicitly select the retained prepared checkpoint")
  let processes ← IO.Process.output {cmd := "/bin/ps",args := #["-axo","command="]}
  unless processes.exitCode == 0 && (processes.stdout.splitOn obsolete.toString).length == 1 do
    throw (IO.userError "old checkpoint is in use")
  let deleted ← remove obsolete
  IO.FS.writeFile output (Json.mkObj [("target",toJson obsolete.toString),("logicalBytes",toJson deleted),
    ("headAndAllSourceBytesIdenticalToBothRetainedCopies",toJson true),
    ("explicitPreparedCheckpointSelected",toJson true),
    ("privateReadCacheRetained",toJson true),("archiveCreated",toJson false)]).pretty
  IO.println s!"Deleted obsolete checkpoint and its derived cache ({deleted} logical bytes)"
