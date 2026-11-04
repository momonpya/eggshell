import Lean.Data.Json.FromToJson
import Lean.Data.Json.Parser
open Lean
def base : System.FilePath := "/Users/ovm/.codex/experiments/eggshell/scope-token-study-20261028/fixed-frame-study"
def workspace : System.FilePath := "/Users/ovm/.codex/worktrees/hook-deadline-baseline/eggshell"
def core := base/"source-owner-core"
def taskLean := "/Users/ovm/.elan/toolchains/leanprover--lean4---v4.33.0/bin/lean"
def read (path : System.FilePath) : IO Json := do IO.ofExcept (Json.parse (← IO.FS.readFile path))
def main (args : List String) : IO Unit := do
  let mode :: tag :: rest := args | throw (IO.userError "mode and unique tag required")
  unless tag.startsWith "source-owner-" do throw (IO.userError "controlled tag required")
  for entry in ← base.readDir do
    if entry.fileName.startsWith "source-owner-" && entry.fileName.endsWith ".guard.json" then
      let previous ← read entry.path
      unless previous.getObjValD "state" == toJson "finished" && previous.getObjValD "ownedPids" == toJson (#[] : Array Nat) do
        throw (IO.userError "previous guard still owns work")
  unless !(← (base/(tag++".guard.json")).pathExists) do throw (IO.userError "preserve previous guard")
  let command ← if mode == "build" then do
      IO.FS.writeFile (core/"Eggshell/SourceBitmap.lean")
        (← IO.FS.readFile (workspace/"docs/candidates/source-owners/SourceBitmap.lean"))
      IO.FS.writeFile (core/"Eggshell/SourceOwners.lean")
        (← IO.FS.readFile (workspace/"docs/candidates/source-owners/SourceOwners.lean"))
      IO.FS.writeFile (core/"tools/research/SourceOwnerChecks.lean")
        (← IO.FS.readFile (workspace/"tools/research/SourceOwnerChecks.lean"))
      let old := (← read (base/"prepared-owner-build/build.json")).getObjValD "settings"
      let parents ← IO.ofExcept (old.getObjValAs? (Array String) "parents")
      let settings := old.setObjVal! "project" (toJson core.toString)
        |>.setObjVal! "core" (toJson core.toString)
        |>.setObjVal! "baselineCore" (toJson (base/"prepared-owner-core").toString)
        |>.setObjVal! "parents" (toJson (#[ (base/"prepared-owner-build").toString ]++parents))
        |>.setObjVal! "output" (toJson (base/"source-owner-build").toString)
        |>.setObjVal! "objectModules" (toJson (base/"prepared-owner-build/object-mapping.json").toString)
        |>.setObjVal! "baselineResponse" (toJson (base/"prepared-owner-build/runtime.rsp").toString)
        |>.setObjVal! "baselineMain" (toJson (base/"prepared-owner-build/tools_research_PreparedOwnerChecks.o").toString)
        |>.setObjVal! "mainModule" (toJson "tools.research.SourceOwnerChecks")
      IO.FS.writeFile (base/"source-owner-build-settings.json") (settings.pretty++"\n")
      pure #["/usr/bin/env","LEAN_NUM_THREADS=1",taskLean,"-M1024","--run",
        (workspace/"tools/research/StudyBuildMain.lean").toString,(base/"source-owner-build-settings.json").toString]
    else if mode == "run" then do
      let directory :: nativeArgs := rest | throw (IO.userError "fixture and command required")
      let fixture : System.FilePath := .mk directory
      unless fixture.isAbsolute && directory.startsWith (base.toString++"/source-owner-fixture-") do
        throw (IO.userError "controlled fresh fixture required")
      pure (#["/usr/bin/env","LEAN_NUM_THREADS=1","PLUGIN_ROOT="++(fixture/"no-plugin-bundle").toString,
        "EGGSHELL_DATA_ROOT="++(fixture/"private").toString,(base/"source-owner-build/StudyMain").toString]++nativeArgs.toArray)
    else throw (IO.userError "build or run required")
  let settings := Json.mkObj [("command",toJson command),("cwd",toJson workspace.toString),
    ("record",toJson (base/(tag++".guard.json")).toString),("ownedPrefixes",toJson #[base.toString]),
    ("limitRssKiB",toJson (3670016 : Nat)),("minFreeKiB",toJson (2097152 : Nat))]
  IO.FS.writeFile (base/(tag++".guard-settings.json")) (settings.pretty++"\n")
