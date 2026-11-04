import Lean.Data.Json.FromToJson
import Lean.Data.Json.Parser
open Lean
def base : System.FilePath := "/Users/ovm/.codex/experiments/eggshell/scope-token-study-20261028/fixed-frame-study"
def output : System.FilePath := "/Users/ovm/.codex/worktrees/hook-deadline-baseline/eggshell/docs/candidates/query-work"
def hash (path : System.FilePath) : IO String := do
  let value ← IO.Process.output {cmd := "/usr/bin/shasum",args := #["-a","256",path.toString]}
  unless value.exitCode == 0 do throw (IO.userError "source identity hashing failed")
  return (value.stdout.splitOn " ").head!
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
  let mut recording := #[]
  for entry in ← base.readDir do
    if entry.fileName.startsWith "query-work-" && entry.fileName.endsWith ".guard.json" &&
        !entry.fileName.startsWith "query-work-cleanup" then
      let guard ← IO.ofExcept (Json.parse (← IO.FS.readFile entry.path))
      unless guard.getObjValD "state" == toJson "finished" && guard.getObjValD "ownedPids" == toJson (#[] : Array Nat) do
        throw (IO.userError "controlled work is still owned")
      if entry.fileName.startsWith "query-work-records" then
        recording := recording.push (entry.fileName,guard,← IO.FS.readFile (base/(entry.fileName.replace ".guard.json" ".log")))
  for name in ["candidate.patch","evidence.json","summary.json","laws.txt","contract-audit.txt","parent-stack.txt","candidate-stack.txt"] do
    unless ← (output/name).pathExists do throw (IO.userError "compact evidence is incomplete")
  IO.FS.writeFile (output/"recording-guards.json") ((toJson recording).compress++"\n")
  let evidence ← IO.ofExcept (Json.parse (← IO.FS.readFile (output/"evidence.json")))
  let identities ← IO.ofExcept (evidence.getObjValAs? (Array String) "sourceHashes")
  unless identities.size == 2 do throw (IO.userError "missing candidate/parent source identities")
  let current := base/"interest-traffic-core/Eggshell/Handoff.lean"
  let parent := base/"query-work-baseline-core/Eggshell/Handoff.lean"
  unless (← hash current) == identities[1]! && (← hash parent) == identities[0]! do
    throw (IO.userError "source changed since candidate evidence was sealed")
  IO.FS.writeFile current (← IO.FS.readFile parent)
  unless (← hash current) == identities[0]! do throw (IO.userError "failed to restore isolated parent")
  let response ← IO.FS.readFile (base/"shared-startup-build/runtime.rsp")
  unless !(response.contains ((base/"query-work-build").toString)) do throw (IO.userError "parent still depends on rejected build")
  IO.FS.writeFile (output/"rejection.json") ((Json.mkObj [("decision",toJson "Rejected: no verified whole-hook or load improvement"),
    ("parentSourceSha256",toJson identities[0]!),("candidateSourceSha256",toJson identities[1]!),
    ("parentRestored",toJson true),("activeRuntime",toJson "shared-startup-build/StudyMain"),
    ("adopted",toJson false)]).pretty++"\n")
  let mut removed := #[]
  for tag in ["query-work-profile1","query-work-profile2","query-work-profile3","query-work-sample1",
      "query-work-sample2","query-work-candidate1","query-work-candidate-sample1","query-work-readback1"] do
    let path := base/("query-work-fixture-"++tag)
    if ← path.pathExists then removed := removed.push (path.toString,← erase path)
  for name in ["query-work-build","query-work-build-settings.json","query-work-baseline-core"] do
    let path := base/name
    if ← path.pathExists then removed := removed.push (path.toString,← erase path)
  for entry in ← base.readDir do
    if entry.fileName.startsWith "query-work-" && !entry.fileName.startsWith "query-work-cleanup" &&
        (entry.fileName.endsWith ".log" || entry.fileName.endsWith ".guard-settings.json") then
      removed := removed.push (entry.path.toString,← erase entry.path)
  let receipt := Json.mkObj [("removed",toJson removed),
    ("apparentBytes",toJson (removed.foldl (fun n item => n+item.2) 0)),("archivesCreated",toJson false),
    ("activeDiagnostic",toJson "frontend-quiescence-fixture-small1"),
    ("activeRuntime",toJson "shared-startup-build/StudyMain"),("neededComparisonAndBuildInputsRetained",toJson true)]
  IO.FS.writeFile (output/"cleanup.json") (receipt.pretty++"\n")
  IO.println (receipt.getObjValD "apparentBytes").compress
