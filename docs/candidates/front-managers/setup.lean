import Lean.Data.Json.FromToJson
import Lean.Data.Json.Parser
open Lean
def base : System.FilePath := "/Users/ovm/.codex/experiments/eggshell/scope-token-study-20261028/fixed-frame-study"
def workspace : System.FilePath := "/Users/ovm/.codex/worktrees/hook-deadline-baseline/eggshell"
def read (path : System.FilePath) : IO Json := do IO.ofExcept (Json.parse (← IO.FS.readFile path))
def main (args : List String) : IO Unit := do
  let mode :: tag :: rest := args | throw (IO.userError "mode and unique tag required")
  for entry in ← base.readDir do
    if entry.fileName.endsWith ".guard.json" && (entry.fileName.startsWith "interest-traffic-" || entry.fileName.startsWith "front-manager-") then
      let prior ← read entry.path
      unless prior.getObjValD "state" == toJson "finished" && prior.getObjValD "ownedPids" == toJson (#[] : Array Nat) do
        throw (IO.userError "previous guard still owns work")
  unless tag.startsWith "front-manager-" && !(← (base/(tag++".guard.json")).pathExists) do
    throw (IO.userError "keep the previous guard")
  let fixture := base/"front-manager-fixture"
  let command ← if mode == "build" then do
      let old := (← read (base/"interest-traffic-build/build.json")).getObjValD "settings"
      let parents ← IO.ofExcept (old.getObjValAs? (Array String) "parents")
      let config := old.setObjVal! "baselineCore" (toJson (base/"front-manager-baseline-core").toString)
        |>.setObjVal! "parents" (toJson (#[ (base/"interest-traffic-build").toString ]++parents))
        |>.setObjVal! "output" (toJson (base/"front-manager-build").toString)
        |>.setObjVal! "objectModules" (toJson (base/"interest-traffic-build/object-mapping.json").toString)
        |>.setObjVal! "baselineResponse" (toJson (base/"interest-traffic-build/runtime.rsp").toString)
        |>.setObjVal! "baselineMain" (toJson (base/"interest-traffic-build/tools_research_SharedInterestLoadChecks.o").toString)
        |>.setObjVal! "mainModule" (toJson "tools.research.FrontManagerChecks")
      IO.FS.writeFile (base/"front-manager-build-settings.json") config.pretty
      pure #["/usr/bin/env","LEAN_NUM_THREADS=1",
        "/Users/ovm/.elan/toolchains/leanprover--lean4---v4.33.0/bin/lean","-M1024","--run",
        (workspace/"tools/research/StudyBuildMain.lean").toString,(base/"front-manager-build-settings.json").toString]
    else if mode == "fixture" then
      pure #["/usr/bin/env","LEAN_NUM_THREADS=1","PLUGIN_ROOT="++(fixture/"no-plugin-bundle").toString,
        "EGGSHELL_DATA_ROOT="++(fixture/"private").toString,(base/"interest-traffic-build/StudyMain").toString,
        "traffic-cold-fixture",fixture.toString]
    else if mode == "run" then
      pure (#["/usr/bin/env","LEAN_NUM_THREADS=1","PLUGIN_ROOT="++(fixture/"no-plugin-bundle").toString,
        "EGGSHELL_DATA_ROOT="++(fixture/"private").toString,(base/"front-manager-build/StudyMain").toString]++rest.toArray++#[fixture.toString])
    else throw (IO.userError "build, fixture or run required")
  let value := Json.mkObj [("command",toJson command),("cwd",toJson workspace.toString),
    ("record",toJson (base/(tag++".guard.json")).toString),("ownedPrefixes",toJson #[base.toString]),
    ("limitRssKiB",toJson (3670016 : Nat)),("minFreeKiB",toJson (2097152 : Nat))]
  IO.FS.writeFile (base/(tag++".guard-settings.json")) value.pretty
