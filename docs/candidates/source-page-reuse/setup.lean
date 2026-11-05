import Lean.Data.Json.FromToJson
import Lean.Data.Json.Parser
open Lean
def base : System.FilePath := "/Users/ovm/.codex/experiments/eggshell/scope-token-study-20261028/fixed-frame-study"
def workspace : System.FilePath := "/Users/ovm/.codex/worktrees/hook-deadline-baseline/eggshell"
def compilerRoot := "/Users/ovm/.elan/toolchains/leanprover--lean4---v4.33.0"
def read (path : System.FilePath) : IO Json := do IO.ofExcept (Json.parse (← IO.FS.readFile path))
partial def capture (source target : System.FilePath) : IO Unit := do
  IO.FS.createDirAll target
  for entry in ← source.readDir do
    if (← entry.path.symlinkMetadata).type == .dir then capture entry.path (target/entry.fileName)
    else if entry.fileName.endsWith ".lean" then IO.FS.writeFile (target/entry.fileName) (← IO.FS.readFile entry.path)
def main (args : List String) : IO Unit := do
  let [mode,tag] := args | throw (IO.userError "action and unique tag required")
  for entry in ← base.readDir do
    if ["owner-binding-","source-page-reuse-"].any (fun stem => entry.fileName.startsWith stem) && entry.fileName.endsWith ".guard.json" then
      let guard ← read entry.path
      unless guard.getObjValD "state" == toJson "finished" && guard.getObjValD "ownedPids" == toJson (#[] : Array Nat) do
        throw (IO.userError "controlled work is still owned")
  unless tag.startsWith "source-page-reuse-" && !(← (base/(tag++".guard.json")).pathExists) do
    throw (IO.userError "preserve previous guarded attempt")
  let command ← match mode with
    | "records" | "cleanup" => pure #[compilerRoot++"/bin/lean",(if mode == "records" then "-M1024" else "-M512"),"--run",
        (workspace/"docs/candidates/source-page-reuse"/(mode++".lean")).toString]
    | "build" | "profile-build" =>
      unless ← (base/"source-page-reuse-baseline-core").pathExists do
        capture (base/"interest-traffic-core/Eggshell") (base/"source-page-reuse-baseline-core/Eggshell")
      IO.FS.writeFile (base/"interest-traffic-core/tools/research/ProjectPageReuseChecks.lean")
        (← IO.FS.readFile (workspace/"tools/research/ProjectPageReuseChecks.lean"))
      let old ← read (base/"owner-binding-build-settings.json")
      let parents ← IO.ofExcept (old.getObjValAs? (Array String) "parents")
      let parent := base/"owner-binding-build"
      let output := if mode == "build" then base/"source-page-reuse-build" else base/"source-page-profile-build"
      let settings := old.setObjVal! "parents" (toJson (#[parent.toString]++parents))
        |>.setObjVal! "baselineCore" (toJson (base/"source-page-reuse-baseline-core").toString)
        |>.setObjVal! "output" (toJson output.toString)
        |>.setObjVal! "objectModules" (toJson (parent/"object-mapping.json").toString)
        |>.setObjVal! "baselineResponse" (toJson (parent/"runtime.rsp").toString)
        |>.setObjVal! "baselineMain" (toJson (parent/"tools_research_FrontTrafficChecks.o").toString)
        |>.setObjVal! "mainModule" (toJson (if mode == "build" then "tools.research.ProjectPageReuseChecks" else "tools.research.FrontTrafficChecks"))
      let settingsPath := base/(output.fileName.get!++"-settings.json")
      IO.FS.writeFile settingsPath settings.pretty
      pure #["/usr/bin/env","LEAN_NUM_THREADS=1",compilerRoot++"/bin/lean","-M1024","--run",
        (workspace/"tools/research/StudyBuildMain.lean").toString,settingsPath.toString]
    | "audit" => pure #["/usr/bin/env","LEAN_NUM_THREADS=1",
        "EGGSHELL_DATA_ROOT="++(base/(tag++"-private")).toString,
        "PLUGIN_ROOT="++(base/"source-page-reuse-no-plugin").toString,
        (base/"source-page-reuse-build/StudyMain").toString,
        (base/"frontend-quiescence-fixture-small1").toString,(base/(tag++"-result")).toString]
    | "profile" | "lexical-profile" | "sample-lexical" => pure (#[compilerRoot++"/bin/lean","-M512","--run",
        (workspace/"docs/candidates/source-page-reuse/profile.lean").toString,
        (base/"source-page-profile-build/StudyMain").toString,
        (base/"frontend-quiescence-fixture-small1").toString,(base/(tag++"-result")).toString]++
        (if mode == "sample-lexical" then #["lexical","sample"] else if mode == "lexical-profile" then #["lexical"] else #[]))
    | "summary" => pure #[compilerRoot++"/bin/lean","-M1024","--run",
        (workspace/"tools/research/OwnedAppendProfile.lean").toString,"summary",
        (base/"source-page-reuse-sample1-result/worker.sample.txt").toString,
        (base/"source-page-reuse-sample1-result/worker-summary.json").toString]
    | _ => throw (IO.userError "unknown page reuse action")
  IO.FS.writeFile (base/(tag++".guard-settings.json")) (Json.mkObj [("command",toJson command),
    ("cwd",toJson workspace.toString),("record",toJson (base/(tag++".guard.json")).toString),
    ("ownedPrefixes",toJson #[base.toString]),("limitRssKiB",toJson (3670016 : Nat)),
    ("minFreeKiB",toJson (2097152 : Nat))]).pretty
