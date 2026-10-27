import Lean.Data.Json.Parser
import Lean.Data.Json.FromToJson
open Lean

private partial def reachable (path : System.FilePath) (seen : IO.Ref (Std.HashSet String)) : IO Unit := do
  if !(← path.pathExists) then return
  let path ← IO.FS.realPath path
  if (← seen.get).contains path.toString then return
  seen.modify (·.insert path.toString)
  if (← path.metadata).type == .dir then
    for entry in ← path.readDir do reachable entry.path seen

private partial def files (path : System.FilePath) : IO (Array System.FilePath) := do
  let mut out := #[]
  for entry in ← path.readDir do
    let metadata ← entry.path.symlinkMetadata
    if metadata.type == .dir then out := out ++ (← files entry.path)
    else if metadata.type == .file then out := out.push entry.path
  return out

private def stem (path : String) : String :=
  let path := (path.splitOn ".olean").head!
  let path := (path.splitOn ".ilean").head!
  if path.endsWith ".o" then path.dropEnd 2 |>.copy else
  if path.endsWith ".source" then path.dropEnd 7 |>.copy else
  if path.endsWith ".dependencies" then path.dropEnd 13 |>.copy else path

/-- Retire only generated files unreachable from the two retained runtime
link responses and current source/interface trees. No source or DB is a
target; an old directory is not assumed dead merely because of its date. -/
def main : IO Unit := do
  let base := System.FilePath.mk "/Users/ovm/.codex/experiments/eggshell"
  let project := System.FilePath.mk "/Users/ovm/.codex/worktrees/hook-deadline-baseline/eggshell"
  let output := project / "docs/candidates/evidence-cause-contract/retired-unreachable-builds.json"
  unless !(← output.pathExists) do throw (IO.userError "preserve retirement evidence")
  let processes ← IO.Process.output {cmd := "/bin/ps",args := #["-axo","command="]}
  unless processes.exitCode == 0 && (processes.stdout.splitOn "StudyBuildMain.lean").length == 1 do
    throw (IO.userError "wait for the native build")
  let reachablePaths ← IO.mkRef ({} : Std.HashSet String)
  let keep := #[base / "shared-original-structure-20261027",base / "evidence-cause-contract-20261027"]
  for root in keep do
    reachable (root / "checkout") reachablePaths
    reachable (root / "product-build/lib") reachablePaths
    for line in (← IO.FS.readFile (root / "product-build/runtime.rsp")).splitOn "\n" do
      if line.trimAscii.isEmpty then continue
      let path ← IO.ofExcept (Json.parse line >>= Json.getStr?)
      reachable (.mk path) reachablePaths
  reachable (project / ".lake/build/lib") reachablePaths
  reachable (.mk "/Users/ovm/Code/eggshell/.lake/build/lib") reachablePaths
  let retainedPaths ← reachablePaths.get
  let protectedStems := retainedPaths.toArray.foldl (fun seen path => seen.insert (stem path))
    ({} : Std.HashSet String)
  let targets := (← files base).filter fun path =>
    let name := path.toString
    let generated := [".o",".source",".dependencies",".olean",".olean.private",".olean.server",".ilean"].any
      (fun suffix : String => name.endsWith suffix)
    generated && !name.startsWith ((base / "numerical-owned-20261024").toString ++ "/") &&
      !(keep.any fun root => name.startsWith (root.toString ++ "/")) &&
      !retainedPaths.contains name && !protectedStems.contains (stem name)
  let mut evidence := #[]
  let mut bytes := 0
  for path in targets do
    unless (processes.stdout.splitOn path.toString).length == 1 do
      throw (IO.userError "generated artifact is still process-referenced")
    let size := (← path.symlinkMetadata).byteSize.toNat
    evidence := evidence.push (path.toString,size)
    bytes := bytes+size
  IO.FS.writeFile output (Json.mkObj [("targets",toJson evidence),("logicalBytes",toJson bytes),
    ("protectedResolvedPaths",toJson retainedPaths.size),("sourceAndInterfaceReachabilityChecked",toJson true),
    ("bothNativeLinkResponsesChecked",toJson true),("sourceDatabasesAndNumericalAssetsRetained",toJson true),
    ("archiveCreated",toJson false)]).pretty
  for path in targets do IO.FS.removeFile path
  IO.println s!"Deleted {targets.size} unreachable generated artifacts, {bytes} logical bytes"
