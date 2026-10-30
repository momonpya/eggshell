import Lean.Data.Json.Parser
import Lean.Data.Json.FromToJson
open Lean

private def check (ok : Bool) (message : String) : IO Unit := unless ok do throw (IO.userError message)
private def read (path : System.FilePath) : IO Json := IO.FS.readFile path >>= fun text => IO.ofExcept (Json.parse text)
private def once (source before after : String) : IO String := do
  check ((source.splitOn before).length == 2) ("trace anchor changed: " ++ toString (before.take 80))
  return source.replace before after

def main : IO Unit := do
  let project : System.FilePath := "/Users/ovm/.codex/worktrees/hook-deadline-baseline/eggshell"
  let root : System.FilePath := "/Users/ovm/.codex/experiments/eggshell/scope-token-study-20261028/shared-snapshot"
  let records := project / "docs/candidates/query-stage-profile"
  let path := project / "tools/research/QueryStageTraceArm.lean"
  check (!(← path.pathExists)) "preserve trace harness"
  let previous ← read (records / "result.json")
  check (previous.getObjValD "sameBaselineBody" == toJson true && previous.getObjValD "stageLines" == toJson (0 : Nat))
    "only repair the completed discarded-stderr observation"
  let mut source ← IO.FS.readFile (project / "tools/research/QueryStageHookArm.lean")
  source ← once source "docs/candidates/query-stage/hooks" "docs/candidates/query-stage-profile/trace"
  source ← once source "query-stage-runtime-build" "query-stage-file-runtime-build"
  source ← once source "\"query-stage-hook-\" ++ arm ++ \"-build\"" "\"query-stage-trace-\" ++ arm ++ \"-build\""
  source ← once source "let session := \"query-stage-\"" "let session := \"query-stage-trace-\""
  source ← once source "(\"LEAN_NUM_THREADS\",some \"1\"),"
    ("(\"LEAN_NUM_THREADS\",some \"1\")," ++
      "(\"EGGSHELL_QUERY_STAGE_LOG\",some (project / \"docs/candidates/query-stage-profile/trace-events.jsonl\").toString),")
  IO.FS.writeFile path source
  let oldRuntime := root / "query-stage-runtime-build"
  let runtime := root / "query-stage-file-runtime-build"
  let runtimeSettings := root / "query-stage-file-runtime.settings.json"
  let settings ← read (root / "query-stage-runtime-build.settings.json")
  let settings := settings.setObjVal! "output" (toJson runtime.toString)
    |>.setObjVal! "parents" (toJson #[oldRuntime.toString])
    |>.setObjVal! "objectModules" (toJson (oldRuntime / "object-mapping.json").toString)
    |>.setObjVal! "baselineResponse" (toJson (oldRuntime / "runtime.rsp").toString)
    |>.setObjVal! "baselineMain" (toJson (oldRuntime / "Main.o").toString)
  IO.FS.writeFile runtimeSettings settings.pretty
  let helperSettings := root / "query-stage-trace-helper.settings.json"
  let settings ← read (root / "query-stage-hook-build.settings.json")
  let settings := settings.setObjVal! "output" (toJson (root / "query-stage-trace-candidate-build").toString)
    |>.setObjVal! "parents" (toJson #[runtime.toString])
    |>.setObjVal! "mainModule" (toJson "tools.research.QueryStageTraceArm")
    |>.setObjVal! "objectModules" (toJson (runtime / "object-mapping.json").toString)
    |>.setObjVal! "baselineResponse" (toJson (runtime / "runtime.rsp").toString)
    |>.setObjVal! "baselineMain" (toJson (runtime / "Main.o").toString)
  IO.FS.writeFile helperSettings settings.pretty
  let guard ← read (root / "query-stage-runtime.guard.settings.json")
  for (label,settings) in [("file-runtime",runtimeSettings),("trace-helper",helperSettings)] do
    let command := #["/usr/bin/env","LEAN_NUM_THREADS=1",
      "/Users/ovm/.elan/toolchains/leanprover--lean4---v4.33.0/bin/lean","-M1024","--run",
      (project / "tools/research/StudyBuildMain.lean").toString,settings.toString]
    let guard := guard.setObjVal! "command" (toJson command)
      |>.setObjVal! "record" (toJson (records / (label ++ ".guard.json")).toString)
    IO.FS.writeFile (root / ("query-stage-" ++ label ++ ".guard.settings.json")) guard.pretty
  let guard := guard.setObjVal! "command" (toJson #["/usr/bin/env","LEAN_NUM_THREADS=1",
      "/Users/ovm/.elan/toolchains/leanprover--lean4---v4.33.0/bin/lean","-M1024","--run",
      (project / "tools/research/TraceQueryStageProfile.lean").toString])
    |>.setObjVal! "record" (toJson (records / "file-trace.guard.json").toString)
  IO.FS.writeFile (root / "query-stage-file-trace.guard.settings.json") guard.pretty
  IO.println "Prepared file-only observation on the existing ready snapshot; no source preparation or model retake"
