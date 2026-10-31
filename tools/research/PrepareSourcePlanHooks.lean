import Lean
open Lean
private def check (ok : Bool) (message : String) : IO Unit := unless ok do throw (IO.userError message)
private def once (source before after : String) : IO String := do
  check ((source.splitOn before).length == 2) ("source-plan hook anchor changed: " ++ toString (before.take 80))
  return source.replace before after

private def withSuite (project : System.FilePath) (source : String) : IO String := do
  let source ← once source "def main (args : List String) : IO Unit := do"
    ((← IO.FS.readFile (project / "tools/research/SourcePlanSuite.lean.inc")) ++
      "\n\ndef main (args : List String) : IO Unit := do\n" ++
      "  if args == [\"suite\"] then\n    sourcePlanSuite\n    return")
  return source

def main (args : List String) : IO Unit := do
  let project : System.FilePath := "/Users/ovm/.codex/worktrees/hook-deadline-baseline/eggshell"
  let root : System.FilePath := "/Users/ovm/.codex/experiments/eggshell/scope-token-study-20261028/shared-snapshot"
  let records := project / "docs/candidates/source-plan"
  let destination := project / "tools/research/SourcePlanHook.lean"
  if args == ["suite"] then
    IO.FS.writeFile destination (← withSuite project (← IO.FS.readFile destination))
    IO.println "Connected native source-plan suite controller"
    return
  check (!(← destination.pathExists)) "preserve generated source-plan hook helper"
  let mut source := (← IO.FS.readFile (project / "tools/research/CheckedOriginalHook.lean")).replace
    "checked-original" "source-plan"
  source ← once source "(if arm == \"baseline\" then \"query-cache-baseline-build\" else \"source-plan-runtime-build\")"
    "(if arm == \"baseline\" then \"owner-palette-runtime-build\" else \"source-plan-runtime-build\")"
  source ← once source "shared-snapshot/source-plan-hook-trial" "shared-snapshot/source-plan-trial"
  source ← once source "  check ([\"baseline\",\"candidate\"].contains arm)"
    "  let audit := mode == \"audit\"\n  let mode := if audit then \"run\" else mode\n  check ([\"baseline\",\"candidate\"].contains arm)"
  source ← once source "  let destination := saved / (\"rep-\" ++ repetition) / s!\"topic-{topic}\""
    "  let destination := saved / (if audit then \"audit\" else \"rep-\" ++ repetition) / s!\"topic-{topic}\""
  source ← once source "  let env := environment arm false"
    "  let env := (environment arm false).map fun (name,value) =>\n    (name,if audit && name == \"EGGSHELL_TRACE_SELECTOR_INPUT\" then some \"1\" else value)"
  source ← once source "  let session := \"source-plan-\" ++ arm ++ \"-\" ++ repetition ++ \"-\" ++ toString topic"
    "  let session := \"source-plan-\" ++ arm ++ (if audit then \"-audit-\" else \"-\") ++ repetition ++ \"-\" ++ toString topic"
  source ← once source "(\"adopted\",toJson false)]).pretty"
    "(\"adopted\",toJson false),(\"sourceAuditRequested\",toJson audit)]).pretty"
  IO.FS.writeFile destination (← withSuite project source)
  for arm in ["baseline","candidate"] do
    let core := root / (if arm == "baseline" then "owner-palette-core" else "source-plan-core")
    let target := core / "tools/research/SourcePlanHook.lean"
    check (!(← target.pathExists)) "preserve candidate helper source"
    let linked ← IO.Process.output {cmd := "/bin/ln",args := #["-s",destination.toString,target.toString]}
    check (linked.exitCode == 0) "cannot bind source-plan helper"
    let baseline := root / (if arm == "baseline" then "owner-palette-runtime-build" else "source-plan-runtime-build")
    let settings := Json.mkObj [
      ("project",toJson core.toString),("core",toJson core.toString),
      ("baselineCore",toJson (root / "query-cache-baseline-core").toString),
      ("output",toJson (root / ("source-plan-hook-" ++ arm ++ "-build")).toString),
      ("toolchain",toJson "/Users/ovm/.elan/toolchains/leanprover--lean4---v4.33.0"),
      ("objectModules",toJson (baseline / "object-mapping.json").toString),
      ("baselineResponse",toJson (baseline / "runtime.rsp").toString),
      ("baselineMain",toJson (baseline / "Main.o").toString),
      ("parents",toJson (if arm == "candidate" then
        #[baseline.toString,(root / "source-plan-hook-baseline-build").toString] else #[baseline.toString])),
      ("force",toJson (#[] : Array String)),
      ("mainModule",toJson "tools.research.SourcePlanHook")]
    let settingsPath := root / ("source-plan-hook-" ++ arm ++ ".settings.json")
    IO.FS.writeFile settingsPath settings.compress
    IO.FS.writeFile (root / ("source-plan-hook-" ++ arm ++ ".guard.settings.json")) (Json.mkObj [
      ("cwd",toJson project.toString),("ownedPrefixes",toJson #[root.toString]),
      ("limitRssKiB",toJson (3670016 : Nat)),("minFreeKiB",toJson (2097152 : Nat)),
      ("record",toJson (records / ("hook-build-" ++ arm ++ ".guard.json")).toString),
      ("command",toJson #["/usr/bin/env","LEAN_NUM_THREADS=1",
        "/Users/ovm/.elan/toolchains/leanprover--lean4---v4.33.0/bin/lean","-M1024","--run",
        (project / "tools/research/StudyBuildMain.lean").toString,settingsPath.toString])]).compress
  IO.FS.writeFile (records / "native-plan.json") (Json.mkObj [
    ("source",toJson "R40 plus unchanged sealed supplement"),
    ("topics",toJson #[1,2,3]),("freshSessionsPerTopicAndArm",toJson (2 : Nat)),
    ("arms",toJson #["baseline","candidate"]),("order",toJson "topic-major, repetition-major, baseline then candidate"),
    ("stopOnChangedBodyOrDenominator",toJson true),("hookDeadlineMs",toJson (30000 : Nat)),
    ("independentAudit",toJson "one candidate topic-1 hook with reference construction enabled, excluded from timings"),
    ("answeringModelCalls",toJson (0 : Nat)),("adopted",toJson false),
    ("limits",Json.mkObj [("aggregateRssKiB",toJson (3670016 : Nat)),("minFreeKiB",toJson (2097152 : Nat))])]).pretty
  IO.println "Prepared paired ordinary hooks and a separate exact-construction audit; no new seed or model calls"
