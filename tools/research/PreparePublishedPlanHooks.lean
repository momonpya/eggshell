import Lean
open Lean
private def check (ok : Bool) (message : String) : IO Unit := unless ok do throw (IO.userError message)
private def once (source before after : String) : IO String := do
  check ((source.splitOn before).length == 2) "published plan harness anchor changed"
  return source.replace before after
def main : IO Unit := do
  let project : System.FilePath := "/Users/ovm/.codex/worktrees/hook-deadline-baseline/eggshell"
  let root : System.FilePath := "/Users/ovm/.codex/experiments/eggshell/scope-token-study-20261028/shared-snapshot"
  let destination := project / "tools/research/PublishedPlanHook.lean"
  check (!(← destination.pathExists)) "preserve generated published plan harness"
  let source ← IO.FS.readFile (project / "tools/research/ServicePlanHook.lean")
  let source := source.replace "service-plan" "published-plan"
  let source ← once source
    "(if arm == \"baseline\" then \"source-plan-runtime-build\" else \"published-plan-runtime-build\")"
    "(if arm == \"baseline\" then \"service-plan-runtime-build\" else \"published-plan-runtime-build\")"
  let source := source.replace "tools_research_ServicePlanHook.dependencies" "tools_research_PublishedPlanHook.dependencies"
  let source ← once source "private def servicePlanSuite : IO Unit := do"
    "private def servicePlanSuite (connectionOnly : Bool := false) : IO Unit := do"
  let source ← once source "  let mut stages := #[]\n"
    ("  if connectionOnly then\n" ++
     "    IO.FS.writeFile (evidence / \"connection.json\") (Json.mkObj [\n" ++
     "      (\"conditionedProblemExact\",toJson sameProblem),(\"actualBodyExact\",toJson sameAuditBody),\n" ++
     "      (\"actualHooks\",toJson (2 : Nat)),(\"answeringModelCalls\",toJson (0 : Nat)),\n" ++
     "      (\"sourceUnchanged\",toJson ((← StudyRuntime.files original) == before)),\n" ++
     "      (\"latencyImprovementMeasured\",toJson false),(\"adopted\",toJson false)]).pretty\n" ++
     "    return\n  let mut stages := #[]\n")
  let source ← once source "def main (args : List String) : IO Unit := do\n"
    "def main (args : List String) : IO Unit := do\n  if args == [\"connection\"] then\n    servicePlanSuite true\n    return\n"
  IO.FS.writeFile destination source
  let records := project / "docs/candidates/published-plan"
  for arm in ["baseline","candidate"] do
    let core := root / (if arm == "baseline" then "service-plan-core" else "published-plan-core")
    let target := core / "tools/research/PublishedPlanHook.lean"
    check (!(← target.pathExists)) "preserve isolated published plan helper"
    let linked ← IO.Process.output {cmd := "/bin/ln",args := #["-s",destination.toString,target.toString]}
    check (linked.exitCode == 0) "cannot bind publication hook helper"
    let baseline := root / (if arm == "baseline" then "service-plan-runtime-build" else "published-plan-runtime-build")
    let settings := Json.mkObj [
      ("project",toJson core.toString),("core",toJson core.toString),
      ("baselineCore",toJson (root / "query-cache-baseline-core").toString),
      ("output",toJson (root / ("published-plan-hook-" ++ arm ++ "-build")).toString),
      ("toolchain",toJson "/Users/ovm/.elan/toolchains/leanprover--lean4---v4.33.0"),
      ("objectModules",toJson (baseline / "object-mapping.json").toString),
      ("baselineResponse",toJson (baseline / "runtime.rsp").toString),
      ("baselineMain",toJson (baseline / "Main.o").toString),
      ("parents",toJson #[baseline.toString]),("force",toJson (#[] : Array String)),
      ("mainModule",toJson "tools.research.PublishedPlanHook")]
    let path := root / ("published-plan-hook-" ++ arm ++ ".settings.json")
    IO.FS.writeFile path settings.compress
    IO.FS.writeFile (root / ("published-plan-hook-" ++ arm ++ ".guard.settings.json")) (Json.mkObj [
      ("cwd",toJson project.toString),("ownedPrefixes",toJson #[root.toString]),
      ("limitRssKiB",toJson (3670016 : Nat)),("minFreeKiB",toJson (2097152 : Nat)),
      ("record",toJson (records / ("hook-build-" ++ arm ++ ".guard.json")).toString),
      ("command",toJson #["/usr/bin/env","LEAN_NUM_THREADS=1",
        "/Users/ovm/.elan/toolchains/leanprover--lean4---v4.33.0/bin/lean","-M1024","--run",
        (project / "tools/research/StudyBuildMain.lean").toString,path.toString])]).compress
  IO.FS.writeFile (root / "published-plan-hooks.guard.settings.json") (Json.mkObj [
    ("cwd",toJson project.toString),("ownedPrefixes",toJson #[root.toString]),
    ("limitRssKiB",toJson (3670016 : Nat)),("minFreeKiB",toJson (2097152 : Nat)),
    ("record",toJson (records / "connection.guard.json").toString),
    ("command",toJson #["/usr/bin/env","LEAN_NUM_THREADS=1",(root / "published-plan-hook-candidate-build/StudyMain").toString,"connection"])]).compress
  IO.FS.writeFile (records / "hooks-plan.json") (Json.mkObj [
    ("source",toJson "fixed R40 plus unchanged sealed supplement; model-free diagnostics"),
    ("initialStage",toJson "only two topic-1 diagnostic hooks to validate the actual connection and full cost problem; no performance/adoption claim"),
    ("topics",toJson #[1,2,3]),("freshSessionsPerTopicAndArm",toJson (2 : Nat)),
    ("order",toJson "topic-major AB/BA"),("independentFullProblemAudit",toJson true),
    ("stopOnChangedProblemBodyOrEvidence",toJson true),("deadlineMs",toJson (30000 : Nat)),
    ("answeringModelCalls",toJson (0 : Nat)),("newSeeds",toJson (0 : Nat)),("adopted",toJson false)]).pretty
  IO.println "Prepared ordinary hooks using the unchanged service-plan harness and fixed paired comparison"
