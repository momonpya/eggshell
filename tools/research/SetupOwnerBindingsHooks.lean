import Lean.Data.Json.Parser
import Lean.Data.Json.FromToJson
open Lean

private def check (ok : Bool) (message : String) : IO Unit := unless ok do throw (IO.userError message)
private def read (path : System.FilePath) : IO Json := IO.FS.readFile path >>= fun text => IO.ofExcept (Json.parse text)
private def once (source before after : String) : IO String := do
  check ((source.splitOn before).length == 2) "owner hook preparation anchor changed"
  return source.replace before after

def main : IO Unit := do
  let project : System.FilePath := "/Users/ovm/.codex/worktrees/hook-deadline-baseline/eggshell"
  let root : System.FilePath := "/Users/ovm/.codex/experiments/eggshell/scope-token-study-20261028/shared-snapshot"
  let records := project / "docs/candidates/owner-bindings"
  let actual := root / "owner-bindings-actual"
  let result ← read (actual / "result.json")
  check (result.getObjValD "sameAllRequestedReadSequences" == toJson true) "actual relation oracle incomplete"
  let samples : Array Json ← IO.ofExcept (result.getObjValAs? _ "samples")
  check (samples.size == 4) "actual inventory comparison incomplete"
  for (old,next) in [(0,1),(3,2)] do
    let a ← IO.ofExcept (samples[old]!.getObjValAs? Nat "elapsedMs")
    let b ← IO.ofExcept (samples[next]!.getObjValAs? Nat "elapsedMs")
    check (b < a) "stop before actual hooks after a slower inventory candidate"
  for name in ["preparation.json","protocol.json","progress.json","result.json"] do
    let target := records / "actual" / name
    check (!(← target.pathExists)) "preserve captured actual inventory"
    IO.FS.createDirAll target.parent.get!
    IO.FS.writeFile target (← IO.FS.readFile (actual / name))
  let path := project / "tools/research/OwnerBindingsHookArm.lean"
  check (!(← path.pathExists)) "preserve matched owner hook harness"
  let source ← IO.FS.readFile (project / "tools/research/RoutingScopeHookArm.lean")
  let source := source.replace "routing-scope" "owner-bindings"
  let source ← once source
    ("    let copied ← IO.Process.output {cmd := \"/bin/cp\",args := #[\"-cR\",\n" ++
     "      (study / \"study/seed-2/work.egg/derived\").toString,(database / \"derived\").toString]}\n" ++
     "    check (copied.exitCode == 0) \"cannot reuse existing numerical preparation\"\n" ++
     "    let source ← DB.PageMap.pin database\n")
    ("    let source ← DB.PageMap.pin database\n" ++
     "    let numerical := database / \"derived\" / source.head.identity / \"semantic\"\n" ++
     "    IO.FS.createDirAll numerical.parent.get!\n" ++
     "    let copied ← IO.Process.output {cmd := \"/bin/cp\",args := #[\"-cR\",\n" ++
     "      (study / \"study/seed-2/work.egg/derived\" / source.head.identity / \"semantic\").toString,numerical.toString]}\n" ++
     "    check (copied.exitCode == 0) \"cannot reuse unchanged numerical preparation\"\n")
  IO.FS.writeFile path source
  let runner := project / "tools/research/RunOwnerBindingsHooks.lean"
  check (!(← runner.pathExists)) "preserve owner hook comparison controller"
  IO.FS.writeFile runner ((← IO.FS.readFile (project / "tools/research/RunRoutingHooks.lean"))
    |>.replace "routing-scope" "owner-bindings" |>.replace "RoutingScopeHookArm" "OwnerBindingsHookArm")
  let original ← read (root / "owner-bindings-audit.settings.json")
  let guard ← read (root / "owner-bindings-audit-build.guard.settings.json")
  for arm in ["baseline","candidate"] do
    let runtime := root / (if arm == "baseline" then "query-cache-baseline-build" else "owner-bindings-runtime-build")
    let core := root / (if arm == "baseline" then "query-cache-baseline-core" else "owner-bindings-core")
    let settings := root / ("owner-bindings-hook-" ++ arm ++ ".settings.json")
    let config := original.setObjVal! "core" (toJson core.toString)
      |>.setObjVal! "parents" (toJson #[runtime.toString])
      |>.setObjVal! "objectModules" (toJson (if arm == "baseline" then
          root / "query-cache-baseline-objects.json" else runtime / "object-mapping.json").toString)
      |>.setObjVal! "output" (toJson (root / ("owner-bindings-hook-" ++ arm ++ "-build")).toString)
      |>.setObjVal! "baselineResponse" (toJson (runtime / "runtime.rsp").toString)
      |>.setObjVal! "baselineMain" (toJson (runtime / "Main.o").toString)
      |>.setObjVal! "mainModule" (toJson "tools.research.OwnerBindingsHookArm")
    IO.FS.writeFile settings config.pretty
    let config := guard.setObjVal! "record" (toJson (records / ("hook-" ++ arm ++ "-build.guard.json")).toString)
      |>.setObjVal! "command" (toJson #["/usr/bin/env","LEAN_NUM_THREADS=1",
        "/Users/ovm/.elan/toolchains/leanprover--lean4---v4.33.0/bin/lean","-M1024","--run",
        (project / "tools/research/StudyBuildMain.lean").toString,settings.toString])
    IO.FS.writeFile (root / ("owner-bindings-hook-" ++ arm ++ ".guard.settings.json")) config.pretty
  let config := guard.setObjVal! "record" (toJson (records / "hooks.guard.json").toString)
    |>.setObjVal! "command" (toJson #["/usr/bin/env","LEAN_NUM_THREADS=1",
      "/Users/ovm/.elan/toolchains/leanprover--lean4---v4.33.0/bin/lean","-M1024","--run",runner.toString])
  IO.FS.writeFile (root / "owner-bindings-hooks.guard.settings.json") config.pretty
  IO.println "Prepared identical source/history two-arm actual hook comparison; copy numerical artifacts only"
