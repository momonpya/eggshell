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
  for entry in ← base.readDir do
    if ["shared-startup-","query-work-"].any (fun stem => entry.fileName.startsWith stem) && entry.fileName.endsWith ".guard.json" then
      let prior ← IO.ofExcept (Json.parse (← IO.FS.readFile entry.path))
      unless prior.getObjValD "state" == toJson "finished" && prior.getObjValD "ownedPids" == toJson (#[] : Array Nat) do
        throw (IO.userError "prior controlled work is still owned")
  if args == ["capture"] then
    let target := base/"query-work-baseline-core"
    unless !(← target.pathExists) do throw (IO.userError "preserve captured sources")
    copyLean (base/"interest-traffic-core/Eggshell") (target/"Eggshell")
    return
  let (mode,tag) ← match args with
    | [tag] => pure ("profile",tag)
    | [tag,"sample"] => pure ("sample",tag)
    | [mode,tag] => pure (mode,tag)
    | _ => throw (IO.userError "action and unique tag required")
  unless tag.startsWith "query-work-" && !(← (base/(tag++".guard.json")).pathExists) do throw (IO.userError "preserve earlier profile")
  let toolchain := "/Users/ovm/.elan/toolchains/leanprover--lean4---v4.33.0"
  let root := base/("query-work-fixture-"++tag)
  let command ← if mode == "records" || mode == "cleanup" then
      pure #[toolchain++"/bin/lean","-M512","--run",(workspace/"docs/candidates/query-work"/(mode++".lean")).toString]
    else if mode == "build" then do
      let old ← read (base/"shared-startup-build-settings.json")
      let parents ← IO.ofExcept (old.getObjValAs? (Array String) "parents")
      let parent := base/"shared-startup-build"
      let settings := old.setObjVal! "parents" (toJson (#[parent.toString]++parents))
        |>.setObjVal! "baselineCore" (toJson (base/"query-work-baseline-core").toString)
        |>.setObjVal! "output" (toJson (base/"query-work-build").toString)
        |>.setObjVal! "objectModules" (toJson (parent/"object-mapping.json").toString)
        |>.setObjVal! "baselineResponse" (toJson (parent/"runtime.rsp").toString)
        |>.setObjVal! "baselineMain" (toJson (parent/"tools_research_FrontTrafficChecks.o").toString)
      IO.FS.writeFile (base/"query-work-build-settings.json") settings.pretty
      pure #["/usr/bin/env","LEAN_NUM_THREADS=1",toolchain++"/bin/lean","-M1024","--run",
        (workspace/"tools/research/StudyBuildMain.lean").toString,(base/"query-work-build-settings.json").toString]
    else if mode == "readback" then
      pure #["/usr/bin/env","LEAN_NUM_THREADS=1","PLUGIN_ROOT="++(root/"no-plugin-bundle").toString,
        "EGGSHELL_DATA_ROOT="++(root/"private").toString,(base/"query-work-build/StudyMain").toString,"literal-readback",
        (base/"frontend-quiescence-fixture-small1").toString,root.toString]
    else if mode == "proofs" || mode == "contract" then do
      let settings ← read (base/"query-work-build-settings.json")
      let parents ← IO.ofExcept (settings.getObjValAs? (Array String) "parents")
      let path := #[(base/"query-work-build/lib").toString]++parents.map (·++"/lib")++
        #[(base/"interest-traffic-core/.lake/build/lib/lean").toString,toolchain++"/lib/lean"]
      let source := if mode == "proofs" then workspace/"docs/candidates/query-work/proofs.lean"
        else base/"interest-traffic-core/Eggshell/ContractAudit.lean"
      pure #["/usr/bin/env","LEAN_NUM_THREADS=1","LEAN_PATH="++String.intercalate ":" path.toList,
        toolchain++"/bin/lean","-M1024",source.toString]
    else if ["profile","sample","candidate","candidate-sample"].contains mode then
      pure (#[toolchain++"/bin/lean","-M512","--run",(workspace/"docs/candidates/query-work/profile.lean").toString,
        (base/((if mode == "candidate" || mode == "candidate-sample" then "query-work" else "shared-startup")++"-build/StudyMain")).toString,
        (base/"frontend-quiescence-fixture-small1").toString,root.toString]++
        (if mode == "sample" || mode == "candidate-sample" then #["sample"] else #[]))
    else throw (IO.userError "unknown query work action")
  IO.FS.writeFile (base/(tag++".guard-settings.json")) (Json.mkObj [("command",toJson command),
    ("cwd",toJson workspace.toString),("record",toJson (base/(tag++".guard.json")).toString),
    ("ownedPrefixes",toJson #[base.toString]),("limitRssKiB",toJson (3670016 : Nat)),("minFreeKiB",toJson (2097152 : Nat))]).pretty
