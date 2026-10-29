import Lean.Data.Json.Parser
import Lean.Data.Json.FromToJson
open Lean
private def read (path : System.FilePath) : IO Json :=
  IO.FS.readFile path >>= fun text => IO.ofExcept (Json.parse text)
private partial def walk (path library : System.FilePath) (active : Std.HashSet String)
    (targets : Array System.FilePath) (pruned : IO.Ref (Array (String × String))) : IO Unit := do
  for entry in ← path.readDir do
    let metadata ← entry.path.symlinkMetadata
    if metadata.type == .dir then walk entry.path library active targets pruned
    else if metadata.type == .symlink then
      let actual ← IO.FS.realPath entry.path
      if !targets.any (fun target => actual == target || actual.toString.startsWith (target.toString ++ "/")) then continue
      let some relative := entry.path.toString.dropPrefix? (library.toString ++ "/") |
        throw (IO.userError "interface is outside selected library")
      let relative := relative.toString
      unless [".olean",".ilean",".olean.server",".olean.private"].any (fun suffix => relative.endsWith suffix) do
        throw (IO.userError "unknown inherited interface kind")
      let name := (relative.splitOn ".").head! |>.replace "/" "."
      if active.contains name then throw (IO.userError s!"active module still needs {name}")
      pruned.modify (·.push (entry.path.toString,actual.toString))
      IO.FS.removeFile entry.path
def main : IO Unit := do
  let root : System.FilePath := "/Users/ovm/.codex/experiments/eggshell/scope-token-study-20261028/shared-snapshot"
  let targets := #[root / "capture-build",root / "correspondence-build"]
  let pruned ← IO.mkRef #[]
  for label in ["product-build","hook-build"] do
    let build := root / label
    let settings ← read (build / "build.json")
    let name ← IO.ofExcept ((settings.getObjValD "settings").getObjValAs? String "mainModule")
    let closure : Array (String × String) ← IO.ofExcept (fromJson? (← read (build / (name.replace "." "_" ++ ".dependencies"))))
    let active := Std.HashSet.ofArray (closure.map Prod.fst)
    let response ← IO.FS.readFile (build / "runtime.rsp")
    unless targets.all (fun target => (response.splitOn target.toString).length == 1) do
      throw (IO.userError "active native object depends on old capture build")
    walk (build / "lib") (build / "lib") active targets pruned
  let output : System.FilePath := "/Users/ovm/.codex/worktrees/hook-deadline-baseline/eggshell/docs/candidates/anchored-capture/pruned-unused-interfaces.json"
  unless !(← output.pathExists) do throw (IO.userError "keep interface retirement evidence")
  let removed ← pruned.get
  IO.FS.writeFile output (Json.mkObj [("interfaces",toJson removed),("mainDependencyClosuresChecked",toJson true),
    ("nativeObjectDependenciesChecked",toJson true)]).pretty
  IO.println s!"Removed {removed.size} unused inherited interfaces"
