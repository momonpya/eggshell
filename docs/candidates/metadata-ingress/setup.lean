import Lean.Data.Json.FromToJson
import Lean.Data.Json.Parser
open Lean
def base : System.FilePath := "/Users/ovm/.codex/experiments/eggshell/scope-token-study-20261028/fixed-frame-study"
def workspace : System.FilePath := "/Users/ovm/.codex/worktrees/hook-deadline-baseline/eggshell"
def compiler := "/Users/ovm/.elan/toolchains/leanprover--lean4---v4.33.0"
def read (path : System.FilePath) : IO Json := do IO.ofExcept (Json.parse (← IO.FS.readFile path))
def main (args : List String) : IO Unit := do
  let [mode,tag] := args | throw (IO.userError "action and fresh tag required")
  unless tag.startsWith "metadata-ingress-" && !(← (base/(tag++".guard.json")).pathExists) do
    throw (IO.userError "preserve earlier attempt")
  let core := base/"interest-traffic-core"
  let fixture := base/"metadata-ingress-fixture"
  let privateRoot := base/(tag++"-data")
  let command ← match mode with
    | "parent-build" | "candidate-build" =>
      IO.FS.writeFile (core/"tools/research/MetadataIngressChecks.lean")
        (← IO.FS.readFile (workspace/"tools/research/MetadataIngressChecks.lean"))
      let driver ← IO.FS.readFile (base/"metadata-ingress-baseline-core/tools/research/FrontTrafficChecks.lean")
      let entry := "def main (args : List String) : IO UInt32 := do\n  match args with\n"
      unless (driver.splitOn entry).length == 2 do throw (IO.userError "native entry changed")
      IO.FS.writeFile (core/"tools/research/FrontTrafficChecks.lean")
        ("import tools.research.MetadataIngressChecks\n"++driver.replace entry
          (entry++"  | [\"metadata-ingress\",mode,root] => Eggshell.Research.MetadataIngressChecks.run mode (.mk root); return 0\n"++
            "  | [\"inspect-ingress\",root] => IO.println (← Eggshell.Research.ProjectIngressAudit.inspect (.mk root)).compress; return 0\n"))
      let candidate := mode == "candidate-build"
      let parentName := if candidate then "metadata-ingress-parent-build" else "public-preparation-candidate-build"
      let parent := base/parentName
      let old ← read (base/(parentName++"-settings.json"))
      let parents ← IO.ofExcept (old.getObjValAs? (Array String) "parents")
      let outputName := if candidate then "metadata-ingress-candidate-build" else "metadata-ingress-parent-build"
      let settings := old.setObjVal! "parents" (toJson (#[parent.toString]++parents))
        |>.setObjVal! "output" (toJson (base/outputName).toString)
        |>.setObjVal! "baselineCore" (toJson (base/"metadata-ingress-baseline-core").toString)
        |>.setObjVal! "objectModules" (toJson (parent/"object-mapping.json").toString)
        |>.setObjVal! "baselineResponse" (toJson (parent/"runtime.rsp").toString)
        |>.setObjVal! "baselineMain" (toJson (parent/"tools_research_FrontTrafficChecks.o").toString)
      let path := base/(outputName++"-settings.json")
      IO.FS.writeFile path settings.pretty
      pure #["/usr/bin/env","LEAN_NUM_THREADS=1",compiler++"/bin/lean","-M1024","--run",
        (workspace/"tools/research/StudyBuildMain.lean").toString,path.toString]
    | "capture" | "prepare" | "observe-parent" | "observe-candidate" | "audit" | "corrupt" | "integration" | "replay" | "prefix" =>
      let parent := if mode == "capture" then "public-preparation-candidate-build" else
        if ["observe-candidate","audit","corrupt","integration","replay","prefix"].contains mode then "metadata-ingress-candidate-build" else "metadata-ingress-parent-build"
      let root := if ["corrupt","integration","replay","prefix"].contains mode then base/(tag++"-result") else fixture
      let dataRoot := if mode == "replay" || mode == "prefix" then root/"data" else privateRoot
      unless !(← dataRoot.pathExists) do throw (IO.userError "preserve private run")
      unless mode == "replay" || mode == "prefix" do IO.FS.createDirAll dataRoot
      pure #["/usr/bin/env","LEAN_NUM_THREADS=1","EGGSHELL_DATA_ROOT="++dataRoot.toString,
        "PLUGIN_ROOT="++(base/"metadata-ingress-no-plugin").toString,(base/parent/"StudyMain").toString,
        (if mode == "capture" then "public-preparation" else "metadata-ingress"),
        (if mode.startsWith "observe-" then "observe" else mode),root.toString]
    | "pairs" => pure #[compiler++"/bin/lean","-M512","--run",
        (workspace/"docs/candidates/source-incidence/paired.lean").toString,(base/(tag++"-result")).toString,
        (base/"metadata-ingress-parent-build/StudyMain").toString,(base/"metadata-ingress-candidate-build/StudyMain").toString]
    | "components" => pure #[compiler++"/bin/lean","-M512","--run",
        (workspace/"docs/candidates/metadata-ingress/components.lean").toString,(base/(tag++"-result")).toString]
    | "mixed" | "restart-audit" =>
      let root := base/(if mode == "mixed" then tag++"-result" else "metadata-ingress-mixed1-result")
      pure (#["/usr/bin/env","LEAN_NUM_THREADS=1","EGGSHELL_DATA_ROOT="++(root/"private").toString,
        "PLUGIN_ROOT="++(base/"metadata-ingress-no-plugin").toString,
        (base/"metadata-ingress-candidate-build/StudyMain").toString]++
        (if mode == "mixed" then #["front-traffic",root.toString,"80","5000"] else #["front-traffic-audit",root.toString]))
    | _ => throw (IO.userError "unknown metadata ingress action")
  IO.FS.writeFile (base/(tag++".guard-settings.json")) (Json.mkObj [("command",toJson command),
    ("cwd",toJson core.toString),("record",toJson (base/(tag++".guard.json")).toString),
    ("ownedPrefixes",toJson #[base.toString]),("limitRssKiB",toJson (3670016 : Nat)),
    ("minFreeKiB",toJson (2097152 : Nat))]).pretty
