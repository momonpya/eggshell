import Lean.Data.Json.FromToJson
import Lean.Data.Json.Parser
open Lean
def base : System.FilePath := "/Users/ovm/.codex/experiments/eggshell/scope-token-study-20261028/fixed-frame-study"
def output : System.FilePath := "/Users/ovm/.codex/worktrees/hook-deadline-baseline/eggshell/docs/candidates/direct-numerical"
partial def erase (path : System.FilePath) : IO Nat := do
  let metadata ← path.symlinkMetadata
  if metadata.type == .dir then
    let mut bytes := 0
    for child in ← path.readDir do bytes := bytes+(← erase child.path)
    IO.FS.removeDir path
    return bytes
  IO.FS.removeFile path
  return metadata.byteSize.toNat
def main : IO Unit := do
  for entry in ← base.readDir do
    if ["direct-numerical-","front-input-","front-traffic-","front-manager-"].any (fun stem => entry.fileName.startsWith stem) &&
        entry.fileName.endsWith ".guard.json" then
      let guard ← IO.ofExcept (Json.parse (← IO.FS.readFile entry.path))
      unless guard.getObjValD "state" == toJson "finished" && guard.getObjValD "ownedPids" == toJson (#[] : Array Nat) do
        throw (IO.userError "controlled work is still owned")
  for name in ["guards.json","failed-attempts.json","components.json","numerical-values.json","replay.json",
      "frozen-request.json","actual-response.json","native-trials.json","native-stages.json","stage-summary.json",
      "candidate.patch","identity.json","laws.txt","contract-audit.txt"] do
    unless ← (output/name).pathExists do throw (IO.userError "compact evidence is incomplete")
  let mut removed := #[]
  for name in ["direct-numerical-fixture-components1","direct-numerical-fixture-components2",
      "direct-numerical-fixture-components3","direct-numerical-fixture-replay1","direct-numerical-fixture-readers1",
      "front-input-fixture-diagnostic2"] do
    let path := base/name
    if ← path.pathExists then
      let bytes ← erase path
      removed := removed.push (path.toString,bytes)
  for entry in ← base.readDir do
    if entry.fileName.startsWith "direct-numerical-" &&
        (entry.fileName.endsWith ".guard-settings.json" || entry.fileName.endsWith ".log") &&
        entry.fileName != "direct-numerical-small1.log" then
      let bytes ← erase entry.path
      removed := removed.push (entry.path.toString,bytes)
  let result := Json.mkObj [("removed",toJson removed),("apparentBytes",toJson (removed.foldl (fun n item => n+item.2) 0)),
    ("archivesCreated",toJson false),
    ("activeDiagnostic",toJson "direct-numerical-fixture-small1"),
    ("activeControlAndBuildInputsRetained",toJson true)]
  IO.FS.writeFile (output/"cleanup.json") (result.pretty++"\n")
  IO.println (Json.mkObj [("apparentBytes",result.getObjValD "apparentBytes"),("archivesCreated",toJson false)]).compress
