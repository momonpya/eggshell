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
  unless tag.startsWith "provider-lifetime-" && !(← (base/(tag++".guard.json")).pathExists) do
    throw (IO.userError "preserve prior attempt")
  let parent := base/"prepared-reader-images-build"
  let old ← read (base/"prepared-reader-images-build-settings.json")
  let parents ← IO.ofExcept (old.getObjValAs? (Array String) "parents")
  let paths := #[parent.toString++"/lib"]++parents.map (·++"/lib")++
    #[(base/"interest-traffic-core/.lake/build/lib/lean").toString,compiler++"/lib/lean"]
  let command ← match mode with
    | "records" | "cleanup" => pure #[compiler++"/bin/lean","-M1024","--run",
        (workspace/"docs/candidates/provider-lifetime"/(mode++".lean")).toString]
    | "capture" =>
      unless !(← (base/"provider-lifetime-baseline-core").pathExists) do throw (IO.userError "preserve captured parent")
      capture (base/"interest-traffic-core/Eggshell") (base/"provider-lifetime-baseline-core/Eggshell")
      pure #["/usr/bin/true"]
    | "check" => pure #["/usr/bin/env","LEAN_NUM_THREADS=1","LEAN_PATH="++String.intercalate ":" paths.toList,
        compiler++"/bin/lean","-M3072","-DwarningAsError=true",(workspace/"tools/research/ProviderLifetimeChecks.lean").toString]
    | "check-native" => pure #["/usr/bin/env","LEAN_NUM_THREADS=1","LEAN_PATH="++String.intercalate ":" paths.toList,
        compiler++"/bin/lean","-M3072","-DwarningAsError=true",(base/"interest-traffic-core/Eggshell/SemanticMatcher.lean").toString]
    | "build" | "build-native" =>
      let native := mode == "build-native"
      let parent := if native then base/"provider-lifetime-build" else parent
      let old ← if native then read (base/"provider-lifetime-build-settings.json") else pure old
      let parents ← IO.ofExcept (old.getObjValAs? (Array String) "parents")
      for name in (if native then ["BuiltinSearchChecks.lean","ProviderLifetimeChecks.lean","FrontTrafficChecks.lean"] else ["ProviderLifetimeChecks.lean"]) do
        IO.FS.writeFile (base/"interest-traffic-core/tools/research"/name) (← IO.FS.readFile (workspace/"tools/research"/name))
      unless (← IO.FS.readFile (base/"interest-traffic-core/tools/research/FrontTrafficChecks.lean")).contains
          "import tools.research.ProviderLifetimeChecks" do throw (IO.userError "apply probe harness patch first")
      let target := if native then "provider-native" else "provider-lifetime"
      let settings := old.setObjVal! "parents" (toJson (#[parent.toString]++parents))
        |>.setObjVal! "baselineCore" (toJson (base/"provider-lifetime-baseline-core").toString)
        |>.setObjVal! "output" (toJson (base/(target++"-build")).toString)
        |>.setObjVal! "objectModules" (toJson (parent/"object-mapping.json").toString)
        |>.setObjVal! "baselineResponse" (toJson (parent/"runtime.rsp").toString)
        |>.setObjVal! "baselineMain" (toJson (parent/"tools_research_FrontTrafficChecks.o").toString)
      let path := base/(target++"-build-settings.json")
      IO.FS.writeFile path settings.pretty
      pure #["/usr/bin/env","LEAN_NUM_THREADS=1",compiler++"/bin/lean","-M1024","--run",
        (workspace/"tools/research/StudyBuildMain.lean").toString,path.toString]
    | "audit" => pure #["/usr/bin/env","LEAN_NUM_THREADS=1",
        "EGGSHELL_DATA_ROOT="++(base/(tag++"-result/private")).toString,
        "PLUGIN_ROOT="++(base/"provider-lifetime-no-plugin").toString,
        (base/"provider-lifetime-build/StudyMain").toString,"provider-lifetime-audit",
        (base/"frontend-quiescence-fixture-small1").toString,(base/(tag++"-result")).toString]
    | "checks" => pure #["/usr/bin/env","LEAN_NUM_THREADS=1",
        "EGGSHELL_DATA_ROOT="++(base/(tag++"-result/private")).toString,
        "PLUGIN_ROOT="++(base/"provider-lifetime-no-plugin").toString,
        (base/"provider-native-build/StudyMain").toString,"builtin-search-checks",(base/(tag++"-result")).toString]
    | "mixed" => pure #["/usr/bin/env","LEAN_NUM_THREADS=1",
        "EGGSHELL_DATA_ROOT="++(base/(tag++"-result/private")).toString,
        "PLUGIN_ROOT="++(base/"provider-lifetime-no-plugin").toString,
        (base/"provider-native-build/StudyMain").toString,"front-traffic",(base/(tag++"-result")).toString,"80","5000"]
    | "profile" | "parent-profile" | "lexical" | "parent-lexical" =>
      let runtime := if mode.startsWith "parent-" then parent/"StudyMain" else base/"provider-native-build/StudyMain"
      pure (#[compiler++"/bin/lean","-M512","--run",(workspace/"docs/candidates/prepared-reader-images/profile.lean").toString,
        runtime.toString,(base/"frontend-quiescence-fixture-small1").toString,(base/(tag++"-result")).toString]++
        (if mode.endsWith "lexical" then #["lexical"] else #[]))
    | "readback" | "parent-readback" => pure #["/usr/bin/env","LEAN_NUM_THREADS=1",
        "EGGSHELL_DATA_ROOT="++(base/(tag++"-result/private")).toString,
        "PLUGIN_ROOT="++(base/"provider-lifetime-no-plugin").toString,
        (if mode == "parent-readback" then parent/"StudyMain" else base/"provider-native-build/StudyMain").toString,
        "literal-readback",(base/"frontend-quiescence-fixture-small1").toString,(base/(tag++"-result")).toString]
    | "contract" => pure #["/usr/bin/env","LEAN_NUM_THREADS=1",
        "LEAN_PATH="++String.intercalate ":" ((base/"provider-native-build/lib").toString::(base/"provider-lifetime-build/lib").toString::paths.toList),
        compiler++"/bin/lean","-M3072",(base/"interest-traffic-core/Eggshell/ContractAudit.lean").toString]
    | _ => throw (IO.userError "unknown provider lifetime action")
  IO.FS.writeFile (base/(tag++".guard-settings.json")) (Json.mkObj [("command",toJson command),
    ("cwd",toJson workspace.toString),("record",toJson (base/(tag++".guard.json")).toString),
    ("ownedPrefixes",toJson #[base.toString]),("limitRssKiB",toJson (3670016 : Nat)),
    ("minFreeKiB",toJson (2097152 : Nat))]).pretty
