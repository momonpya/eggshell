import Lean.Data.Json.FromToJson
import Lean.Data.Json.Parser
open Lean
def base : System.FilePath := "/Users/ovm/.codex/experiments/eggshell/scope-token-study-20261028/fixed-frame-study"
def workspace : System.FilePath := "/Users/ovm/.codex/worktrees/hook-deadline-baseline/eggshell"
def core := base/"source-graph-core"
def taskLean := "/Users/ovm/.elan/toolchains/leanprover--lean4---v4.33.0/bin/lean"
def read (path : System.FilePath) : IO Json := do IO.ofExcept (Json.parse (← IO.FS.readFile path))
def main (args : List String) : IO Unit := do
  let mode :: tag :: rest := args | throw (IO.userError "mode and unique tag required")
  unless tag.startsWith "source-graph-" do throw (IO.userError "controlled tag required")
  for entry in ← base.readDir do
    if entry.fileName.startsWith "source-graph-" && entry.fileName.endsWith ".guard.json" then
      let previous ← read entry.path
      unless previous.getObjValD "state" == toJson "finished" && previous.getObjValD "ownedPids" == toJson (#[] : Array Nat) do
        throw (IO.userError "previous guard still owns work")
  unless !(← (base/(tag++".guard.json")).pathExists) do throw (IO.userError "preserve previous guard")
  let command ← if mode == "build" then do
      IO.FS.writeFile (base/"source-graph-latest-build.json") (toJson (tag++".guard.json")).compress
      IO.FS.writeFile (core/"Main.lean")
        ((← IO.FS.readFile (base/"source-route-core/Main.lean")).replace
          "def main (arguments : List String)" "def sourceRouteEngine (arguments : List String)")
      IO.FS.writeFile (core/"tools/research/SourceRouteChecks.lean")
        (← IO.FS.readFile (workspace/"tools/research/SourceRouteChecks.lean"))
      let old := (← read (base/"source-route-build/build.json")).getObjValD "settings"
      let parents ← IO.ofExcept (old.getObjValAs? (Array String) "parents")
      let settings := old.setObjVal! "project" (toJson core.toString)
        |>.setObjVal! "core" (toJson core.toString)
        |>.setObjVal! "baselineCore" (toJson (base/"source-route-core").toString)
        |>.setObjVal! "parents" (toJson (#[ (base/"source-route-build").toString ]++parents))
        |>.setObjVal! "output" (toJson (base/"source-graph-build").toString)
        |>.setObjVal! "objectModules" (toJson (base/"source-route-build/object-mapping.json").toString)
        |>.setObjVal! "baselineResponse" (toJson (base/"source-route-build/runtime.rsp").toString)
        |>.setObjVal! "baselineMain" (toJson (base/"source-route-build/tools_research_SourceRouteChecks.o").toString)
        |>.setObjVal! "mainModule" (toJson "tools.research.SourceRouteChecks")
      IO.FS.writeFile (base/"source-graph-build-settings.json") (settings.pretty++"\n")
      pure #["/usr/bin/env","LEAN_NUM_THREADS=1",taskLean,"-M1024","--run",
        (workspace/"tools/research/StudyBuildMain.lean").toString,(base/"source-graph-build-settings.json").toString]
    else if mode == "run" then do
      let latest ← IO.ofExcept ((← read (base/"source-graph-latest-build.json")).getStr?)
      let completed ← read (base/latest)
      unless completed.getObjValD "state" == toJson "finished" && completed.getObjValD "exitCode" == toJson (0 : Nat) &&
          completed.getObjValD "guardTriggered" == toJson false do
        throw (IO.userError "latest candidate build did not succeed; refusing an older executable")
      unless (← IO.FS.readFile (core/"tools/research/SourceRouteChecks.lean")) ==
          (← IO.FS.readFile (workspace/"tools/research/SourceRouteChecks.lean")) do
        throw (IO.userError "native checker source changed after its build")
      let directory :: nativeArgs := rest | throw (IO.userError "fixture and command required")
      let fixture : System.FilePath := .mk directory
      unless fixture.isAbsolute && (directory.startsWith (base.toString++"/source-graph-fixture-") ||
          (directory == (base/"source-route-fixture-fixed").toString && nativeArgs.head? == some "source-route-replay")) do
        throw (IO.userError "controlled fresh fixture required")
      pure (#["/usr/bin/env","LEAN_NUM_THREADS=1","PLUGIN_ROOT="++(fixture/"no-plugin-bundle").toString,
        "EGGSHELL_HANDOFF_TRACE="++(fixture/"handoff.log").toString,
        "EGGSHELL_DATA_ROOT="++(fixture/"private").toString,(base/"source-graph-build/StudyMain").toString]++nativeArgs.toArray)
    else throw (IO.userError "build or run required")
  let settings := Json.mkObj [("command",toJson command),("cwd",toJson workspace.toString),
    ("record",toJson (base/(tag++".guard.json")).toString),("ownedPrefixes",toJson #[base.toString]),
    ("limitRssKiB",toJson (3670016 : Nat)),("minFreeKiB",toJson (2097152 : Nat))]
  IO.FS.writeFile (base/(tag++".guard-settings.json")) (settings.pretty++"\n")
