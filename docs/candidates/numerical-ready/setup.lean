import Lean.Data.Json.FromToJson
import Lean.Data.Json.Parser
open Lean
def base : System.FilePath := "/Users/ovm/.codex/experiments/eggshell/scope-token-study-20261028/fixed-frame-study"
def workspace : System.FilePath := "/Users/ovm/.codex/worktrees/hook-deadline-baseline/eggshell"
def leanRoot : System.FilePath := "/Users/ovm/.elan/toolchains/leanprover--lean4---v4.33.0"
def main (args : List String) : IO Unit := do
  let [tag,mode] := args | throw (IO.userError "fresh query-stage tag/mode required")
  unless tag.startsWith "numerical-ready-" && !tag.contains '/' &&
      ["build","laws-build","laws","off16","on16","on80","off80","records","metrics","retire","compiled-retire","verify","complete"].contains mode && !(← (base/(tag++".guard.json")).pathExists) do
    throw (IO.userError "preserve preceding query-stage trial")
  let command ← if mode == "complete" then
      pure #[(leanRoot/"bin/lean").toString,"-j1","-M512","--run",
        (workspace/"docs/candidates/provider-stages/records.lean").toString,"--numerical-ready","complete"]
    else if mode == "compiled-retire" then
      pure #[(leanRoot/"bin/lean").toString,"-j1","-M512","--run",
        (workspace/"docs/candidates/shared-leases/retire.lean").toString,"--completed-observers"]
    else if mode == "metrics" then
      pure #[(leanRoot/"bin/lean").toString,"-j1","-M512","--run",
        (workspace/"docs/candidates/numerical-ready/metrics.lean").toString]
    else if mode == "verify" then
      pure #[ (leanRoot/"bin/lean").toString,"-j1","-M512","--run",
        (workspace/"docs/candidates/provider-stages/records.lean").toString,"--numerical-ready","verify"]
    else if mode == "retire" then
      pure #[ (leanRoot/"bin/lean").toString,"-j1","-M512","--run",
        (workspace/"docs/candidates/shared-leases/retire.lean").toString,"--numerical-ready"]
    else if mode == "records" then
      pure #[ (leanRoot/"bin/lean").toString,"-j1","-M512","--run",
        (workspace/"docs/candidates/provider-stages/records.lean").toString,"--numerical-ready","collect"]
    else if mode == "laws" then
      pure #[(base/"numerical-ready-laws-build/StudyMain").toString,(base/(tag++"-result")).toString]
    else if mode == "build" || mode == "laws-build" then do
      let laws := mode == "laws-build"
      if laws then
        IO.FS.writeFile (base/"interest-traffic-core/tools/research/NumericalReadyChecks.lean")
          (← IO.FS.readFile (workspace/"tools/research/NumericalReadyChecks.lean"))
      let parent := if laws then "numerical-ready-build" else "provider-stages-build"
      let target := if laws then "numerical-ready-laws-build" else "numerical-ready-build"
      let original ← IO.ofExcept (Json.parse (← IO.FS.readFile (base/"provider-stages-build-settings.json")))
      let parents ← IO.ofExcept (original.getObjValAs? (Array String) "parents")
      let settings := original.setObjVal! "output" (toJson (base/target).toString)
        |>.setObjVal! "parents" (toJson (#[ (base/parent).toString ]++parents))
        |>.setObjVal! "objectModules" (toJson (base/parent/"object-mapping.json").toString)
        |>.setObjVal! "baselineResponse" (toJson (base/parent/"runtime.rsp").toString)
        |>.setObjVal! "baselineMain" (toJson (base/parent/"tools_research_SessionDispatchChecks.o").toString)
        |>.setObjVal! "baselineCore" (toJson (base/"numerical-ready-parent-core").toString)
      let settings := if laws then settings.setObjVal! "mainModule" (toJson "tools.research.NumericalReadyChecks") else settings
      let path := base/(target++"-settings.json")
      IO.FS.writeFile path settings.pretty
      pure #[ (leanRoot/"bin/lean").toString,"-j1","-M1536","--run",
        (workspace/"tools/research/StudyBuildMain.lean").toString,path.toString]
    else do
      let runtime := base/"numerical-ready-build/StudyMain"
      let hashed ← IO.Process.output {cmd := "/usr/bin/shasum",args := #["-a","256",runtime.toString]}
      unless hashed.exitCode == 0 do throw (IO.userError "cannot seal query-stage runtime")
      let sha := (hashed.stdout.splitOn " ").headD ""
      let aliasPath := base/"worker-cpu-target/bin/eggshelld"
      unless (← aliasPath.symlinkMetadata).type == .symlink do throw (IO.userError "isolated target changed type")
      IO.FS.removeFile aliasPath
      let linked ← IO.Process.output {cmd := "/bin/ln",args := #["-s",runtime.toString,aliasPath.toString]}
      unless linked.exitCode == 0 do throw (IO.userError "cannot select query-stage runtime")
      let root := base/(tag++"-result")
      let call := #["/usr/bin/env","LEAN_NUM_THREADS=1","EGGSHELL_DATA_ROOT="++(root/"private").toString,
        "EGGSHELL_CONFIG="++(root/"eggshell.toml").toString,"PLUGIN_ROOT="++(base/"worker-cpu-target").toString,
        "EGGSHELL_TRACE_SERVICE_PROFILE=1","EGGSHELL_TRACE_QUERY_STAGES="++(if mode.startsWith "on" then "1" else "0"),
        (base/"session-dispatch-client-build/StudyMain").toString,root.toString,runtime.toString,sha]
      pure (if mode.endsWith "80" then call.push "burst80" else call)
  IO.FS.writeFile (base/(tag++".guard-settings.json")) (Json.mkObj [("command",toJson command),
    ("cwd",toJson workspace.toString),("record",toJson (base/(tag++".guard.json")).toString),
    ("ownedPrefixes",toJson #[base.toString]),("limitRssKiB",toJson (3670016 : Nat)),
    ("minFreeKiB",toJson (2097152 : Nat))]).pretty
