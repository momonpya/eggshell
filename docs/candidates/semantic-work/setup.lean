import Lean.Data.Json.FromToJson
import Lean.Data.Json.Parser
open Lean
def base : System.FilePath := "/Users/ovm/.codex/experiments/eggshell/scope-token-study-20261028/fixed-frame-study"
def workspace : System.FilePath := "/Users/ovm/.codex/worktrees/hook-deadline-baseline/eggshell"
def compiler := "/Users/ovm/.elan/toolchains/leanprover--lean4---v4.33.0/bin/lean"
def read (path : System.FilePath) : IO Json := do IO.ofExcept (Json.parse (← IO.FS.readFile path))
def main (args : List String) : IO Unit := do
  let [tag,mode] := args | throw (IO.userError "fresh semantic-work tag and mode required")
  unless tag.startsWith "semantic-work-" && !(← (base/(tag++".guard.json")).pathExists) do
    throw (IO.userError "preserve previous diagnostic")
  let core := base/"interest-traffic-core"
  let target := base/"focus-locators-build/StudyMain"
  let root := base/(tag++"-result")
  let command ← match mode with
    | "build" =>
      let original := base/"semantic-work-baseline-core"
      unless !(← original.pathExists) do throw (IO.userError "preserve original source")
      IO.FS.createDirAll (original/"Eggshell")
      for file in ["SearchRank.lean","Handoff.lean"] do
        IO.FS.writeFile (original/"Eggshell"/file) (← IO.FS.readFile (core/"Eggshell"/file))
      let applied ← IO.Process.output {cmd := "/usr/bin/git",args :=
        #["apply","--unidiff-zero",(workspace/"docs/candidates/focus-locators/candidate.patch").toString],cwd := core.toString}
      unless applied.exitCode == 0 do throw (IO.userError ("cannot select fixed focus core: "++applied.stderr))
      IO.FS.writeFile (core/"tools/research/WorkerCpuProfile.lean")
        (← IO.FS.readFile (workspace/"tools/research/WorkerCpuProfile.lean"))
      let parent := base/"focus-locators-build"
      let old ← read (base/"metadata-ingress-candidate-build-settings.json")
      let parents ← IO.ofExcept (old.getObjValAs? (Array String) "parents")
      let settings := old.setObjVal! "parents" (toJson (#[parent.toString,(base/"metadata-ingress-candidate-build").toString]++parents))
        |>.setObjVal! "mainModule" (toJson "tools.research.WorkerCpuProfile")
        |>.setObjVal! "output" (toJson (base/"semantic-work-client-build").toString)
        |>.setObjVal! "baselineCore" Json.null
        |>.setObjVal! "objectModules" (toJson (parent/"object-mapping.json").toString)
        |>.setObjVal! "baselineResponse" (toJson (parent/"runtime.rsp").toString)
        |>.setObjVal! "baselineMain" (toJson (parent/"tools_research_FocusLocatorChecks.o").toString)
      let path := base/"semantic-work-client-build-settings.json"
      IO.FS.writeFile path settings.pretty
      pure #["/usr/bin/env","LEAN_NUM_THREADS=1",compiler,"-M1024","--run",
        (workspace/"tools/research/StudyBuildMain.lean").toString,path.toString]
    | "profile" =>
      let aliasPath := base/"worker-cpu-target/bin/eggshelld"
      let metadata ← try pure (some (← aliasPath.symlinkMetadata)) catch _ => pure none
      if let some metadata := metadata then
        unless metadata.type == .symlink do throw (IO.userError "target alias is not a symlink")
        IO.FS.removeFile aliasPath
      let linked ← IO.Process.output {cmd := "/bin/ln",args := #["-s",target.toString,aliasPath.toString]}
      unless linked.exitCode == 0 do throw (IO.userError "cannot select fixed runtime")
      pure #["/usr/bin/env","LEAN_NUM_THREADS=1","EGGSHELL_DATA_ROOT="++(root/"private").toString,
        "EGGSHELL_CONFIG="++(root/"eggshell.toml").toString,"PLUGIN_ROOT="++(base/"worker-cpu-target").toString,
        "EGGSHELL_TRACE_SERVICE_PROFILE=1",(base/"semantic-work-client-build/StudyMain").toString,
        root.toString,target.toString,"b887fdbfe6e62db2f9da961a8b903c91bdd262030cf02c13105cafe91453a1ea"]
    | _ => throw (IO.userError "unknown semantic-work mode")
  IO.FS.writeFile (base/(tag++".guard-settings.json")) (Json.mkObj [("command",toJson command),
    ("cwd",toJson workspace.toString),("record",toJson (base/(tag++".guard.json")).toString),
    ("ownedPrefixes",toJson #[base.toString]),("limitRssKiB",toJson (3670016 : Nat)),
    ("minFreeKiB",toJson (2097152 : Nat))]).pretty
