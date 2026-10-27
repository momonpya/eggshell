import Lean.Data.Json.Parser
import Lean.Data.Json.FromToJson
open Lean
def main (args : List String) : IO Unit := do
  let active : System.FilePath := "/Users/ovm/.codex/experiments/eggshell/feedback-pilot-20261028"
  let base : System.FilePath := "/Users/ovm/.codex/experiments/eggshell/verified-winner-20261027"
  let (label,database,mode) ← match args with
    | [] => pure ("journal-read",(active / "usage-history-start/work.egg").toString,#[])
    | [label,database] => pure (label,database,#[])
    | ["publication",label,database] => pure (label,database,#["publication"])
    | _ => throw (IO.userError "optional LABEL DATABASE")
  unless !label.isEmpty && label.toList.all (fun c => c.isAlphanum || c == '-') do
    throw (IO.userError "simple report label required")
  let root := active / "storage-integration"
  let settings := root / (label ++ ".settings.json")
  unless !(← settings.pathExists) do throw (IO.userError "preserve prior diagnosis settings")
  let command := #["/usr/bin/env","-u","CODEX_THREAD_ID","-u","CODEX_TURN_ID","LEAN_NUM_THREADS=1",
    "EGGSHELL_DATA_ROOT=" ++ (active / "usage-history-start/data").toString,
    (base / "storage-journal-build/StudyMain").toString] ++ mode ++ #[database,(root / label).toString]
  IO.FS.writeFile settings (Json.mkObj [("command",toJson command),
    ("cwd",toJson "/Users/ovm/.codex/worktrees/hook-deadline-baseline/eggshell"),
    ("ownedPrefixes",toJson #[active.toString,base.toString]),("limitRssKiB",toJson (3670016 : Nat)),
    ("minFreeKiB",toJson (2097152 : Nat)),("record",toJson (root / (label ++ ".guard.json")).toString)]).pretty
