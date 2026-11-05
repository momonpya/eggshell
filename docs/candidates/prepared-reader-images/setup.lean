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
    if ["source-page-reuse-","prepared-reader-images-"].any (fun stem => entry.fileName.startsWith stem) && entry.fileName.endsWith ".guard.json" then
      let guard ← read entry.path
      unless guard.getObjValD "state" == toJson "finished" && guard.getObjValD "ownedPids" == toJson (#[] : Array Nat) do
        throw (IO.userError "controlled work is still owned")
  unless tag.startsWith "prepared-reader-images-" && !(← (base/(tag++".guard.json")).pathExists) do
    throw (IO.userError "preserve previous guarded attempt")
  let command ← match mode with
    | "records" | "cleanup" => pure #[compilerRoot++"/bin/lean",(if mode == "records" then "-M1024" else "-M512"),"--run",
        (workspace/"docs/candidates/prepared-reader-images"/(mode++".lean")).toString]
    | "capture" =>
      unless !(← (base/"prepared-reader-images-baseline-core").pathExists) do throw (IO.userError "preserve baseline")
      capture (base/"interest-traffic-core/Eggshell") (base/"prepared-reader-images-baseline-core/Eggshell")
      pure #["/usr/bin/true"]
    | "check" =>
      let old ← read (base/"owner-binding-build-settings.json")
      let parents ← IO.ofExcept (old.getObjValAs? (Array String) "parents")
      let paths := #[(base/"owner-binding-build/lib").toString]++parents.map (·++"/lib")++
        #[(base/"interest-traffic-core/.lake/build/lib/lean").toString,compilerRoot++"/lib/lean"]
      pure #["/usr/bin/env","LEAN_NUM_THREADS=1","LEAN_PATH="++String.intercalate ":" paths.toList,
        compilerRoot++"/bin/lean","-M1024","-DwarningAsError=true",
        (base/"interest-traffic-core/Eggshell/PreparedReaders.lean").toString]
    | "build" =>
      for name in ["PreparedReaderChecks.lean","FrontTrafficChecks.lean"] do
        IO.FS.writeFile (base/"interest-traffic-core/tools/research"/name) (← IO.FS.readFile (workspace/"tools/research"/name))
      let old ← read (base/"owner-binding-build-settings.json")
      let parents ← IO.ofExcept (old.getObjValAs? (Array String) "parents")
      let parent := base/"owner-binding-build"
      let settings := old.setObjVal! "parents" (toJson (#[parent.toString]++parents))
        |>.setObjVal! "baselineCore" (toJson (base/"prepared-reader-images-baseline-core").toString)
        |>.setObjVal! "output" (toJson (base/"prepared-reader-images-build").toString)
        |>.setObjVal! "objectModules" (toJson (parent/"object-mapping.json").toString)
        |>.setObjVal! "baselineResponse" (toJson (parent/"runtime.rsp").toString)
        |>.setObjVal! "baselineMain" (toJson (parent/"tools_research_FrontTrafficChecks.o").toString)
      IO.FS.writeFile (base/"prepared-reader-images-build-settings.json") settings.pretty
      pure #["/usr/bin/env","LEAN_NUM_THREADS=1",compilerRoot++"/bin/lean","-M1024","--run",
        (workspace/"tools/research/StudyBuildMain.lean").toString,(base/"prepared-reader-images-build-settings.json").toString]
    | "audit" => pure #["/usr/bin/env","LEAN_NUM_THREADS=1",
        "EGGSHELL_DATA_ROOT="++(base/(tag++"-private")).toString,
        "PLUGIN_ROOT="++(base/"prepared-reader-images-no-plugin").toString,
        (base/"prepared-reader-images-build/StudyMain").toString,"prepared-reader-audit",
        (base/"frontend-quiescence-fixture-small1").toString,(base/(tag++"-result")).toString]
    | "build-fixture" =>
      IO.FS.writeFile (base/"interest-traffic-core/tools/research/SourceOwnerChecks.lean")
        (← IO.FS.readFile (workspace/"tools/research/SourceOwnerChecks.lean"))
      let old ← read (base/"prepared-reader-images-build-settings.json")
      let parents ← IO.ofExcept (old.getObjValAs? (Array String) "parents")
      let parent := base/"prepared-reader-images-build"
      let settings := old.setObjVal! "parents" (toJson (#[parent.toString]++parents))
        |>.setObjVal! "output" (toJson (base/"prepared-reader-images-fixture-build").toString)
        |>.setObjVal! "objectModules" (toJson (parent/"object-mapping.json").toString)
        |>.setObjVal! "baselineResponse" (toJson (parent/"runtime.rsp").toString)
        |>.setObjVal! "baselineMain" (toJson (parent/"tools_research_FrontTrafficChecks.o").toString)
        |>.setObjVal! "mainModule" (toJson "tools.research.SourceOwnerChecks")
      let path := base/"prepared-reader-images-fixture-build-settings.json"
      IO.FS.writeFile path settings.pretty
      pure #[compilerRoot++"/bin/lean","-M1024","--run",(workspace/"tools/research/StudyBuildMain.lean").toString,path.toString]
    | "fixture" | "captured" => pure (#["/usr/bin/env","LEAN_NUM_THREADS=1",
        "EGGSHELL_DATA_ROOT="++(base/"prepared-reader-images-synthetic-private").toString,
        "PLUGIN_ROOT="++(base/"prepared-reader-images-no-plugin").toString,
        (if mode == "fixture" then base/"prepared-reader-images-fixture-build/StudyMain" else base/"prepared-reader-images-build/StudyMain").toString,
        (if mode == "fixture" then "source-owners" else "prepared-reader-captured"),
        (base/"prepared-reader-images-synthetic").toString]++(if mode == "fixture" then #["2"] else #[]))
    | "proofs" | "contract" =>
      let settings ← read (base/"prepared-reader-images-build-settings.json")
      let parents ← IO.ofExcept (settings.getObjValAs? (Array String) "parents")
      let paths := #[(base/"prepared-reader-images-build/lib").toString]++parents.map (·++"/lib")++
        #[(base/"interest-traffic-core/.lake/build/lib/lean").toString,compilerRoot++"/lib/lean"]
      let file := if mode == "proofs" then workspace/"docs/candidates/prepared-reader-images/proofs.lean"
        else base/"interest-traffic-core/Eggshell/ContractAudit.lean"
      pure #["/usr/bin/env","LEAN_NUM_THREADS=1","LEAN_PATH="++String.intercalate ":" paths.toList,
        compilerRoot++"/bin/lean","-M1024",file.toString]
    | "profile" | "parent-profile" | "lexical" | "parent-lexical" =>
      let runtime := if mode.startsWith "parent-" then base/"owner-binding-build/StudyMain"
        else base/"prepared-reader-images-build/StudyMain"
      pure (#[compilerRoot++"/bin/lean","-M512","--run",
        (workspace/"docs/candidates/prepared-reader-images/profile.lean").toString,runtime.toString,
        (base/"frontend-quiescence-fixture-small1").toString,(base/(tag++"-result")).toString]++
        (if mode.endsWith "lexical" then #["lexical"] else #[]))
    | "readback" | "parent-readback" => pure #["/usr/bin/env","LEAN_NUM_THREADS=1",
        "EGGSHELL_DATA_ROOT="++(base/(tag++"-result/private")).toString,
        "PLUGIN_ROOT="++(base/"prepared-reader-images-no-plugin").toString,
        (if mode == "parent-readback" then base/"owner-binding-build/StudyMain" else base/"prepared-reader-images-build/StudyMain").toString,
        "literal-readback",(base/"frontend-quiescence-fixture-small1").toString,(base/(tag++"-result")).toString]
    | "compare" => pure #[compilerRoot++"/bin/lean","-M512","--run",
        (workspace/"docs/candidates/prepared-reader-images/compare.lean").toString,
        (base/(tag.replace "-pair" "-parent"++"-result")).toString,
        (base/(tag.replace "-pair" "-candidate"++"-result")).toString]
    | _ => throw (IO.userError "unknown prepared reader action")
  if ["audit","captured","fixture"].contains mode then
    let binary := if mode == "fixture" then base/"prepared-reader-images-fixture-build/StudyMain" else base/"prepared-reader-images-build/StudyMain"
    let identity ← IO.Process.output {cmd := "/usr/bin/shasum",args := #["-a","256",binary.toString]}
    unless identity.exitCode == 0 do throw (IO.userError "audit runtime identity unavailable")
    IO.FS.writeFile (base/(tag++".runtime.sha256")) identity.stdout
  IO.FS.writeFile (base/(tag++".guard-settings.json")) (Json.mkObj [("command",toJson command),
    ("cwd",toJson workspace.toString),("record",toJson (base/(tag++".guard.json")).toString),
    ("ownedPrefixes",toJson #[base.toString]),("limitRssKiB",toJson (3670016 : Nat)),
    ("minFreeKiB",toJson (2097152 : Nat))]).pretty
