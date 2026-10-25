import Lean.Data.Json.FromToJson
import Lean.Data.Json.Parser
import Std.Data.HashMap
import Std.Data.HashSet

open Lean
namespace Eggshell.Research.StudyBuild

structure Settings where
  project : String
  core : String
  output : String
  toolchain : String
  baselineResponse : String
  baselineMain : String
  objectModules : String
  parents : Array String
  force : Array String
  mainModule : String
  deriving FromJson, ToJson

structure State where
  done : Std.HashMap String Bool := {}
  active : Std.HashSet String := {}
  objects : Std.HashMap String String := {}
  records : Array Json := #[]

private def check (b : Bool) (message : String) : IO Unit :=
  unless b do throw (IO.userError message)

private def readJson (path : String) : IO Json := do
  IO.ofExcept (Json.parse (← IO.FS.readFile path))

/-- Lean resolves a package root before its individual module. Inherited
interfaces therefore form one explicit overlay, including opaque companions. -/
private partial def inheritLibrary (source target : System.FilePath) : IO Unit := do
  IO.FS.createDirAll target
  for entry in ← source.readDir do
    if !(← entry.path.pathExists) then continue
    let destination := target / entry.fileName
    if ← entry.path.isDir then inheritLibrary entry.path destination
    else if !(← destination.pathExists) then
      let linked ← IO.Process.output {cmd := "/bin/ln",args := #["-s",entry.path.toString,destination.toString]}
      check (linked.exitCode == 0) s!"cannot link inherited interface: {destination}"

private def detachInterfaces (path : System.FilePath) : IO Unit := do
  let parent := path.parent.get!
  let name := path.fileName.get!
  for entry in ← parent.readDir do
    if entry.fileName.startsWith (name ++ ".") && (← entry.path.symlinkMetadata).type == .symlink then
      IO.FS.removeFile entry.path

private def modulePath (name : String) := (name.replace "." "/")
private def stem (name : String) := name.replace "." "_"

private def imports (source : String) : Array String :=
  source.splitOn "\n" |>.filterMap (fun row =>
    let row := row.trimAscii.toString
    let introducer := if row.startsWith "public import " then "public import " else "import "
    if !row.startsWith introducer then none else
      let words := (row.drop introducer.length).toString.splitOn " " |>.filter (! ·.isEmpty)
      (if words.head? == some "all" then words.drop 1 else words).head?) |>.toArray

private def run (settings : Settings) (label command : String) (args : Array String) : IO Unit := do
  let library := settings.output ++ "/lib:" ++ settings.core ++ "/.lake/build/lib/lean:" ++ settings.toolchain ++ "/lib/lean"
  let result ← IO.Process.output {cmd := command,args,env := #[("LEAN_PATH",some library)]}
  IO.FS.writeFile (settings.output ++ "/" ++ label ++ ".stdout") result.stdout
  IO.FS.writeFile (settings.output ++ "/" ++ label ++ ".stderr") result.stderr
  check (result.exitCode == 0) s!"{label} failed: {result.stdout}\n{result.stderr}"

private partial def visit (settings : Settings) (state : IO.Ref State) (name : String) : IO Bool := do
  if let some done := (← state.get).done[name]? then return done
  check (!(← state.get).active.contains name) s!"module cycle: {name}"
  state.modify fun s => {s with active := s.active.insert name}
  let path := modulePath name
  let source := (if name.startsWith "tools.research." then settings.project else settings.core) ++ "/" ++ path ++ ".lean"
  if !(← System.FilePath.pathExists source) then
    check (← System.FilePath.pathExists (settings.toolchain ++ "/lib/lean/" ++ path ++ ".olean")) s!"missing module: {name}"
    state.modify fun s => {s with done := s.done.insert name false,active := s.active.erase name}
    return false
  let text ← IO.FS.readFile source
  let mut changed := false
  for dependency in imports text do changed := (← visit settings state dependency) || changed
  let object := settings.output ++ "/" ++ stem name ++ ".o"
  let cached := settings.output ++ "/" ++ stem name ++ ".source"
  let localLibrary := settings.output ++ "/lib/" ++ path ++ ".olean"
  let localReady ← if !(← System.FilePath.pathExists object) then pure false
    else if !(← System.FilePath.pathExists localLibrary) then pure false
    else if !(← System.FilePath.pathExists cached) then pure false
    else pure ((← IO.FS.readFile cached) == text)
  let hasLocal ← if ← System.FilePath.pathExists localLibrary then
    pure ((← (System.FilePath.mk localLibrary).symlinkMetadata).type != .symlink)
    else pure false
  let inherited ← System.FilePath.pathExists (settings.core ++ "/.lake/build/lib/lean/" ++ path ++ ".olean")
  if !hasLocal && inherited && !changed && !settings.force.contains name then
    state.modify fun s => {s with done := s.done.insert name false,active := s.active.erase name}
    return false
  let compiled := !localReady || changed
  if compiled then
    (← IO.getStdout).putStrLn ((Json.mkObj [("compiling",toJson name)]).compress)
    (← IO.getStdout).flush
    IO.FS.createDirAll (System.FilePath.mk localLibrary).parent.get!
    detachInterfaces (.mk (settings.output ++ "/lib/" ++ path))
    let generated := settings.output ++ "/" ++ stem name ++ ".c"
    let packageRoot := if name.startsWith "tools.research." then settings.project else settings.core
    run settings (stem name ++ "-lean") (settings.toolchain ++ "/bin/lean")
      #["--root=" ++ packageRoot,"-j1","-M3072","-DwarningAsError=true","-c",generated,"-o",localLibrary,source]
    run settings (stem name ++ "-c") (settings.toolchain ++ "/bin/leanc") #["-c","-O2","-o",object,generated]
    IO.FS.writeFile cached text
    IO.FS.removeFile generated
  state.modify fun s => {s with
    done := s.done.insert name compiled
    active := s.active.erase name
    objects := s.objects.insert name object
    records := s.records.push (Json.mkObj [
      ("module",toJson name),("source",toJson source),("object",toJson object),("compiled",toJson compiled)])}
  return compiled

def build (input : String) : IO Unit := do
  let settings ← IO.ofExcept (fromJson? (α := Settings) (← readJson input))
  IO.FS.createDirAll settings.output
  inheritLibrary (.mk (settings.core ++ "/.lake/build/lib/lean")) (.mk (settings.output ++ "/lib"))
  let state ← IO.mkRef ({} : State)
  let _ ← visit settings state settings.mainModule
  let state ← state.get
  let mut modules : Std.HashMap String String := {}
  let objectMap ← IO.ofExcept ((← readJson settings.objectModules).getObj?)
  for (path,name) in objectMap.toArray do modules := modules.insert path (← IO.ofExcept name.getStr?)
  for parent in settings.parents do
    if !(← System.FilePath.pathExists (parent ++ "/modules.json")) then continue
    let names ← IO.ofExcept ((← readJson (parent ++ "/modules.json")).getArr?)
    for name in names do
      let name ← IO.ofExcept name.getStr?
      modules := modules.insert (parent ++ "/" ++ stem name ++ ".o") name
  let mut used : Std.HashSet String := {}
  let mut arguments := #[]
  for row in (← IO.FS.readFile settings.baselineResponse).splitOn "\n" do
    if row.trimAscii.isEmpty then continue
    let path ← IO.ofExcept (Json.parse row >>= Json.getStr?)
    if path == settings.baselineMain then continue
    if let some name := modules[path]? then
      if let some replacement := state.objects[name]? then
        if !used.contains name then arguments := arguments.push replacement
        used := used.insert name
        continue
    arguments := arguments.push path
  for (name,path) in state.objects do
    if !used.contains name then arguments := arguments.push path
  let response := settings.output ++ "/runtime.rsp"
  IO.FS.writeFile response ("\n".intercalate (arguments.toList.map (fun arg => (toJson arg).compress)) ++ "\n")
  run settings "link" (settings.toolchain ++ "/bin/leanc")
    #["-Wl,-dead_strip","-o",settings.output ++ "/StudyMain","@" ++ response]
  IO.FS.writeFile (settings.output ++ "/build.json") (Json.mkObj [
    ("settings",toJson settings),("modules",toJson state.records),("newPythonOrRuby",toJson false)]).pretty

end Eggshell.Research.StudyBuild

def main (args : List String) : IO UInt32 := do
  try
    let [input] := args | throw (IO.userError "StudyBuildMain SETTINGS")
    Eggshell.Research.StudyBuild.build input
    return 0
  catch error => IO.eprintln error.toString; return 1
