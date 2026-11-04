import Lean.Data.Json.FromToJson
import Lean.Data.Json.Parser
open Lean
def main (args : List String) : IO Unit := do
  let [mode,tag] := args | throw (IO.userError "build/run and unique tag required")
  let base : System.FilePath := "/Users/ovm/.codex/experiments/eggshell/scope-token-study-20261028/fixed-frame-study"
  let workspace : System.FilePath := "/Users/ovm/.codex/worktrees/hook-deadline-baseline/eggshell"
  for entry in ← base.readDir do
    if entry.fileName.startsWith "front-manager-" && entry.fileName.endsWith ".guard.json" then
      let value ← IO.ofExcept (Json.parse (← IO.FS.readFile entry.path))
      unless value.getObjValD "state" == toJson "finished" && value.getObjValD "ownedPids" == toJson (#[] : Array Nat) do
        throw (IO.userError "previous work is still owned")
  unless tag.startsWith "front-manager-" && !(← (base/(tag++".guard.json")).pathExists) do
    throw (IO.userError "retain previous guard")
  let command ← if mode == "build" then do
      let old ← IO.ofExcept (Json.parse (← IO.FS.readFile (base/"front-manager-build-settings.json")))
      let parents ← IO.ofExcept (old.getObjValAs? (Array String) "parents")
      let config := old.setObjVal! "baselineCore" (toJson (base/"interest-traffic-core").toString)
        |>.setObjVal! "parents" (toJson (#[(base/"front-manager-build").toString]++parents))
        |>.setObjVal! "output" (toJson (base/"front-retirement-build").toString)
        |>.setObjVal! "objectModules" (toJson (base/"front-manager-build/object-mapping.json").toString)
        |>.setObjVal! "baselineResponse" (toJson (base/"front-manager-build/runtime.rsp").toString)
        |>.setObjVal! "baselineMain" (toJson (base/"front-manager-build/tools_research_FrontManagerChecks.o").toString)
        |>.setObjVal! "mainModule" (toJson "tools.research.FrontRetirementChecks")
      IO.FS.writeFile (base/"front-retirement-build-settings.json") config.pretty
      pure #["/usr/bin/env","LEAN_NUM_THREADS=1",
        "/Users/ovm/.elan/toolchains/leanprover--lean4---v4.33.0/bin/lean","-M1024","--run",
        (workspace/"tools/research/StudyBuildMain.lean").toString,(base/"front-retirement-build-settings.json").toString]
    else if mode == "run" then pure #["/usr/bin/env","LEAN_NUM_THREADS=1",
      "EGGSHELL_DATA_ROOT="++(base/"front-manager-fixture/private").toString,
      "PLUGIN_ROOT="++(base/"front-manager-fixture/no-plugin-bundle").toString,
      (base/"front-retirement-build/StudyMain").toString,(base/"front-manager-fixture").toString]
    else throw (IO.userError "build/run required")
  let config := Json.mkObj [("command",toJson command),("cwd",toJson workspace.toString),
    ("record",toJson (base/(tag++".guard.json")).toString),("ownedPrefixes",toJson #[base.toString]),
    ("limitRssKiB",toJson (3670016 : Nat)),("minFreeKiB",toJson (2097152 : Nat))]
  IO.FS.writeFile (base/(tag++".guard-settings.json")) config.pretty
