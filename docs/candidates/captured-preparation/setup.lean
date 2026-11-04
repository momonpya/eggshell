import Lean.Data.Json.FromToJson
import Lean.Data.Json.Parser
open Lean
def base : System.FilePath := "/Users/ovm/.codex/experiments/eggshell/scope-token-study-20261028/fixed-frame-study"
def workspace : System.FilePath := "/Users/ovm/.codex/worktrees/hook-deadline-baseline/eggshell"
def core := base/"cut-preparation-core"
def taskLean := "/Users/ovm/.elan/toolchains/leanprover--lean4---v4.33.0/bin/lean"
def read (path : System.FilePath) : IO Json := do IO.ofExcept (Json.parse (← IO.FS.readFile path))
def main (args : List String) : IO Unit := do
  let mode :: tag :: rest := args | throw (IO.userError "mode and unique tag required")
  unless tag.startsWith "cut-preparation-" do throw (IO.userError "controlled tag required")
  for entry in ← base.readDir do
    if entry.fileName.startsWith "cut-preparation-" && entry.fileName.endsWith ".guard.json" then
      let previous ← read entry.path
      unless previous.getObjValD "state" == toJson "finished" && previous.getObjValD "ownedPids" == toJson (#[] : Array Nat) do
        throw (IO.userError "previous guard still owns work")
  unless !(← (base/(tag++".guard.json")).pathExists) do throw (IO.userError "retain previous guard")
  let command ← if mode == "build" then do
      IO.FS.writeFile (base/"cut-preparation-latest-build.json") (toJson (tag++".guard.json")).compress
      IO.FS.writeFile (core/"tools/research/CapturedPreparationChecks.lean")
        (← IO.FS.readFile (workspace/"tools/research/CapturedPreparationChecks.lean"))
      let old := (← read (base/"source-cue-build/build.json")).getObjValD "settings"
      let parents ← IO.ofExcept (old.getObjValAs? (Array String) "parents")
      let settings := old.setObjVal! "project" (toJson core.toString)
        |>.setObjVal! "core" (toJson core.toString)
        |>.setObjVal! "baselineCore" (toJson (base/"source-cue-core").toString)
        |>.setObjVal! "parents" (toJson (#[ (base/"source-cue-build").toString ]++parents))
        |>.setObjVal! "output" (toJson (base/"cut-preparation-build").toString)
        |>.setObjVal! "objectModules" (toJson (base/"source-cue-build/object-mapping.json").toString)
        |>.setObjVal! "baselineResponse" (toJson (base/"source-cue-build/runtime.rsp").toString)
        |>.setObjVal! "baselineMain" (toJson (base/"source-cue-build/tools_research_SourceRouteChecks.o").toString)
        |>.setObjVal! "mainModule" (toJson "tools.research.CapturedPreparationChecks")
      IO.FS.writeFile (base/"cut-preparation-build-settings.json") (settings.pretty++"\n")
      pure #["/usr/bin/env","LEAN_NUM_THREADS=1",taskLean,"-M1024","--run",
        (workspace/"tools/research/StudyBuildMain.lean").toString,(base/"cut-preparation-build-settings.json").toString]
    else if mode == "run" then do
      let latest ← IO.ofExcept ((← read (base/"cut-preparation-latest-build.json")).getStr?)
      let completed ← read (base/latest)
      unless completed.getObjValD "state" == toJson "finished" && completed.getObjValD "exitCode" == toJson (0 : Nat) do
        throw (IO.userError "latest build did not succeed")
      unless (← IO.FS.readFile (core/"tools/research/CapturedPreparationChecks.lean")) ==
          (← IO.FS.readFile (workspace/"tools/research/CapturedPreparationChecks.lean")) do
        throw (IO.userError "native checker changed after its build")
      let directory :: nativeArgs := rest | throw (IO.userError "fixture and native command required")
      let fixture : System.FilePath := .mk directory
      unless fixture.isAbsolute && directory.startsWith (base.toString++"/cut-preparation-fixture-") do
        throw (IO.userError "controlled fixture required")
      pure (#["/usr/bin/env","LEAN_NUM_THREADS=1","PLUGIN_ROOT="++(fixture/"no-plugin-bundle").toString,
        "EGGSHELL_DATA_ROOT="++(fixture/"private").toString,(base/"cut-preparation-build/StudyMain").toString]++nativeArgs.toArray)
    else throw (IO.userError "build or run required")
  let settings := Json.mkObj [("command",toJson command),("cwd",toJson workspace.toString),
    ("record",toJson (base/(tag++".guard.json")).toString),("ownedPrefixes",toJson #[base.toString]),
    ("limitRssKiB",toJson (3670016 : Nat)),("minFreeKiB",toJson (2097152 : Nat))]
  IO.FS.writeFile (base/(tag++".guard-settings.json")) settings.pretty
