import Lean.Data.Json.FromToJson
import Lean.Data.Json.Parser
open Lean
def base : System.FilePath := "/Users/ovm/.codex/experiments/eggshell/scope-token-study-20261028/fixed-frame-study"
def workspace : System.FilePath := "/Users/ovm/.codex/worktrees/hook-deadline-baseline/eggshell"
def main (args : List String) : IO Unit := do
  let mode::tag::rest := args | throw (IO.userError "mode and unique tag required")
  for entry in ← base.readDir do
    if (entry.fileName.startsWith "front-manager-" || entry.fileName.startsWith "front-traffic-") &&
        entry.fileName.endsWith ".guard.json" then
      let value ← IO.ofExcept (Json.parse (← IO.FS.readFile entry.path))
      unless value.getObjValD "state" == toJson "finished" && value.getObjValD "ownedPids" == toJson (#[] : Array Nat) do
        throw (IO.userError "previous work is still owned")
  unless tag.startsWith "front-traffic-" && !(← (base/(tag++".guard.json")).pathExists) do
    throw (IO.userError "retain previous guard")
  let command ← if mode == "build" then do
      let old ← IO.ofExcept (Json.parse (← IO.FS.readFile (base/"front-manager-build-settings.json")))
      let parents ← IO.ofExcept (old.getObjValAs? (Array String) "parents")
      let config := old.setObjVal! "baselineCore" (toJson (base/"front-traffic-baseline-core").toString)
        |>.setObjVal! "parents" (toJson (#[(base/"front-traffic-parent-build").toString,(base/"front-manager-build").toString]++parents))
        |>.setObjVal! "output" (toJson (base/"front-traffic-build").toString)
        |>.setObjVal! "objectModules" (toJson (base/"front-manager-build/object-mapping.json").toString)
        |>.setObjVal! "baselineResponse" (toJson (base/"front-manager-build/runtime.rsp").toString)
        |>.setObjVal! "baselineMain" (toJson (base/"front-manager-build/tools_research_FrontManagerChecks.o").toString)
        |>.setObjVal! "mainModule" (toJson "tools.research.FrontTrafficChecks")
      IO.FS.writeFile (base/"front-traffic-build-settings.json") config.pretty
      pure #["/usr/bin/env","LEAN_NUM_THREADS=1",
        "/Users/ovm/.elan/toolchains/leanprover--lean4---v4.33.0/bin/lean","-M1024","--run",
        (workspace/"tools/research/StudyBuildMain.lean").toString,(base/"front-traffic-build-settings.json").toString]
    else if mode == "checks" || mode == "audit" then do
      let [fixture] := rest | throw (IO.userError "fresh controlled fixture required")
      unless fixture.startsWith "front-traffic-fixture-" do throw (IO.userError "controlled fixture prefix required")
      let root := base/fixture
      pure #["/usr/bin/env","LEAN_NUM_THREADS=1","PLUGIN_ROOT="++(root/"no-plugin-bundle").toString,
        "EGGSHELL_DATA_ROOT="++(root/"private").toString,(base/"front-traffic-build/StudyMain").toString,
        if mode == "checks" then "front-deadline-checks" else "front-traffic-audit",root.toString]
    else if mode == "run" || mode == "profile" then do
      let [fixture,count,size] := rest | throw (IO.userError "fresh fixture name, count and size required")
      unless fixture.startsWith "front-traffic-fixture-" do throw (IO.userError "isolated fixture prefix required")
      let root := base/fixture
      pure #["/usr/bin/env","LEAN_NUM_THREADS=1","PLUGIN_ROOT="++(root/"no-plugin-bundle").toString,
        "EGGSHELL_DATA_ROOT="++(root/"private").toString,(base/"front-traffic-build/StudyMain").toString,
        if mode == "profile" then "front-traffic-profile" else "front-traffic",root.toString,count,size]
    else throw (IO.userError "build/run required")
  let config := Json.mkObj [("command",toJson command),("cwd",toJson workspace.toString),
    ("record",toJson (base/(tag++".guard.json")).toString),("ownedPrefixes",toJson #[base.toString]),
    ("limitRssKiB",toJson (3670016 : Nat)),("minFreeKiB",toJson (2097152 : Nat))]
  IO.FS.writeFile (base/(tag++".guard-settings.json")) config.pretty
