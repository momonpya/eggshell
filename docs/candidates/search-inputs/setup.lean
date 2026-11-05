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
    else if entry.fileName.endsWith ".lean" then
      IO.FS.writeFile (target/entry.fileName) (← IO.FS.readFile entry.path)
def main (args : List String) : IO Unit := do
  let [mode,tag] := args | throw (IO.userError "search-inputs action and fresh tag required")
  unless tag.startsWith "search-inputs-" && !(← (base/(tag++".guard.json")).pathExists) do
    throw (IO.userError "preserve prior attempt")
  let core := base/"interest-traffic-core"
  let parent := base/"metadata-ingress-candidate-build"
  let command ← match mode with
    | "capture" =>
      let target := base/"search-inputs-baseline-core"
      unless !(← target.pathExists) do throw (IO.userError "preserve frozen parent source")
      capture (core/"Eggshell") (target/"Eggshell")
      capture (core/"tools") (target/"tools")
      pure #["/usr/bin/true"]
    | "build" =>
      IO.FS.writeFile (core/"tools/research/SearchInputChecks.lean")
        (← IO.FS.readFile (workspace/"tools/research/SearchInputChecks.lean"))
      let driver ← IO.FS.readFile (base/"search-inputs-baseline-core/tools/research/FrontTrafficChecks.lean")
      let entry := "def main (args : List String) : IO UInt32 := do\n  match args with\n"
      unless (driver.splitOn entry).length == 2 do throw (IO.userError "native entry changed")
      IO.FS.writeFile (core/"tools/research/FrontTrafficChecks.lean")
        ("import tools.research.SearchInputChecks\n"++driver.replace entry
          (entry++"  | [\"search-input-checks\",source,root] => Eggshell.Research.SearchInputChecks.run (.mk source) (.mk root); return 0\n"))
      let old ← read (base/"metadata-ingress-candidate-build-settings.json")
      let parents ← IO.ofExcept (old.getObjValAs? (Array String) "parents")
      let settings := old.setObjVal! "parents" (toJson (#[parent.toString]++parents))
        |>.setObjVal! "output" (toJson (base/"search-inputs-build").toString)
        |>.setObjVal! "baselineCore" (toJson (base/"search-inputs-baseline-core").toString)
        |>.setObjVal! "objectModules" (toJson (parent/"object-mapping.json").toString)
        |>.setObjVal! "baselineResponse" (toJson (parent/"runtime.rsp").toString)
        |>.setObjVal! "baselineMain" (toJson (parent/"tools_research_FrontTrafficChecks.o").toString)
      let path := base/"search-inputs-build-settings.json"
      IO.FS.writeFile path settings.pretty
      pure #["/usr/bin/env","LEAN_NUM_THREADS=1",compiler++"/bin/lean","-M1024","--run",
        (workspace/"tools/research/StudyBuildMain.lean").toString,path.toString]
    | "checks" =>
      let root := base/(tag++"-result")
      pure #["/usr/bin/env","LEAN_NUM_THREADS=1","EGGSHELL_DATA_ROOT="++(root/"private").toString,
        "PLUGIN_ROOT="++(base/"search-inputs-no-plugin").toString,
        (base/"search-inputs-build/StudyMain").toString,"search-input-checks",
        (base/"frontend-quiescence-fixture-small1/work.project").toString,root.toString]
    | "receipt-build" =>
      IO.FS.writeFile (core/"tools/research/ReceiptPublicationProfile.lean")
        (← IO.FS.readFile (workspace/"tools/research/ReceiptPublicationProfile.lean"))
      let old ← read (base/"metadata-ingress-candidate-build-settings.json")
      let parents ← IO.ofExcept (old.getObjValAs? (Array String) "parents")
      let settings := old.setObjVal! "parents" (toJson (#[parent.toString]++parents))
        |>.setObjVal! "mainModule" (toJson "tools.research.ReceiptPublicationProfile")
        |>.setObjVal! "output" (toJson (base/"search-inputs-receipt-build").toString)
        |>.setObjVal! "objectModules" (toJson (parent/"object-mapping.json").toString)
        |>.setObjVal! "baselineResponse" (toJson (parent/"runtime.rsp").toString)
        |>.setObjVal! "baselineMain" (toJson (parent/"tools_research_FrontTrafficChecks.o").toString)
      let path := base/"search-inputs-receipt-build-settings.json"
      IO.FS.writeFile path settings.pretty
      pure #["/usr/bin/env","LEAN_NUM_THREADS=1",compiler++"/bin/lean","-M1024","--run",
        (workspace/"tools/research/StudyBuildMain.lean").toString,path.toString]
    | "receipt-profile" =>
      let root := base/(tag++"-result")
      pure #["/usr/bin/env","LEAN_NUM_THREADS=1","EGGSHELL_DATA_ROOT="++(root/"private").toString,
        (base/"search-inputs-receipt-build/StudyMain").toString,root.toString]
    | "pairs" => pure #[compiler++"/bin/lean","-M512","--run",
        (workspace/"docs/candidates/source-incidence/paired.lean").toString,
        (base/(tag++"-result")).toString,(parent/"StudyMain").toString,
        (base/"search-inputs-build/StudyMain").toString]
    | "readback-parent" | "readback-candidate" =>
      let root := base/(tag++"-result")
      let engine := if mode == "readback-parent" then parent else base/"search-inputs-build"
      pure #["/usr/bin/env","LEAN_NUM_THREADS=1","EGGSHELL_DATA_ROOT="++(root/"private").toString,
        "PLUGIN_ROOT="++(base/"search-inputs-no-plugin").toString,"EGGSHELL_TRACE_SERVICE_PROFILE=1",
        (engine/"StudyMain").toString,"literal-readback",(base/"frontend-quiescence-fixture-small1").toString,root.toString]
    | _ => throw (IO.userError "unknown search-inputs action")
  IO.FS.writeFile (base/(tag++".guard-settings.json")) (Json.mkObj [("command",toJson command),
    ("cwd",toJson core.toString),("record",toJson (base/(tag++".guard.json")).toString),
    ("ownedPrefixes",toJson #[base.toString]),("limitRssKiB",toJson (3670016 : Nat)),
    ("minFreeKiB",toJson (2097152 : Nat))]).pretty
