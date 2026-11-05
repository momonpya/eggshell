import Lean.Data.Json.FromToJson
import Lean.Data.Json.Parser
open Lean
def base : System.FilePath := "/Users/ovm/.codex/experiments/eggshell/scope-token-study-20261028/fixed-frame-study"
def workspace : System.FilePath := "/Users/ovm/.codex/worktrees/hook-deadline-baseline/eggshell"
def compiler := "/Users/ovm/.elan/toolchains/leanprover--lean4---v4.33.0/bin/lean"
def read (path : System.FilePath) : IO Json := do IO.ofExcept (Json.parse (← IO.FS.readFile path))
def main (args : List String) : IO Unit := do
  let (tag,mode,arm) ← match args with
    | [tag,mode] => pure (tag,mode,"parent")
    | [tag,mode,arm] => pure (tag,mode,arm)
    | _ => throw (IO.userError "fresh focus-locators tag, mode and optional arm required")
  unless tag.startsWith "focus-locators-" && !(← (base/(tag++".guard.json")).pathExists) do
    throw (IO.userError "preserve earlier focus attempt")
  let parent := base/"metadata-ingress-candidate-build"
  let root := base/(tag++"-result")
  let command ← match mode with
    | "build" | "client-build" =>
      let core := base/"interest-traffic-core"
      let client := mode == "client-build"
      let name := if client then "WorkerCpuProfile" else "FocusLocatorChecks"
      let selected := if client then base/"focus-locators-build" else parent
      let output := if client then base/"focus-locators-client-build" else base/"focus-locators-build"
      IO.FS.writeFile (core/s!"tools/research/{name}.lean")
        (← IO.FS.readFile (workspace/s!"tools/research/{name}.lean"))
      let old ← read (base/"metadata-ingress-candidate-build-settings.json")
      let parents ← IO.ofExcept (old.getObjValAs? (Array String) "parents")
      let settings := old.setObjVal! "parents" (toJson (#[selected.toString,parent.toString]++parents))
        |>.setObjVal! "mainModule" (toJson ("tools.research."++name))
        |>.setObjVal! "output" (toJson output.toString)
        |>.setObjVal! "baselineCore" Json.null
        |>.setObjVal! "objectModules" (toJson (selected/"object-mapping.json").toString)
        |>.setObjVal! "baselineResponse" (toJson (selected/"runtime.rsp").toString)
        |>.setObjVal! "baselineMain" (toJson (selected/(if client then "tools_research_FocusLocatorChecks.o" else "tools_research_FrontTrafficChecks.o")).toString)
      let path := base/(if client then "focus-locators-client-build-settings.json" else "focus-locators-build-settings.json")
      IO.FS.writeFile path settings.pretty
      pure #["/usr/bin/env","LEAN_NUM_THREADS=1",compiler,"-M1024","--run",
        (workspace/"tools/research/StudyBuildMain.lean").toString,path.toString]
    | "checks" => pure #["/usr/bin/env","LEAN_NUM_THREADS=1",(base/"focus-locators-build/StudyMain").toString,
        "focus-locator-checks",root.toString]
    | "profile" | "burst" =>
      unless arm == "parent" || arm == "candidate" do throw (IO.userError "unknown profile arm")
      let target := if arm == "parent" then parent/"StudyMain" else base/"focus-locators-build/StudyMain"
      let aliasPath := base/"worker-cpu-target/bin/eggshelld"
      IO.FS.createDirAll aliasPath.parent.get!
      let metadata ← try pure (some (← aliasPath.symlinkMetadata)) catch _ => pure none
      if let some metadata := metadata then
        unless metadata.type == .symlink do throw (IO.userError "target alias is not a symlink")
        IO.FS.removeFile aliasPath
      let linked ← IO.Process.output {cmd := "/bin/ln",args := #["-s",target.toString,aliasPath.toString]}
      unless linked.exitCode == 0 do throw (IO.userError "cannot select target runtime")
      let sealed ← IO.Process.output {cmd := "/usr/bin/shasum",args := #["-a","256",target.toString]}
      unless sealed.exitCode == 0 do throw (IO.userError "cannot seal target runtime")
      let digest := (sealed.stdout.splitOn " ").headD ""
      pure #["/usr/bin/env","LEAN_NUM_THREADS=1","EGGSHELL_DATA_ROOT="++(root/"private").toString,
        "EGGSHELL_CONFIG="++(root/"eggshell.toml").toString,"PLUGIN_ROOT="++(base/"worker-cpu-target").toString,
        "EGGSHELL_TRACE_SERVICE_PROFILE=1",(base/"focus-locators-client-build/StudyMain").toString,
        root.toString,target.toString,digest,if mode == "burst" then "burst80" else "80"]
    | "pairs" => pure #["/usr/bin/env","LEAN_NUM_THREADS=1",compiler,"-j1","-M512","--run",
        (workspace/"docs/candidates/focus-locators/paired.lean").toString,tag]
    | _ => throw (IO.userError "unknown focus-locators mode")
  IO.FS.writeFile (base/(tag++".guard-settings.json")) (Json.mkObj [("command",toJson command),
    ("cwd",toJson workspace.toString),("record",toJson (base/(tag++".guard.json")).toString),
    ("ownedPrefixes",toJson #[base.toString]),("limitRssKiB",toJson (3670016 : Nat)),
    ("minFreeKiB",toJson (2097152 : Nat))]).pretty
