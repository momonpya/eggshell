import Lean.Data.Json.FromToJson
import Lean.Data.Json.Parser
open Lean
def base : System.FilePath := "/Users/ovm/.codex/experiments/eggshell/scope-token-study-20261028/fixed-frame-study"
def workspace : System.FilePath := "/Users/ovm/.codex/worktrees/hook-deadline-baseline/eggshell"
def read (path : System.FilePath) : IO Json := do IO.ofExcept (Json.parse (← IO.FS.readFile path))
partial def copyLean (source target : System.FilePath) : IO Unit := do
  IO.FS.createDirAll target
  for entry in ← source.readDir do
    let kind := (← entry.path.symlinkMetadata).type
    if kind == .dir then copyLean entry.path (target/entry.fileName)
    else if kind == .file && entry.fileName.endsWith ".lean" then IO.FS.writeFile (target/entry.fileName) (← IO.FS.readFile entry.path)
def main (args : List String) : IO Unit := do
  let [mode,tag] := args | throw (IO.userError "action and unique tag required")
  for entry in ← base.readDir do
    if ["query-residency-","owner-binding-"].any (fun stem => entry.fileName.startsWith stem) && entry.fileName.endsWith ".guard.json" then
      let guard ← read entry.path
      unless guard.getObjValD "state" == toJson "finished" && guard.getObjValD "ownedPids" == toJson (#[] : Array Nat) do
        throw (IO.userError "controlled work is still owned")
  unless tag.startsWith "owner-binding-" && !(← (base/(tag++".guard.json")).pathExists) do throw (IO.userError "preserve earlier trial")
  let runtime := base/"query-residency-build/StudyMain"
  let source := base/"frontend-quiescence-fixture-small1"
  let root := base/("owner-binding-fixture-"++tag)
  let toolchain := "/Users/ovm/.elan/toolchains/leanprover--lean4---v4.33.0"
  let command ← match mode with
    | "records" | "cleanup" => pure #[toolchain++"/bin/lean","-M512","--run",
        (workspace/"docs/candidates/owner-binding"/(mode++".lean")).toString]
    | "capture" =>
        unless !(← (base/"owner-binding-baseline-core").pathExists) do throw (IO.userError "baseline already captured")
        copyLean (base/"interest-traffic-core/Eggshell") (base/"owner-binding-baseline-core/Eggshell")
        pure #["/usr/bin/true"]
    | "build" =>
        for name in ["FrontTrafficChecks.lean","OwnerBindingChecks.lean"] do
          IO.FS.writeFile (base/"interest-traffic-core/tools/research"/name) (← IO.FS.readFile (workspace/"tools/research"/name))
        let old ← read (base/"query-residency-build-settings.json")
        let parents ← IO.ofExcept (old.getObjValAs? (Array String) "parents")
        let parent := base/"query-residency-build"
        let settings := old.setObjVal! "parents" (toJson (#[parent.toString]++parents))
          |>.setObjVal! "baselineCore" (toJson (base/"owner-binding-baseline-core").toString)
          |>.setObjVal! "output" (toJson (base/"owner-binding-build").toString)
          |>.setObjVal! "objectModules" (toJson (parent/"object-mapping.json").toString)
          |>.setObjVal! "baselineResponse" (toJson (parent/"runtime.rsp").toString)
          |>.setObjVal! "baselineMain" (toJson (parent/"tools_research_FrontTrafficChecks.o").toString)
        IO.FS.writeFile (base/"owner-binding-build-settings.json") settings.pretty
        pure #["/usr/bin/env","LEAN_NUM_THREADS=1",toolchain++"/bin/lean","-M1024","--run",
          (workspace/"tools/research/StudyBuildMain.lean").toString,(base/"owner-binding-build-settings.json").toString]
    | "audit" => pure #["/usr/bin/env","LEAN_NUM_THREADS=1","PLUGIN_ROOT="++(root/"no-plugin-bundle").toString,
        "EGGSHELL_DATA_ROOT="++(root/"private").toString,(base/"owner-binding-build/StudyMain").toString,
        "owner-binding-audit",source.toString,root.toString]
    | "proofs" | "contract" | "check-handoff" =>
        let settings ← read (base/"owner-binding-build-settings.json")
        let parents ← IO.ofExcept (settings.getObjValAs? (Array String) "parents")
        let paths := #[(base/"owner-binding-build/lib").toString]++parents.map (·++"/lib")++
          #[(base/"interest-traffic-core/.lake/build/lib/lean").toString,toolchain++"/lib/lean"]
        let file := if mode == "contract" then base/"interest-traffic-core/Eggshell/ContractAudit.lean"
          else if mode == "check-handoff" then base/"interest-traffic-core/Eggshell/Handoff.lean"
          else workspace/"docs/candidates/owner-binding/proofs.lean"
        pure #["/usr/bin/env","LEAN_NUM_THREADS=1","LEAN_PATH="++String.intercalate ":" paths.toList,
          toolchain++"/bin/lean","-M1024",file.toString]
    | "check-declarations" =>
        let full ← IO.FS.readFile (base/"interest-traffic-core/Eggshell/Handoff.lean")
        let [_,tail] := full.splitOn "structure PreparedOwnerBinding where" | throw (IO.userError "binding declarations not uniquely located")
        let [body,_] := tail.splitOn "\ndef federatedDiscovery (" | throw (IO.userError "binding declaration end not uniquely located")
        let file := base/(tag++".lean")
        IO.FS.writeFile file ("module\nimport all Eggshell.Handoff\nopen Lean\nnamespace Eggshell.Plugin\nstructure PreparedOwnerBinding where"++body++"\nend Eggshell.Plugin\n")
        let settings ← read (base/"query-residency-build-settings.json")
        let parents ← IO.ofExcept (settings.getObjValAs? (Array String) "parents")
        let paths := #[(base/"query-residency-build/lib").toString]++parents.map (·++"/lib")++
          #[(base/"interest-traffic-core/.lake/build/lib/lean").toString,toolchain++"/lib/lean"]
        pure #["/usr/bin/env","LEAN_NUM_THREADS=1","LEAN_PATH="++String.intercalate ":" paths.toList,
          toolchain++"/bin/lean","-M1024","-DwarningAsError=true",file.toString]
    | "build-fixture" =>
        IO.FS.writeFile (base/"interest-traffic-core/tools/research/SourceOwnerChecks.lean")
          (← IO.FS.readFile (workspace/"tools/research/SourceOwnerChecks.lean"))
        let settings ← read (base/"owner-binding-build-settings.json")
        let parents ← IO.ofExcept (settings.getObjValAs? (Array String) "parents")
        let parent := base/"owner-binding-build"
        let settings := settings.setObjVal! "parents" (toJson (#[parent.toString]++parents))
          |>.setObjVal! "output" (toJson (base/"owner-binding-fixture-build").toString)
          |>.setObjVal! "objectModules" (toJson (parent/"object-mapping.json").toString)
          |>.setObjVal! "baselineResponse" (toJson (parent/"runtime.rsp").toString)
          |>.setObjVal! "baselineMain" (toJson (parent/"tools_research_FrontTrafficChecks.o").toString)
          |>.setObjVal! "mainModule" (toJson "tools.research.SourceOwnerChecks")
        IO.FS.writeFile (base/"owner-binding-fixture-build-settings.json") settings.pretty
        pure #[toolchain++"/bin/lean","-M1024","--run",(workspace/"tools/research/StudyBuildMain.lean").toString,
          (base/"owner-binding-fixture-build-settings.json").toString]
    | "synthetic-fixture" => pure #["/usr/bin/env","EGGSHELL_DATA_ROOT="++(base/"owner-binding-synthetic-private").toString,
        "PLUGIN_ROOT="++(base/"owner-binding-no-plugin").toString,
        (base/"owner-binding-fixture-build/StudyMain").toString,"source-owners",(base/"owner-binding-synthetic-checked").toString,"2"]
    | "synthetic" => pure #["/usr/bin/env","EGGSHELL_DATA_ROOT="++(base/"owner-binding-synthetic-private").toString,
        "PLUGIN_ROOT="++(base/"owner-binding-no-plugin").toString,
        (base/"owner-binding-build/StudyMain").toString,"owner-binding-synthetic",(base/"owner-binding-synthetic-checked").toString]
    | "profile" | "parent-profile" | "candidate-lexical" | "parent-lexical" =>
        let executable := if mode.startsWith "parent-" then runtime else base/"owner-binding-build/StudyMain"
        pure (#[toolchain++"/bin/lean","-M512","--run",(workspace/"docs/candidates/owner-binding/profile.lean").toString,
          executable.toString,source.toString,root.toString]++(if mode.endsWith "lexical" then #["lexical"] else #[]))
    | "readback" | "parent-readback" => pure #["/usr/bin/env","LEAN_NUM_THREADS=1",
        "PLUGIN_ROOT="++(root/"no-plugin-bundle").toString,"EGGSHELL_DATA_ROOT="++(root/"private").toString,
        (if mode == "parent-readback" then runtime else base/"owner-binding-build/StudyMain").toString,
        "literal-readback",source.toString,root.toString]
    | "lexical" => pure #[toolchain++"/bin/lean","-M512","--run",(workspace/"docs/candidates/owner-binding/profile.lean").toString,
        runtime.toString,source.toString,root.toString,"lexical"]
    | "sample-lexical" => pure #[toolchain++"/bin/lean","-M512","--run",(workspace/"docs/candidates/owner-binding/profile.lean").toString,
        runtime.toString,source.toString,root.toString,"lexical","sample"]
    | _ => throw (IO.userError "unknown residency action")
  IO.FS.writeFile (base/(tag++".guard-settings.json")) (Json.mkObj [("command",toJson command),
    ("cwd",toJson workspace.toString),("record",toJson (base/(tag++".guard.json")).toString),
    ("ownedPrefixes",toJson #[base.toString]),("limitRssKiB",toJson (3670016 : Nat)),("minFreeKiB",toJson (2097152 : Nat))]).pretty
