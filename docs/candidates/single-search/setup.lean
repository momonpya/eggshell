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
    if ["single-search-","direct-numerical-","front-input-","front-traffic-","front-manager-"].any (fun stem => entry.fileName.startsWith stem) &&
        entry.fileName.endsWith ".guard.json" then
      let prior ← read entry.path
      unless prior.getObjValD "state" == toJson "finished" && prior.getObjValD "ownedPids" == toJson (#[] : Array Nat) do
        throw (IO.userError "prior controlled work is still owned")
  if args == ["capture"] then
    let target := base/"single-search-baseline-core"
    unless !(← target.pathExists) do throw (IO.userError "preserve captured sources")
    copyLean (base/"interest-traffic-core/Eggshell") (target/"Eggshell")
    return
  let mode::tag::rest := args | throw (IO.userError "mode and unique tag required")
  unless tag.startsWith "single-search-" && !(← (base/(tag++".guard.json")).pathExists) do
    throw (IO.userError "preserve prior trial")
  let command ← if mode == "build" then do
      for name in ["SingleSearchChecks.lean","DirectNumericalChecks.lean","FrontTrafficChecks.lean","FrontInputAudit.lean"] do
        let source ← IO.FS.readFile (workspace/"tools/research"/name)
        let target := base/"interest-traffic-core/tools/research"/name
        IO.FS.writeFile target source
        unless (← IO.FS.readFile target) == source do throw (IO.userError "checker source changed")
      let old ← read (base/"direct-numerical-build-settings.json")
      let parents ← IO.ofExcept (old.getObjValAs? (Array String) "parents")
      let parent := base/"direct-numerical-build"
      let settings := old.setObjVal! "parents" (toJson (#[parent.toString]++parents))
        |>.setObjVal! "baselineCore" (toJson (base/"single-search-baseline-core").toString)
        |>.setObjVal! "output" (toJson (base/"single-search-build").toString)
        |>.setObjVal! "objectModules" (toJson (parent/"object-mapping.json").toString)
        |>.setObjVal! "baselineResponse" (toJson (parent/"runtime.rsp").toString)
        |>.setObjVal! "baselineMain" (toJson (parent/"tools_research_FrontTrafficChecks.o").toString)
      IO.FS.writeFile (base/"single-search-build-settings.json") settings.pretty
      pure #["/usr/bin/env","LEAN_NUM_THREADS=1","/Users/ovm/.elan/toolchains/leanprover--lean4---v4.33.0/bin/lean",
        "-M1024","--run",(workspace/"tools/research/StudyBuildMain.lean").toString,(base/"single-search-build-settings.json").toString]
    else if ["policy","readers","traffic"].contains mode then do
      let rootName::extra := rest | throw (IO.userError "controlled fixture required")
      unless rootName.startsWith "single-search-fixture-" do throw (IO.userError "fixture outside candidate ownership")
      let root := base/rootName
      let action := if mode == "policy" then #["single-search-policy",root.toString]
        else if mode == "readers" then #["front-input-diagnostic",root.toString,"8"]
        else #["front-traffic",root.toString,"80"]++extra.toArray
      pure (#["/usr/bin/env","LEAN_NUM_THREADS=1","PLUGIN_ROOT="++(root/"no-plugin-bundle").toString,
        "EGGSHELL_DATA_ROOT="++(root/"private").toString,(base/"single-search-build/StudyMain").toString]++action)
    else if mode == "retained-read" then do
      pure #["/usr/bin/env","LEAN_NUM_THREADS=1","/Users/ovm/.elan/toolchains/leanprover--lean4---v4.33.0/bin/lean",
        "-M512","--run",(workspace/"docs/candidates/single-search/retained-read.lean").toString,
        (base/"single-search-build/StudyMain").toString,(base/"single-search-fixture-small1").toString]
    else if mode == "contract" || mode == "proofs" then do
      let settings ← read (base/"single-search-build-settings.json")
      let parents ← IO.ofExcept (settings.getObjValAs? (Array String) "parents")
      let toolchain := "/Users/ovm/.elan/toolchains/leanprover--lean4---v4.33.0"
      let path := #[(base/"single-search-build/lib").toString]++parents.map (·++"/lib")++
        #[(base/"interest-traffic-core/.lake/build/lib/lean").toString,toolchain++"/lib/lean"]
      let source := if mode == "proofs" then workspace/"tools/research/SingleSearchProofs.lean"
        else base/"interest-traffic-core/Eggshell/ContractAudit.lean"
      pure #["/usr/bin/env","LEAN_NUM_THREADS=1","LEAN_PATH="++String.intercalate ":" path.toList,
        toolchain++"/bin/lean","-M1024",source.toString]
    else throw (IO.userError "unknown candidate action")
  let guard := Json.mkObj [("command",toJson command),("cwd",toJson workspace.toString),
    ("record",toJson (base/(tag++".guard.json")).toString),("ownedPrefixes",toJson #[base.toString]),
    ("limitRssKiB",toJson (3670016 : Nat)),("minFreeKiB",toJson (2097152 : Nat))]
  IO.FS.writeFile (base/(tag++".guard-settings.json")) guard.pretty
