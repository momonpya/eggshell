import Lean.Data.Json.FromToJson
import Lean.Data.Json.Parser
open Lean
def base : System.FilePath := "/Users/ovm/.codex/experiments/eggshell/scope-token-study-20261028/fixed-frame-study"
def output : System.FilePath := "/Users/ovm/.codex/worktrees/hook-deadline-baseline/eggshell/docs/candidates/shared-startup"
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
    if entry.fileName.startsWith "shared-startup-" && entry.fileName.endsWith ".guard.json" &&
        !entry.fileName.startsWith "shared-startup-cleanup" then
      let guard ← IO.ofExcept (Json.parse (← IO.FS.readFile entry.path))
      unless guard.getObjValD "state" == toJson "finished" && guard.getObjValD "ownedPids" == toJson (#[] : Array Nat) do
        throw (IO.userError "controlled work is still owned")
      if entry.fileName.startsWith "shared-startup-records" || entry.fileName.startsWith "shared-startup-details" then
        recording := recording.push (entry.fileName,guard,← IO.FS.readFile (base/(entry.fileName.replace ".guard.json" ".log")))
  for name in ["candidate.patch","evidence.json","stage-details.json","summary.json","laws.txt","contract-audit.txt"] do
    unless ← (output/name).pathExists do throw (IO.userError "compact evidence is incomplete")
  IO.FS.writeFile (output/"recording-guards.json") ((toJson recording).compress++"\n")
  let mut removed := #[]
  for name in ["shared-startup-fixture-shared-startup-startup1","shared-startup-fixture-shared-startup-readback1"] do
    let path := base/name
    if ← path.pathExists then removed := removed.push (path.toString,← erase path)
  for entry in ← base.readDir do
    if entry.fileName.startsWith "shared-startup-" && !entry.fileName.startsWith "shared-startup-cleanup" &&
        (entry.fileName.endsWith ".log" || entry.fileName.endsWith ".guard-settings.json") then
      removed := removed.push (entry.path.toString,← erase entry.path)
  let receipt := Json.mkObj [("removed",toJson removed),
    ("apparentBytes",toJson (removed.foldl (fun n item => n+item.2) 0)),("archivesCreated",toJson false),
    ("activeDiagnostic",toJson "frontend-quiescence-fixture-small1"),
    ("activeRuntime",toJson "shared-startup-build/StudyMain"),("neededComparisonAndBuildInputsRetained",toJson true)]
  IO.FS.writeFile (output/"cleanup.json") (receipt.pretty++"\n")
  IO.println (receipt.getObjValD "apparentBytes").compress
