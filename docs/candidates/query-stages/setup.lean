import Lean.Data.Json.FromToJson
import Lean.Data.Json.Parser
open Lean
def base : System.FilePath := "/Users/ovm/.codex/experiments/eggshell/scope-token-study-20261028/fixed-frame-study"
def workspace : System.FilePath := "/Users/ovm/.codex/worktrees/hook-deadline-baseline/eggshell"
def leanRoot : System.FilePath := "/Users/ovm/.elan/toolchains/leanprover--lean4---v4.33.0"
def main (args : List String) : IO Unit := do
  let [tag,mode] := args | throw (IO.userError "fresh query-stage tag/mode required")
  unless tag.startsWith "query-stages-" && !tag.contains '/' &&
      ["build","off16","on16","on80","off80","records","provider-gaps","retire","verify"].contains mode && !(← (base/(tag++".guard.json")).pathExists) do
    throw (IO.userError "preserve preceding query-stage trial")
  let command ← if mode == "verify" then
      pure #[ (leanRoot/"bin/lean").toString,"-j1","-M512","--run",
        (workspace/"docs/candidates/query-stages/records.lean").toString,"verify"]
    else if mode == "retire" then
      pure #[ (leanRoot/"bin/lean").toString,"-j1","-M512","--run",
        (workspace/"docs/candidates/shared-leases/retire.lean").toString,"--query-stages"]
    else if mode == "provider-gaps" then
      pure #[ (leanRoot/"bin/lean").toString,"-j1","-M512","--run",
        (workspace/"docs/candidates/query-stages/records.lean").toString,"provider-gaps"]
    else if mode == "records" then
      pure #[ (leanRoot/"bin/lean").toString,"-j1","-M512","--run",
        (workspace/"docs/candidates/query-stages/records.lean").toString,"query-stages-build1","query-stages-build2",
        "query-stages-off16-1","query-stages-on16-1","query-stages-off16-2","query-stages-on16-2",
        "query-stages-on80-1","query-stages-off80-1"]
    else if mode == "build" then do
      let original ← IO.ofExcept (Json.parse (← IO.FS.readFile (base/"hosted-endpoint-build-settings.json")))
      let parents ← IO.ofExcept (original.getObjValAs? (Array String) "parents")
      let settings := original.setObjVal! "output" (toJson (base/"query-stages-build").toString)
        |>.setObjVal! "parents" (toJson (#[ (base/"hosted-endpoint-build").toString ]++parents))
        |>.setObjVal! "objectModules" (toJson (base/"hosted-endpoint-build/object-mapping.json").toString)
        |>.setObjVal! "baselineResponse" (toJson (base/"hosted-endpoint-build/runtime.rsp").toString)
        |>.setObjVal! "baselineMain" (toJson (base/"hosted-endpoint-build/tools_research_SessionDispatchChecks.o").toString)
        |>.setObjVal! "baselineCore" (toJson (base/"query-stages-parent-core").toString)
      let path := base/"query-stages-build-settings.json"
      IO.FS.writeFile path settings.pretty
      pure #[ (leanRoot/"bin/lean").toString,"-j1","-M1536","--run",
        (workspace/"tools/research/StudyBuildMain.lean").toString,path.toString]
    else do
      let runtime := base/"query-stages-build/StudyMain"
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
