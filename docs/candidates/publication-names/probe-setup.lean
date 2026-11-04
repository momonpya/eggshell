import Lean.Data.Json.FromToJson
import Lean.Data.Json.Parser
open Lean
def base : System.FilePath := "/Users/ovm/.codex/experiments/eggshell/scope-token-study-20261028/fixed-frame-study"
def workspace : System.FilePath := "/Users/ovm/.codex/worktrees/hook-deadline-baseline/eggshell"
def read (path : System.FilePath) : IO Json := do IO.ofExcept (Json.parse (← IO.FS.readFile path))
def main (args : List String) : IO Unit := do
  let [mode,tag] := args | throw (IO.userError "mode and unique tag required")
  for entry in ← base.readDir do
    if entry.fileName.endsWith ".guard.json" && (entry.fileName.startsWith "interest-traffic-" ||
        entry.fileName.startsWith "publication-names-probe-") then
      let previous ← read entry.path
      unless previous.getObjValD "state" == toJson "finished" && previous.getObjValD "ownedPids" == toJson (#[] : Array Nat) do
        throw (IO.userError "previous guard still owns work")
  unless tag.startsWith "publication-names-probe-" && !(← (base/(tag++".guard.json")).pathExists) do
    throw (IO.userError "retain the previous controlled probe")
  let command ← if mode == "build" then do
      let old := (← read (base/"interest-traffic-build/build.json")).getObjValD "settings"
      let parents ← IO.ofExcept (old.getObjValAs? (Array String) "parents")
      let config := old.setObjVal! "baselineCore" (toJson (base/"interest-traffic-core").toString)
        |>.setObjVal! "parents" (toJson (#[ (base/"interest-traffic-build").toString ]++parents))
        |>.setObjVal! "output" (toJson (base/"publication-names-probe-build").toString)
        |>.setObjVal! "objectModules" (toJson (base/"interest-traffic-build/object-mapping.json").toString)
        |>.setObjVal! "baselineResponse" (toJson (base/"interest-traffic-build/runtime.rsp").toString)
        |>.setObjVal! "baselineMain" (toJson (base/"interest-traffic-build/tools_research_SharedInterestLoadChecks.o").toString)
        |>.setObjVal! "mainModule" (toJson "tools.research.TempAllocationChecks")
      IO.FS.writeFile (base/"publication-names-probe-build-settings.json") config.pretty
      pure #["/usr/bin/env","LEAN_NUM_THREADS=1",
        "/Users/ovm/.elan/toolchains/leanprover--lean4---v4.33.0/bin/lean","-M1024","--run",
        (workspace/"tools/research/StudyBuildMain.lean").toString,(base/"publication-names-probe-build-settings.json").toString]
    else if mode == "run" then
      pure #["/usr/bin/env","LEAN_NUM_THREADS=1",(base/"publication-names-probe-build/StudyMain").toString,
        (base/"interest-traffic-fixture-names-ablation").toString]
    else throw (IO.userError "build or run required")
  let value := Json.mkObj [("command",toJson command),("cwd",toJson workspace.toString),
    ("record",toJson (base/(tag++".guard.json")).toString),("ownedPrefixes",toJson #[base.toString]),
    ("limitRssKiB",toJson (3670016 : Nat)),("minFreeKiB",toJson (2097152 : Nat))]
  IO.FS.writeFile (base/(tag++".guard-settings.json")) value.pretty
