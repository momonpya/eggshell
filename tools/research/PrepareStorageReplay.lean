import Lean.Data.Json.Parser
import Lean.Data.Json.FromToJson
open Lean

private def root : System.FilePath := "/Users/ovm/.codex/experiments/eggshell/feedback-pilot-20261028"
private def built : System.FilePath := "/Users/ovm/.codex/experiments/eggshell/verified-winner-20261027/storage-build"
def main (args : List String) : IO Unit := do
  let [label] := args | throw (IO.userError "baseline | payload")
  unless ["baseline","payload"].contains label do throw (IO.userError "predeclared storage arms only")
  let app := root / ("storage-" ++ label)
  let output := root / ("row-replay-" ++ label)
  unless !(← app.pathExists) && !(← output.pathExists) do throw (IO.userError "preserve this arm")
  let planPath := root / "usage-authorized-plan.json"
  let plan ← IO.ofExcept (Json.parse (← IO.FS.readFile planPath))
  let environment ← IO.ofExcept (plan.getObjValAs? (Array (String × Option String)) "environment")
  if label == "payload" then
    let restore ← IO.Process.output {
      cmd := (root / "controller/StudyMain").toString
      args := #["runtime","restore",(root / "row-replay-baseline/before.egg").toString,
        ← IO.ofExcept (plan.getObjValAs? String "database")]}
    unless restore.exitCode == 0 do throw (IO.userError restore.stderr)
  IO.FS.createDirAll app
  for name in ["StudyMain","build.json"] do
    let result ← IO.Process.output {cmd := "/bin/cp",args := #["-c",(built / name).toString,(app / name).toString]}
    unless result.exitCode == 0 do throw (IO.userError result.stderr)
  let digest ← IO.Process.output {
    cmd := (root / "controller/StudyMain").toString,args := #["artifacts",(app / "StudyMain").toString]}
  unless digest.exitCode == 0 do throw (IO.userError digest.stderr)
  IO.FS.writeFile (app / "digest.json") digest.stdout
  let unset := environment.filterMap fun row => if row.2.isNone then some #["-u",row.1] else none
  let variables := environment.filterMap fun row => row.2.map (fun value => row.1 ++ "=" ++ value)
  let checkpoint := root / "usage-history-start/data/sessions/01a17f26-8be8-7430-94ff-3b11b52cd73f/checkpoints/22e597bf8b18e5687e1bc0412a2fc924052a7a93de60f5ec1f1b8419bc93aa55.json"
  let command := #["/usr/bin/env"] ++ unset.flatten ++ variables ++
    #[(app / "StudyMain").toString,planPath.toString,checkpoint.toString,output.toString]
  IO.FS.writeFile (root / ("row-replay-" ++ label ++ ".settings.json")) (Json.mkObj [
    ("command",toJson command),("cwd",toJson "/Users/ovm/.codex/worktrees/hook-deadline-baseline/eggshell"),
    ("ownedPrefixes",toJson #[root.toString]),("limitRssKiB",toJson (3670016 : Nat)),
    ("minFreeKiB",toJson (2097152 : Nat)),
    ("record",toJson (root / ("row-replay-" ++ label ++ ".guard.json")).toString)]).pretty
