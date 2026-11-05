import Lean.Data.Json.FromToJson
import Lean.Data.Json.Parser
open Lean
def base : System.FilePath := "/Users/ovm/.codex/experiments/eggshell/scope-token-study-20261028/fixed-frame-study"
def workspace : System.FilePath := "/Users/ovm/.codex/worktrees/hook-deadline-baseline/eggshell"
def compiler := "/Users/ovm/.elan/toolchains/leanprover--lean4---v4.33.0/bin/lean"
def read (path : System.FilePath) : IO Json := do IO.ofExcept (Json.parse (← IO.FS.readFile path))
def main (args : List String) : IO Unit := do
  let [tag,mode] := args | throw (IO.userError "fresh worker-cpu tag and build/profile required")
  unless tag.startsWith "worker-cpu-" && !(← (base/(tag++".guard.json")).pathExists) do
    throw (IO.userError "preserve prior profile attempt")
  let root := base/(tag++"-result")
  let parent := base/"metadata-ingress-candidate-build"
  let command ← match mode with
    | "build" =>
      let core := base/"interest-traffic-core"
      IO.FS.writeFile (core/"tools/research/WorkerCpuProfile.lean")
        (← IO.FS.readFile (workspace/"tools/research/WorkerCpuProfile.lean"))
      let old ← read (base/"metadata-ingress-candidate-build-settings.json")
      let parents ← IO.ofExcept (old.getObjValAs? (Array String) "parents")
      let settings := old.setObjVal! "parents" (toJson (#[parent.toString]++parents))
        |>.setObjVal! "mainModule" (toJson "tools.research.WorkerCpuProfile")
        |>.setObjVal! "output" (toJson (base/"worker-cpu-build").toString)
        |>.setObjVal! "baselineCore" Json.null
        |>.setObjVal! "objectModules" (toJson (parent/"object-mapping.json").toString)
        |>.setObjVal! "baselineResponse" (toJson (parent/"runtime.rsp").toString)
        |>.setObjVal! "baselineMain" (toJson (parent/"tools_research_FrontTrafficChecks.o").toString)
      let path := base/"worker-cpu-build-settings.json"
      IO.FS.writeFile path settings.pretty
      pure #["/usr/bin/env","LEAN_NUM_THREADS=1",compiler,"-M1024","--run",
        (workspace/"tools/research/StudyBuildMain.lean").toString,path.toString]
    | "profile" | "profile-candidate" =>
      let target := if mode == "profile" then parent/"StudyMain" else base/"maintenance-scope-build/StudyMain"
      let shim := base/"worker-cpu-target/bin/eggshelld"
      IO.FS.createDirAll shim.parent.get!
      if ← shim.pathExists then
        unless (← shim.symlinkMetadata).type == .symlink do throw (IO.userError "target alias is not a symlink")
        IO.FS.removeFile shim
      let linked ← IO.Process.output {cmd := "/bin/ln",args := #["-s",target.toString,shim.toString]}
      unless linked.exitCode == 0 do throw (IO.userError "cannot select frozen target runtime")
      unless (← IO.FS.realPath shim) == (← IO.FS.realPath target) do
        throw (IO.userError "native client target changed")
      let sealed ← IO.Process.output {cmd := "/usr/bin/shasum",args := #["-a","256",target.toString]}
      unless sealed.exitCode == 0 do throw (IO.userError "cannot seal target runtime")
      let digest := (sealed.stdout.splitOn " ").headD ""
      pure #["/usr/bin/env","LEAN_NUM_THREADS=1","EGGSHELL_DATA_ROOT="++(root/"private").toString,
        "EGGSHELL_CONFIG="++(root/"eggshell.toml").toString,"PLUGIN_ROOT="++(base/"worker-cpu-target").toString,
        "EGGSHELL_TRACE_SERVICE_PROFILE=1",(base/"worker-cpu-build/StudyMain").toString,root.toString,target.toString,digest]
    | _ => throw (IO.userError "unknown worker-cpu mode")
  IO.FS.writeFile (base/(tag++".guard-settings.json")) (Json.mkObj [("command",toJson command),
    ("cwd",toJson workspace.toString),("record",toJson (base/(tag++".guard.json")).toString),
    ("ownedPrefixes",toJson #[base.toString]),("limitRssKiB",toJson (3670016 : Nat)),
    ("minFreeKiB",toJson (2097152 : Nat))]).pretty
