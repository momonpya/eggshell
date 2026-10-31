import Lean
open Lean
private def check (ok : Bool) (message : String) : IO Unit := unless ok do throw (IO.userError message)
private def once (source before after : String) : IO String := do
  check ((source.splitOn before).length == 2) ("service hook anchor changed: " ++ toString (before.take 80))
  return source.replace before after

def main : IO Unit := do
  let project : System.FilePath := "/Users/ovm/.codex/worktrees/hook-deadline-baseline/eggshell"
  let root : System.FilePath := "/Users/ovm/.codex/experiments/eggshell/scope-token-study-20261028/shared-snapshot"
  let records := project / "docs/candidates/service-plan"
  let target := project / "tools/research/ServicePlanHook.lean"
  check (!(← target.pathExists)) "preserve service hook harness"
  let original ← IO.FS.readFile (project / "tools/research/SourcePlanHook.lean")
  let heads := original.splitOn "private def sourcePlanSuite : IO Unit := do\n"
  check (heads.length == 2) "service hook suite start"
  let suffix := heads[1]!.splitOn "def main (args : List String) : IO Unit := do\n"
  check (suffix.length == 2) "service hook suite end"
  let suite ← IO.FS.readFile (project / "tools/research/ServicePlanSuite.lean.inc")
  let mut source := (heads[0]! ++ suite ++ "\n\ndef main (args : List String) : IO Unit := do\n" ++ suffix[1]!)
    |>.replace "source-plan" "service-plan" |>.replace "sourcePlanSuite" "servicePlanSuite"
    |>.replace "tools_research_SourcePlanHook" "tools_research_ServicePlanHook"
  source ← once source "(if arm == \"baseline\" then \"owner-palette-runtime-build\" else \"service-plan-runtime-build\")"
    "(if arm == \"baseline\" then \"source-plan-runtime-build\" else \"service-plan-runtime-build\")"
  source ← once source "(\"sourceAuditRequested\",toJson audit)" "(\"nativeDeliveryAudit\",toJson audit)"
  IO.FS.writeFile target source
  for arm in ["baseline","candidate"] do
    let core := root / (if arm == "baseline" then "source-plan-core" else "service-plan-core")
    let link := core / "tools/research/ServicePlanHook.lean"
    check (!(← link.pathExists)) "preserve native service hook source"
    let linked ← IO.Process.output {cmd := "/bin/ln",args := #["-s",target.toString,link.toString]}
    check (linked.exitCode == 0) "cannot bind service hook source"
    let baseline := root / (if arm == "baseline" then "source-plan-runtime-build" else "service-plan-runtime-build")
    let settings := Json.mkObj [
      ("project",toJson core.toString),("core",toJson core.toString),
      ("baselineCore",toJson (root / "query-cache-baseline-core").toString),
      ("output",toJson (root / ("service-plan-hook-" ++ arm ++ "-build")).toString),
      ("toolchain",toJson "/Users/ovm/.elan/toolchains/leanprover--lean4---v4.33.0"),
      ("objectModules",toJson (baseline / "object-mapping.json").toString),
      ("baselineResponse",toJson (baseline / "runtime.rsp").toString),
      ("baselineMain",toJson (baseline / "Main.o").toString),
      ("parents",toJson (if arm == "candidate" then
        #[baseline.toString,(root / "service-plan-hook-baseline-build").toString] else #[baseline.toString])),
      ("force",toJson (#[] : Array String)),("mainModule",toJson "tools.research.ServicePlanHook")]
    let path := root / ("service-plan-hook-" ++ arm ++ ".settings.json")
    IO.FS.writeFile path settings.compress
    IO.FS.writeFile (root / ("service-plan-hook-" ++ arm ++ ".guard.settings.json")) (Json.mkObj [
      ("cwd",toJson project.toString),("ownedPrefixes",toJson #[root.toString]),
      ("limitRssKiB",toJson (3670016 : Nat)),("minFreeKiB",toJson (2097152 : Nat)),
      ("record",toJson (records / ("hook-build-" ++ arm ++ ".guard.json")).toString),
      ("command",toJson #["/usr/bin/env","LEAN_NUM_THREADS=1",
        "/Users/ovm/.elan/toolchains/leanprover--lean4---v4.33.0/bin/lean","-M1024","--run",
        (project / "tools/research/StudyBuildMain.lean").toString,path.toString])]).compress
  IO.FS.writeFile (records / "native-plan.json") (Json.mkObj [
    ("source",toJson "R40 with unchanged sealed supplement"),("topics",toJson #[1,2,3]),
    ("freshSessionsPerTopicAndArm",toJson (2 : Nat)),
    ("order",toJson "topic-major; repetition 0 AB, repetition 1 BA"),
    ("stopOnChangedBodyProblemOrDenominator",toJson true),
    ("hookDeadlineMs",toJson (30000 : Nat)),
    ("independentAudit",toJson "baseline and candidate topic 1, excluded from ordinary timings"),
    ("answeringModelCalls",toJson (0 : Nat)),("adopted",toJson false)]).pretty
  IO.println "Prepared an actual-hook AB/BA comparison with a separate problem/body audit"
