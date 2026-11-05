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
    else if entry.fileName.endsWith ".lean" && entry.fileName != "OrderedIncidence.lean" then
      IO.FS.writeFile (target/entry.fileName) (← IO.FS.readFile entry.path)
def main (args : List String) : IO Unit := do
  let [mode,tag] := args | throw (IO.userError "source-incidence action and fresh tag required")
  unless tag.startsWith "source-incidence-" && !(← (base/(tag++".guard.json")).pathExists) do
    throw (IO.userError "preserve prior attempt")
  let core := base/"interest-traffic-core"
  let command ← match mode with
    | "capture" =>
      let target := base/"source-incidence-baseline-core"
      unless !(← target.pathExists) do throw (IO.userError "preserve frozen parent source")
      capture (core/"Eggshell") (target/"Eggshell")
      capture (core/"tools") (target/"tools")
      pure #["/usr/bin/true"]
    | "proof" => pure #["/usr/bin/env","LEAN_NUM_THREADS=1",
        "LEAN_PATH="++(base/"local-selection-traffic-build/lib").toString++":"++(core/".lake/build/lib/lean").toString,
        compiler++"/bin/lean","-M1024",(core/"Eggshell/OrderedIncidence.lean").toString,
        "-o",(base/"source-incidence-proof.olean").toString]
    | "build" =>
      IO.FS.writeFile (core/"tools/research/SourceIncidenceChecks.lean")
        (← IO.FS.readFile (workspace/"tools/research/SourceIncidenceChecks.lean"))
      let driver ← IO.FS.readFile (base/"source-incidence-baseline-core/tools/research/FrontTrafficChecks.lean")
      let entry := "def main (args : List String) : IO UInt32 := do\n  match args with\n"
      unless (driver.splitOn entry).length == 2 do throw (IO.userError "native traffic entry changed")
      IO.FS.writeFile (core/"tools/research/FrontTrafficChecks.lean")
        ("import tools.research.SourceIncidenceChecks\n"++driver.replace entry
          (entry++"  | [\"source-incidence-checks\"] => Eggshell.Research.SourceIncidenceChecks.run; return 0\n"))
      let parent := base/"local-selection-traffic-build"
      let old ← read (base/"local-selection-traffic-build-settings.json")
      let parents ← IO.ofExcept (old.getObjValAs? (Array String) "parents")
      let settings := old.setObjVal! "parents" (toJson (#[parent.toString]++parents))
        |>.setObjVal! "mainModule" (toJson "tools.research.FrontTrafficChecks")
        |>.setObjVal! "output" (toJson (base/"source-incidence-build").toString)
        |>.setObjVal! "baselineCore" (toJson (base/"source-incidence-baseline-core").toString)
        |>.setObjVal! "objectModules" (toJson (parent/"object-mapping.json").toString)
        |>.setObjVal! "baselineResponse" (toJson (parent/"runtime.rsp").toString)
        |>.setObjVal! "baselineMain" (toJson (parent/"tools_research_FrontTrafficChecks.o").toString)
      let path := base/"source-incidence-build-settings.json"
      IO.FS.writeFile path settings.pretty
      pure #["/usr/bin/env","LEAN_NUM_THREADS=1",compiler++"/bin/lean","-M1024","--run",
        (workspace/"tools/research/StudyBuildMain.lean").toString,path.toString]
    | "checks" => pure #[(base/"source-incidence-build/StudyMain").toString,"source-incidence-checks"]
    | "pairs" => pure #[compiler++"/bin/lean","-M512","--run",
        (workspace/"docs/candidates/source-incidence/paired.lean").toString,(base/(tag++"-result")).toString]
    | "mixed" | "restart-audit" =>
      let root := base/(if mode == "mixed" then tag++"-result" else "source-incidence-mixed1-result")
      pure (#["/usr/bin/env","LEAN_NUM_THREADS=1","EGGSHELL_DATA_ROOT="++(root/"private").toString,
        "PLUGIN_ROOT="++(base/"source-incidence-no-plugin").toString,
        (base/"source-incidence-build/StudyMain").toString]++
        (if mode == "mixed" then #["front-traffic",root.toString,"80","5000"] else #["front-traffic-audit",root.toString]))
    | _ => throw (IO.userError "unknown source-incidence action")
  IO.FS.writeFile (base/(tag++".guard-settings.json")) (Json.mkObj [("command",toJson command),
    ("cwd",toJson core.toString),("record",toJson (base/(tag++".guard.json")).toString),
    ("ownedPrefixes",toJson #[base.toString]),("limitRssKiB",toJson (3670016 : Nat)),
    ("minFreeKiB",toJson (2097152 : Nat))]).pretty
