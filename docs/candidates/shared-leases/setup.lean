import Lean.Data.Json.FromToJson
open Lean
def base : System.FilePath := "/Users/ovm/.codex/experiments/eggshell/scope-token-study-20261028/fixed-frame-study"
def workspace : System.FilePath := "/Users/ovm/.codex/worktrees/hook-deadline-baseline/eggshell"
def main (args : List String) : IO Unit := do
  let [tag,mode] := args | throw (IO.userError "fresh shared-leases tag and mode required")
  unless (tag.startsWith "shared-leases-" || tag.startsWith "hosted-endpoint-") &&
      !(← (base/(tag++".guard.json")).pathExists) do
    throw (IO.userError "preserve preceding source-lease attempt")
  let root := base/(tag++"-result")
  let runtime := base/(if tag.startsWith "hosted-endpoint-" then
    "hosted-endpoint-build/StudyMain" else "shared-leases-build/StudyMain")
  let command ← match mode with
    | "leases" => pure #["/usr/bin/env","LEAN_NUM_THREADS=1",runtime.toString,"shared-lease-checks",root.toString]
    | "policy" => pure #["/usr/bin/env","LEAN_NUM_THREADS=1",runtime.toString,"private-page-checks",root.toString]
    | "hosted" => pure #["/usr/bin/env","LEAN_NUM_THREADS=1",runtime.toString,"hosted-endpoint-checks",root.toString]
    | "profile" | "burst80" => do
      let aliasPath := base/"worker-cpu-target/bin/eggshelld"
      if ← aliasPath.pathExists then
        unless (← aliasPath.symlinkMetadata).type == .symlink do throw (IO.userError "target is not a symlink")
        IO.FS.removeFile aliasPath
      let linked ← IO.Process.output {cmd := "/bin/ln",args := #["-s",runtime.toString,aliasPath.toString]}
      unless linked.exitCode == 0 do throw (IO.userError "cannot select sealed runtime")
      let sealed ← IO.Process.output {cmd := "/usr/bin/shasum",args := #["-a","256",runtime.toString]}
      unless sealed.exitCode == 0 do throw (IO.userError "cannot seal runtime")
      let digest := (sealed.stdout.splitOn " ").headD ""
      let call := #["/usr/bin/env","LEAN_NUM_THREADS=1","EGGSHELL_DATA_ROOT="++(root/"private").toString,
        "EGGSHELL_CONFIG="++(root/"eggshell.toml").toString,"PLUGIN_ROOT="++(base/"worker-cpu-target").toString,
        "EGGSHELL_TRACE_SERVICE_PROFILE=1",(base/"session-dispatch-client-build/StudyMain").toString,
        root.toString,runtime.toString,digest]
      pure (if mode == "burst80" then call.push "burst80" else call)
    | _ => throw (IO.userError "unknown source-lease mode")
  IO.FS.writeFile (base/(tag++".guard-settings.json")) (Json.mkObj [("command",toJson command),
    ("cwd",toJson workspace.toString),("record",toJson (base/(tag++".guard.json")).toString),
    ("ownedPrefixes",toJson #[base.toString]),("limitRssKiB",toJson (3670016 : Nat)),
    ("minFreeKiB",toJson (2097152 : Nat))]).pretty
