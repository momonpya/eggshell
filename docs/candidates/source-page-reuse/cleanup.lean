import Lean.Data.Json.FromToJson
import Lean.Data.Json.Parser
open Lean
def base : System.FilePath := "/Users/ovm/.codex/experiments/eggshell/scope-token-study-20261028/fixed-frame-study"
def output : System.FilePath := "/Users/ovm/.codex/worktrees/hook-deadline-baseline/eggshell/docs/candidates/source-page-reuse"
def read (path : System.FilePath) : IO Json := do IO.ofExcept (Json.parse (← IO.FS.readFile path))
def hash (path : System.FilePath) : IO String := do
  let result ← IO.Process.output {cmd := "/usr/bin/shasum",args := #["-a","256",path.toString]}
  unless result.exitCode == 0 do throw (IO.userError "cleanup identity unavailable")
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
  unless evidence.getObjValD "diagnosticOnly" == toJson true &&
      evidence.getObjValD "adopted" == toJson false && (← (output/"diagnostic.patch").pathExists) do
    throw (IO.userError "diagnostic evidence is incomplete")
  let mut recording := #[]
  for entry in ← base.readDir do
    if entry.fileName.startsWith "source-page-reuse-" && entry.fileName.endsWith ".guard.json" &&
        !entry.fileName.startsWith "source-page-reuse-cleanup" then
      let guard ← read entry.path
      unless guard.getObjValD "state" == toJson "finished" && guard.getObjValD "ownedPids" == toJson (#[] : Array Nat) do
        throw (IO.userError "diagnostic work is still owned")
      if entry.fileName.startsWith "source-page-reuse-records" then
        recording := recording.push (entry.fileName,guard,← IO.FS.readFile (base/(entry.fileName.replace ".guard.json" ".log")))
  IO.FS.writeFile (output/"recording-guards.json") ((toJson recording).compress++"\n")
  let (before,after) ← IO.ofExcept (fromJson? (evidence.getObjValD "workerSourceHashes") : Except String (String × String))
  let source := base/"interest-traffic-core/Eggshell/Worker.lean"
  let original := base/"source-page-reuse-baseline-core/Eggshell/Worker.lean"
  unless (← hash source) == after && (← hash original) == before do
    throw (IO.userError "worker source changed after sealing")
  let unchanged ← IO.ofExcept (fromJson? (evidence.getObjValD "unchanged") : Except String (Array (String × String)))
  for (name,expected) in unchanged do
    unless (← hash (base/"interest-traffic-core/Eggshell"/name)) == expected do
      throw (IO.userError "non-diagnostic source changed after sealing")
  for (directory,key) in [("source-page-reuse-build","auditRuntimeSha256"),("source-page-profile-build","profileRuntimeSha256")] do
    unless toJson (← hash (base/directory/"StudyMain")) == evidence.getObjValD key do
      throw (IO.userError "diagnostic executable changed after sealing")
  unless (← hash (base/"owner-binding-build/StudyMain")) ==
      "613e3ba59e2bdd9689a5fdf2eae7fbbcddad850c0f6cd450419069bc10b79266" do
    throw (IO.userError "retained candidate executable changed")
  let fixture := base/"frontend-quiescence-fixture-small1"
  let heads ← (List.range 16).toArray.mapM fun owner => read (fixture/"work.project/owners"/toString owner/"source.egg/head")
  unless toJson heads == (← read (fixture/"frozen-readback.json")).getObjValD "sourceHeads" do
    throw (IO.userError "frozen original cut changed")
  IO.FS.writeFile source (← IO.FS.readFile original)
  unless (← hash source) == before do throw (IO.userError "diagnostic worker was not restored exactly")
  let mut removed := #[]
  for name in ["source-page-reuse-audit1-result","source-page-reuse-audit1-private",
      "source-page-reuse-lexical1-result","source-page-reuse-meaning1-result","source-page-reuse-sample1-result",
      "source-page-reuse-build","source-page-profile-build","source-page-reuse-baseline-core",
      "source-page-reuse-build-settings.json","source-page-profile-build-settings.json",
      "interest-traffic-core/tools/research/ProjectPageReuseChecks.lean"] do
    let path := base/name
    if ← path.pathExists then removed := removed.push (path.toString,← erase path)
  for entry in ← base.readDir do
    if entry.fileName.startsWith "source-page-reuse-" && !entry.fileName.startsWith "source-page-reuse-cleanup" &&
        (entry.fileName.endsWith ".log" || entry.fileName.endsWith ".guard-settings.json") then
      removed := removed.push (entry.path.toString,← erase entry.path)
  let receipt := Json.mkObj [("removed",toJson removed),
    ("apparentBytes",toJson (removed.foldl (fun total item => total+item.2) 0)),
    ("diagnosticSourceRestored",toJson true),("workerSha256",toJson before),
    ("originalHeadsUnchanged",toJson true),("activeRuntime",toJson "owner-binding-build/StudyMain"),
    ("archivesCreated",toJson false),("adopted",toJson false)]
  IO.FS.writeFile (output/"cleanup.json") (receipt.pretty++"\n")
  IO.println (receipt.getObjValD "apparentBytes").compress
