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
    else if kind == .file && entry.fileName.endsWith ".lean" then
      IO.FS.writeFile (target/entry.fileName) (← IO.FS.readFile entry.path)
def main (args : List String) : IO Unit := do
  for entry in ← base.readDir do
    if ["frontend-quiescence-","single-search-","direct-numerical-","front-input-","front-traffic-","front-manager-"].any (fun stem => entry.fileName.startsWith stem) &&
        entry.fileName.endsWith ".guard.json" then
      let prior ← read entry.path
      unless prior.getObjValD "state" == toJson "finished" && prior.getObjValD "ownedPids" == toJson (#[] : Array Nat) do
        throw (IO.userError "prior controlled work is still owned")
  if args == ["capture"] then
    let target := base/"frontend-quiescence-baseline-core"
    unless !(← target.pathExists) do throw (IO.userError "preserve captured sources")
    copyLean (base/"interest-traffic-core/Eggshell") (target/"Eggshell")
    return
  let mode::tag::rest := args | throw (IO.userError "mode and unique tag required")
  unless tag.startsWith "frontend-quiescence-" && !(← (base/(tag++".guard.json")).pathExists) do
    throw (IO.userError "preserve prior trial")
  let command ← if mode == "build" then do
      for name in ["FrontTrafficChecks.lean","FrontSessionChecks.lean"] do
        let source ← IO.FS.readFile (workspace/"tools/research"/name)
        IO.FS.writeFile (base/"interest-traffic-core/tools/research"/name) source
      let old ← read (base/"single-search-build-settings.json")
      let parents ← IO.ofExcept (old.getObjValAs? (Array String) "parents")
      let parent := base/"single-search-build"
      let settings := old.setObjVal! "parents" (toJson (#[parent.toString]++parents))
        |>.setObjVal! "baselineCore" (toJson (base/"frontend-quiescence-baseline-core").toString)
        |>.setObjVal! "output" (toJson (base/"frontend-quiescence-build").toString)
        |>.setObjVal! "objectModules" (toJson (parent/"object-mapping.json").toString)
        |>.setObjVal! "baselineResponse" (toJson (parent/"runtime.rsp").toString)
        |>.setObjVal! "baselineMain" (toJson (parent/"tools_research_FrontTrafficChecks.o").toString)
      IO.FS.writeFile (base/"frontend-quiescence-build-settings.json") settings.pretty
      pure #["/usr/bin/env","LEAN_NUM_THREADS=1","/Users/ovm/.elan/toolchains/leanprover--lean4---v4.33.0/bin/lean",
        "-M1024","--run",(workspace/"tools/research/StudyBuildMain.lean").toString,(base/"frontend-quiescence-build-settings.json").toString]
    else if ["policy","readers","traffic"].contains mode then do
      let rootName::extra := rest | throw (IO.userError "controlled fixture required")
      unless rootName.startsWith "frontend-quiescence-fixture-" do throw (IO.userError "fixture outside candidate ownership")
      let root := base/rootName
      let action := if mode == "policy" then #["front-session-policy",root.toString]
        else if mode == "readers" then #["front-input-diagnostic",root.toString,"8"]
        else #["front-traffic",root.toString,"80"]++extra.toArray
      pure (#["/usr/bin/env","LEAN_NUM_THREADS=1","PLUGIN_ROOT="++(root/"no-plugin-bundle").toString,
        "EGGSHELL_DATA_ROOT="++(root/"private").toString,(base/"frontend-quiescence-build/StudyMain").toString]++action)
    else if mode == "contract" || mode == "proofs" || mode == "terms" then do
      let settings ← read (base/"frontend-quiescence-build-settings.json")
      let parents ← IO.ofExcept (settings.getObjValAs? (Array String) "parents")
      let toolchain := "/Users/ovm/.elan/toolchains/leanprover--lean4---v4.33.0"
      let path := #[(base/"frontend-quiescence-build/lib").toString]++parents.map (·++"/lib")++
        #[(base/"interest-traffic-core/.lake/build/lib/lean").toString,toolchain++"/lib/lean"]
      let source := if mode == "proofs" then workspace/"tools/research/FrontSessionProofs.lean"
        else if mode == "terms" then workspace/"docs/candidates/frontend-quiescence/terms.lean"
        else base/"interest-traffic-core/Eggshell/ContractAudit.lean"
      pure (#["/usr/bin/env","LEAN_NUM_THREADS=1","LEAN_PATH="++String.intercalate ":" path.toList,
        toolchain++"/bin/lean","-M1024"]++(if mode == "terms" then #["--run"] else #[])++#[source.toString])
    else throw (IO.userError "unknown candidate action")
  let guard := Json.mkObj [("command",toJson command),("cwd",toJson workspace.toString),
    ("record",toJson (base/(tag++".guard.json")).toString),("ownedPrefixes",toJson #[base.toString]),
    ("limitRssKiB",toJson (3670016 : Nat)),("minFreeKiB",toJson (2097152 : Nat))]
  IO.FS.writeFile (base/(tag++".guard-settings.json")) guard.pretty
