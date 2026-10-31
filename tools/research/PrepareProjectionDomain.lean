import Lean
open Lean
def main : IO Unit := do
  let project : System.FilePath := "/Users/ovm/.codex/worktrees/hook-deadline-baseline/eggshell"
  let root : System.FilePath := "/Users/ovm/.codex/experiments/eggshell/scope-token-study-20261028/shared-snapshot"
  let core := root / "service-plan-core"
  let baseline := root / "service-plan-runtime-build"
  let target := core / "tools/research/ProjectionDomainAudit.lean"
  unless !(← target.pathExists) && !(← (root / "projection-domain-build").pathExists) do
    throw (IO.userError "preserve projection domain build")
  let linked ← IO.Process.output {cmd := "/bin/ln",args := #["-s",(project / "tools/research/ProjectionDomainAudit.lean").toString,target.toString]}
  unless linked.exitCode == 0 do throw (IO.userError "cannot bind projection audit")
  let settings := Json.mkObj [("project",toJson core.toString),("core",toJson core.toString),
    ("baselineCore",toJson (root / "query-cache-baseline-core").toString),("output",toJson (root / "projection-domain-build").toString),
    ("toolchain",toJson "/Users/ovm/.elan/toolchains/leanprover--lean4---v4.33.0"),
    ("objectModules",toJson (baseline / "object-mapping.json").toString),
    ("baselineResponse",toJson (baseline / "runtime.rsp").toString),("baselineMain",toJson (baseline / "Main.o").toString),
    ("parents",toJson #[baseline.toString,(root / "recorded-navigation-build").toString]),
    ("force",toJson (#[] : Array String)),("mainModule",toJson "tools.research.ProjectionDomainAudit")]
  let path := root / "projection-domain.settings.json"
  IO.FS.writeFile path settings.compress
  for (name,command) in [("build",#["/usr/bin/env","LEAN_NUM_THREADS=1",
        "/Users/ovm/.elan/toolchains/leanprover--lean4---v4.33.0/bin/lean","-M1024","--run",
        (project / "tools/research/StudyBuildMain.lean").toString,path.toString]),
      ("audit",#["/usr/bin/env","LEAN_NUM_THREADS=1",(root / "projection-domain-build/StudyMain").toString,
        (project / "docs/candidates/projection-domain/audit").toString])] do
    IO.FS.writeFile (root / ("projection-domain-" ++ name ++ ".guard.settings.json")) (Json.mkObj [
      ("cwd",toJson project.toString),("ownedPrefixes",toJson #[root.toString]),
      ("limitRssKiB",toJson (3670016 : Nat)),("minFreeKiB",toJson (2097152 : Nat)),
      ("record",toJson (project / "docs/candidates/projection-domain" / (name ++ ".guard.json")).toString),
      ("command",toJson command)]).compress
  IO.println "Prepared separate complete file/original domain diagnostics; no selector or model changes"
