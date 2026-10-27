import Lean.Data.Json.Parser
import Lean.Data.Json.FromToJson
open Lean

/-- These files cache transitive source stamps. Native linking and imported
interface provenance use .o/.source/.olean, which remain untouched. -/
def main : IO Unit := do
  let base := System.FilePath.mk "/Users/ovm/.codex/experiments/eggshell"
  let root := base / "shared-original-structure-20261027/product-build"
  let output := System.FilePath.mk "/Users/ovm/.codex/worktrees/hook-deadline-baseline/eggshell/docs/candidates/evidence-cause-contract/retired-preparation-cache.json"
  unless !(← output.pathExists) do throw (IO.userError "preserve existing retirement")
  let processes ← IO.Process.output {cmd := "/bin/ps",args := #["-axo","command="]}
  unless processes.exitCode == 0 && (processes.stdout.splitOn "StudyBuildMain.lean").length == 1 do
    throw (IO.userError "a native build may be using dependency caches")
  let response ← IO.FS.readFile (root / "runtime.rsp")
  let mut paths := #[]
  let mut bytes := 0
  for entry in ← root.readDir do
    if entry.fileName.endsWith ".dependencies" then
      unless (← entry.path.symlinkMetadata).type == .file &&
        (response.splitOn entry.path.toString).length == 1 do throw (IO.userError "cache target changed")
      let size := (← entry.path.symlinkMetadata).byteSize.toNat
      paths := paths.push (entry.path.toString,size)
      bytes := bytes + size
  IO.FS.createDirAll output.parent.get!
  IO.FS.writeFile output (Json.mkObj [("targets",toJson paths),("logicalBytes",toJson bytes),
    ("sourceObjectsInterfacesRuntimeAndDatabasesRetained",toJson true),("archiveCreated",toJson false)]).pretty
  for (path,_) in paths do IO.FS.removeFile path
  IO.println s!"Deleted {paths.size} recomputable stamp caches, {bytes} logical bytes"
