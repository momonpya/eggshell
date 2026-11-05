import Lean.Data.Json.FromToJson
open Lean
def base : System.FilePath := "/Users/ovm/.codex/experiments/eggshell/scope-token-study-20261028/fixed-frame-study"
def workspace : System.FilePath := "/Users/ovm/.codex/worktrees/hook-deadline-baseline/eggshell"
def main (args : List String) : IO Unit := do
  let [tag,mode] := args | throw (IO.userError "fresh protocol tag and mode required")
  unless tag.startsWith "source-protocol-" && !tag.contains '/' &&
      (["external","hosted","overlap","overlap-no-trace"].contains mode) &&
      !(← (base/(tag++".guard.json")).pathExists) do
    throw (IO.userError "preserve preceding source protocol trial")
  let root := base/(tag++"-result")
  let environment := #["/usr/bin/env","LEAN_NUM_THREADS=1","EGGSHELL_DATA_ROOT="++(root/"private").toString,
    "EGGSHELL_CONFIG="++(root/"eggshell.toml").toString,"PLUGIN_ROOT="++(base/"worker-cpu-target").toString,
    "EGGSHELL_TRACE_SERVICE_PROFILE="++(if mode == "overlap" then "1" else "0")]
  let command := if mode.startsWith "overlap" then environment++#[
    (base/"source-observer-build/StudyMain").toString,"observe-source-overlap",root.toString,
    (base/"hosted-endpoint-build/StudyMain").toString,"f332d24c852a0b52063b07ecb651ff37362ba7c644aa918b09e8e37213feb276"]
    else environment++#[(base/"source-protocol-build/StudyMain").toString,"source-protocol-study",root.toString,
    (base/"hosted-endpoint-build/StudyMain").toString,"f332d24c852a0b52063b07ecb651ff37362ba7c644aa918b09e8e37213feb276",mode]
  IO.FS.writeFile (base/(tag++".guard-settings.json")) (Json.mkObj [("command",toJson command),
    ("cwd",toJson workspace.toString),("record",toJson (base/(tag++".guard.json")).toString),
    ("ownedPrefixes",toJson #[base.toString]),("limitRssKiB",toJson (3670016 : Nat)),
    ("minFreeKiB",toJson (2097152 : Nat))]).pretty
