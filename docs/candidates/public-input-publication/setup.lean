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
  unless tag.startsWith "public-input-publication-" && !(← (base/(tag++".guard.json")).pathExists) do
    throw (IO.userError "preserve previous attempt")
  let old ← read (base/"prepared-reader-images-build-settings.json")
  let parents ← IO.ofExcept (old.getObjValAs? (Array String) "parents")
  let parent := base/"prepared-reader-images-build"
  let paths := #[parent.toString++"/lib"]++parents.map (·++"/lib")++
    #[(base/"interest-traffic-core/.lake/build/lib/lean").toString,compiler++"/lib/lean"]
  let command ← match mode with
    | "capture" =>
      unless !(← (base/"public-input-publication-baseline-core").pathExists) do throw (IO.userError "preserve captured parent")
      capture (base/"interest-traffic-core/Eggshell") (base/"public-input-publication-baseline-core/Eggshell")
      pure #["/usr/bin/true"]
    | "records" | "cleanup" => pure #[compiler++"/bin/lean","-M1024","--run",
        (workspace/"docs/candidates/public-input-publication"/(mode++".lean")).toString]
    | "check-probe" => pure #["/usr/bin/env","LEAN_NUM_THREADS=1",
        "LEAN_PATH="++String.intercalate ":" ((base/"public-input-publication-build/lib").toString::paths.toList),
        compiler++"/bin/lean","-M3072","-DwarningAsError=true",(workspace/"tools/research/PublicInputChecks.lean").toString]
    | "check" => pure #["/usr/bin/env","LEAN_NUM_THREADS=1","LEAN_PATH="++String.intercalate ":" paths.toList,
        compiler++"/bin/lean","-M1024","-DwarningAsError=true",
        (base/"interest-traffic-core/Eggshell/PreparedInputs.lean").toString]
    | "build" =>
      for name in ["PublicInputChecks.lean"] do
        IO.FS.writeFile (base/"interest-traffic-core/tools/research"/name) (← IO.FS.readFile (workspace/"tools/research"/name))
      unless (← IO.FS.readFile (base/"interest-traffic-core/tools/research/FrontTrafficChecks.lean")).contains
          "import tools.research.PublicInputChecks" do
        throw (IO.userError "apply the isolated product and harness patches before reproducing")
      let settings := old.setObjVal! "parents" (toJson (#[parent.toString]++parents))
        |>.setObjVal! "baselineCore" (toJson (base/"public-input-publication-baseline-core").toString)
        |>.setObjVal! "output" (toJson (base/"public-input-publication-build").toString)
        |>.setObjVal! "objectModules" (toJson (parent/"object-mapping.json").toString)
        |>.setObjVal! "baselineResponse" (toJson (parent/"runtime.rsp").toString)
        |>.setObjVal! "baselineMain" (toJson (parent/"tools_research_FrontTrafficChecks.o").toString)
      let path := base/"public-input-publication-build-settings.json"
      IO.FS.writeFile path settings.pretty
      pure #["/usr/bin/env","LEAN_NUM_THREADS=1",compiler++"/bin/lean","-M1024","--run",
        (workspace/"tools/research/StudyBuildMain.lean").toString,path.toString]
    | "audit" => pure #["/usr/bin/env","LEAN_NUM_THREADS=1",
        "EGGSHELL_DATA_ROOT="++(base/(tag++"-result/private")).toString,
        "PLUGIN_ROOT="++(base/"public-input-publication-no-plugin").toString,
        (base/"public-input-publication-build/StudyMain").toString,"public-input-audit",
        (base/"frontend-quiescence-fixture-small1").toString,(base/(tag++"-result")).toString]
    | "profile" | "parent-profile" => pure #[compiler++"/bin/lean","-M512","--run",
        (workspace/"docs/candidates/prepared-reader-images/profile.lean").toString,
        (if mode == "parent-profile" then parent/"StudyMain" else base/"public-input-publication-build/StudyMain").toString,
        (base/"frontend-quiescence-fixture-small1").toString,(base/(tag++"-result")).toString]
    | "readback" | "parent-readback" => pure #["/usr/bin/env","LEAN_NUM_THREADS=1",
        "EGGSHELL_DATA_ROOT="++(base/(tag++"-result/private")).toString,
        "PLUGIN_ROOT="++(base/"public-input-publication-no-plugin").toString,
        (if mode == "parent-readback" then parent/"StudyMain" else base/"public-input-publication-build/StudyMain").toString,
        "literal-readback",(base/"frontend-quiescence-fixture-small1").toString,(base/(tag++"-result")).toString]
    | "contract" =>
      pure #["/usr/bin/env","LEAN_NUM_THREADS=1",
        "LEAN_PATH="++String.intercalate ":" ((base/"public-input-publication-build/lib").toString::paths.toList),
        compiler++"/bin/lean","-M3072",(base/"interest-traffic-core/Eggshell/ContractAudit.lean").toString]
    | _ => throw (IO.userError "unknown public publication action")
  IO.FS.writeFile (base/(tag++".guard-settings.json")) (Json.mkObj [("command",toJson command),
    ("cwd",toJson workspace.toString),("record",toJson (base/(tag++".guard.json")).toString),
    ("ownedPrefixes",toJson #[base.toString]),("limitRssKiB",toJson (3670016 : Nat)),
    ("minFreeKiB",toJson (2097152 : Nat))]).pretty
