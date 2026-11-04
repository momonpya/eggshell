import Lean.Data.Json.FromToJson
import Lean.Data.Json.Parser
open Lean

def base : System.FilePath := "/Users/ovm/.codex/experiments/eggshell/scope-token-study-20261028/fixed-frame-study"
def output : System.FilePath := "/Users/ovm/.codex/worktrees/hook-deadline-baseline/eggshell/docs/candidates/front-traffic"

partial def erase (path : System.FilePath) : IO Nat := do
  let metadata ← path.symlinkMetadata
  if metadata.type == .dir then
    let mut bytes := 0
    for child in ← path.readDir do bytes := bytes + (← erase child.path)
    IO.FS.removeDir path
    return bytes
  else
    IO.FS.removeFile path
    return metadata.byteSize.toNat

def main : IO Unit := do
  for entry in ← base.readDir do
    if entry.fileName.startsWith "front-traffic-" && entry.fileName.endsWith ".guard.json" then
      let prior ← IO.ofExcept (Json.parse (← IO.FS.readFile entry.path))
      unless prior.getObjValD "state" == toJson "finished" && prior.getObjValD "ownedPids" == toJson (#[] : Array Nat) do
        throw (IO.userError "controlled work is still owned")
  let record ← IO.ofExcept (Json.parse (← IO.FS.readFile (output/"native-trials.json")))
  unless ((record.getObjValAs? (Array Json) "trials").toOption.getD #[]).size == 7 &&
      (← (output/"profile-observations.json").pathExists) && (← (output/"candidate.patch").pathExists) do
    throw (IO.userError "compact evidence has not been sealed")
  let mut removed := #[]
  for name in ["preflight1","preflight2","preflight3","small1","small2","small3","profile1","deadlines1","deadlines2","deadlines3"] do
    let path := base/("front-traffic-fixture-"++name)
    if ← path.pathExists then
      let bytes ← erase path
      removed := removed.push (path.toString,bytes)
  for entry in ← base.readDir do
    if entry.fileName.startsWith "front-traffic-" &&
        (entry.fileName.endsWith ".log" || entry.fileName.endsWith ".guard-settings.json") then
      let bytes ← erase entry.path
      removed := removed.push (entry.path.toString,bytes)
  for name in ["failed-writers.json","failed-guard.json","preflight-guard.json"] do
    let path := output/name
    if ← path.pathExists then
      let bytes ← erase path
      removed := removed.push (path.toString,bytes)
  let result := Json.mkObj [("removed",toJson removed),("apparentBytes",toJson (removed.foldl (fun n item => n+item.2) 0)),
    ("archivesCreated",toJson false),("sourceAndControlRuntimesRetained",toJson true)]
  IO.FS.writeFile (output/"cleanup.json") (result.pretty++"\n")
  IO.println result.compress
