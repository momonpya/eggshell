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
    if ["shared-startup-","literal-boundaries-"].any (fun stem => entry.fileName.startsWith stem) && entry.fileName.endsWith ".guard.json" then
      let prior ← read entry.path
      unless prior.getObjValD "state" == toJson "finished" && prior.getObjValD "ownedPids" == toJson (#[] : Array Nat) do
        throw (IO.userError "prior controlled work is still owned")
  if args == ["capture"] then
    let target := base/"shared-startup-baseline-core"
    unless !(← target.pathExists) do throw (IO.userError "preserve captured sources")
    copyLean (base/"interest-traffic-core/Eggshell") (target/"Eggshell")
    return
  let (mode,tag) ← match args with
    | [mode,tag] => pure (mode,tag)
    | _ => throw (IO.userError "mode and fresh tag required")
  unless tag.startsWith "shared-startup-" && !(← (base/(tag++".guard.json")).pathExists) do throw (IO.userError "preserve prior trial")
  let toolchain := "/Users/ovm/.elan/toolchains/leanprover--lean4---v4.33.0"
  let root := base/("shared-startup-fixture-"++tag)
  let command ← if mode == "build" then do
      for name in ["FrontTrafficChecks.lean","StartupChecks.lean"] do
        IO.FS.writeFile (base/"interest-traffic-core/tools/research"/name) (← IO.FS.readFile (workspace/"tools/research"/name))
      let old ← read (base/"literal-boundaries-build-settings.json")
      let parents ← IO.ofExcept (old.getObjValAs? (Array String) "parents")
      let parent := base/"literal-boundaries-build"
      let settings := old.setObjVal! "parents" (toJson (#[parent.toString]++parents))
        |>.setObjVal! "baselineCore" (toJson (base/"shared-startup-baseline-core").toString)
        |>.setObjVal! "output" (toJson (base/"shared-startup-build").toString)
        |>.setObjVal! "objectModules" (toJson (parent/"object-mapping.json").toString)
        |>.setObjVal! "baselineResponse" (toJson (parent/"runtime.rsp").toString)
        |>.setObjVal! "baselineMain" (toJson (parent/"tools_research_FrontTrafficChecks.o").toString)
      IO.FS.writeFile (base/"shared-startup-build-settings.json") settings.pretty
      pure #["/usr/bin/env","LEAN_NUM_THREADS=1",toolchain++"/bin/lean","-M1024","--run",
        (workspace/"tools/research/StudyBuildMain.lean").toString,(base/"shared-startup-build-settings.json").toString]
    else if mode == "records" || mode == "cleanup" || mode == "details" then
      pure (#[toolchain++"/bin/lean","-M512","--run",
        (workspace/"docs/candidates/shared-startup"/((if mode == "details" then "records" else mode)++".lean")).toString]++
        (if mode == "details" then #["details"] else #[]))
    else if mode == "startup" || mode == "readback" then
      pure (#["/usr/bin/env","LEAN_NUM_THREADS=1","PLUGIN_ROOT="++(root/"no-plugin-bundle").toString,
        "EGGSHELL_DATA_ROOT="++(root/"private").toString,(base/"shared-startup-build/StudyMain").toString,
        (if mode == "startup" then "shared-startup" else "literal-readback"),
        (if mode == "startup" then root.toString else (base/"frontend-quiescence-fixture-small1").toString)]++
        (if mode == "readback" then #[root.toString] else #[]))
    else if mode == "proofs" || mode == "contract" then do
      let settings ← read (base/"shared-startup-build-settings.json")
      let parents ← IO.ofExcept (settings.getObjValAs? (Array String) "parents")
      let path := #[(base/"shared-startup-build/lib").toString]++parents.map (·++"/lib")++
        #[(base/"interest-traffic-core/.lake/build/lib/lean").toString,toolchain++"/lib/lean"]
      let source := if mode == "proofs" then workspace/"docs/candidates/shared-startup/proofs.lean"
        else base/"interest-traffic-core/Eggshell/ContractAudit.lean"
      pure #["/usr/bin/env","LEAN_NUM_THREADS=1","LEAN_PATH="++String.intercalate ":" path.toList,toolchain++"/bin/lean","-M1024",source.toString]
    else throw (IO.userError "unknown shared startup action")
  IO.FS.writeFile (base/(tag++".guard-settings.json")) (Json.mkObj [("command",toJson command),
    ("cwd",toJson workspace.toString),("record",toJson (base/(tag++".guard.json")).toString),
    ("ownedPrefixes",toJson #[base.toString]),("limitRssKiB",toJson (3670016 : Nat)),("minFreeKiB",toJson (2097152 : Nat))]).pretty
