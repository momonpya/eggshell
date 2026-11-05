import Lean.Data.Json.FromToJson
import Lean.Data.Json.Parser
open Lean
def base : System.FilePath := "/Users/ovm/.codex/experiments/eggshell/scope-token-study-20261028/fixed-frame-study"
def workspace : System.FilePath := "/Users/ovm/.codex/worktrees/hook-deadline-baseline/eggshell"
def compiler := "/Users/ovm/.elan/toolchains/leanprover--lean4---v4.33.0/bin/lean"
def read (path : System.FilePath) : IO Json := do IO.ofExcept (Json.parse (← IO.FS.readFile path))
def main (args : List String) : IO Unit := do
  let [tag,mode] := args | throw (IO.userError "fresh maintenance-scope tag and build/checks required")
  unless tag.startsWith "maintenance-scope-" && !(← (base/(tag++".guard.json")).pathExists) do
    throw (IO.userError "preserve previous maintenance attempt")
  let parent := base/"metadata-ingress-candidate-build"
  let root := base/(tag++"-result")
  let command ← match mode with
    | "build" =>
      let core := base/"interest-traffic-core"
      let saved := base/"maintenance-scope-baseline-core/tools/research/FrontTrafficChecks.lean"
      IO.FS.createDirAll saved.parent.get!
      if !(← saved.pathExists) then IO.FS.writeFile saved (← IO.FS.readFile (core/"tools/research/FrontTrafficChecks.lean"))
      IO.FS.writeFile (core/"tools/research/MaintenanceScopeChecks.lean")
        (← IO.FS.readFile (workspace/"tools/research/MaintenanceScopeChecks.lean"))
      IO.FS.writeFile (core/"tools/research/FrontTrafficChecks.lean") (← IO.FS.readFile saved)
      let old ← read (base/"metadata-ingress-candidate-build-settings.json")
      let parents ← IO.ofExcept (old.getObjValAs? (Array String) "parents")
      let settings := old.setObjVal! "parents" (toJson (#[parent.toString]++parents))
        |>.setObjVal! "mainModule" (toJson "tools.research.MaintenanceScopeChecks")
        |>.setObjVal! "output" (toJson (base/"maintenance-scope-build").toString)
        |>.setObjVal! "baselineCore" Json.null
        |>.setObjVal! "objectModules" (toJson (parent/"object-mapping.json").toString)
        |>.setObjVal! "baselineResponse" (toJson (parent/"runtime.rsp").toString)
        |>.setObjVal! "baselineMain" (toJson (parent/"tools_research_FrontTrafficChecks.o").toString)
      let path := base/"maintenance-scope-build-settings.json"
      IO.FS.writeFile path settings.pretty
      pure #["/usr/bin/env","LEAN_NUM_THREADS=1",compiler,"-M1024","--run",
        (workspace/"tools/research/StudyBuildMain.lean").toString,path.toString]
    | "checks" => pure #["/usr/bin/env","LEAN_NUM_THREADS=1","EGGSHELL_DATA_ROOT="++(root/"private").toString,
        (base/"maintenance-scope-build/StudyMain").toString,"maintenance-scope-checks",
        (base/"frontend-quiescence-fixture-small1").toString,root.toString]
    | "pairs" => pure #["/usr/bin/env","LEAN_NUM_THREADS=1",compiler,"-j1","-M512","--run",
        (workspace/"docs/candidates/maintenance-scope/paired.lean").toString]
    | "selection" => pure #["/usr/bin/env","LEAN_NUM_THREADS=1","EGGSHELL_DATA_ROOT="++(root/"private").toString,
        "EGGSHELL_CONFIG="++(root/"eggshell.toml").toString,"PLUGIN_ROOT="++(base/"worker-cpu-no-plugin").toString,
        "EGGSHELL_TRACE_SELECTION_RANGES=1","EGGSHELL_TRACE_SELECTOR_INPUT=1",compiler,"-j1","-M512","--run",
        (workspace/"docs/candidates/worker-cpu/selection.lean").toString,root.toString]
    | _ => throw (IO.userError "unknown maintenance-scope mode")
  IO.FS.writeFile (base/(tag++".guard-settings.json")) (Json.mkObj [("command",toJson command),
    ("cwd",toJson workspace.toString),("record",toJson (base/(tag++".guard.json")).toString),
    ("ownedPrefixes",toJson #[base.toString]),("limitRssKiB",toJson (3670016 : Nat)),
    ("minFreeKiB",toJson (2097152 : Nat))]).pretty
