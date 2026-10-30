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
  baselineCore : Option String := none
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
  inheritedStamps : Std.HashMap String String := {}
  inheritedDependencies : Std.HashMap String System.FilePath := {}
  inputStamps : Std.HashMap String String := {}
  closures : Std.HashMap String (Std.HashSet String) := {}

private def check (b : Bool) (message : String) : IO Unit :=
  unless b do throw (IO.userError message)

private def readJson (path : String) : IO Json := do
  IO.ofExcept (Json.parse (← IO.FS.readFile path))

/-- Lean resolves a package root before its individual module. Inherited
interfaces therefore form one explicit overlay, including opaque companions. -/
private partial def inheritLibrary (source target : System.FilePath) : IO Unit := do
  IO.FS.createDirAll target
  -- Link to the actual interface, not another overlay's link. Chained
  -- candidate libraries otherwise exceed the OS symlink limit despite a
  -- valid inherited object, and later cleanup can break an unrelated build.
  let actualSource ← IO.FS.realPath source
  if (← IO.FS.realPath target) == actualSource then return
  for entry in ← actualSource.readDir do
    if !(← entry.path.pathExists) then continue
    let destination := target / entry.fileName
    if ← entry.path.isDir then inheritLibrary entry.path destination
    else
      let metadata ← try pure (some (← destination.symlinkMetadata)) catch _ => pure none
      if metadata.any (·.type == .symlink) then IO.FS.removeFile destination
      if metadata.isNone || metadata.any (·.type == .symlink) then
        let actual ← IO.FS.realPath entry.path
        let linked ← IO.Process.output {cmd := "/bin/ln",args := #["-s",actual.toString,destination.toString]}
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

/-- `include_str` contributes executable identity even without an import
edge. A cached module must bind those literal file bytes as well as its own
text; otherwise a changed transport can leave an old implementation stamp. -/
private def sourceStamp (path : System.FilePath) (source : String) : IO String := do
  let mut included := #[]
  for suffix in (source.splitOn "include_str \"").drop 1 do
    let some name := (suffix.splitOn "\"").head? |
      throw (IO.userError "unterminated include_str in build source")
    let dependency := path.parent.get! / name
    let bytes ← IO.FS.readFile dependency
    included := included.push (name,bytes)
  return (toJson (source,included)).compress

private def validDigest (value : String) : Bool :=
  value.length == 64 && value.toList.all (fun c => ('0' ≤ c && c ≤ '9') || ('a' ≤ c && c ≤ 'f'))

/-- Keep each compiled module's full .source witness, but reference its exact
UTF-8 bytes by SHA-256 in transitive closures. No shell evaluates source text. -/
private def stampDigest (value : String) : IO String := do
  let result ← IO.Process.output {cmd := "/usr/bin/shasum",args := #["-a","256"]} (some value)
  let digest := (result.stdout.splitOn " ").headD ""
  check (result.exitCode == 0 && validDigest digest) "cannot digest native input stamp"
  return digest

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
    let stamp ← stampDigest (toJson (settings.toolchain,name)).compress
    state.modify fun s => {s with
      done := s.done.insert name false,active := s.active.erase name
      inputStamps := s.inputStamps.insert name stamp
      closures := s.closures.insert name (({} : Std.HashSet String).insert name)}
    return false
  let text ← IO.FS.readFile source
  let stamp ← sourceStamp (.mk source) text
  let inputDigest ← stampDigest stamp
  let mut changed := false
  let mut closure := ({} : Std.HashSet String).insert name
  for dependency in imports text do
    changed := (← visit settings state dependency) || changed
    for included in (← state.get).closures[dependency]?.getD {} do
      closure := closure.insert included
  state.modify fun s => {s with
    inputStamps := s.inputStamps.insert name inputDigest
    closures := s.closures.insert name closure}
  -- A failed build may already have refreshed a dependency. Its compile flag
  -- is false on retry, so it cannot establish whether a cached parent is new.
  -- Bind the exact, deduplicated transitive input set instead of that flag.
  let stamps := (← state.get).inputStamps
  let dependencyStamp := toJson (closure.toArray.qsort (· < ·) |>.map
    (fun moduleName => (moduleName,stamps[moduleName]?.getD ""))) |>.compress
  let object := settings.output ++ "/" ++ stem name ++ ".o"
  let cached := settings.output ++ "/" ++ stem name ++ ".source"
  let dependencies := settings.output ++ "/" ++ stem name ++ ".dependencies"
  let localLibrary := settings.output ++ "/lib/" ++ path ++ ".olean"
  let localReady ← if !(← System.FilePath.pathExists object) then pure false
    else if !(← System.FilePath.pathExists localLibrary) then pure false
    else if !(← System.FilePath.pathExists cached) then pure false
    else if !(← System.FilePath.pathExists dependencies) then pure false
    else pure ((← IO.FS.readFile cached) == stamp && (← IO.FS.readFile dependencies) == dependencyStamp)
  let hasLocal ← if ← System.FilePath.pathExists localLibrary then
    pure ((← (System.FilePath.mk localLibrary).symlinkMetadata).type != .symlink)
    else pure false
  -- Research sources live in the changing project, rather than the frozen
  -- candidate checkout. An inherited interface cannot establish their bytes.
  -- Compile them locally once; the local source cache handles later reuse.
  -- A changed ordinary module must not inherit an old object either. Use
  -- the actual object's stamp; for an unstamped frozen base, require the
  -- explicitly selected parent source to be byte-identical. Missing source
  -- provenance causes a rebuild rather than silently selecting old code.
  let matchedStamp ← match (← state.get).inheritedStamps[name]? with
    | some original => pure (original == stamp)
    | none => match settings.baselineCore with
      | none => pure false
      | some baseline => do
          let previous := System.FilePath.mk (baseline ++ "/" ++ path ++ ".lean")
          if !(← previous.pathExists) then pure false else
            pure ((← sourceStamp previous (← IO.FS.readFile previous)) == stamp)
  -- A different executable's response deliberately omits the selected entry
  -- point. An inherited interface alone cannot provide its native `main`.
  -- The response may combine objects from several ancestors. Matching this
  -- module's source does not show that its native callers used today's ABI.
  -- Validate the actual object's complete input closure, not the last build's
  -- change flag. Unstamped objects must be rebuilt.
  let matchedDependencies ← match (← state.get).inheritedDependencies[name]? with
    | none => pure false
    | some path => do
      let previous ← IO.FS.readFile path
      pure (previous == dependencyStamp)
  let inherited ← if name == settings.mainModule || name.startsWith "tools.research." ||
      name.startsWith "tests." || !matchedStamp || !matchedDependencies then pure false else
    System.FilePath.pathExists (settings.core ++ "/.lake/build/lib/lean/" ++ path ++ ".olean")
  if !hasLocal && inherited && !changed && !settings.force.contains name then
    state.modify fun s => {s with done := s.done.insert name false,active := s.active.erase name}
    return false
  let compiled := !localReady
  if compiled then
    -- Inherited source links may resolve outside the selected package root.
    -- Materialize only the module being rebuilt, preserving its exact bytes.
    if (← (System.FilePath.mk source).symlinkMetadata).type == .symlink then
      IO.FS.removeFile source
      IO.FS.writeFile source text
    (← IO.getStdout).putStrLn ((Json.mkObj [("compiling",toJson name)]).compress)
    (← IO.getStdout).flush
    IO.FS.createDirAll (System.FilePath.mk localLibrary).parent.get!
    detachInterfaces (.mk (settings.output ++ "/lib/" ++ path))
    let generated := settings.output ++ "/" ++ stem name ++ ".c"
    let packageRoot := if name.startsWith "tools.research." then settings.project else settings.core
    run settings (stem name ++ "-lean") (settings.toolchain ++ "/bin/lean")
      #["--root=" ++ packageRoot,"-j1","-M3072","-DwarningAsError=true","-c",generated,"-o",localLibrary,source]
    run settings (stem name ++ "-c") (settings.toolchain ++ "/bin/leanc") #["-c","-O2","-o",object,generated]
    IO.FS.writeFile cached stamp
    IO.FS.writeFile dependencies dependencyStamp
    IO.FS.removeFile generated
  state.modify fun s => {s with
    done := s.done.insert name (!matchedStamp || changed)
    active := s.active.erase name
    objects := s.objects.insert name object
    records := s.records.push (Json.mkObj [
      ("module",toJson name),("source",toJson source),("object",toJson object),("compiled",toJson compiled)])}
  return !matchedStamp || changed

/-- A derived runtime can have native objects that were not in its own input
map. Its recorded link inputs, rather than a caller's manually merged map,
identify those modules. Reject contradictory names before compiling. -/
private def effectiveObjectMap (settings : Settings) : IO Json := do
  let mut objects ← IO.ofExcept ((← readJson settings.objectModules).getObj?)
  let response : System.FilePath := .mk settings.baselineResponse
  if response.fileName == some "runtime.rsp" then
    let directory := response.parent.get!
    let manifest := directory / "build.json"
    if ← manifest.pathExists then
      let parent ← readJson manifest.toString
      let output : String ← IO.ofExcept ((parent.getObjValD "settings").getObjValAs? _ "output")
      check ((System.FilePath.mk output).normalize == directory.normalize) "baseline native manifest belongs to another output"
      let mut linked : Std.HashSet String := {}
      for row in (← IO.FS.readFile response).splitOn "\n" do
        if row.trimAscii.isEmpty then continue
        linked := linked.insert (← IO.ofExcept (Json.parse row >>= Json.getStr?))
      for row in ← IO.ofExcept (parent.getObjValAs? (Array Json) "modules") do
        let path : String ← IO.ofExcept (row.getObjValAs? _ "object")
        if !linked.contains path then continue
        let name : String ← IO.ofExcept (row.getObjValAs? _ "module")
        if let some previous := objects[path]? then
          check (previous == toJson name) "contradictory baseline native module mapping"
        objects := objects.insert path (toJson name)
  return Json.obj objects

def build (input : String) : IO Unit := do
  let settings ← IO.ofExcept (fromJson? (α := Settings) (← readJson input))
  IO.FS.createDirAll settings.output
  inheritLibrary (.mk (settings.core ++ "/.lake/build/lib/lean")) (.mk (settings.output ++ "/lib"))
  let effective ← effectiveObjectMap settings
  IO.FS.writeFile (settings.output ++ "/object-mapping.json") effective.pretty
  let objectMap ← IO.ofExcept effective.getObj?
  let mut inheritedStamps : Std.HashMap String String := {}
  let mut inheritedDependencies : Std.HashMap String System.FilePath := {}
  for row in (← IO.FS.readFile settings.baselineResponse).splitOn "\n" do
    if row.trimAscii.isEmpty then continue
    let path ← IO.ofExcept (Json.parse row >>= Json.getStr?)
    let some name := objectMap[path]? | continue
    let name ← IO.ofExcept name.getStr?
    let cache := (System.FilePath.mk path).withExtension "source"
    if ← cache.pathExists then
      inheritedStamps := inheritedStamps.insert name (← IO.FS.readFile cache)
    let dependencies := (System.FilePath.mk path).withExtension "dependencies"
    if ← dependencies.pathExists then inheritedDependencies := inheritedDependencies.insert name dependencies
  let state ← IO.mkRef ({inheritedStamps,inheritedDependencies} : State)
  let _ ← visit settings state settings.mainModule
  let state ← state.get
  let mut modules : Std.HashMap String String := {}
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

private partial def dependencyFiles (root : System.FilePath) : IO (Array System.FilePath) := do
  let mut files := #[]
  for entry in ← root.readDir do
    let kind := (← entry.path.symlinkMetadata).type
    if kind == .dir && !["numerical-owned-20261024",".git","node_modules","models","lib"].contains entry.fileName then
      files := files ++ (← dependencyFiles entry.path)
    else if kind == .file && entry.fileName.endsWith ".dependencies" &&
        (← (entry.path.withExtension "source").pathExists) then files := files.push entry.path
  return files

/-- One-time in-place compaction of research build metadata. Full .source,
objects, interfaces, runtime binaries and DBs are never modified. Equality of
all observed input strings is preserved by checking the reverse digest map. -/
def compactDependencies (directory report : System.FilePath) : IO Unit := do
  check (directory == .mk "/Users/ovm/.codex/experiments/eggshell" && !(← report.pathExists))
    "explicit research metadata root and fresh report required"
  let processes ← IO.Process.output {cmd := "/bin/ps",args := #["-axo","command="]}
  check (processes.exitCode == 0 && (processes.stdout.splitOn "StudyBuildMain.lean").length ≤ 2)
    "another native builder may be using dependency metadata"
  let mut known : Std.HashMap String String := {}
  let mut reversed : Std.HashMap String String := {}
  let mut plans : Array (System.FilePath × String × String × Nat) := #[]
  for path in ← dependencyFiles directory do
    let original ← IO.FS.readFile path
    let values : Array (String × String) ← IO.ofExcept (fromJson? (← IO.ofExcept (Json.parse original)))
    let mut encoded := #[]
    for (name,value) in values do
      let digest ← if validDigest value then pure value else do
        if let some existing := known[value]? then pure existing else do
          let digest ← stampDigest value
          if let some previous := reversed[digest]? then
            check (previous == value) "distinct observed input stamps have the same digest"
          known := known.insert value digest
          reversed := reversed.insert digest value
          pure digest
      encoded := encoded.push (name,digest)
    let compact := (toJson encoded).compress
    if compact != original then plans := plans.push (path,← stampDigest original,compact,original.utf8ByteSize)
  IO.FS.createDirAll report.parent.get!
  let entries := plans.map fun (path,before,after,bytes) => Json.mkObj [
    ("path",toJson path.toString),("beforeSha256",toJson before),
    ("beforeBytes",toJson bytes),("afterBytes",toJson after.utf8ByteSize)]
  let record := Json.mkObj [("files",Json.arr entries),("uniqueInputStamps",toJson known.size),
    ("observedDigestCollisions",toJson (0 : Nat)),("fileCount",toJson plans.size),
    ("beforeBytes",toJson (plans.foldl (fun total row => total+row.2.2.2) 0)),
    ("afterBytes",toJson (plans.foldl (fun total row => total+row.2.2.1.utf8ByteSize) 0)),
    ("sourceObjectsInterfacesRuntimesAndDatabasesUnchanged",toJson true),("archiveCreated",toJson false)]
  IO.FS.writeFile report (record.setObjVal! "completed" (toJson false)).pretty
  for (path,before,after,_) in plans do
    check ((← stampDigest (← IO.FS.readFile path)) == before) "dependency metadata changed during compaction"
    let temporary := path.withExtension "dependencies.compacting"
    check (!(← temporary.pathExists)) "unexpected metadata compaction temporary"
    IO.FS.writeFile temporary after
    IO.FS.rename temporary path
  IO.FS.writeFile report (record.setObjVal! "completed" (toJson true)).pretty
  IO.println (Json.mkObj [("files",toJson plans.size),("uniqueInputStamps",toJson known.size),
    ("beforeBytes",record.getObjValD "beforeBytes"),("afterBytes",record.getObjValD "afterBytes")]).compress

end Eggshell.Research.StudyBuild
open Eggshell.Research.StudyBuild

private def resumeAudit (directory : String) : IO Unit := do
  let root := System.FilePath.mk directory
  check (root.isAbsolute && !(← root.pathExists)) "new absolute resumed-build fixture required"
  IO.FS.createDirAll (root / "core/.lake/build/lib/lean")
  let core := root / "core"
  let toolchain := "/Users/ovm/.elan/toolchains/leanprover--lean4---v4.33.0"
  IO.FS.writeFile (root / "objects.json") "{}"
  IO.FS.writeFile (root / "baseline.rsp") ""
  let settings : Settings := {
    project := core.toString,core := core.toString,output := (root / "build").toString,toolchain
    baselineResponse := (root / "baseline.rsp").toString,baselineMain := "absent"
    objectModules := (root / "objects.json").toString,parents := #[],force := #[],mainModule := "Main"}
  let plan := root / "plan.json"
  IO.FS.writeFile plan (toJson settings).pretty
  IO.FS.writeFile (core / "Box.lean") "module\n@[expose] public section\nstructure Box where\n  x : Nat\n"
  let middle := "module\npublic import Box\n@[expose] public section\ndef answer (box : Box) : Nat := box.x+1\n"
  IO.FS.writeFile (core / "Middle.lean") middle
  IO.FS.writeFile (core / "Broken.lean") "module\n"
  IO.FS.writeFile (core / "Main.lean") "import Box\nimport Broken\nimport Middle\ndef main : IO Unit := IO.println (toString (answer ⟨2⟩))\n"
  build plan.toString
  let before ← IO.Process.output {cmd := (root / "build/StudyMain").toString}
  check (before.exitCode == 0 && before.stdout.trimAscii == "3") "invalid initial layout fixture"
  IO.FS.writeFile (core / "Box.lean") "module\n@[expose] public section\nstructure Box where\n  y : Nat\n  x : Nat\n"
  IO.FS.writeFile (core / "Broken.lean") "module\n#check deliberately_missing_name\n"
  IO.FS.writeFile (core / "Main.lean") "import Box\nimport Broken\nimport Middle\ndef main : IO Unit := IO.println (toString (answer ⟨9,2⟩))\n"
  let mut failed := false
  try build plan.toString catch _ => failed := true
  check failed "fixture did not stop after refreshing its dependency"
  IO.FS.writeFile (core / "Broken.lean") "module\n"
  build plan.toString
  let after ← IO.Process.output {cmd := (root / "build/StudyMain").toString}
  let record ← readJson (root / "build/build.json").toString
  let modules ← IO.ofExcept (record.getObjValAs? (Array Json) "modules")
  let compiled := fun name => modules.find? (fun row => (row.getObjValAs? String "module").toOption == some name)
    |>.bind (fun row => (row.getObjValAs? Bool "compiled").toOption)
  check (after.exitCode == 0 && after.stdout.trimAscii == "3" && compiled "Box" == some false &&
      compiled "Middle" == some true && (← IO.FS.readFile (core / "Middle.lean")) == middle)
    "resumed build reused a parent with the old field layout"
  let derived : Settings := {settings with
    output := (root / "derived").toString
    baselineResponse := (root / "build/runtime.rsp").toString
    baselineMain := (root / "build/Main.o").toString
    baselineCore := some core.toString}
  IO.FS.writeFile (root / "derived-plan.json") (toJson derived).pretty
  build (root / "derived-plan.json").toString
  let derivedResult ← IO.Process.output {cmd := (root / "derived/StudyMain").toString}
  check (derivedResult.exitCode == 0 && derivedResult.stdout.trimAscii == "3")
    "derived build duplicated an object omitted by the caller's empty map"
  let conflict := Json.mkObj [((root / "build/Box.o").toString,toJson "WrongModule")]
  IO.FS.writeFile (root / "objects.json") conflict.pretty
  let mut conflictRejected := false
  try
    let _ ← effectiveObjectMap derived
    pure ()
  catch _ => conflictRejected := true
  check conflictRejected "contradictory native module mapping was accepted"
  IO.FS.writeFile (root / "results.json") (Json.mkObj [
    ("dependencyCachedOnRetry",toJson true),("unchangedParentRecompiled",toJson true),
    ("omittedDerivedNativeObjectsRecovered",toJson true),("contradictoryNativeMappingRejected",toJson true),
    ("runtimeValueBefore",toJson before.stdout.trimAscii.copy),("runtimeValueAfter",toJson after.stdout.trimAscii.copy),
    ("staleLayoutWouldReturn",toJson (10 : Nat)),("answeringModelCalls",toJson (0 : Nat))]).pretty

def main (args : List String) : IO UInt32 := do
  try
    if let ["compact-dependencies",directory,report] := args then
      compactDependencies (.mk directory) (.mk report)
      return 0
    if args == ["digest-check"] then
      let digest ← stampDigest "abc"
      check (digest == "ba7816bf8f01cfea414140de5dae2223b00361a396177a9cb410ff61f20015ad") "SHA-256 boundary disagrees"
      let first ← stampDigest (toJson ("source",#[ ("payload","日本語\n") ])).compress
      let second ← stampDigest (toJson ("source",#[ ("payload","日本語\nchanged") ])).compress
      check (first != second) "included-byte change did not change its digest"
      IO.println "Native source metadata digest boundary passed"
      return 0
    if let ["resume-check",directory] := args then
      resumeAudit directory
      return 0
    if let ["source-stamp-check",directory] := args then
      let root := System.FilePath.mk directory
      check (root.isAbsolute && !(← root.pathExists)) "fresh absolute stamp fixture required"
      IO.FS.createDir root
      let path := root / "Module.lean"
      let source := "def payload := (include_str \"payload.txt\")\n"
      IO.FS.writeFile path source
      IO.FS.writeFile (root / "payload.txt") "first"
      let first ← sourceStamp path source
      IO.FS.writeFile (root / "payload.txt") "changed"
      let second ← sourceStamp path source
      let repeated ← sourceStamp path source
      check (first != second && second == repeated && (← IO.FS.readFile path) == source)
        "embedded file change was not bound to the cache stamp"
      IO.FS.removeFile path
      IO.FS.removeFile (root / "payload.txt")
      IO.FS.removeDir root
      IO.println (Json.mkObj [("sourceUnchanged",toJson true),("includeChangeInvalidates",toJson true),
        ("repeatStable",toJson true),("fixtureRemoved",toJson true)]).compress
      return 0
    let [input] := args | throw (IO.userError "StudyBuildMain SETTINGS")
    Eggshell.Research.StudyBuild.build input
    return 0
  catch error => IO.eprintln error.toString; return 1
