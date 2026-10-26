import Lean.Data.Json.FromToJson
open Lean

private partial def freeze (directory : System.FilePath) : IO (Array String) := do
  let mut paths := #[]
  for entry in ← directory.readDir do
    if [".lake",".git"].contains entry.fileName then continue
    let metadata ← entry.path.symlinkMetadata
    if metadata.type == .dir then paths := paths ++ (← freeze entry.path)
    else if metadata.type == .symlink && entry.fileName.endsWith ".lean" then
      let bytes ← IO.FS.readBinFile entry.path
      IO.FS.removeFile entry.path
      IO.FS.writeBinFile entry.path bytes
      unless (← IO.FS.readBinFile entry.path) == bytes do throw (IO.userError "source isolation changed bytes")
      paths := paths.push entry.path.toString
  return paths

def main : IO Unit := do
  let root := System.FilePath.mk "/Users/ovm/.codex/experiments/eggshell/captured-correspondence-20261026"
  let output := root / "materialized-sources.json"
  unless !(← output.pathExists) do throw (IO.userError "keep earlier isolation record")
  let paths ← freeze (root / "checkout")
  IO.FS.writeFile output (Json.mkObj [("paths",toJson paths),("contentUnchanged",toJson true),
    ("parentSourcesUntouched",toJson true)]).pretty
  IO.println s!"Materialized {paths.size} inherited Lean source files"
