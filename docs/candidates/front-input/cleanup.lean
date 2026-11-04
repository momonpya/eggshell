import Lean.Data.Json.FromToJson
import Lean.Data.Json.Parser
open Lean

def base : System.FilePath := "/Users/ovm/.codex/experiments/eggshell/scope-token-study-20261028/fixed-frame-study"
def output : System.FilePath := "/Users/ovm/.codex/worktrees/hook-deadline-baseline/eggshell/docs/candidates/front-input"

partial def erase (path : System.FilePath) : IO Nat := do
  let metadata ← path.symlinkMetadata
  if metadata.type == .dir then
    let mut bytes := 0
    for child in ← path.readDir do bytes := bytes + (← erase child.path)
    IO.FS.removeDir path
    return bytes
  IO.FS.removeFile path
  return metadata.byteSize.toNat

def main : IO Unit := do
  for entry in ← base.readDir do
    if ["front-input-","front-traffic-","front-manager-"].any (fun stem => entry.fileName.startsWith stem) &&
        entry.fileName.endsWith ".guard.json" then
      let prior ← IO.ofExcept (Json.parse (← IO.FS.readFile entry.path))
      unless prior.getObjValD "state" == toJson "finished" && prior.getObjValD "ownedPids" == toJson (#[] : Array Nat) do
        throw (IO.userError "controlled work is still owned")
  for name in ["guards.json","blocked-drain.json","deliveries.json","identity.json","candidate.patch",
      "recovery-checks.json","ready-stage-report.json","ready-input-report.json","ready-drain.json",
      "laws.txt","contract-audit.txt","startup-sample.json","service-key-report.json"] do
    unless ← (output/name).pathExists do throw (IO.userError "compact evidence is incomplete")
  let mut removed := #[]
  for name in ["front-input-fixture-diagnostic1","front-input-fixture-ready1","front-input-fixture-ready2","front-input-inspect.lean"] do
    let path := base/name
    if ← path.pathExists then
      let bytes ← erase path
      removed := removed.push (path.toString,bytes)
  for entry in ← base.readDir do
    if entry.fileName.startsWith "front-input-" &&
        (entry.fileName.endsWith ".log" || entry.fileName.endsWith ".guard-settings.json") then
      let bytes ← erase entry.path
      removed := removed.push (entry.path.toString,bytes)
  let report := Json.mkObj [("removed",toJson removed),
    ("apparentBytes",toJson (removed.foldl (fun n item => n+item.2) 0)),
    ("archivesCreated",toJson false),
    ("retainedActiveInputs",toJson #["front-input-fixture-diagnostic2","front-input-baseline-core",
      "front-input-build","front-traffic-build"]),
    ("reason",toJson "Retain only the current fixed-source diagnostic, active build/control inputs and protected original data. Ended fixtures and raw logs are not archived.")]
  IO.FS.writeFile (output/"cleanup.json") (report.pretty++"\n")
  IO.println report.compress
