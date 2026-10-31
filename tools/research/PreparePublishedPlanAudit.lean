import Lean
open Lean
def main : IO Unit := do
  let project : System.FilePath := "/Users/ovm/.codex/worktrees/hook-deadline-baseline/eggshell"
  let root : System.FilePath := "/Users/ovm/.codex/experiments/eggshell/scope-token-study-20261028/shared-snapshot"
  let core := root / "published-plan-core"
  let baseline := root / "published-plan-runtime-build"
  let target := core / "tools/research/PublishedPlanMetadataAudit.lean"
  unless !(← target.pathExists) && !(← (root / "published-plan-audit-build").pathExists) do
    throw (IO.userError "preserve publication metadata audit")
  let linked ← IO.Process.output {cmd := "/bin/ln",args := #["-s",(project / "tools/research/PublishedPlanMetadataAudit.lean").toString,target.toString]}
  unless linked.exitCode == 0 do throw (IO.userError "cannot bind publication audit")
  let settings := Json.mkObj [
    ("project",toJson core.toString),("core",toJson core.toString),
    ("baselineCore",toJson (root / "query-cache-baseline-core").toString),
    ("output",toJson (root / "published-plan-audit-build").toString),
    ("toolchain",toJson "/Users/ovm/.elan/toolchains/leanprover--lean4---v4.33.0"),
    ("objectModules",toJson (baseline / "object-mapping.json").toString),
    ("baselineResponse",toJson (baseline / "runtime.rsp").toString),
    ("baselineMain",toJson (baseline / "Main.o").toString),
    ("parents",toJson #[baseline.toString]),("force",toJson (#[] : Array String)),
    ("mainModule",toJson "tools.research.PublishedPlanMetadataAudit")]
  let path := root / "published-plan-audit.settings.json"
  IO.FS.writeFile path settings.compress
  let records := project / "docs/candidates/published-plan"
  for (name,command) in [
      ("audit-build",#["/usr/bin/env","LEAN_NUM_THREADS=1",
        "/Users/ovm/.elan/toolchains/leanprover--lean4---v4.33.0/bin/lean","-M1024","--run",
        (project / "tools/research/StudyBuildMain.lean").toString,path.toString]),
      ("audit",#["/usr/bin/env","LEAN_NUM_THREADS=1",(root / "published-plan-audit-build/StudyMain").toString,
        (root / "published-plan-audit-db").toString,(records / "metadata-audit.json").toString])] do
    IO.FS.writeFile (root / ("published-plan-" ++ name ++ ".guard.settings.json")) (Json.mkObj [
      ("cwd",toJson project.toString),("ownedPrefixes",toJson #[root.toString]),
      ("limitRssKiB",toJson (3670016 : Nat)),("minFreeKiB",toJson (2097152 : Nat)),
      ("record",toJson (records / (name ++ ".guard.json")).toString),("command",toJson command)]).compress
  IO.println "Prepared durable metadata, exact cost, old-pin and delta audit"
