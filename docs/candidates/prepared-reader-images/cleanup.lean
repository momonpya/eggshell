import Lean.Data.Json.FromToJson
import Lean.Data.Json.Parser
open Lean
def base : System.FilePath := "/Users/ovm/.codex/experiments/eggshell/scope-token-study-20261028/fixed-frame-study"
def output : System.FilePath := "/Users/ovm/.codex/worktrees/hook-deadline-baseline/eggshell/docs/candidates/prepared-reader-images"
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
  for name in ["candidate.patch","evidence.json","laws.txt","contract-audit.txt"] do
    unless ← (output/name).pathExists do throw (IO.userError "sealed candidate evidence is incomplete")
  let mut recording := #[]
  for entry in ← base.readDir do
    if entry.fileName.startsWith "prepared-reader-images-" && entry.fileName.endsWith ".guard.json" &&
        !entry.fileName.startsWith "prepared-reader-images-cleanup" then
      let guard ← read entry.path
      unless guard.getObjValD "state" == toJson "finished" && guard.getObjValD "ownedPids" == toJson (#[] : Array Nat) do
        throw (IO.userError "controlled work is still owned")
      if entry.fileName.startsWith "prepared-reader-images-records" then
        recording := recording.push (entry.fileName,guard,← IO.FS.readFile (base/(entry.fileName.replace ".guard.json" ".log")))
  IO.FS.writeFile (output/"recording-guards.json") ((toJson recording).compress++"\n")
  let evidence ← read (output/"evidence.json")
  let identities ← IO.ofExcept (fromJson? (evidence.getObjValD "sourceHashes") : Except String (Array (String × Option String × String)))
  for (name,before,current) in identities do
    unless (← hash (base/"interest-traffic-core/Eggshell"/name)) == current do
      throw (IO.userError "candidate source changed after sealing")
    if let some before := before then
      unless (← hash (base/"prepared-reader-images-baseline-core/Eggshell"/name)) == before do
        throw (IO.userError "captured parent source changed")
  unless toJson (← hash (base/"prepared-reader-images-build/StudyMain")) == evidence.getObjValD "runtimeSha256" do
    throw (IO.userError "candidate runtime changed after sealing")
  unless !(← IO.FS.readFile (base/"prepared-reader-images-build/runtime.rsp")).contains
      (base/"prepared-reader-images-fixture-build").toString do
    throw (IO.userError "active candidate depends on ended fixture builder")
  let source := base/"frontend-quiescence-fixture-small1"
  let heads ← (List.range 16).toArray.mapM fun owner => read (source/"work.project/owners"/toString owner/"source.egg/head")
  unless toJson heads == (← read (source/"frozen-readback.json")).getObjValD "sourceHeads" do
    throw (IO.userError "original cut changed")
  let mut removed := #[]
  for entry in ← base.readDir do
    if entry.fileName.startsWith "prepared-reader-images-" &&
        (entry.fileName.endsWith "-result" || entry.fileName.endsWith "-private") then
      removed := removed.push (entry.path.toString,← erase entry.path)
  for name in ["prepared-reader-images-synthetic","prepared-reader-images-fixture-build",
      "prepared-reader-images-fixture-build-settings.json"] do
    let path := base/name
    if ← path.pathExists then removed := removed.push (path.toString,← erase path)
  for entry in ← base.readDir do
    if entry.fileName.startsWith "prepared-reader-images-" && !entry.fileName.startsWith "prepared-reader-images-cleanup" &&
        (entry.fileName.endsWith ".log" || entry.fileName.endsWith ".guard-settings.json" || entry.fileName.endsWith ".runtime.sha256") then
      removed := removed.push (entry.path.toString,← erase entry.path)
  let receipt := Json.mkObj [("removed",toJson removed),
    ("apparentBytes",toJson (removed.foldl (fun total item => total+item.2) 0)),
    ("originalHeadsUnchanged",toJson true),("archivesCreated",toJson false),("adopted",toJson false),
    ("retainedRuntime",toJson "prepared-reader-images-build/StudyMain"),
    ("parentRuntime",toJson "owner-binding-build/StudyMain"),("candidateRetainedInIsolation",toJson true)]
  IO.FS.writeFile (output/"cleanup.json") (receipt.pretty++"\n")
  IO.println (receipt.getObjValD "apparentBytes").compress
