module
public import Lean.Data.Json.Parser
public import Lean.Data.Json.FromToJson
@[expose] public section
namespace StudyLocal
open Lean
def project : System.FilePath := "/Users/ovm/.codex/worktrees/hook-deadline-baseline/eggshell"
def base : System.FilePath := "/Users/ovm/.codex/experiments/eggshell/scope-token-study-20261028/fixed-frame-study"
def compiler : System.FilePath := "/Users/ovm/.elan/toolchains/leanprover--lean4---v4.33.0"
def check (valid : Bool) (message : String) : IO Unit := unless valid do throw (IO.userError message)
def read (path : System.FilePath) : IO Json := IO.FS.readFile path >>= (IO.ofExcept ∘ Json.parse)
def write (path : System.FilePath) (value : Json) : IO Unit := IO.FS.writeFile path value.compress
def command (cmd : String) (args : Array String) (cwd : System.FilePath := project) : IO String := do
  let result ← IO.Process.output {cmd,args,cwd := some cwd}
  check (result.exitCode == 0) (result.stdout++result.stderr)
  return result.stdout
def hash (path : System.FilePath) : IO String :=
  return ((← command "/usr/bin/shasum" #["-a","256",path.toString]).splitOn " ").headD ""
def idle : IO Unit := do
  let rows := (← command "/bin/ps" #["-axo","command="]).splitOn "\n"
  check (!(rows.any fun row =>
    match row.trimAscii.toString.splitOn " " |>.filter (!·.isEmpty) with
    | executable :: "guard" :: _ => executable.startsWith (base.toString++"/") && executable.endsWith "/StudyMain"
    | _ => false)) "resource guard is live"
def materialize (originBuild destination build : System.FilePath) (entry settings : String) : IO Unit := do
  check (!(← destination.pathExists) && !(← build.pathExists)) "fresh isolated build required"
  discard <| command (compiler/"bin/lean").toString #["-j1","-M768","--run",
    (project/"tools/research/DiscoveryStagesStudy.lean").toString,"materialize-native",originBuild.toString,
    destination.toString,build.toString,entry,(base/settings).toString]

/-- Import a finished local compiler cache by copying bytes, never linking
mutable output. StudyBuildMain still checks each source and its entire input
closure before reuse. Changed entries are rebuilt in the fresh destination. -/
def copyLocalArtifacts (origin destination : System.FilePath) : IO Unit := do
  check (!(← destination.pathExists)) "fresh compiler cache destination required"
  IO.FS.createDirAll destination
  let manifest ← read (origin/"build.json")
  for row in ← IO.ofExcept (manifest.getObjValAs? (Array Json) "modules") do
    let name ← IO.ofExcept (row.getObjValAs? String "module")
    check (name.toList.all fun char => char.isAlphanum || char == '_' || char == '.') "invalid native module"
    let stem := name.replace "." "_"
    let interface := origin/"lib"/(name.replace "." "/"++".olean")
    if !(← interface.pathExists) || (← interface.symlinkMetadata).type != .file then continue
    for extension in ["o","source","dependencies"] do
      let path := origin/(stem++"."++extension)
      check (← path.pathExists) "finished compiler cache is incomplete"
      IO.FS.writeBinFile (destination/(stem++"."++extension)) (← IO.FS.readBinFile path)
    let moduleName := (name.splitOn ".").getLast!
    let parent := interface.parent.get!
    let targetParent := destination/"lib"/(name.replace "." "/") |>.parent.get!
    IO.FS.createDirAll targetParent
    for entry in ← parent.readDir do
      if entry.fileName.startsWith (moduleName++".") && !(← entry.path.isDir) then
        IO.FS.writeBinFile (targetParent/entry.fileName) (← IO.FS.readBinFile entry.path)
def finished (tag : String) : IO Json := do
  let record ← read (base/(tag++".guard.json"))
  check (record.getObjValD "state" == toJson "finished" && record.getObjValD "exitCode" == toJson (0 : Nat) &&
    record.getObjValD "ownedPids" == toJson (#[] : Array Nat)) (tag++" has not succeeded and drained")
  return record
def guard (tag : String) (args : Array String) : IO Unit := do
  idle
  let path := base/(tag++".guard-settings.json")
  check (!(← path.pathExists)) "preserve previous guarded stage"
  write path (Json.mkObj [("command",toJson args),("cwd",toJson project.toString),
    ("record",toJson (base/(tag++".guard.json")).toString),("ownedPrefixes",toJson #[base.toString]),
    ("limitRssKiB",toJson (4358524 : Nat)),("minFreeKiB",toJson (2097152 : Nat))])
end StudyLocal
