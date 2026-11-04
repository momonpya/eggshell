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
    if ["input-frame-","query-residency-"].any (fun stem => entry.fileName.startsWith stem) && entry.fileName.endsWith ".guard.json" then
      let guard ← read entry.path
      unless guard.getObjValD "state" == toJson "finished" && guard.getObjValD "ownedPids" == toJson (#[] : Array Nat) do
        throw (IO.userError "controlled work is still owned")
  unless tag.startsWith "query-residency-" && !(← (base/(tag++".guard.json")).pathExists) do throw (IO.userError "preserve earlier trial")
  let runtime := base/"input-frame-build/StudyMain"
  let source := base/"frontend-quiescence-fixture-small1"
  let root := base/("query-residency-fixture-"++tag)
  let toolchain := "/Users/ovm/.elan/toolchains/leanprover--lean4---v4.33.0"
  let command ← match mode with
    | "records" | "cleanup" => pure #[toolchain++"/bin/lean","-M512","--run",
        (workspace/"docs/candidates/query-residency"/(mode++".lean")).toString]
    | "capture" =>
        unless !(← (base/"query-residency-baseline-core").pathExists) do throw (IO.userError "baseline already captured")
        copyLean (base/"interest-traffic-core/Eggshell") (base/"query-residency-baseline-core/Eggshell")
        pure #["/usr/bin/true"]
    | "build" =>
        for name in ["FrontTrafficChecks.lean","SourcePinBatchChecks.lean"] do
          IO.FS.writeFile (base/"interest-traffic-core/tools/research"/name) (← IO.FS.readFile (workspace/"tools/research"/name))
        let old ← read (base/"input-frame-build-settings.json")
        let parents ← IO.ofExcept (old.getObjValAs? (Array String) "parents")
        let parent := base/"input-frame-build"
        let settings := old.setObjVal! "parents" (toJson (#[parent.toString]++parents))
          |>.setObjVal! "baselineCore" (toJson (base/"query-residency-baseline-core").toString)
          |>.setObjVal! "output" (toJson (base/"query-residency-build").toString)
          |>.setObjVal! "objectModules" (toJson (parent/"object-mapping.json").toString)
          |>.setObjVal! "baselineResponse" (toJson (parent/"runtime.rsp").toString)
          |>.setObjVal! "baselineMain" (toJson (parent/"tools_research_FrontTrafficChecks.o").toString)
        IO.FS.writeFile (base/"query-residency-build-settings.json") settings.pretty
        pure #["/usr/bin/env","LEAN_NUM_THREADS=1",toolchain++"/bin/lean","-M1024","--run",
          (workspace/"tools/research/StudyBuildMain.lean").toString,(base/"query-residency-build-settings.json").toString]
    | "audit" => pure #["/usr/bin/env","LEAN_NUM_THREADS=1","PLUGIN_ROOT="++(root/"no-plugin-bundle").toString,
        "EGGSHELL_DATA_ROOT="++(root/"private").toString,(base/"query-residency-build/StudyMain").toString,
        "source-pin-batch",source.toString,root.toString]
    | "proofs" | "contract" =>
        let settings ← read (base/"query-residency-build-settings.json")
        let parents ← IO.ofExcept (settings.getObjValAs? (Array String) "parents")
        let paths := #[(base/"query-residency-build/lib").toString]++parents.map (·++"/lib")++
          #[(base/"interest-traffic-core/.lake/build/lib/lean").toString,toolchain++"/lib/lean"]
        let file := if mode == "contract" then base/"interest-traffic-core/Eggshell/ContractAudit.lean"
          else workspace/"docs/candidates/query-residency/proofs.lean"
        pure #["/usr/bin/env","LEAN_NUM_THREADS=1","LEAN_PATH="++String.intercalate ":" paths.toList,
          toolchain++"/bin/lean","-M1024",file.toString]
    | "profile" | "parent-profile" | "candidate-lexical" | "parent-lexical" =>
        let executable := if mode.startsWith "parent-" then runtime else base/"query-residency-build/StudyMain"
        pure (#[toolchain++"/bin/lean","-M512","--run",(workspace/"docs/candidates/query-residency/profile.lean").toString,
          executable.toString,source.toString,root.toString]++(if mode.endsWith "lexical" then #["lexical"] else #[]))
    | "readback" | "parent-readback" => pure #["/usr/bin/env","LEAN_NUM_THREADS=1",
        "PLUGIN_ROOT="++(root/"no-plugin-bundle").toString,"EGGSHELL_DATA_ROOT="++(root/"private").toString,
        (if mode == "parent-readback" then runtime else base/"query-residency-build/StudyMain").toString,
        "literal-readback",source.toString,root.toString]
    | "lexical" => pure #[toolchain++"/bin/lean","-M512","--run",(workspace/"docs/candidates/query-residency/profile.lean").toString,
        runtime.toString,source.toString,root.toString,"lexical"]
    | "sample-lexical" => pure #[toolchain++"/bin/lean","-M512","--run",(workspace/"docs/candidates/query-residency/profile.lean").toString,
        runtime.toString,source.toString,root.toString,"lexical","sample"]
    | _ => throw (IO.userError "unknown residency action")
  IO.FS.writeFile (base/(tag++".guard-settings.json")) (Json.mkObj [("command",toJson command),
    ("cwd",toJson workspace.toString),("record",toJson (base/(tag++".guard.json")).toString),
    ("ownedPrefixes",toJson #[base.toString]),("limitRssKiB",toJson (3670016 : Nat)),("minFreeKiB",toJson (2097152 : Nat))]).pretty
