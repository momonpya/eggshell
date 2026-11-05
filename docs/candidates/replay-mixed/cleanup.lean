import Lean.Data.Json.FromToJson
import Lean.Data.Json.Parser
open Lean
def base : System.FilePath := "/Users/ovm/.codex/experiments/eggshell/scope-token-study-20261028/fixed-frame-study"
def output : System.FilePath := "/Users/ovm/.codex/worktrees/hook-deadline-baseline/eggshell/docs/candidates/replay-mixed"
def read (path : System.FilePath) : IO Json := do IO.ofExcept (Json.parse (← IO.FS.readFile path))
partial def erase (path : System.FilePath) : IO Nat := do
  let metadata ← path.symlinkMetadata
  if metadata.type == .dir then
    let mut bytes := 0
    for entry in ← path.readDir do bytes := bytes+(← erase entry.path)
    IO.FS.removeDir path
    return bytes
  unless metadata.type == .file || metadata.type == .symlink do throw (IO.userError "special file in ended fixture")
  IO.FS.removeFile path
  return metadata.byteSize.toNat
def main : IO Unit := do
  unless (← (output/"evidence.json").pathExists) && (← (output/"analysis.json").pathExists) &&
      !(← (output/"cleanup.json").pathExists) do throw (IO.userError "seal both evidence and analysis before cleanup")
  let mut controls := #[]
  let mut paths := #[]
  for entry in ← base.readDir do
    if !entry.fileName.startsWith "replay-mixed-" || !entry.fileName.endsWith ".guard.json" ||
        entry.fileName.contains "cleanup" then continue
    let guard ← read entry.path
    unless guard.getObjValD "state" == toJson "finished" && guard.getObjValD "ownedPids" == toJson (#[] : Array Nat) do
      throw (IO.userError "guard still owns work")
    let tag := entry.fileName.replace ".guard.json" ""
    let text ← IO.FS.readFile (base/(tag++".log"))
    let lines := text.splitOn "\n"
    controls := controls.push (entry.fileName,guard,String.intercalate "\n" (lines.drop (lines.length-16)))
    for suffix in [".guard.json",".guard-settings.json",".log"] do paths := paths.push (base/(tag++suffix))
  let rejected := base/"replay-mixed-retire1.log"
  if ← rejected.pathExists then
    controls := controls.push ("replay-mixed-retire1",Json.mkObj [("started",toJson false)],← IO.FS.readFile rejected)
    paths := paths.push rejected |>.push (base/"replay-mixed-retire1.guard-settings.json")
  IO.FS.writeFile (output/"control-guards.json") (toJson controls).pretty
  let root := base/"replay-mixed-native1-result"
  let mut removed := #[]
  unless root.parent == some base && (← root.symlinkMetadata).type == .dir do throw (IO.userError "unexpected cleanup root")
  removed := removed.push (root.toString,← erase root)
  for path in paths do
    if ← path.pathExists then removed := removed.push (path.toString,← erase path)
  IO.FS.writeFile (output/"cleanup.json") (Json.mkObj [("removed",toJson removed),
    ("apparentBytes",toJson (removed.foldl (fun n row => n+row.2) (0 : Nat))),
    ("activeOriginalsAndBuildDependenciesRetained",toJson true),("archiveCreated",toJson false)]).pretty
  IO.println (Json.mkObj [("removedPaths",toJson removed.size),
    ("apparentBytes",toJson (removed.foldl (fun n row => n+row.2) (0 : Nat))),("archiveCreated",toJson false)]).compress
