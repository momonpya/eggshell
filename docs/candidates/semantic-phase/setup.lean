import Lean.Data.Json.FromToJson
open Lean
def base : System.FilePath := "/Users/ovm/.codex/experiments/eggshell/scope-token-study-20261028/fixed-frame-study"
def workspace : System.FilePath := "/Users/ovm/.codex/worktrees/hook-deadline-baseline/eggshell"
def compiler := "/Users/ovm/.elan/toolchains/leanprover--lean4---v4.33.0/bin/lean"
def main (args : List String) : IO Unit := do
  let (tag,extra) ← match args with
    | [tag] => pure (tag,#[])
    | [tag,runtime,verify] => pure (tag,#["EGGSHELL_PROFILE_RUNTIME="++runtime,"EGGSHELL_CHECK_LOCAL_SELECTION="++verify])
    | [tag,runtime,verify,sample] => pure (tag,#["EGGSHELL_PROFILE_RUNTIME="++runtime,
        "EGGSHELL_CHECK_LOCAL_SELECTION="++verify,"EGGSHELL_PROFILE_SAMPLE="++sample])
    | _ => throw (IO.userError "fresh semantic-phase tag and optional runtime/verification required")
  unless tag.startsWith "semantic-phase-" && !(← (base/(tag++".guard.json")).pathExists) do
    throw (IO.userError "preserve previous profile")
  let root := base/(tag++"-result")
  let command := #["/usr/bin/env","LEAN_NUM_THREADS=1","EGGSHELL_DATA_ROOT="++(root/"private").toString,
    "EGGSHELL_CONFIG="++(root/"eggshell.toml").toString,"PLUGIN_ROOT="++(base/"semantic-phase-no-plugin").toString,
    "EGGSHELL_HANDOFF_TRACE="++(root/"handoff.trace").toString,"EGGSHELL_TRACE_SERVICE_PROFILE=1"]++extra++
    #[compiler,"-M512","--run",(workspace/"docs/candidates/semantic-phase/run.lean").toString,root.toString]
  IO.FS.writeFile (base/(tag++".guard-settings.json")) (Json.mkObj [("command",toJson command),
    ("cwd",toJson workspace.toString),("record",toJson (base/(tag++".guard.json")).toString),
    ("ownedPrefixes",toJson #[base.toString]),("limitRssKiB",toJson (3670016 : Nat)),
    ("minFreeKiB",toJson (2097152 : Nat))]).pretty
