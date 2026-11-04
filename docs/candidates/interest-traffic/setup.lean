import Lean.Data.Json.FromToJson
import Lean.Data.Json.Parser
open Lean
def base : System.FilePath := "/Users/ovm/.codex/experiments/eggshell/scope-token-study-20261028/fixed-frame-study"
def workspace : System.FilePath := "/Users/ovm/.codex/worktrees/hook-deadline-baseline/eggshell"
def core := base/"interest-traffic-core"
def taskLean := "/Users/ovm/.elan/toolchains/leanprover--lean4---v4.33.0/bin/lean"
def read (path : System.FilePath) : IO Json := do IO.ofExcept (Json.parse (← IO.FS.readFile path))
def main (args : List String) : IO Unit := do
  let mode :: tag :: rest := args | throw (IO.userError "mode and unique tag required")
  unless tag.startsWith "interest-traffic-" do throw (IO.userError "controlled tag required")
  for entry in ← base.readDir do
    if entry.fileName.startsWith "interest-traffic-" && entry.fileName.endsWith ".guard.json" then
      let previous ← read entry.path
      unless previous.getObjValD "state" == toJson "finished" && previous.getObjValD "ownedPids" == toJson (#[] : Array Nat) do
        throw (IO.userError "previous guard still owns work")
  unless !(← (base/(tag++".guard.json")).pathExists) do throw (IO.userError "retain previous guard")
  let command ← if mode == "build" then do
      IO.FS.writeFile (base/"interest-traffic-latest-build.json") (toJson (tag++".guard.json")).compress
      IO.FS.writeFile (core/"tools/research/SharedInterestLoadChecks.lean")
        (← IO.FS.readFile (workspace/"tools/research/SharedInterestLoadChecks.lean"))
      IO.FS.writeFile (core/"tools/research/ConcurrentHookChecks.lean")
        (← IO.FS.readFile (workspace/"tools/research/ConcurrentHookChecks.lean"))
      IO.FS.writeFile (core/"tools/research/SourcePreparationChecks.lean")
        (← IO.FS.readFile (workspace/"tools/research/SourcePreparationChecks.lean"))
      IO.FS.writeFile (core/"tools/research/ImmutablePublicationChecks.lean")
        (← IO.FS.readFile (workspace/"tools/research/ImmutablePublicationChecks.lean"))
      let old := (← read (base/"interest-lifetime-build/build.json")).getObjValD "settings"
      let parents ← IO.ofExcept (old.getObjValAs? (Array String) "parents")
      let settings := old.setObjVal! "project" (toJson core.toString)
        |>.setObjVal! "core" (toJson core.toString)
        |>.setObjVal! "baselineCore" (toJson (base/"interest-lifetime-core").toString)
        |>.setObjVal! "parents" (toJson (#[ (base/"interest-lifetime-build").toString ]++parents))
        |>.setObjVal! "output" (toJson (base/"interest-traffic-build").toString)
        |>.setObjVal! "objectModules" (toJson (base/"interest-lifetime-build/object-mapping.json").toString)
        |>.setObjVal! "baselineResponse" (toJson (base/"interest-lifetime-build/runtime.rsp").toString)
        |>.setObjVal! "baselineMain" (toJson (base/"interest-lifetime-build/tools_research_InterestLifetimeChecks.o").toString)
        |>.setObjVal! "mainModule" (toJson "tools.research.SharedInterestLoadChecks")
      IO.FS.writeFile (base/"interest-traffic-build-settings.json") (settings.pretty++"\n")
      pure #["/usr/bin/env","LEAN_NUM_THREADS=1",taskLean,"-M1024","--run",
        (workspace/"tools/research/StudyBuildMain.lean").toString,(base/"interest-traffic-build-settings.json").toString]
    else if mode == "run" then do
      let latest ← IO.ofExcept ((← read (base/"interest-traffic-latest-build.json")).getStr?)
      let completed ← read (base/latest)
      unless completed.getObjValD "state" == toJson "finished" && completed.getObjValD "exitCode" == toJson (0 : Nat) do
        throw (IO.userError "latest build did not succeed")
      unless (← IO.FS.readFile (core/"tools/research/SharedInterestLoadChecks.lean")) ==
          (← IO.FS.readFile (workspace/"tools/research/SharedInterestLoadChecks.lean")) do
        throw (IO.userError "native checker changed after its build")
      let directory :: nativeArgs := rest | throw (IO.userError "fixture and native command required")
      let fixture : System.FilePath := .mk directory
      unless fixture.isAbsolute && directory.startsWith (base.toString++"/interest-traffic-fixture-") do
        throw (IO.userError "controlled fixture required")
      pure (#["/usr/bin/env","LEAN_NUM_THREADS=1","PLUGIN_ROOT="++(fixture/"no-plugin-bundle").toString,
        "EGGSHELL_DATA_ROOT="++(fixture/"private").toString,(base/"interest-traffic-build/StudyMain").toString]++nativeArgs.toArray)
    else throw (IO.userError "build or run required")
  let settings := Json.mkObj [("command",toJson command),("cwd",toJson workspace.toString),
    ("record",toJson (base/(tag++".guard.json")).toString),("ownedPrefixes",toJson #[base.toString]),
    ("limitRssKiB",toJson (3670016 : Nat)),("minFreeKiB",toJson (2097152 : Nat))]
  IO.FS.writeFile (base/(tag++".guard-settings.json")) settings.pretty
