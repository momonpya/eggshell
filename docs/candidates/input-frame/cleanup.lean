import Lean.Data.Json.FromToJson
import Lean.Data.Json.Parser
open Lean
def base : System.FilePath := "/Users/ovm/.codex/experiments/eggshell/scope-token-study-20261028/fixed-frame-study"
def output : System.FilePath := "/Users/ovm/.codex/worktrees/hook-deadline-baseline/eggshell/docs/candidates/input-frame"
def read (path : System.FilePath) : IO Json := do IO.ofExcept (Json.parse (← IO.FS.readFile path))
def hash (path : System.FilePath) : IO String := do
  let result ← IO.Process.output {cmd := "/usr/bin/shasum",args := #["-a","256",path.toString]}
  unless result.exitCode == 0 do throw (IO.userError "cleanup source identity failed")
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
    unless ← (output/name).pathExists do throw (IO.userError "compact evidence is incomplete")
  let mut recording := #[]
  for entry in ← base.readDir do
    if entry.fileName.startsWith "input-frame-" && entry.fileName.endsWith ".guard.json" &&
        !entry.fileName.startsWith "input-frame-cleanup" then
      let guard ← read entry.path
      unless guard.getObjValD "state" == toJson "finished" && guard.getObjValD "ownedPids" == toJson (#[] : Array Nat) do
        throw (IO.userError "controlled work is still owned")
      if entry.fileName.startsWith "input-frame-records" then
        recording := recording.push (entry.fileName,guard,← IO.FS.readFile (base/(entry.fileName.replace ".guard.json" ".log")))
  IO.FS.writeFile (output/"recording-guards.json") ((toJson recording).compress++"\n")
  let evidence ← read (output/"evidence.json")
  let identities ← IO.ofExcept (fromJson? (evidence.getObjValD "sourceHashes") : Except String (Array (String × String × String)))
  for (name,prior,current) in identities do
    unless (← hash (base/"input-frame-baseline-core/Eggshell"/name)) == prior &&
        (← hash (base/"interest-traffic-core/Eggshell"/name)) == current do
      throw (IO.userError "candidate changed after sealing")
  unless (← hash (base/"input-frame-build/StudyMain")) ==
      (evidence.getObjValAs? String "runtimeSha256").toOption.getD "" do throw (IO.userError "candidate runtime changed")
  let source := base/"frontend-quiescence-fixture-small1"
  let heads ← (List.range 16).toArray.mapM fun owner => read (source/"work.project/owners"/toString owner/"source.egg/head")
  unless toJson heads == (← read (source/"frozen-readback.json")).getObjValD "sourceHeads" do throw (IO.userError "original cut changed")
  let mut removed := #[]
  for entry in ← base.readDir do
    if entry.fileName.startsWith "input-frame-fixture-" then removed := removed.push (entry.path.toString,← erase entry.path)
  for entry in ← base.readDir do
    if entry.fileName.startsWith "input-frame-" && !entry.fileName.startsWith "input-frame-cleanup" &&
        (entry.fileName.endsWith ".log" || entry.fileName.endsWith ".guard-settings.json") then
      removed := removed.push (entry.path.toString,← erase entry.path)
  let receipt := Json.mkObj [("removed",toJson removed),("apparentBytes",toJson (removed.foldl (fun n item => n+item.2) 0)),
    ("archivesCreated",toJson false),("candidateRetainedInIsolation",toJson true),
    ("retainedRuntime",toJson "input-frame-build/StudyMain"),("controlRuntime",toJson "prepared-lexical-build/StudyMain"),
    ("retainedOriginalCut",toJson "frontend-quiescence-fixture-small1"),("originalHeadsUnchanged",toJson true),
    ("adopted",toJson false)]
  IO.FS.writeFile (output/"cleanup.json") (receipt.pretty++"\n")
  IO.println (receipt.getObjValD "apparentBytes").compress
