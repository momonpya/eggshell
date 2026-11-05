import Lean.Data.Json.FromToJson
import Lean.Data.Json.Parser
open Lean
def base : System.FilePath := "/Users/ovm/.codex/experiments/eggshell/scope-token-study-20261028/fixed-frame-study"
def destination : System.FilePath := "/Users/ovm/.codex/worktrees/hook-deadline-baseline/eggshell/docs/candidates/session-dispatch"
def read (path : System.FilePath) : IO Json := do IO.ofExcept (Json.parse (← IO.FS.readFile path))
def check (ok : Bool) (message : String) : IO Unit := unless ok do throw (IO.userError message)
def hash (path : System.FilePath) : IO String := do
  let result ← IO.Process.output {cmd := "/usr/bin/shasum",args := #["-a","256",path.toString]}
  check (result.exitCode == 0) "cannot check retained input"
  return (result.stdout.splitOn " ").headD ""
partial def bytes (path : System.FilePath) : IO Nat := do
  let metadata ← path.symlinkMetadata
  if metadata.type != .dir then return metadata.byteSize.toNat
  let mut total := 0
  for entry in ← path.readDir do total := total+(← bytes entry.path)
  return total
partial def remove (path : System.FilePath) : IO Unit := do
  if (← path.symlinkMetadata).type == .dir then
    for entry in ← path.readDir do remove entry.path
    IO.FS.removeDir path
  else IO.FS.removeFile path
def main : IO Unit := do
  check (!(← (destination/"cleanup.json").pathExists)) "preserve prior cleanup"
  let verification ← read (destination/"verification.json")
  check (verification.getObjValD "actualOutputs" == toJson (70 : Nat)) "actual bodies were not verified"
  let mut guards := #[]
  let mut paths : Array System.FilePath := #[]
  for entry in ← base.readDir do
    let name := entry.fileName
    unless name.startsWith "session-dispatch-" && !name.startsWith "session-dispatch-cleanup" do continue
    if name.endsWith ".guard.json" then
      let record ← read entry.path
      check (record.getObjValD "state" == toJson "finished" && record.getObjValD "ownedPids" == toJson (#[] : Array Nat)) "live guard blocks cleanup"
      let pid ← IO.ofExcept (record.getObjValAs? Nat "guardPid")
      let probe ← IO.Process.output {cmd := "/bin/ps",args := #["-p",toString pid,"-o","pid="]}
      check (probe.exitCode != 0 && probe.stdout.trimAscii.isEmpty) "guard process remains"
      guards := guards.push (Json.mkObj [("name",toJson name),("record",record)])
    if name.endsWith ".log" || name.endsWith ".guard.json" || name.endsWith ".guard-settings.json" then paths := paths.push entry.path
  for name in ["session-dispatch-builder-fixture","session-dispatch-builder-fixture2","session-dispatch-policy1-result",
    "session-dispatch-policy2-result","session-dispatch-smoke1-result","session-dispatch-control2-result"] do
    if ← (base/name).pathExists then paths := paths.push (base/name)
  let identity ← read (destination/"identity-before.json")
  for key in ["candidate","parent"] do
    let item := identity.getObjValD key
    let path ← IO.ofExcept (item.getObjValAs? String "path")
    check (toJson (← hash (.mk path)) == item.getObjValD "sha256") "needed runtime changed"
  check ((← hash (base/"session-dispatch-client-build/StudyMain")) ==
    (← IO.ofExcept (identity.getObjValAs? String "nativeClientSha256"))) "native client changed"
  for name in ["OperationPlan","OperationPool","PublicationService","PreparedReaders","Worker","Numerical","Handoff","SearchRank"] do
    let suffix := "Eggshell/"++name++".lean"
    check ((← IO.FS.readFile (base/"interest-traffic-core"/suffix)) ==
      (← IO.FS.readFile (base/"session-dispatch-baseline-core"/suffix))) "isolated source was not restored"
  let mut removed := #[]
  for path in paths do removed := removed.push (Json.mkObj [("path",toJson path.toString),("apparentBytes",toJson (← bytes path))])
  IO.FS.writeFile (destination/"guards.json") (toJson guards).pretty
  let report := Json.mkObj [("removed",toJson removed),("archiveCreated",toJson false),
    ("preservedCurrentOriginalFixtureAndNeededBuildInputs",toJson true),("sourceRestored",toJson true),
    ("runtimeIdentitiesUnchanged",toJson true),("completed",toJson false)]
  IO.FS.writeFile (destination/"cleanup.json") report.pretty
  for path in paths do remove path
  IO.FS.writeFile (destination/"cleanup.json") (report.setObjVal! "completed" (toJson true)).pretty
  IO.println (Json.mkObj [("deletedPaths",toJson paths.size),
    ("deletedBytes",toJson (removed.foldl (fun total row => total+(row.getObjValAs? Nat "apparentBytes").toOption.getD 0) 0))]).compress
