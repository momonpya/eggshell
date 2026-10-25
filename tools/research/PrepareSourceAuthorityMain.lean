import Lean.Data.Json.Parser
import Lean.Data.Json.FromToJson
import Std.Data.HashMap
open Lean

private def readJson (path : System.FilePath) : IO Json := do
  IO.ofExcept (Json.parse (← IO.FS.readFile path))

private def command (args : Array String) : IO Unit := do
  let result ← IO.Process.output {cmd := "/bin/cp",args}
  unless result.exitCode == 0 do throw (IO.userError "source-authority candidate clone failed")

def main (args : List String) : IO Unit := do
  let project := System.FilePath.mk "/Users/ovm/.codex/worktrees/hook-deadline-baseline/eggshell"
  let parent := System.FilePath.mk "/Users/ovm/.codex/experiments/eggshell/publication-service-20261026"
  let root := System.FilePath.mk "/Users/ovm/.codex/experiments/eggshell/source-authority-20261026"
  if args.isEmpty then
    unless !(← root.pathExists) do throw (IO.userError "keep existing source-authority candidate")
    IO.FS.createDir root
    command #["-cR",(parent / "checkout").toString,(root / "checkout").toString]
    for relative in #["Eggshell/SynapseProvenance.lean","Eggshell/SynapseJournal.lean","Eggshell/Warm.lean"] do
      let target := root / "checkout" / relative
      if ← target.pathExists then
        if (← target.symlinkMetadata).type == .symlink then IO.FS.removeFile target
      IO.FS.writeFile target (← IO.FS.readFile (project / "tools/research/source-authority" / relative))
    let library := root / "checkout/.lake/build/lib/lean"
    if (← library.symlinkMetadata).type == .symlink then IO.FS.removeFile library
    else IO.FS.removeDirAll library
    let linked ← IO.Process.output {cmd := "/bin/ln",args := #["-s",(parent / "build/lib").toString,library.toString]}
    unless linked.exitCode == 0 do throw (IO.userError "could not bind the parent interfaces")
  else unless args == ["relink"] && (← root.pathExists) do
    throw (IO.userError "PrepareSourceAuthorityMain [relink]")
  let plan ← readJson (parent / "build-plan.json")
  let mut names : Std.HashMap String String := {}
  let objectModules ← IO.ofExcept (plan.getObjValAs? String "objectModules")
  let objectJson ← readJson (.mk objectModules)
  let map ← IO.ofExcept objectJson.getObj?
  for (path,name) in map.toArray do names := names.insert path (← IO.ofExcept name.getStr?)
  for prior in ← IO.ofExcept (plan.getObjValAs? (Array String) "parents") do
    let path := System.FilePath.mk prior / "modules.json"
    if !(← path.pathExists) then continue
    for value in ← IO.ofExcept ((← readJson path).getArr?) do
      let name ← IO.ofExcept value.getStr?
      names := names.insert (prior ++ "/" ++ name.replace "." "_" ++ ".o") name
  let mut parentObjects : Std.HashMap String String := {}
  for item in ← (parent / "build").readDir do
    if item.fileName == "Main.o" then parentObjects := parentObjects.insert "Main" item.path.toString
    else if item.fileName.startsWith "Eggshell_" && item.fileName.endsWith ".o" then
      let stem := String.ofList (item.fileName.toList.take (item.fileName.length-2))
      let name := stem.replace "_" "."
      let source := parent / "checkout" / (name.replace "." "/" ++ ".lean")
      unless (← IO.FS.readFile source) == (← IO.FS.readFile (parent / "build" / (stem ++ ".source"))) do
        throw (IO.userError "parent object no longer matches its reviewed source")
      parentObjects := parentObjects.insert name item.path.toString
  let mut used : Std.HashSet String := {}
  let mut response := #[]
  let baselineResponse ← IO.ofExcept (plan.getObjValAs? String "baselineResponse")
  let baselineMain ← IO.ofExcept (plan.getObjValAs? String "baselineMain")
  for line in (← IO.FS.readFile (.mk baselineResponse)).splitOn "\n" do
    if line.trimAscii.isEmpty then continue
    let path ← IO.ofExcept (Json.parse line >>= Json.getStr?)
    let name := if path == baselineMain then some "Main" else names[path]?
    let selected := name.bind (parentObjects[·]?) |>.getD path
    if selected.endsWith ".o" then
      if used.contains selected then continue
      used := used.insert selected
    response := response.push selected
    if let some name := name then names := names.insert selected name
  for (name,path) in parentObjects do
    if !used.contains path then response := response.push path
    names := names.insert path name
  let responsePath := root / "parent.rsp"
  IO.FS.writeFile responsePath ("\n".intercalate (response.toList.map (fun path => (toJson path).compress)) ++ "\n")
  let mapPath := root / "parent-objects.json"
  IO.FS.writeFile mapPath (Json.mkObj (names.toList.map fun (path,name) => (path,toJson name))).pretty
  let plan := plan.setObjVal! "core" (toJson (root / "checkout").toString)
    |>.setObjVal! "output" (toJson (root / "build").toString)
    |>.setObjVal! "baselineResponse" (toJson responsePath.toString)
    |>.setObjVal! "baselineMain" (toJson (parent / "build/Main.o").toString)
    |>.setObjVal! "objectModules" (toJson mapPath.toString)
    |>.setObjVal! "force" (toJson #["Eggshell.SynapseProvenance","Eggshell.SynapseJournal","Eggshell.Warm","Main"])
  IO.FS.writeFile (root / "build-plan.json") plan.pretty
  let settings ← readJson (parent / "build.settings.json")
  let toolchain := "/Users/ovm/.elan/toolchains/leanprover--lean4---v4.33.0"
  let settings := settings.setObjVal! "record" (toJson (root / "build.guard.json").toString)
    |>.setObjVal! "ownedPrefixes" (toJson #[root.toString])
    |>.setObjVal! "minFreeKiB" (toJson (4194304 : Nat))
    |>.setObjVal! "command" (toJson #["/usr/bin/env","LEAN_PATH=" ++ toolchain ++ "/lib/lean",
      toolchain ++ "/bin/lean","-j1","-M1536","--run",
      (project / "tools/research/StudyBuildMain.lean").toString,(root / "build-plan.json").toString])
  IO.FS.writeFile (root / "build.settings.json") settings.pretty
  IO.println "prepared isolated source-authority candidate"
