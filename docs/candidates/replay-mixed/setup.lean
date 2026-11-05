import Lean.Data.Json.FromToJson
import Lean.Data.Json.Parser
open Lean
def base : System.FilePath := "/Users/ovm/.codex/experiments/eggshell/scope-token-study-20261028/fixed-frame-study"
def workspace : System.FilePath := "/Users/ovm/.codex/worktrees/hook-deadline-baseline/eggshell"
def compiler := "/Users/ovm/.elan/toolchains/leanprover--lean4---v4.33.0"
def read (path : System.FilePath) : IO Json := do IO.ofExcept (Json.parse (← IO.FS.readFile path))
def hash (path : System.FilePath) : IO String := do
  let result ← IO.Process.output {cmd := "/usr/bin/shasum",args := #["-a","256",path.toString]}
  unless result.exitCode == 0 do throw (IO.userError "cannot verify frozen source")
  return (result.stdout.splitOn " ").head!
def main (args : List String) : IO Unit := do
  let [mode,tag] := args | throw (IO.userError "action and unique tag required")
  unless tag.startsWith "replay-mixed-" && !(← (base/(tag++".guard.json")).pathExists) do
    throw (IO.userError "preserve prior attempt")
  let core := base/"interest-traffic-core"
  let evidence ← read (workspace/"docs/candidates/replay-registration/evidence.json")
  let sources ← IO.ofExcept (evidence.getObjValAs? (Array (String × String × String)) "sourceHashes")
  for (name,_,expected) in sources do
    unless (← hash (core/"Eggshell"/name)) == expected do throw (IO.userError "replay core changed after validation")
  let command ← match mode with
    | "build" =>
      let parent := base/"replay-registration-full-build"
      unless toJson (← hash (parent/"StudyMain")) == evidence.getObjValD "fullCheckRuntimeSha256" do
        throw (IO.userError "checked parent runtime changed")
      IO.FS.writeFile (core/"tools/research/FrontTrafficChecks.lean")
        (← IO.FS.readFile (workspace/"tools/research/FrontTrafficChecks.lean"))
      let old ← read (base/"replay-registration-full-build-settings.json")
      let parents ← IO.ofExcept (old.getObjValAs? (Array String) "parents")
      let settings := old.setObjVal! "parents" (toJson (#[parent.toString]++parents))
        |>.setObjVal! "mainModule" (toJson "tools.research.FrontTrafficChecks")
        |>.setObjVal! "output" (toJson (base/"replay-mixed-build").toString)
        |>.setObjVal! "objectModules" (toJson (parent/"object-mapping.json").toString)
        |>.setObjVal! "baselineResponse" (toJson (parent/"runtime.rsp").toString)
        |>.setObjVal! "baselineMain" (toJson (parent/"tools_research_ReplayWorkMain.o").toString)
      let path := base/"replay-mixed-build-settings.json"
      IO.FS.writeFile path settings.pretty
      pure #["/usr/bin/env","LEAN_NUM_THREADS=1",compiler++"/bin/lean","-M1024","--run",
        (workspace/"tools/research/StudyBuildMain.lean").toString,path.toString]
    | "mixed" | "restart-audit" =>
      let root := base/(if mode == "mixed" then tag++"-result" else "replay-mixed-native1-result")
      pure (#["/usr/bin/env","LEAN_NUM_THREADS=1","EGGSHELL_DATA_ROOT="++(root/"private").toString,
        "PLUGIN_ROOT="++(base/"replay-mixed-no-plugin").toString,(base/"replay-mixed-build/StudyMain").toString]++
        (if mode == "mixed" then #["front-traffic",root.toString,"80","5000"]
          else #["front-traffic-audit",root.toString]))
    | "retire" | "records" | "cleanup" => pure #[compiler++"/bin/lean","-M1024","--run",
        (workspace/"docs/candidates/replay-mixed"/(mode++".lean")).toString]
    | "analysis" => pure #[compiler++"/bin/lean","-M1024","--run",
        (workspace/"docs/candidates/replay-mixed/records.lean").toString,"analyse"]
    | _ => throw (IO.userError "unknown mixed action")
  IO.FS.writeFile (base/(tag++".guard-settings.json")) (Json.mkObj [("command",toJson command),
    ("cwd",toJson workspace.toString),("record",toJson (base/(tag++".guard.json")).toString),
    ("ownedPrefixes",toJson #[base.toString]),("limitRssKiB",toJson (3670016 : Nat)),
    ("minFreeKiB",toJson (2097152 : Nat))]).pretty
