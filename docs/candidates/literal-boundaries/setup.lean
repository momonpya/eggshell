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
    if ["literal-boundaries-","frontend-quiescence-","single-search-"].any (fun stem => entry.fileName.startsWith stem) &&
        entry.fileName.endsWith ".guard.json" then
      let prior ← read entry.path
      unless prior.getObjValD "state" == toJson "finished" && prior.getObjValD "ownedPids" == toJson (#[] : Array Nat) do
        throw (IO.userError "prior controlled work is still owned")
  if args == ["capture"] then
    let target := base/"literal-boundaries-baseline-core"
    unless !(← target.pathExists) do throw (IO.userError "preserve captured sources")
    copyLean (base/"interest-traffic-core/Eggshell") (target/"Eggshell")
    IO.FS.createDirAll (target/"tools")
    for name in ["RetrievalGrams.lean","RetrievalGramsTests.lean"] do
      IO.FS.writeFile (target/"tools"/name) (← IO.FS.readFile (base/"interest-traffic-core/tools"/name))
    return
  let (mode,tag) ← match args with
    | [tag] => pure ("baseline",tag)
    | [mode,tag] => pure (mode,tag)
    | _ => throw (IO.userError "mode and fresh tag required")
  unless tag.startsWith "literal-boundaries-" && !(← (base/(tag++".guard.json")).pathExists) do
    throw (IO.userError "preserve prior trial")
  let toolchain := "/Users/ovm/.elan/toolchains/leanprover--lean4---v4.33.0"
  let command ← if mode == "build" || mode == "grammar-build" then do
      if mode == "build" then
        for name in ["FrontTrafficChecks.lean","LiteralRankChecks.lean"] do
          let source ← IO.FS.readFile (workspace/"tools/research"/name)
          IO.FS.writeFile (base/"interest-traffic-core/tools/research"/name) source
      let previous := if mode == "build" then "frontend-quiescence" else "literal-boundaries"
      let old ← read (base/(previous++"-build-settings.json"))
      let parents ← IO.ofExcept (old.getObjValAs? (Array String) "parents")
      let parent := base/(previous++"-build")
      let stem := if mode == "build" then "literal-boundaries-build" else "literal-boundaries-grammar-build"
      let settings := old.setObjVal! "parents" (toJson (#[parent.toString]++parents))
        |>.setObjVal! "baselineCore" (toJson (base/"literal-boundaries-baseline-core").toString)
        |>.setObjVal! "output" (toJson (base/stem).toString)
        |>.setObjVal! "objectModules" (toJson (parent/"object-mapping.json").toString)
        |>.setObjVal! "baselineResponse" (toJson (parent/"runtime.rsp").toString)
        |>.setObjVal! "baselineMain" (toJson (parent/"tools_research_FrontTrafficChecks.o").toString)
        |>.setObjVal! "mainModule" (toJson (if mode == "build" then "tools.research.FrontTrafficChecks" else "tools.RetrievalGramsTests"))
      IO.FS.writeFile (base/(stem++"-settings.json")) settings.pretty
      pure #["/usr/bin/env","LEAN_NUM_THREADS=1",toolchain++"/bin/lean","-M1024","--run",
        (workspace/"tools/research/StudyBuildMain.lean").toString,(base/(stem++"-settings.json")).toString]
    else if mode == "records" || mode == "cleanup" then
      pure #[toolchain++"/bin/lean","-M512","--run",
        (workspace/"docs/candidates/literal-boundaries"/(mode++".lean")).toString]
    else if mode == "grammar-run" then
      pure #[(base/"literal-boundaries-grammar-build/StudyMain").toString]
    else if mode == "audit" then
      pure #["/usr/bin/env","LEAN_NUM_THREADS=1","EGGSHELL_DATA_ROOT="++(base/"literal-boundaries-fixture-audit1/private").toString,
        (base/"literal-boundaries-build/StudyMain").toString,"literal-rank-audit",
        (base/"frontend-quiescence-fixture-small1").toString,(base/"literal-boundaries-fixture-audit1").toString]
    else if mode == "readback" then
      pure #["/usr/bin/env","LEAN_NUM_THREADS=1",
        "PLUGIN_ROOT="++(base/("literal-boundaries-fixture-"++tag)/"no-plugin-bundle").toString,
        "EGGSHELL_DATA_ROOT="++(base/("literal-boundaries-fixture-"++tag)/"private").toString,
        (base/"literal-boundaries-build/StudyMain").toString,"literal-readback",
        (base/"frontend-quiescence-fixture-small1").toString,(base/("literal-boundaries-fixture-"++tag)).toString]
    else if mode == "baseline" || mode == "probe" then
      pure (#["/usr/bin/env","LEAN_NUM_THREADS=1",toolchain++"/bin/lean","-M512","--run",
        (workspace/"docs/candidates/literal-boundaries/probe.lean").toString,
        (base/(if mode == "baseline" then "frontend-quiescence-build/StudyMain" else "literal-boundaries-build/StudyMain")).toString,
        (base/"frontend-quiescence-fixture-small1").toString,
        (base/(if mode == "baseline" then "literal-boundaries-fixture-baseline1" else "literal-boundaries-fixture-"++tag)).toString]++
        (if mode == "probe" then #["warm"] else #[]))
    else if mode == "proofs" || mode == "contract" then do
      let settings ← read (base/"literal-boundaries-build-settings.json")
      let parents ← IO.ofExcept (settings.getObjValAs? (Array String) "parents")
      let path := #[(base/"literal-boundaries-build/lib").toString]++parents.map (·++"/lib")++
        #[(base/"interest-traffic-core/.lake/build/lib/lean").toString,toolchain++"/lib/lean"]
      let source := if mode == "proofs" then workspace/"docs/candidates/literal-boundaries/proofs.lean"
        else base/"interest-traffic-core/Eggshell/ContractAudit.lean"
      pure #["/usr/bin/env","LEAN_NUM_THREADS=1","LEAN_PATH="++String.intercalate ":" path.toList,
        toolchain++"/bin/lean","-M1024",source.toString]
    else throw (IO.userError "unknown literal-boundary action")
  let guard := Json.mkObj [("command",toJson command),("cwd",toJson workspace.toString),
    ("record",toJson (base/(tag++".guard.json")).toString),("ownedPrefixes",toJson #[base.toString]),
    ("limitRssKiB",toJson (3670016 : Nat)),("minFreeKiB",toJson (2097152 : Nat))]
  IO.FS.writeFile (base/(tag++".guard-settings.json")) guard.pretty
