import Lean.Data.Json.Parser
import Lean.Data.Json.FromToJson
import Std.Data.HashSet
open Lean

private def read (path : System.FilePath) : IO Json :=
  IO.FS.readFile path >>= fun text => IO.ofExcept (Json.parse text)

/-- Retain dependency evidence for every object in the current candidate,
checked reference, default parent and negative audit fixture. Source stamps,
native objects and all interfaces remain untouched. -/
def main : IO Unit := do
  let root : System.FilePath := "/Users/ovm/.codex/experiments/eggshell/scope-token-study-20261028/shared-snapshot"
  let output : System.FilePath := "/Users/ovm/.codex/worktrees/hook-deadline-baseline/eggshell/docs/candidates/runtime-integration/retired-unused-dependencies.json"
  unless !(← output.pathExists) do throw (IO.userError "preserve prior dependency retirement")
  let processes ← IO.Process.output {cmd := "/bin/ps",args := #["-axo","command="]}
  unless processes.exitCode == 0 && (processes.stdout.splitOn "StudyBuildMain.lean").length == 1 do
    throw (IO.userError "wait for the native builder")
  let parents := #["maintenance-build","trace-cache-build","dependency-checked-runtime-build",
    "product-build","cached-usage-runtime-build"]
  let mut retained : Std.HashSet String := {}
  for name in parents do
    let parent := root / System.FilePath.mk name
    for line in (← IO.FS.readFile (parent / "runtime.rsp")).splitOn "\n" do
      if line.trimAscii.isEmpty then continue
      let path ← IO.ofExcept (Json.parse line >>= Json.getStr?)
      let evidence := (System.FilePath.mk path).withExtension "dependencies"
      retained := retained.insert evidence.normalize.toString
      if ← evidence.pathExists then retained := retained.insert (← IO.FS.realPath evidence).toString
    let settings := (← read (parent / "build.json")).getObjValD "settings"
    let main ← IO.ofExcept (settings.getObjValAs? String "mainModule")
    retained := retained.insert (parent / System.FilePath.mk (main.replace "." "_" ++ ".dependencies")).normalize.toString
  let mut targets : Array (String × Nat) := #[]
  for directory in ← root.readDir do
    if !directory.fileName.endsWith "-build" || (← directory.path.symlinkMetadata).type != .dir then continue
    if (processes.stdout.splitOn directory.path.toString).length != 1 then continue
    for entry in ← directory.path.readDir do
      if !entry.fileName.endsWith ".dependencies" || (← entry.path.symlinkMetadata).type != .file then continue
      if retained.contains entry.path.normalize.toString then continue
      unless (← (entry.path.withExtension "source").pathExists) do continue
      targets := targets.push (entry.path.toString,(← entry.path.symlinkMetadata).byteSize.toNat)
  IO.FS.createDirAll output.parent.get!
  IO.FS.writeFile output (Json.mkObj [("targets",toJson targets),
    ("logicalBytes",toJson (targets.foldl (fun total row => total+row.2) 0)),
    ("protectedLinkResponses",toJson parents),("protectedDependencyPaths",toJson retained.size),
    ("sourceStampsNativeObjectsAndInterfacesRetained",toJson true),
    ("databasesModelsAndRuntimesUntouched",toJson true),("archiveCreated",toJson false)]).pretty
  for (path,_) in targets do IO.FS.removeFile (.mk path)
  IO.println s!"Deleted {targets.size} unused dependency-cache copies; current native dependency evidence retained"
