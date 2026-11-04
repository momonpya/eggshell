import Lean.Data.Json.FromToJson
import Lean.Data.Json.Parser
open Lean
def base : System.FilePath := "/Users/ovm/.codex/experiments/eggshell/scope-token-study-20261028/fixed-frame-study"
def output : System.FilePath := "/Users/ovm/.codex/worktrees/hook-deadline-baseline/eggshell/docs/candidates/single-search"
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
    if ["single-search-","direct-numerical-","front-input-","front-traffic-","front-manager-"].any (fun stem => entry.fileName.startsWith stem) &&
        entry.fileName.endsWith ".guard.json" then
      let guard ← IO.ofExcept (Json.parse (← IO.FS.readFile entry.path))
      unless guard.getObjValD "state" == toJson "finished" && guard.getObjValD "ownedPids" == toJson (#[] : Array Nat) do
        throw (IO.userError "controlled work is still owned")
  for name in ["guards.json","failed-attempts.json","identity.json","candidate.patch","policy.json",
      "summary.json","native-reports.json","native-trials.json","native-stages.json","logs.json","laws.txt","contract-audit.txt"] do
    unless ← (output/name).pathExists do throw (IO.userError "compact evidence is incomplete")
  let mut removed := #[]
  for name in ["single-search-fixture-policy1","single-search-fixture-readers1","direct-numerical-fixture-small1"] do
    let path := base/name
    if ← path.pathExists then removed := removed.push (path.toString,← erase path)
  for entry in ← base.readDir do
    if (entry.fileName.startsWith "single-search-" &&
        (entry.fileName.endsWith ".guard-settings.json" || entry.fileName.endsWith ".log")) ||
        entry.fileName == "direct-numerical-small1.log" then
      removed := removed.push (entry.path.toString,← erase entry.path)
  let result := Json.mkObj [("removed",toJson removed),
    ("apparentBytes",toJson (removed.foldl (fun n item => n+item.2) 0)),("archivesCreated",toJson false),
    ("activeDiagnostic",toJson "single-search-fixture-small1"),
    ("activeControlAndBuildInputsRetained",toJson true)]
  IO.FS.writeFile (output/"cleanup.json") (result.pretty++"\n")
  IO.println (Json.mkObj [("apparentBytes",result.getObjValD "apparentBytes"),("archivesCreated",toJson false)]).compress
