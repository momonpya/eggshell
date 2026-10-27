import Lean.Data.Json.Parser
import Lean.Data.Json.FromToJson
open Lean

/-- Temporarily mount the original failing publication at its original path.
The current DB, including its prepared views, is moved aside and restored. -/
def main (args : List String) : IO Unit := do
  let [mode] := args | throw (IO.userError "prepare | restore")
  let active : System.FilePath := "/Users/ovm/.codex/experiments/eggshell/feedback-pilot-20261028"
  let base : System.FilePath := "/Users/ovm/.codex/experiments/eggshell/verified-winner-20261027"
  let root := active / "storage-integration"
  let database := active / "usage-history-start/work.egg"
  let held := root / "current-held.egg"
  if mode == "restore" then
    let guard ← IO.ofExcept (Json.parse (← IO.FS.readFile (root / "service-replay.guard.json")))
    unless guard.getObjValD "state" == toJson "finished" &&
        guard.getObjValD "ownedPids" == toJson (#[] : Array Nat) do
      throw (IO.userError "stop the owned service replay before restoring the current DB")
    let output := root / "service-output.egg"
    unless (← held.pathExists) && !(← output.pathExists) do throw (IO.userError "preserve service output and current DB")
    IO.FS.rename database output
    IO.FS.rename held database
    unless (← IO.FS.readFile (database / "head")) == (← IO.FS.readFile (root / "held-head")) do
      throw (IO.userError "restored current publication differs from the held input")
    IO.FS.writeFile (root / "restored.json") (Json.mkObj [
      ("currentHeadRestored",toJson true),("currentDerivedDirectoriesRetained",toJson true)]).compress
    return
  unless mode == "prepare" && !(← held.pathExists) && !(← (root / "held-head").pathExists) do
    throw (IO.userError "preserve an already mounted replay")
  IO.FS.writeFile (root / "held-head") (← IO.FS.readFile (database / "head"))
  IO.FS.rename database held
  let restored ← IO.Process.output {
    cmd := (active / "controller/StudyMain").toString
    args := #["runtime","restore",(active / "row-replay-baseline/before.egg").toString,database.toString]}
  unless restored.exitCode == 0 do throw (IO.userError restored.stderr)
  let planPath := active / "usage-authorized-plan.json"
  let plan ← IO.ofExcept (Json.parse (← IO.FS.readFile planPath))
  let environment ← IO.ofExcept (plan.getObjValAs? (Array (String × Option String)) "environment")
  let environment := environment.filter (·.1 != "EGGSHELL_PREFIX") ++
    #[("EGGSHELL_PREFIX",some (root / "prefix").toString)]
  let unset := environment.filterMap fun row => if row.2.isNone then some #["-u",row.1] else none
  let variables := environment.filterMap fun row => row.2.map (fun value => row.1 ++ "=" ++ value)
  let checkpoint := active / "usage-history-start/data/sessions/01a17f26-8be8-7430-94ff-3b11b52cd73f/checkpoints/22e597bf8b18e5687e1bc0412a2fc924052a7a93de60f5ec1f1b8419bc93aa55.json"
  let command := #["/usr/bin/env"] ++ unset.flatten ++ variables ++
    #[(base / "storage-service-build/StudyMain").toString,"service",(root / "prefix/libexec/eggshell").toString,
      planPath.toString,checkpoint.toString,(root / "service-replay").toString]
  IO.FS.writeFile (root / "service-replay.settings.json") (Json.mkObj [("command",toJson command),
    ("cwd",toJson "/Users/ovm/.codex/worktrees/hook-deadline-baseline/eggshell"),
    ("ownedPrefixes",toJson #[active.toString,base.toString]),("limitRssKiB",toJson (3670016 : Nat)),
    ("minFreeKiB",toJson (2097152 : Nat)),("record",toJson (root / "service-replay.guard.json").toString)]).pretty
