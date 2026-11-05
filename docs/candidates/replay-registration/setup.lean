import Lean.Data.Json.FromToJson
import Lean.Data.Json.Parser
open Lean
def base : System.FilePath := "/Users/ovm/.codex/experiments/eggshell/scope-token-study-20261028/fixed-frame-study"
def workspace : System.FilePath := "/Users/ovm/.codex/worktrees/hook-deadline-baseline/eggshell"
def compiler := "/Users/ovm/.elan/toolchains/leanprover--lean4---v4.33.0"
def read (path : System.FilePath) : IO Json := do IO.ofExcept (Json.parse (← IO.FS.readFile path))
partial def capture (source target : System.FilePath) : IO Unit := do
  IO.FS.createDirAll target
  for entry in ← source.readDir do
    if (← entry.path.symlinkMetadata).type == .dir then capture entry.path (target/entry.fileName)
    else if entry.fileName.endsWith ".lean" then IO.FS.writeFile (target/entry.fileName) (← IO.FS.readFile entry.path)
def main (args : List String) : IO Unit := do
  let [mode,tag] := args | throw (IO.userError "action and unique tag required")
  unless tag.startsWith "replay-registration-" && !(← (base/(tag++".guard.json")).pathExists) do
    throw (IO.userError "preserve prior attempt")
  let parent := base/(if mode == "full-build" then "replay-registration-build" else "provider-native-build")
  let core := base/"interest-traffic-core"
  let old ← read (base/((if mode == "full-build" then "replay-registration-build" else "provider-native-build")++"-settings.json"))
  let parents ← IO.ofExcept (old.getObjValAs? (Array String) "parents")
  let command ← match mode with
    | "capture" =>
      unless !(← (base/"replay-registration-baseline-core").pathExists) do throw (IO.userError "preserve captured baseline")
      capture (core/"Eggshell") (base/"replay-registration-baseline-core/Eggshell")
      capture (core/"tools") (base/"replay-registration-baseline-core/tools")
      pure #["/usr/bin/true"]
    | "baseline-build" | "candidate-build" | "full-build" =>
      let full := mode == "full-build"
      for name in ["ReplayRegistrationChecks.lean","ReplayWorkMain.lean","ReplayWorkChecks.lean"] do
        IO.FS.writeFile (core/"tools/research"/name) (← IO.FS.readFile (workspace/"tools/research"/name))
      let target := if mode == "baseline-build" then "replay-registration-baseline-build"
        else if full then "replay-registration-full-build" else "replay-registration-build"
      let settings := old.setObjVal! "parents" (toJson (#[parent.toString]++parents))
        |>.setObjVal! "project" (toJson core.toString)
        |>.setObjVal! "mainModule" (toJson (if full then "tools.research.ReplayWorkMain" else "tools.research.ReplayRegistrationChecks"))
        |>.setObjVal! "baselineCore" (toJson (base/"replay-registration-baseline-core").toString)
        |>.setObjVal! "output" (toJson (base/target).toString)
        |>.setObjVal! "objectModules" (toJson (parent/"object-mapping.json").toString)
        |>.setObjVal! "baselineResponse" (toJson (parent/"runtime.rsp").toString)
        |>.setObjVal! "baselineMain" (toJson (parent/((← IO.ofExcept (old.getObjValAs? String "mainModule")).replace "." "_"++".o")).toString)
      let path := base/(target++"-settings.json")
      IO.FS.writeFile path settings.pretty
      pure #["/usr/bin/env","LEAN_NUM_THREADS=1",compiler++"/bin/lean","-M1024","--run",
        (workspace/"tools/research/StudyBuildMain.lean").toString,path.toString]
    | "audit" =>
      let paths := #[(base/"replay-registration-full-build/lib").toString,
        (base/"replay-registration-build/lib").toString,parent.toString++"/lib"]++
        parents.map (·++"/lib")++#[(core/".lake/build/lib/lean").toString,compiler++"/lib/lean"]
      pure #["/usr/bin/env","LEAN_NUM_THREADS=1","LEAN_PATH="++String.intercalate ":" paths.toList,
        compiler++"/bin/lean","-M3072","-DwarningAsError=true",
        (workspace/"tools/research/ReplayRegistrationAudit.lean").toString]
    | "records" | "cleanup" => pure #[compiler++"/bin/lean","-M512","--run",
        (workspace/"docs/candidates/replay-registration"/(mode++".lean")).toString]
    | "observe" | "verify" | "full" | "prefix" =>
      let build := if mode == "observe" then "replay-registration-baseline-build"
        else if ["full","prefix"].contains mode then "replay-registration-full-build" else "replay-registration-build"
      pure (#["/usr/bin/env","LEAN_NUM_THREADS=1","EGGSHELL_DATA_ROOT="++(base/(tag++"-result")/(if ["full","prefix"].contains mode then "data" else "private")).toString,
        "PLUGIN_ROOT="++(base/"replay-registration-no-plugin").toString,(base/build/"StudyMain").toString]++
        (if mode == "full" then #[(base/(tag++"-result")).toString]
          else if mode == "prefix" then #[(base/(tag++"-result")).toString,"prefix"]
          else #[mode,(base/(tag++"-result")).toString]))
    | _ => throw (IO.userError "unknown registration action")
  IO.FS.writeFile (base/(tag++".guard-settings.json")) (Json.mkObj [("command",toJson command),
    ("cwd",toJson workspace.toString),("record",toJson (base/(tag++".guard.json")).toString),
    ("ownedPrefixes",toJson #[base.toString]),("limitRssKiB",toJson (3670016 : Nat)),
    ("minFreeKiB",toJson (2097152 : Nat))]).pretty
