import Lean.Data.Json.FromToJson
import Lean.Data.Json.Parser
open Lean
def base : System.FilePath := "/Users/ovm/.codex/experiments/eggshell/scope-token-study-20261028/fixed-frame-study"
def workspace : System.FilePath := "/Users/ovm/.codex/worktrees/hook-deadline-baseline/eggshell"
def main (args : List String) : IO Unit := do
  let tag::mode::rest := args | throw (IO.userError "fresh direct-waits tag, mode, optional arm and size required")
  unless tag.startsWith "direct-waits-" && !(← (base/(tag++".guard.json")).pathExists) do
    throw (IO.userError "preserve previous dispatch attempt")
  let root := base/(tag++"-result")
  let command ← match mode,rest with
    | "policy",[] => pure #["/usr/bin/env","LEAN_NUM_THREADS=1",(base/"direct-waits-build/StudyMain").toString,
        "direct-wait-checks",root.toString]
    | "profile",[arm,size] =>
      unless (arm == "parent" || arm == "candidate") && #["32","80","burst80"].contains size do
        throw (IO.userError "unknown fixed dispatch arm or size")
      let target := base/(if arm == "parent" then "focus-locators-build/StudyMain" else "direct-waits-build/StudyMain")
      let aliasPath := base/"worker-cpu-target/bin/eggshelld"
      let metadata ← try pure (some (← aliasPath.symlinkMetadata)) catch _ => pure none
      if let some metadata := metadata then
        unless metadata.type == .symlink do throw (IO.userError "target alias is not a symlink")
        IO.FS.removeFile aliasPath
      let linked ← IO.Process.output {cmd := "/bin/ln",args := #["-s",target.toString,aliasPath.toString]}
      unless linked.exitCode == 0 do throw (IO.userError "cannot select sealed runtime")
      let sealed ← IO.Process.output {cmd := "/usr/bin/shasum",args := #["-a","256",target.toString]}
      unless sealed.exitCode == 0 do throw (IO.userError "cannot seal dispatch runtime")
      let digest := (sealed.stdout.splitOn " ").headD ""
      let call := #["/usr/bin/env","LEAN_NUM_THREADS=1","EGGSHELL_DATA_ROOT="++(root/"private").toString,
        "EGGSHELL_CONFIG="++(root/"eggshell.toml").toString,"PLUGIN_ROOT="++(base/"worker-cpu-target").toString,
        "EGGSHELL_TRACE_SERVICE_PROFILE=1",(base/"session-dispatch-client-build/StudyMain").toString,
        root.toString,target.toString,digest]
      pure (if size == "32" then call else call.push size)
    | _,_ => throw (IO.userError "unknown dispatch mode")
  IO.FS.writeFile (base/(tag++".guard-settings.json")) (Json.mkObj [("command",toJson command),
    ("cwd",toJson workspace.toString),("record",toJson (base/(tag++".guard.json")).toString),
    ("ownedPrefixes",toJson #[base.toString]),("limitRssKiB",toJson (3670016 : Nat)),
    ("minFreeKiB",toJson (2097152 : Nat))]).pretty
