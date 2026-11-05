import Lean.Data.Json.FromToJson
import Lean.Data.Json.Parser
open Lean
def base : System.FilePath := "/Users/ovm/.codex/experiments/eggshell/scope-token-study-20261028/fixed-frame-study"
def workspace : System.FilePath := "/Users/ovm/.codex/worktrees/hook-deadline-baseline/eggshell"
def compiler := "/Users/ovm/.elan/toolchains/leanprover--lean4---v4.33.0/bin/lean"
def read (path : System.FilePath) : IO Json := do IO.ofExcept (Json.parse (← IO.FS.readFile path))
def main (args : List String) : IO Unit := do
  let [tag,mode] := args | throw (IO.userError "fresh session-readers tag and build/checks required")
  unless tag.startsWith "session-readers-" && !(← (base/(tag++".guard.json")).pathExists) do
    throw (IO.userError "preserve prior component attempt")
  let command ← match mode with
    | "build" =>
      let core := base/"interest-traffic-core"
      IO.FS.writeFile (core/"tools/research/SessionReaderChecks.lean")
        (← IO.FS.readFile (workspace/"tools/research/SessionReaderChecks.lean"))
      let parent := base/"focus-locators-build"
      let old ← read (base/"metadata-ingress-candidate-build-settings.json")
      let parents ← IO.ofExcept (old.getObjValAs? (Array String) "parents")
      let settings := old.setObjVal! "parents" (toJson (#[parent.toString,(base/"metadata-ingress-candidate-build").toString]++parents))
        |>.setObjVal! "mainModule" (toJson "tools.research.SessionReaderChecks")
        |>.setObjVal! "output" (toJson (base/"session-readers-build").toString)
        |>.setObjVal! "baselineCore" Json.null
        |>.setObjVal! "objectModules" (toJson (parent/"object-mapping.json").toString)
        |>.setObjVal! "baselineResponse" (toJson (parent/"runtime.rsp").toString)
        |>.setObjVal! "baselineMain" (toJson (parent/"tools_research_FocusLocatorChecks.o").toString)
      let path := base/"session-readers-build-settings.json"
      IO.FS.writeFile path settings.pretty
      pure #["/usr/bin/env","LEAN_NUM_THREADS=1",compiler,"-M1024","--run",
        (workspace/"tools/research/StudyBuildMain.lean").toString,path.toString]
    | "checks" =>
      let root := base/(tag++"-result")
      pure #["/usr/bin/env","LEAN_NUM_THREADS=1","EGGSHELL_DATA_ROOT="++(root/"private").toString,
        "PLUGIN_ROOT="++(base/"session-readers-no-plugin").toString,
        (base/"session-readers-build/StudyMain").toString,"session-reader-checks",root.toString]
    | _ => throw (IO.userError "unknown component mode")
  IO.FS.writeFile (base/(tag++".guard-settings.json")) (Json.mkObj [("command",toJson command),
    ("cwd",toJson workspace.toString),("record",toJson (base/(tag++".guard.json")).toString),
    ("ownedPrefixes",toJson #[base.toString]),("limitRssKiB",toJson (3670016 : Nat)),
    ("minFreeKiB",toJson (2097152 : Nat))]).pretty
