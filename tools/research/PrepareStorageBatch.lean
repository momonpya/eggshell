import Lean.Data.Json.Parser
import Lean.Data.Json.FromToJson
open Lean
def main : IO Unit := do
  let active : System.FilePath := "/Users/ovm/.codex/experiments/eggshell/feedback-pilot-20261028"
  let project := "/Users/ovm/.codex/worktrees/hook-deadline-baseline/eggshell"
  let path := active / "storage-pending.settings.json"
  unless !(← path.pathExists) do throw (IO.userError "preserve previous batch settings")
  let command := #["/Users/ovm/.elan/toolchains/leanprover--lean4---v4.33.0/bin/lean","-M1024","--run",
    project ++ "/tools/research/ReplayPendingStorage.lean",(active / "usage-authorized-plan.json").toString,
    (active / "usage-history-start/data/sessions/01a17f26-8be8-7430-94ff-3b11b52cd73f/checkpoints").toString,
    (active / "storage-payload/StudyMain").toString,(active / "storage-pending").toString]
  IO.FS.writeFile path (Json.mkObj [("command",toJson command),("cwd",toJson project),
    ("ownedPrefixes",toJson #[active.toString]),("limitRssKiB",toJson (3670016 : Nat)),
    ("minFreeKiB",toJson (2097152 : Nat)),
    ("record",toJson (active / "storage-pending.guard.json").toString)]).pretty
