import Lean.Data.Json.Parser
import Lean.Data.Json.FromToJson
open Lean

private partial def protect (path : System.FilePath) (targets : Array System.FilePath) : IO Unit := do
  for entry in ← path.readDir do
    let kind := (← entry.path.symlinkMetadata).type
    if kind == .dir then protect entry.path targets
    else if kind == .symlink then
      let actual ← IO.FS.realPath entry.path
      unless !(targets.any fun target => actual == target || actual.toString.startsWith (target.toString ++ "/")) do
        throw (IO.userError "active interface or source refers to a retirement target")

private partial def retire (path : System.FilePath) : IO Nat := do
  let metadata ← path.symlinkMetadata
  if metadata.type == .dir then
    let mut bytes := 0
    for entry in ← path.readDir do bytes := bytes+(← retire entry.path)
    IO.FS.removeDir path
    return bytes
  else
    IO.FS.removeFile path
    return if metadata.type == .file then metadata.byteSize.toNat else 0

/-- Keep actual .o/.source/interfaces and the unfinished hook build. Drop
ended helper builds and parent transitive-stamp copies only. -/
def main : IO Unit := do
  let base := System.FilePath.mk "/Users/ovm/.codex/experiments/eggshell"
  let parent := base / "filtered-postings-20261027"
  let root := base / "range-postings-20261027"
  let output := root / "retired-build-cache.json"
  unless !(← output.pathExists) do throw (IO.userError "preserve retirement record")
  let processes ← IO.Process.output {cmd := "/bin/ps",args := #["-axo","command="]}
  unless processes.exitCode == 0 && (processes.stdout.splitOn "StudyBuildMain.lean").length == 1 do
    throw (IO.userError "native build remains live")
  let directories := #[parent / "hook-build",parent / "audit-build"]
  let mut targets := directories
  for build in [parent / "product-build",root / "product-build"] do
    for entry in ← build.readDir do
      if entry.fileName.endsWith ".dependencies" && (← entry.path.symlinkMetadata).type == .file then
        targets := targets.push entry.path
  for path in targets do
    unless (processes.stdout.splitOn path.toString).length == 1 do throw (IO.userError "retirement target is process-referenced")
  for keep in [base / "shared-original-structure-20261027",parent,root] do
    protect (keep / "checkout") targets
    protect (keep / "product-build/lib") targets
    let response ← IO.FS.readFile (keep / "product-build/runtime.rsp")
    for target in targets do
      unless (response.splitOn target.toString).length == 1 do throw (IO.userError "native linker still uses target")
  let mut deleted := #[]
  for path in targets do deleted := deleted.push (path.toString,← retire path)
  IO.FS.writeFile output (Json.mkObj [("deleted",toJson deleted),
    ("logicalBytes",toJson (deleted.foldl (fun sum entry => sum+entry.2) 0)),
    ("activeSourceObjectsInterfacesAndDatabasesRetained",toJson true),("archiveCreated",toJson false)]).pretty
  IO.println s!"Deleted {targets.size} ended helper/cache targets"
