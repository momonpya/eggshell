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
    if ["prepared-lexical-","subset-rank-"].any (fun stem => entry.fileName.startsWith stem) && entry.fileName.endsWith ".guard.json" then
      let guard ← read entry.path
      unless guard.getObjValD "state" == toJson "finished" && guard.getObjValD "ownedPids" == toJson (#[] : Array Nat) do
        throw (IO.userError "prior work is still owned")
  let [mode,tag] := args | throw (IO.userError "action and unique tag required")
  unless tag.startsWith "subset-rank-" && !(← (base/(tag++".guard.json")).pathExists) do throw (IO.userError "preserve previous trial")
  let toolchain := "/Users/ovm/.elan/toolchains/leanprover--lean4---v4.33.0"
  let root := base/("subset-rank-fixture-"++tag)
  let command ← if mode == "build" then do
      let captured := base/"subset-rank-baseline-core"
      if !(← captured.pathExists) then copyLean (base/"interest-traffic-core/Eggshell") (captured/"Eggshell")
      for name in ["FrontTrafficChecks.lean","SubsetRankChecks.lean"] do
        IO.FS.writeFile (base/"interest-traffic-core/tools/research"/name) (← IO.FS.readFile (workspace/"tools/research"/name))
      let old ← read (base/"prepared-lexical-build-settings.json")
      let parents ← IO.ofExcept (old.getObjValAs? (Array String) "parents")
      let parent := base/"prepared-lexical-build"
      let settings := old.setObjVal! "parents" (toJson (#[parent.toString]++parents))
        |>.setObjVal! "baselineCore" (toJson captured.toString)
        |>.setObjVal! "output" (toJson (base/"subset-rank-build").toString)
        |>.setObjVal! "objectModules" (toJson (parent/"object-mapping.json").toString)
        |>.setObjVal! "baselineResponse" (toJson (parent/"runtime.rsp").toString)
        |>.setObjVal! "baselineMain" (toJson (parent/"tools_research_FrontTrafficChecks.o").toString)
      IO.FS.writeFile (base/"subset-rank-build-settings.json") settings.pretty
      pure #["/usr/bin/env","LEAN_NUM_THREADS=1",toolchain++"/bin/lean","-M1024","--run",
        (workspace/"tools/research/StudyBuildMain.lean").toString,(base/"subset-rank-build-settings.json").toString]
    else if mode == "check-module" || mode == "proofs" || mode == "contract" then do
      let settings ← read (base/"subset-rank-build-settings.json")
      let parents ← IO.ofExcept (settings.getObjValAs? (Array String) "parents")
      let paths := #[(base/"subset-rank-build/lib").toString]++parents.map (·++"/lib")++
        #[(base/"interest-traffic-core/.lake/build/lib/lean").toString,toolchain++"/lib/lean"]
      let file := if mode == "check-module" then base/"interest-traffic-core/Eggshell/SubsetLexical.lean"
        else if mode == "contract" then base/"interest-traffic-core/Eggshell/ContractAudit.lean"
        else workspace/"docs/candidates/subset-rank/proofs.lean"
      pure #["/usr/bin/env","LEAN_NUM_THREADS=1","LEAN_PATH="++String.intercalate ":" paths.toList,
        toolchain++"/bin/lean","-M1024",file.toString]
    else if mode == "profile" || mode == "parent-profile" then
      pure #[toolchain++"/bin/lean","-M512","--run",(workspace/"docs/candidates/query-work/profile.lean").toString,
        (base/(if mode == "profile" then "subset-rank-build/StudyMain" else "prepared-lexical-build/StudyMain")).toString,
        (base/"frontend-quiescence-fixture-small1").toString,root.toString]
    else if mode == "readback" || mode == "parent-readback" then
      pure #["/usr/bin/env","LEAN_NUM_THREADS=1","PLUGIN_ROOT="++(root/"no-plugin-bundle").toString,
        "EGGSHELL_DATA_ROOT="++(root/"private").toString,
        (base/(if mode == "readback" then "subset-rank-build/StudyMain" else "prepared-lexical-build/StudyMain")).toString,"literal-readback",
        (base/"frontend-quiescence-fixture-small1").toString,root.toString]
    else if mode == "audit" then
      pure #["/usr/bin/env","LEAN_NUM_THREADS=1","PLUGIN_ROOT="++(root/"no-plugin-bundle").toString,
        "EGGSHELL_DATA_ROOT="++(root/"private").toString,(base/"subset-rank-build/StudyMain").toString,
        "subset-rank-audit",(base/"frontend-quiescence-fixture-small1").toString,root.toString]
    else if mode == "records" || mode == "cleanup" then
      pure #[toolchain++"/bin/lean","-M512","--run",(workspace/"docs/candidates/subset-rank"/(mode++".lean")).toString]
    else throw (IO.userError "unknown subset rank action")
  IO.FS.writeFile (base/(tag++".guard-settings.json")) (Json.mkObj [("command",toJson command),
    ("cwd",toJson workspace.toString),("record",toJson (base/(tag++".guard.json")).toString),
    ("ownedPrefixes",toJson #[base.toString]),("limitRssKiB",toJson (3670016 : Nat)),("minFreeKiB",toJson (2097152 : Nat))]).pretty
