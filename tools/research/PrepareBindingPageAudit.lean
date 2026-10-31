import Lean
open Lean
def main : IO Unit := do
  let project : System.FilePath := "/Users/ovm/.codex/worktrees/hook-deadline-baseline/eggshell"
  let root : System.FilePath := "/Users/ovm/.codex/experiments/eggshell/scope-token-study-20261028/shared-snapshot"
  let core := root / "project-metadata-core"
  let baseline := root / "project-metadata-runtime-build"
  let records := project / "docs/candidates/project-metadata"
  let target := core / "tools/research/BindingPageAudit.lean"
  if ← target.pathExists then IO.FS.removeFile target
  IO.FS.writeFile target (← IO.FS.readFile (project / "tools/research/BindingPageAudit.lean"))
  let settingsPath := root / "project-metadata-audit.settings.json"
  IO.FS.writeFile settingsPath (Json.mkObj [
    ("project",toJson core.toString),("core",toJson core.toString),
    ("baselineCore",toJson (root / "query-cache-baseline-core").toString),
    ("output",toJson (root / "project-metadata-audit-build").toString),
    ("toolchain",toJson "/Users/ovm/.elan/toolchains/leanprover--lean4---v4.33.0"),
    ("objectModules",toJson (baseline / "object-mapping.json").toString),
    ("baselineResponse",toJson (baseline / "runtime.rsp").toString),
    ("baselineMain",toJson (baseline / "Main.o").toString),
    ("parents",toJson #[baseline.toString]),("force",toJson (#[] : Array String)),
    ("mainModule",toJson "tools.research.BindingPageAudit")]).compress
  let mut attempt := 1
  while ← (records / s!"audit-build-{attempt}.guard.json").pathExists do attempt := attempt+1
  for (name,record,command) in [
    ("audit-build",s!"audit-build-{attempt}",#["/usr/bin/env","LEAN_NUM_THREADS=1",
      "/Users/ovm/.elan/toolchains/leanprover--lean4---v4.33.0/bin/lean","-M1024","--run",
      (project / "tools/research/StudyBuildMain.lean").toString,settingsPath.toString]),
    ("audit","audit",#["/usr/bin/env","LEAN_NUM_THREADS=1",
      (root / "project-metadata-audit-build/StudyMain").toString,
      (root / "project-metadata-audit-trial").toString,(records / "binding-audit.json").toString])] do
    IO.FS.writeFile (root / ("project-metadata-" ++ name ++ ".guard.settings.json")) (Json.mkObj [
      ("cwd",toJson project.toString),("ownedPrefixes",toJson #[root.toString]),
      ("limitRssKiB",toJson (3670016 : Nat)),("minFreeKiB",toJson (2097152 : Nat)),
      ("record",toJson (records / (record ++ ".guard.json")).toString),("command",toJson command)]).compress
  IO.println "Prepared binding codec, complete batch and bounded metadata workload audit"
