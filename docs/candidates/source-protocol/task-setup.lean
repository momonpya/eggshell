import Lean.Data.Json.FromToJson
open Lean
def base : System.FilePath := "/Users/ovm/.codex/experiments/eggshell/scope-token-study-20261028/fixed-frame-study"
def workspace : System.FilePath := "/Users/ovm/.codex/worktrees/hook-deadline-baseline/eggshell"
def main (args : List String) : IO Unit := do
  let [tag,mode] := args | throw (IO.userError "fresh task observer tag/mode required")
  unless (tag.startsWith "task-observer-" || tag.startsWith "task-waiter-") && !tag.contains '/' &&
      ["policy","profile","burst80","records","retire","retire-builds","verify"].contains mode && !(← (base/(tag++".guard.json")).pathExists) do
    throw (IO.userError "preserve preceding task observer trial")
  let root := base/(tag++"-result")
  let runtime := base/(if ["records","retire","retire-builds","verify"].contains mode then "hosted-endpoint-build/StudyMain" else
    if tag.startsWith "task-waiter-" then "task-waiter-build/StudyMain" else "task-observer-build/StudyMain")
  let sealed ← IO.Process.output {cmd := "/usr/bin/shasum",args := #["-a","256",runtime.toString]}
  unless sealed.exitCode == 0 do throw (IO.userError "cannot seal task observer runtime")
  let sha := (sealed.stdout.splitOn " ").headD ""
  let command ← if ["records","retire","retire-builds","verify"].contains mode then
      pure (#["/Users/ovm/.elan/toolchains/leanprover--lean4---v4.33.0/bin/lean","-j1","-M512","--run",
        (workspace/"docs/candidates"/(if mode.startsWith "retire" then "shared-leases" else "source-protocol")/
          (if mode.startsWith "retire" then "retire.lean" else "records.lean")).toString]++
        (if mode == "retire" then #["--source-protocol"] else if mode == "retire-builds" then #["--source-protocol-builds"]
          else if mode == "verify" then #["verify"] else #[]))
    else if mode == "policy" then
      pure #["/usr/bin/env","LEAN_NUM_THREADS=1",runtime.toString,"task-watch-checks",root.toString]
    else do
      let aliasPath := base/"worker-cpu-target/bin/eggshelld"
      unless (← aliasPath.symlinkMetadata).type == .symlink do throw (IO.userError "target is not an isolated symlink")
      IO.FS.removeFile aliasPath
      let linked ← IO.Process.output {cmd := "/bin/ln",args := #["-s",runtime.toString,aliasPath.toString]}
      unless linked.exitCode == 0 do throw (IO.userError "cannot select task observer runtime")
      let call := #["/usr/bin/env","LEAN_NUM_THREADS=1","EGGSHELL_DATA_ROOT="++(root/"private").toString,
        "EGGSHELL_CONFIG="++(root/"eggshell.toml").toString,"PLUGIN_ROOT="++(base/"worker-cpu-target").toString,
        "EGGSHELL_TRACE_SERVICE_PROFILE=1",(base/"session-dispatch-client-build/StudyMain").toString,
        root.toString,runtime.toString,sha]
      pure (if mode == "burst80" then call.push "burst80" else call)
  IO.FS.writeFile (base/(tag++".guard-settings.json")) (Json.mkObj [("command",toJson command),
    ("cwd",toJson workspace.toString),("record",toJson (base/(tag++".guard.json")).toString),
    ("ownedPrefixes",toJson #[base.toString]),("limitRssKiB",toJson (3670016 : Nat)),
    ("minFreeKiB",toJson (2097152 : Nat))]).pretty
