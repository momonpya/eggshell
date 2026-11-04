import Lean.Data.Json.FromToJson
import Lean.Data.Json.Parser
open Lean

def base : System.FilePath := "/Users/ovm/.codex/experiments/eggshell/scope-token-study-20261028/fixed-frame-study"
def folder : System.FilePath := "/Users/ovm/.codex/worktrees/hook-deadline-baseline/eggshell/docs/candidates/front-managers"
def read (path : System.FilePath) : IO Json := do IO.ofExcept (Json.parse (← IO.FS.readFile path))
partial def bytes (path : System.FilePath) : IO Nat := do
  let stat ← path.symlinkMetadata
  if stat.type != .dir then return stat.byteSize.toNat
  let mut total := 0
  for entry in ← path.readDir do total := total+(← bytes entry.path)
  return total

def main : IO Unit := do
  unless (← (folder/"identity.json").pathExists) && !(← (folder/"cleanup.json").pathExists) do
    throw (IO.userError "seal evidence first; retain earlier deletion accounting")
  for entry in ← base.readDir do
    if entry.fileName.startsWith "front-manager-" && entry.fileName.endsWith ".guard.json" then
      let row ← read entry.path
      unless row.getObjValD "state" == toJson "finished" && row.getObjValD "ownedPids" == toJson (#[] : Array Nat) do
        throw (IO.userError "controlled work still owns resources")
  let mut earlier := #[]
  for (tag,name) in [("shared1","front-manager-shared1.sha256"),("shared2","front-manager-shared2.sha256")] do
    let path := base/name
    if ← path.pathExists then
      earlier := earlier.push (Json.mkObj [("trial",toJson tag),
        ("sha256",toJson ((← IO.FS.readFile path).take 64).toString)])
  IO.FS.writeFile (folder/"earlier-runtimes.json") ((toJson earlier).pretty++"\n")
  let mut remove := #[base/"front-manager-fixture",base/"front-retirement-build",base/"front-retirement-build-settings.json"]
  for entry in ← base.readDir do
    if !entry.fileName.startsWith "front-manager-" then continue
    if entry.fileName.startsWith "front-manager-build9." then continue
    if entry.fileName.endsWith ".log" || entry.fileName.endsWith ".guard.json" ||
        entry.fileName.endsWith ".guard-settings.json" || entry.fileName.endsWith ".sha256" then
      remove := remove.push entry.path
  let mut removed := #[]
  let mut total := 0
  for path in remove do
    if !(← path.pathExists) then continue
    let size ← bytes path
    let stat ← path.symlinkMetadata
    if stat.type == .dir then IO.FS.removeDirAll path else IO.FS.removeFile path
    unless !(← path.pathExists) do throw (IO.userError s!"cleanup did not remove {path}")
    total := total+size
    removed := removed.push (Json.mkObj [("path",toJson path.toString),("apparentBytes",toJson size)])
  let check ← IO.Process.output {cmd := "/usr/bin/shasum",args := #["-a","256","-c",
    "/Users/ovm/.codex/worktrees/hook-deadline-baseline/eggshell/docs/candidates/project-cache/protected-after.sha256"],cwd := some base.toString}
  unless check.exitCode == 0 do throw (IO.userError check.stderr)
  IO.FS.writeFile (folder/"protected-check.txt") check.stdout
  let result := Json.mkObj [("removed",toJson removed),("apparentBytes",toJson total),
    ("archived",toJson false),("protectedVerified",toJson true),
    ("retainedCurrentRuntime",toJson (base/"front-manager-build/StudyMain").toString),
    ("retainedBuildInputs",toJson true)]
  IO.FS.writeFile (folder/"cleanup.json") (result.pretty++"\n")
  IO.println (Json.mkObj [("apparentBytes",toJson total),("removed",toJson removed.size),("archived",toJson false)]).compress
