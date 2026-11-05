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
  let [mode,tag] := args | throw (IO.userError "local-selection action and fresh tag required")
  unless tag.startsWith "local-selection-" && !(← (base/(tag++".guard.json")).pathExists) do
    throw (IO.userError "preserve prior attempt")
  let core := base/"interest-traffic-core"
  let command ← match mode with
    | "capture" =>
      let target := base/"local-selection-baseline-core"
      unless !(← target.pathExists) do throw (IO.userError "preserve frozen parent source")
      capture (core/"Eggshell") (target/"Eggshell")
      capture (core/"tools") (target/"tools")
      pure #["/usr/bin/true"]
    | "build" | "traffic-build" =>
      IO.FS.writeFile (core/"tools/research/LocalSelectionChecks.lean")
        (← IO.FS.readFile (workspace/"tools/research/LocalSelectionChecks.lean"))
      let parent := base/(if mode == "build" then "grouped-ingress-traffic-build" else "local-selection-build")
      let old ← read (base/(if mode == "build" then "grouped-ingress-traffic-build-settings.json" else "local-selection-build-settings.json"))
      let parents ← IO.ofExcept (old.getObjValAs? (Array String) "parents")
      let settings := old.setObjVal! "parents" (toJson (#[parent.toString]++parents))
        |>.setObjVal! "mainModule" (toJson (if mode == "build" then "tools.research.LocalSelectionChecks" else "tools.research.FrontTrafficChecks"))
        |>.setObjVal! "output" (toJson (base/(if mode == "build" then "local-selection-build" else "local-selection-traffic-build")).toString)
        |>.setObjVal! "baselineCore" (toJson (base/"local-selection-baseline-core").toString)
        |>.setObjVal! "objectModules" (toJson (parent/"object-mapping.json").toString)
        |>.setObjVal! "baselineResponse" (toJson (parent/"runtime.rsp").toString)
        |>.setObjVal! "baselineMain" (toJson (parent/(if mode == "build" then "tools_research_FrontTrafficChecks.o" else "tools_research_LocalSelectionChecks.o")).toString)
      let path := base/(if mode == "build" then "local-selection-build-settings.json" else "local-selection-traffic-build-settings.json")
      IO.FS.writeFile path settings.pretty
      pure #["/usr/bin/env","LEAN_NUM_THREADS=1",compiler++"/bin/lean","-M1024","--run",
        (workspace/"tools/research/StudyBuildMain.lean").toString,path.toString]
    | "checks" => pure #[(base/"local-selection-build/StudyMain").toString,"local-selection-checks"]
    | "pairs" => pure #[compiler++"/bin/lean","-M512","--run",
        (workspace/"docs/candidates/local-selection/paired.lean").toString,(base/(tag++"-result")).toString]
    | "mixed" | "restart-audit" =>
      let root := base/(if mode == "mixed" then tag++"-result" else "local-selection-mixed1-result")
      pure (#["/usr/bin/env","LEAN_NUM_THREADS=1","EGGSHELL_DATA_ROOT="++(root/"private").toString,
        "PLUGIN_ROOT="++(base/"local-selection-no-plugin").toString,
        (base/"local-selection-traffic-build/StudyMain").toString]++
        (if mode == "mixed" then #["front-traffic",root.toString,"80","5000"] else #["front-traffic-audit",root.toString]))
    | _ => throw (IO.userError "unknown local selection action")
  IO.FS.writeFile (base/(tag++".guard-settings.json")) (Json.mkObj [("command",toJson command),
    ("cwd",toJson workspace.toString),("record",toJson (base/(tag++".guard.json")).toString),
    ("ownedPrefixes",toJson #[base.toString]),("limitRssKiB",toJson (3670016 : Nat)),
    ("minFreeKiB",toJson (2097152 : Nat))]).pretty
