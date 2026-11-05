import Lean.Data.Json.FromToJson
import Lean.Data.Json.Parser
open Lean
def base : System.FilePath := "/Users/ovm/.codex/experiments/eggshell/scope-token-study-20261028/fixed-frame-study"
def workspace : System.FilePath := "/Users/ovm/.codex/worktrees/hook-deadline-baseline/eggshell"
def output := workspace/"docs/candidates/public-input-publication"
def read (path : System.FilePath) : IO Json := do IO.ofExcept (Json.parse (← IO.FS.readFile path))
def hash (path : System.FilePath) : IO String := do
  let result ← IO.Process.output {cmd := "/usr/bin/shasum",args := #["-a","256",path.toString]}
  unless result.exitCode == 0 do throw (IO.userError "cleanup identity unavailable")
  return (result.stdout.splitOn " ").head!
def hashText (text : String) : IO String := do
  let result ← IO.Process.output {cmd := "/usr/bin/shasum",args := #["-a","256"]} (some text)
  unless result.exitCode == 0 do throw (IO.userError "cleanup name identity unavailable")
  return (result.stdout.splitOn " ").head!
partial def erase (path : System.FilePath) : IO Nat := do
  let metadata ← path.symlinkMetadata
  if metadata.type == .dir then
    let mut bytes := 0
    for entry in ← path.readDir do bytes := bytes+(← erase entry.path)
    IO.FS.removeDir path
    return bytes
  IO.FS.removeFile path
  return metadata.byteSize.toNat
def main : IO Unit := do
  unless !(← (output/"cleanup.json").pathExists) do throw (IO.userError "preserve cleanup receipt")
  let evidence ← read (output/"evidence.json")
  let mut recording := #[]
  for entry in ← base.readDir do
    if entry.fileName.startsWith "public-input-publication-" && entry.fileName.endsWith ".guard.json" &&
        !entry.fileName.contains "cleanup" then
      let guard ← read entry.path
      unless guard.getObjValD "state" == toJson "finished" && guard.getObjValD "ownedPids" == toJson (#[] : Array Nat) do
        throw (IO.userError "controlled work remains owned")
      if entry.fileName.contains "records" then recording := recording.push (entry.fileName,guard)
  IO.FS.writeFile (output/"recording-guards.json") (toJson recording).pretty
  let identities ← IO.ofExcept (fromJson? (evidence.getObjValD "sourceHashes") : Except String (Array (String × String × String)))
  let baseline := base/"public-input-publication-baseline-core/Eggshell"
  let core := base/"interest-traffic-core"
  for (name,before,current) in identities do
    unless (← hash (core/"Eggshell"/name)) == current && (← hash (baseline/name)) == before do
      throw (IO.userError "candidate or parent source changed after sealing")
  unless toJson (← hash (base/"public-input-publication-build/StudyMain")) == evidence.getObjValD "runtimeSha256" do
    throw (IO.userError "tested runtime changed")
  let source := base/"frontend-quiescence-fixture-small1"
  let expected := (← read (source/"frozen-readback.json")).getObjValD "sourceHeads"
  let heads ← (List.range 16).toArray.mapM fun owner => read (source/"work.project/owners"/toString owner/"source.egg/head")
  unless toJson heads == expected do throw (IO.userError "original cut changed")
  let listing ← IO.Process.output {cmd := "rg",args := #["--files","--hidden","--no-ignore",(source/"work.project").toString]}
  unless listing.exitCode == 0 do throw (IO.userError "cannot inventory experiment publications")
  let paths := (listing.stdout.splitOn "\n").filter fun name =>
    name.contains "/query-inputs/" && name.endsWith "/public/latest.json"
  unless paths.length == 16 do throw (IO.userError "unexpected public projection inventory")
  let mut projections : Array System.FilePath := #[]
  for name in paths do
    let path := System.FilePath.mk name
    let value ← read path
    let input := value.getObjValD "input"
    let producer ← IO.ofExcept (input.getObjValAs? String "producer")
    let model ← IO.ofExcept (input.getObjValAs? String "model")
    let encoder ← IO.ofExcept (input.getObjValAs? String "encoder")
    let folder := path.parent.get!.parent.get!
    unless heads.contains (input.getObjValD "source") && folder.parent.get!.fileName == some "query-inputs" &&
        folder.fileName == some (← hashText (toJson (producer,model,encoder)).compress) do
      throw (IO.userError "foreign publication in cleanup inventory")
    projections := projections.push folder
  let frontend := core/"tools/research/FrontTrafficChecks.lean"
  let originalFrontend ← IO.FS.readFile frontend
  let restoredFrontend := originalFrontend.replace "import tools.research.PublicInputChecks\n" ""
    |>.replace ("  | [\"public-input-audit\",source,root] => do\n"++
      "      Eggshell.Research.PublicInputChecks.run (.mk source) (.mk root)\n      return 0\n") ""
  unless restoredFrontend == (← IO.FS.readFile (workspace/"tools/research/FrontTrafficChecks.lean")) &&
      (← hash (core/"tools/research/PublicInputChecks.lean")) == (← hash (workspace/"tools/research/PublicInputChecks.lean")) do
    throw (IO.userError "research harness changed outside this experiment")
  -- Remove only this experiment's source edits. The parallel-owner/egraph/vector/
  -- synapse implementation and the parent's checked-reader cache are retained.
  for (name,_,_) in identities do IO.FS.writeFile (core/"Eggshell"/name) (← IO.FS.readFile (baseline/name))
  IO.FS.writeFile frontend restoredFrontend
  IO.FS.removeFile (core/"tools/research/PublicInputChecks.lean")
  let mut removed := #[]
  for path in projections do removed := removed.push (path.toString,← erase path)
  for entry in ← base.readDir do
    if entry.fileName.startsWith "public-input-publication-" && !entry.fileName.contains "cleanup" &&
        ((entry.fileName.endsWith "-result" || entry.fileName.endsWith "-private") ||
          ["public-input-publication-build","public-input-publication-baseline-core","public-input-publication-build-settings.json"].contains entry.fileName ||
          entry.fileName.endsWith ".log" || entry.fileName.endsWith ".guard-settings.json" || entry.fileName.endsWith ".guard.json") then
      removed := removed.push (entry.path.toString,← erase entry.path)
  let current ← (List.range 16).toArray.mapM fun owner => read (source/"work.project/owners"/toString owner/"source.egg/head")
  unless toJson current == expected do throw (IO.userError "cleanup changed original heads")
  IO.FS.writeFile (output/"cleanup.json") (Json.mkObj [("removed",toJson removed),
    ("apparentBytes",toJson (removed.foldl (fun total item => total+item.2) 0)),
    ("restoredParent",evidence.getObjValD "parentRuntimeSha256"),("sourceEditsRestored",toJson true),
    ("originalHeadsUnchanged",toJson true),("archivesCreated",toJson false),("adopted",toJson false)]).pretty
