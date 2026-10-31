import Lean
open Lean
def main : IO Unit := do
  let project : System.FilePath := "/Users/ovm/.codex/worktrees/hook-deadline-baseline/eggshell"
  let root : System.FilePath := "/Users/ovm/.codex/experiments/eggshell/scope-token-study-20261028/shared-snapshot"
  let core := root / "prepared-view-core"
  let runtime := root / "prepared-view-runtime-build"
  let records := project / "docs/candidates/prepared-view"
  let target := core / "tools/research/SourceViewStorageAudit.lean"
  if ← target.pathExists then IO.FS.removeFile target
  IO.FS.writeFile target (← IO.FS.readFile (project / "tools/research/SourceViewStorageAudit.lean"))
  let settingsPath := root / "prepared-view-storage-audit.settings.json"
  IO.FS.writeFile settingsPath (Json.mkObj [
    ("project",toJson core.toString),("core",toJson core.toString),
    ("baselineCore",toJson (root / "query-cache-baseline-core").toString),
    ("output",toJson (root / "prepared-view-storage-audit-build").toString),
    ("toolchain",toJson "/Users/ovm/.elan/toolchains/leanprover--lean4---v4.33.0"),
    ("objectModules",toJson (runtime / "object-mapping.json").toString),
    ("baselineResponse",toJson (runtime / "runtime.rsp").toString),
    ("baselineMain",toJson (runtime / "Main.o").toString),
    ("parents",toJson #[runtime.toString]),("force",toJson (#[] : Array String)),
    ("mainModule",toJson "tools.research.SourceViewStorageAudit")]).compress
  let mut attempt := 1
  while ← (records / s!"storage-build-{attempt}.guard.json").pathExists do attempt := attempt+1
  for (name,record,command) in [
    ("storage-build",s!"storage-build-{attempt}",#["/usr/bin/env","LEAN_NUM_THREADS=1",
      "/Users/ovm/.elan/toolchains/leanprover--lean4---v4.33.0/bin/lean","-M1024","--run",
      (project / "tools/research/StudyBuildMain.lean").toString,settingsPath.toString]),
    ("storage-audit","storage-audit",#["/usr/bin/env","LEAN_NUM_THREADS=1",
      (root / "prepared-view-storage-audit-build/StudyMain").toString,
      (root / "prepared-view-storage-trial").toString,(records / "storage-audit.json").toString])] do
    IO.FS.writeFile (root / ("prepared-view-" ++ name ++ ".guard.settings.json")) (Json.mkObj [
      ("cwd",toJson project.toString),("ownedPrefixes",toJson #[root.toString]),
      ("limitRssKiB",toJson (3670016 : Nat)),("minFreeKiB",toJson (2097152 : Nat)),
      ("record",toJson (records / (record ++ ".guard.json")).toString),("command",toJson command)]).compress
  IO.println "Prepared actual publication/delta and metadata-only service storage checks"
