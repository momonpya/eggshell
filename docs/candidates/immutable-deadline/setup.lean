import Lean.Data.Json.FromToJson
import Lean.Data.Json.Parser
open Lean
def base : System.FilePath := "/Users/ovm/.codex/experiments/eggshell/scope-token-study-20261028/fixed-frame-study"
def workspace : System.FilePath := "/Users/ovm/.codex/worktrees/hook-deadline-baseline/eggshell"
def leanRoot : System.FilePath := "/Users/ovm/.elan/toolchains/leanprover--lean4---v4.33.0"
def read (path : System.FilePath) : IO Json := do IO.ofExcept (Json.parse (← IO.FS.readFile path))
def hash (path : System.FilePath) : IO String := do
  let result ← IO.Process.output {cmd := "/usr/bin/shasum",args := #["-a","256",path.toString]}
  unless result.exitCode == 0 do throw (IO.userError "cannot seal immutable deadline runtime")
  return (result.stdout.splitOn " ").headD ""
def main (args : List String) : IO Unit := do
  let [tag,mode] := args | throw (IO.userError "fresh immutable-deadline tag/mode required")
  unless tag.startsWith "immutable-deadline-" && !tag.contains '/' && !(← (base/(tag++".guard.json")).pathExists) do
    throw (IO.userError "preserve preceding immutable-deadline trial")
  let command ← if mode == "build" then do
      IO.FS.writeFile (base/"interest-traffic-core/tools/research/ImmutableDeadlineChecks.lean")
        (← IO.FS.readFile (workspace/"tools/research/ImmutableDeadlineChecks.lean"))
      let parent := base/"working-set-build"
      let original ← read (base/"working-set-build-settings.json")
      let parents ← IO.ofExcept (original.getObjValAs? (Array String) "parents")
      let settings := original.setObjVal! "output" (toJson (base/"immutable-deadline-build").toString)
        |>.setObjVal! "parents" (toJson (#[parent.toString]++parents))
        |>.setObjVal! "objectModules" (toJson (parent/"object-mapping.json").toString)
        |>.setObjVal! "baselineResponse" (toJson (parent/"runtime.rsp").toString)
        |>.setObjVal! "baselineMain" (toJson (parent/"tools_research_WorkingSetProfile.o").toString)
        |>.setObjVal! "baselineCore" Json.null
        |>.setObjVal! "mainModule" (toJson "tools.research.ImmutableDeadlineChecks")
      let path := base/"immutable-deadline-build-settings.json"
      IO.FS.writeFile path settings.pretty
      pure #[(leanRoot/"bin/lean").toString,"-j1","-M1536","--run",(workspace/"tools/research/StudyBuildMain.lean").toString,path.toString]
    else if mode == "checks" then
      pure #[(base/"immutable-deadline-build/StudyMain").toString,"immutable-deadline-check",(base/(tag++"-result")).toString]
    else if mode == "hook16" then do
      let sourceAudit ← read (workspace/"docs/candidates/immutable-deadline/native-sources-final.json")
      unless sourceAudit.getObjValD "exactExpectedChangeSet" == toJson true &&
        sourceAudit.getObjValD "parentModules" == sourceAudit.getObjValD "candidateModules" do
        throw (IO.userError "candidate changed undeclared native source inputs")
      let checked ← read (base/"immutable-deadline-checks3.guard.json")
      unless checked.getObjValD "state" == toJson "finished" && checked.getObjValD "exitCode" == toJson (0 : Nat) &&
        checked.getObjValD "ownedPids" == toJson (#[] : Array Nat) do throw (IO.userError "immutable deadline lifetime checks failed")
      let runtime := base/"immutable-deadline-build/StudyMain"
      unless sourceAudit.getObjValD "candidateRuntimeSha256" == toJson (← hash runtime) do
        throw (IO.userError "native source audit belongs to another runtime")
      let client := base/"numerical-stages-client-build/StudyMain"
      unless (← hash client) == "a80cad2a80fb084842d22e3ead44358762fbdea3e175601b1d407d82c67b308e" do throw (IO.userError "sealed native client changed")
      let parentSha ← hash (base/"readonly-pages-build/StudyMain")
      unless parentSha == "33c408217bb99d6278ad1519d0f65bfa39ddda23f58a1275e6cbac428184247d" do throw (IO.userError "sealed parent hook runtime changed")
      let sealPath := workspace/"docs/candidates/immutable-deadline/seal.json"
      let sealedBytes := (Json.mkObj [("runtimeSha256",toJson (← hash runtime)),("parentRuntimeSha256",toJson parentSha)]).pretty
      if ← sealPath.pathExists then
        unless (← IO.FS.readFile sealPath) == sealedBytes do throw (IO.userError "immutable deadline runtime changed after sealing")
      else IO.FS.writeFile sealPath sealedBytes
      let link := base/"worker-cpu-target/bin/eggshelld"
      unless (← link.symlinkMetadata).type == .symlink do throw (IO.userError "isolated runtime target changed type")
      IO.FS.removeFile link
      let linked ← IO.Process.output {cmd := "/bin/ln",args := #["-s",runtime.toString,link.toString]}
      unless linked.exitCode == 0 do throw (IO.userError "cannot select isolated immutable runtime")
      let root := base/(tag++"-result")
      pure #["/usr/bin/env","LEAN_NUM_THREADS=1","EGGSHELL_DATA_ROOT="++(root/"private").toString,
        "EGGSHELL_CONFIG="++(root/"eggshell.toml").toString,"PLUGIN_ROOT="++(base/"worker-cpu-target").toString,
        "EGGSHELL_TRACE_SERVICE_PROFILE=1","EGGSHELL_TRACE_QUERY_STAGES=1","EGGSHELL_TRACE_NUMERICAL_STAGES=1",
        client.toString,root.toString,runtime.toString,← hash runtime]
    else throw (IO.userError "unknown immutable deadline mode")
  IO.FS.writeFile (base/(tag++".guard-settings.json")) (Json.mkObj [("command",toJson command),("cwd",toJson workspace.toString),
    ("record",toJson (base/(tag++".guard.json")).toString),("ownedPrefixes",toJson #[base.toString]),
    ("limitRssKiB",toJson (3670016 : Nat)),("minFreeKiB",toJson (2097152 : Nat))]).pretty
