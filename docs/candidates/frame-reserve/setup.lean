import Lean.Data.Json.FromToJson
import Lean.Data.Json.Parser
open Lean
def base : System.FilePath := "/Users/ovm/.codex/experiments/eggshell/scope-token-study-20261028/fixed-frame-study"
def workspace : System.FilePath := "/Users/ovm/.codex/worktrees/hook-deadline-baseline/eggshell"
def compiler := "/Users/ovm/.elan/toolchains/leanprover--lean4---v4.33.0/bin/lean"
def read (path : System.FilePath) : IO Json := do IO.ofExcept (Json.parse (← IO.FS.readFile path))
def main (args : List String) : IO Unit := do
  let [tag,mode] := args | throw (IO.userError "fresh frame-reserve tag and build/capture/replay required")
  unless tag.startsWith "frame-reserve-" && !(← (base/(tag++".guard.json")).pathExists) do
    throw (IO.userError "preserve prior frame audit")
  let root := base/(tag++"-result")
  let parent := base/"metadata-ingress-candidate-build"
  let command ← match mode with
    | "build" =>
      let core := base/"interest-traffic-core"
      IO.FS.writeFile (core/"tools/research/FrameReserveAudit.lean")
        (← IO.FS.readFile (workspace/"tools/research/FrameReserveAudit.lean"))
      let old ← read (base/"metadata-ingress-candidate-build-settings.json")
      let parents ← IO.ofExcept (old.getObjValAs? (Array String) "parents")
      let settings := old.setObjVal! "parents" (toJson (#[parent.toString]++parents))
        |>.setObjVal! "mainModule" (toJson "tools.research.FrameReserveAudit")
        |>.setObjVal! "output" (toJson (base/"frame-reserve-build").toString)
        |>.setObjVal! "baselineCore" Json.null
        |>.setObjVal! "objectModules" (toJson (parent/"object-mapping.json").toString)
        |>.setObjVal! "baselineResponse" (toJson (parent/"runtime.rsp").toString)
        |>.setObjVal! "baselineMain" (toJson (parent/"tools_research_FrontTrafficChecks.o").toString)
      let path := base/"frame-reserve-build-settings.json"
      IO.FS.writeFile path settings.pretty
      pure #["/usr/bin/env","LEAN_NUM_THREADS=1",compiler,"-M1024","--run",
        (workspace/"tools/research/StudyBuildMain.lean").toString,path.toString]
    | "capture" => pure #["/usr/bin/env","LEAN_NUM_THREADS=1","EGGSHELL_DATA_ROOT="++(root/"private").toString,
        "EGGSHELL_CONFIG="++(root/"eggshell.toml").toString,"PLUGIN_ROOT="++(base/"frame-reserve-no-plugin").toString,
        "EGGSHELL_TRACE_SELECTION_RANGES=1","EGGSHELL_TRACE_SELECTOR_INPUT=1",compiler,"-j1","-M512","--run",
        (workspace/"docs/candidates/worker-cpu/selection.lean").toString,root.toString]
    | "replay" => pure #["/usr/bin/env","LEAN_NUM_THREADS=1",(base/"frame-reserve-build/StudyMain").toString,
        (base/"frame-reserve-capture1-result").toString,root.toString]
    | _ => throw (IO.userError "unknown frame audit mode")
  IO.FS.writeFile (base/(tag++".guard-settings.json")) (Json.mkObj [("command",toJson command),
    ("cwd",toJson workspace.toString),("record",toJson (base/(tag++".guard.json")).toString),
    ("ownedPrefixes",toJson #[base.toString]),("limitRssKiB",toJson (3670016 : Nat)),
    ("minFreeKiB",toJson (2097152 : Nat))]).pretty
