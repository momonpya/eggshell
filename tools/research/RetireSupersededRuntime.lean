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
    let kind := (← entry.path.symlinkMetadata).type
    if kind == .dir then out := out ++ (← files entry.path)
    else if kind == .file then out := out.push entry.path
  return out
private def stem (path : String) : String :=
  let path := (path.splitOn ".olean").head!
  let path := (path.splitOn ".ilean").head!
  if path.endsWith ".o" then path.dropEnd 2 |>.copy else
  if path.endsWith ".source" then path.dropEnd 7 |>.copy else
  if path.endsWith ".dependencies" then path.dropEnd 13 |>.copy else
  if path.endsWith ".ir" then path.dropEnd 3 |>.copy else path

/-- The new active runtime has passed the exact-candidate proof and native
checks. Retire older generated files only when no active native/import/source
dependency reaches them. Old .lean sources and captured evidence remain. -/
def main : IO Unit := do
  let base := System.FilePath.mk "/Users/ovm/.codex/experiments/eggshell"
  let root := base / "range-postings-20261027"
  let output := root / "retired-superseded-runtime.json"
  unless !(← output.pathExists) do throw (IO.userError "preserve retirement evidence")
  let checks ← IO.ofExcept (Json.parse (← IO.FS.readFile (root / "checked-ranges/result.json")))
  unless checks.getObjValD "allPassed" == toJson true do throw (IO.userError "active runtime is not checked")
  let processes ← IO.Process.output {cmd := "/bin/ps",args := #["-axo","command="]}
  unless processes.exitCode == 0 && (processes.stdout.splitOn "StudyBuildMain.lean").length == 1 do
    throw (IO.userError "a build remains live")
  let seen ← IO.mkRef ({} : Std.HashSet String)
  reachable (root / "checkout") seen
  reachable (root / "product-build/lib") seen
  reachable (.mk "/Users/ovm/.codex/worktrees/hook-deadline-baseline/eggshell/.lake/build/lib") seen
  reachable (.mk "/Users/ovm/Code/eggshell/.lake/build/lib") seen
  for line in (← IO.FS.readFile (root / "product-build/runtime.rsp")).splitOn "\n" do
    if line.trimAscii.isEmpty then continue
    reachable (.mk (← IO.ofExcept (Json.parse line >>= Json.getStr?))) seen
  let retained ← seen.get
  let retainedStems := retained.toArray.foldl (fun set path => set.insert (stem path)) ({} : Std.HashSet String)
  let candidates := (← files base).filter fun path =>
    let name := path.toString
    let generated := [".o",".source",".dependencies",".olean",".olean.private",".olean.server",".ilean",".ir"].any
      (fun suffix : String => name.endsWith suffix)
    let executable := ["StudyMain","Probe","product"].contains (path.fileName.getD "")
    !name.startsWith (root.toString ++ "/") &&
      !name.startsWith ((base / "numerical-owned-20261024").toString ++ "/") &&
      (generated || executable) && !retained.contains name && !retainedStems.contains (stem name)
  let mut deleted := #[]
  for path in candidates do
    unless (processes.stdout.splitOn path.toString).length == 1 do throw (IO.userError "old artifact is process-referenced")
    deleted := deleted.push (path.toString,(← path.symlinkMetadata).byteSize.toNat)
  IO.FS.writeFile output (Json.mkObj [("targets",toJson deleted),
    ("logicalBytes",toJson (deleted.foldl (fun sum entry => sum+entry.2) 0)),
    ("currentNativeAndSourceInterfaceDependenciesPreserved",toJson true),
    ("oldLeanSourcesAndRecordedComparisonsPreserved",toJson true),("archiveCreated",toJson false)]).pretty
  for path in candidates do IO.FS.removeFile path
  IO.println s!"Deleted {candidates.size} superseded generated files/executables"
