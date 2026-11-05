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
  let [mode,tag] := args | throw (IO.userError "public preparation action and fresh tag required")
  unless tag.startsWith "public-preparation-" && !(← (base/(tag++".guard.json")).pathExists) do
    throw (IO.userError "preserve prior attempt")
  let core := base/"interest-traffic-core"
  let command ← match mode with
    | "capture-source" =>
      let target := base/"public-preparation-baseline-core"
      unless !(← target.pathExists) do throw (IO.userError "preserve frozen parent source")
      capture (core/"Eggshell") (target/"Eggshell")
      capture (core/"tools") (target/"tools")
      pure #["/usr/bin/true"]
    | "build" | "candidate-build" =>
      let candidate := mode == "candidate-build"
      let earlierHarness := base/"public-preparation-parent-harness.lean"
      if candidate && !(← earlierHarness.pathExists) then
        IO.FS.writeFile earlierHarness (← IO.FS.readFile (core/"tools/research/PublicPreparationChecks.lean"))
      IO.FS.writeFile (core/"tools/research/PublicPreparationChecks.lean")
        (← IO.FS.readFile (workspace/"tools/research/PublicPreparationChecks.lean"))
      let driver ← IO.FS.readFile (base/"public-preparation-baseline-core/tools/research/FrontTrafficChecks.lean")
      let entry := "def main (args : List String) : IO UInt32 := do\n  match args with\n"
      unless (driver.splitOn entry).length == 2 do throw (IO.userError "native traffic entry changed")
      IO.FS.writeFile (core/"tools/research/FrontTrafficChecks.lean")
        ("import tools.research.PublicPreparationChecks\n"++driver.replace entry
          (entry++"  | [\"public-preparation\",mode,root] => Eggshell.Research.PublicPreparationChecks.run mode (.mk root); return 0\n"))
      let parent := base/(if candidate then "public-preparation-build" else "source-incidence-build")
      let old ← read (base/(if candidate then "public-preparation-build-settings.json" else "source-incidence-build-settings.json"))
      let parents ← IO.ofExcept (old.getObjValAs? (Array String) "parents")
      let settings := old.setObjVal! "parents" (toJson (#[parent.toString]++parents))
        |>.setObjVal! "output" (toJson (base/(if candidate then "public-preparation-candidate-build" else "public-preparation-build")).toString)
        |>.setObjVal! "baselineCore" (toJson (base/"public-preparation-baseline-core").toString)
        |>.setObjVal! "objectModules" (toJson (parent/"object-mapping.json").toString)
        |>.setObjVal! "baselineResponse" (toJson (parent/"runtime.rsp").toString)
        |>.setObjVal! "baselineMain" (toJson (parent/"tools_research_FrontTrafficChecks.o").toString)
      let path := base/(if candidate then "public-preparation-candidate-build-settings.json" else "public-preparation-build-settings.json")
      IO.FS.writeFile path settings.pretty
      pure #["/usr/bin/env","LEAN_NUM_THREADS=1",compiler++"/bin/lean","-M1024","--run",
        (workspace/"tools/research/StudyBuildMain.lean").toString,path.toString]
    | "capture" | "observe" | "verify" =>
      let root := base/"public-preparation-fixture"
      let privateRoot := base/(tag++"-data")
      unless !(← privateRoot.pathExists) do throw (IO.userError "preserve private observation")
      IO.FS.createDirAll privateRoot
      pure #["/usr/bin/env","LEAN_NUM_THREADS=1","EGGSHELL_DATA_ROOT="++privateRoot.toString,
        "PLUGIN_ROOT="++(base/"public-preparation-no-plugin").toString,
        (base/(if mode == "verify" then "public-preparation-candidate-build/StudyMain" else "public-preparation-build/StudyMain")).toString,
        "public-preparation",mode,root.toString]
    | "replay" | "prefix" =>
      let root := base/(tag++"-result")
      unless !(← root.pathExists) do throw (IO.userError "preserve replay fixture")
      pure #["/usr/bin/env","LEAN_NUM_THREADS=1","EGGSHELL_DATA_ROOT="++(root/"data").toString,
        "PLUGIN_ROOT="++(base/"public-preparation-no-plugin").toString,
        (base/"public-preparation-candidate-build/StudyMain").toString,"public-preparation",mode,root.toString]
    | "pairs" => pure #[compiler++"/bin/lean","-M512","--run",
        (workspace/"docs/candidates/source-incidence/paired.lean").toString,(base/(tag++"-result")).toString,
        (base/"public-preparation-build/StudyMain").toString,(base/"public-preparation-candidate-build/StudyMain").toString,
        "fresh-derived"]
    | "mixed" | "restart-audit" =>
      let root := base/(if mode == "mixed" then tag++"-result" else "public-preparation-mixed1-result")
      pure (#["/usr/bin/env","LEAN_NUM_THREADS=1","EGGSHELL_DATA_ROOT="++(root/"private").toString,
        "PLUGIN_ROOT="++(base/"public-preparation-no-plugin").toString,
        (base/"public-preparation-candidate-build/StudyMain").toString]++
        (if mode == "mixed" then #["front-traffic",root.toString,"80","5000"] else #["front-traffic-audit",root.toString]))
    | _ => throw (IO.userError "unknown public preparation action")
  IO.FS.writeFile (base/(tag++".guard-settings.json")) (Json.mkObj [("command",toJson command),
    ("cwd",toJson core.toString),("record",toJson (base/(tag++".guard.json")).toString),
    ("ownedPrefixes",toJson #[base.toString]),("limitRssKiB",toJson (3670016 : Nat)),
    ("minFreeKiB",toJson (2097152 : Nat))]).pretty
