import Lean.Data.Json.FromToJson
import Lean.Data.Json.Parser
open Lean
def base : System.FilePath := "/Users/ovm/.codex/experiments/eggshell/scope-token-study-20261028/fixed-frame-study"
def workspace : System.FilePath := "/Users/ovm/.codex/worktrees/hook-deadline-baseline/eggshell"
def leanRoot : System.FilePath := "/Users/ovm/.elan/toolchains/leanprover--lean4---v4.33.0"
def read (path : System.FilePath) : IO Json := do IO.ofExcept (Json.parse (← IO.FS.readFile path))
def main (args : List String) : IO Unit := do
  let [tag,mode] := args | throw (IO.userError "fresh working-set tag/mode required")
  unless tag.startsWith "working-set-" && !tag.contains '/' && !(← (base/(tag++".guard.json")).pathExists) do
    throw (IO.userError "preserve preceding working-set trial")
  let command ← if mode == "build" then do
      IO.FS.writeFile (base/"interest-traffic-core/tools/research/WorkingSetProfile.lean")
        (← IO.FS.readFile (workspace/"tools/research/WorkingSetProfile.lean"))
      let parent := base/"readonly-pages-build"
      let original ← read (base/"readonly-pages-build-settings.json")
      let parents ← IO.ofExcept (original.getObjValAs? (Array String) "parents")
      let settings := original.setObjVal! "output" (toJson (base/"working-set-build").toString)
        |>.setObjVal! "parents" (toJson (#[parent.toString]++parents))
        |>.setObjVal! "objectModules" (toJson (parent/"object-mapping.json").toString)
        |>.setObjVal! "baselineResponse" (toJson (parent/"runtime.rsp").toString)
        |>.setObjVal! "baselineMain" (toJson (parent/"tools_research_ReadonlyPageChecks.o").toString)
        |>.setObjVal! "baselineCore" Json.null
        |>.setObjVal! "mainModule" (toJson "tools.research.WorkingSetProfile")
      let path := base/"working-set-build-settings.json"
      IO.FS.writeFile path settings.pretty
      pure #[(leanRoot/"bin/lean").toString,"-j1","-M1536","--run",(workspace/"tools/research/StudyBuildMain.lean").toString,path.toString]
    else if mode == "sixteen" then do
      let built ← read (base/"working-set-build2.guard.json")
      unless built.getObjValD "state" == toJson "finished" && built.getObjValD "exitCode" == toJson (0 : Nat) &&
        built.getObjValD "ownedPids" == toJson (#[] : Array Nat) do throw (IO.userError "working-set observer did not build/drain")
      let root := base/(tag++"-result")
      pure #["/usr/bin/env","LEAN_NUM_THREADS=1","EGGSHELL_DATA_ROOT="++(root/"private").toString,
        "EGGSHELL_CONFIG="++(root/"eggshell.toml").toString,"PLUGIN_ROOT="++(base/"worker-cpu-target").toString,
        "EGGSHELL_TRACE_SERVICE_PROFILE=1","EGGSHELL_TRACE_QUERY_STAGES=1","EGGSHELL_TRACE_NUMERICAL_STAGES=1",
        (base/"working-set-build/StudyMain").toString,root.toString]
    else throw (IO.userError "unknown working-set mode")
  IO.FS.writeFile (base/(tag++".guard-settings.json")) (Json.mkObj [("command",toJson command),("cwd",toJson workspace.toString),
    ("record",toJson (base/(tag++".guard.json")).toString),("ownedPrefixes",toJson #[base.toString]),
    ("limitRssKiB",toJson (3670016 : Nat)),("minFreeKiB",toJson (2097152 : Nat))]).pretty
