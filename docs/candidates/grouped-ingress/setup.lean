import Lean.Data.Json.FromToJson
import Lean.Data.Json.Parser
open Lean
def base : System.FilePath := "/Users/ovm/.codex/experiments/eggshell/scope-token-study-20261028/fixed-frame-study"
def workspace : System.FilePath := "/Users/ovm/.codex/worktrees/hook-deadline-baseline/eggshell"
def compiler := "/Users/ovm/.elan/toolchains/leanprover--lean4---v4.33.0"
def read (path : System.FilePath) : IO Json := do IO.ofExcept (Json.parse (← IO.FS.readFile path))
partial def capture (source target : System.FilePath) : IO Unit := do
  IO.FS.createDirAll target
  for entry in ← source.readDir do
    if (← entry.path.symlinkMetadata).type == .dir then capture entry.path (target/entry.fileName)
    else if entry.fileName.endsWith ".lean" then IO.FS.writeFile (target/entry.fileName) (← IO.FS.readFile entry.path)
def main (args : List String) : IO Unit := do
  let [mode,tag] := args | throw (IO.userError "action and unique tag required")
  unless tag.startsWith "grouped-ingress-" && !(← (base/(tag++".guard.json")).pathExists) do
    throw (IO.userError "preserve prior attempt")
  let core := base/"interest-traffic-core"
  let command ← match mode with
    | "capture" =>
      unless !(← (base/"grouped-ingress-baseline-core").pathExists) do throw (IO.userError "preserve captured parent")
      capture (core/"Eggshell") (base/"grouped-ingress-baseline-core/Eggshell")
      capture (core/"tools") (base/"grouped-ingress-baseline-core/tools")
      pure #["/usr/bin/true"]
    | "build" | "traffic-build" =>
      IO.FS.writeFile (core/"tools/research/GroupedIngressChecks.lean")
        (← IO.FS.readFile (workspace/"tools/research/GroupedIngressChecks.lean"))
      if mode == "traffic-build" then
        IO.FS.writeFile (core/"tools/research/FrontTrafficChecks.lean")
          (← IO.FS.readFile (workspace/"tools/research/FrontTrafficChecks.lean"))
      let parent := base/"replay-mixed-build"
      let old ← read (base/"replay-mixed-build-settings.json")
      let parents ← IO.ofExcept (old.getObjValAs? (Array String) "parents")
      let settings := old.setObjVal! "parents" (toJson (#[parent.toString]++parents))
        |>.setObjVal! "mainModule" (toJson (if mode == "build" then "tools.research.GroupedIngressChecks" else "tools.research.FrontTrafficChecks"))
        |>.setObjVal! "output" (toJson (base/(if mode == "build" then "grouped-ingress-build" else "grouped-ingress-traffic-build")).toString)
        |>.setObjVal! "baselineCore" (toJson (base/"grouped-ingress-baseline-core").toString)
        |>.setObjVal! "objectModules" (toJson (parent/"object-mapping.json").toString)
        |>.setObjVal! "baselineResponse" (toJson (parent/"runtime.rsp").toString)
        |>.setObjVal! "baselineMain" (toJson (parent/"tools_research_FrontTrafficChecks.o").toString)
      let path := base/(if mode == "build" then "grouped-ingress-build-settings.json" else "grouped-ingress-traffic-build-settings.json")
      IO.FS.writeFile path settings.pretty
      pure #["/usr/bin/env","LEAN_NUM_THREADS=1",compiler++"/bin/lean","-M1024","--run",
        (workspace/"tools/research/StudyBuildMain.lean").toString,path.toString]
    | "mixed" | "restart-audit" =>
      let root := base/(if mode == "mixed" then tag++"-result" else "grouped-ingress-mixed1-result")
      pure (#["/usr/bin/env","LEAN_NUM_THREADS=1","EGGSHELL_DATA_ROOT="++(root/"private").toString,
        "PLUGIN_ROOT="++(base/"grouped-ingress-no-plugin").toString,
        (base/"grouped-ingress-traffic-build/StudyMain").toString]++
        (if mode == "mixed" then #["front-traffic",root.toString,"80","5000"] else #["front-traffic-audit",root.toString]))
    | "checks" | "context" | "integration" =>
      let root := base/((if mode == "integration" then "grouped-ingress-context2" else tag)++"-result")
      pure (#["/usr/bin/env","LEAN_NUM_THREADS=1",
        "EGGSHELL_DATA_ROOT="++(root/"data").toString,
        "PLUGIN_ROOT="++(base/"grouped-ingress-no-plugin").toString,
        (base/"grouped-ingress-build/StudyMain").toString]++
        (if mode == "checks" then #[root.toString] else
          #[(if mode == "context" then "context" else "preparation-integration"),root.toString]))
    | _ => throw (IO.userError "unknown grouped ingress action")
  IO.FS.writeFile (base/(tag++".guard-settings.json")) (Json.mkObj [("command",toJson command),
    ("cwd",toJson workspace.toString),("record",toJson (base/(tag++".guard.json")).toString),
    ("ownedPrefixes",toJson #[base.toString]),("limitRssKiB",toJson (3670016 : Nat)),
    ("minFreeKiB",toJson (2097152 : Nat))]).pretty
