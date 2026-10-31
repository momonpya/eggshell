import Lean
open Lean
private def check (ok : Bool) (message : String) : IO Unit := unless ok do throw (IO.userError message)
def main : IO Unit := do
  let project : System.FilePath := "/Users/ovm/.codex/worktrees/hook-deadline-baseline/eggshell"
  let root : System.FilePath := "/Users/ovm/.codex/experiments/eggshell/scope-token-study-20261028/shared-snapshot"
  let core := root / "service-plan-core"
  let baseline := root / "service-plan-runtime-build"
  let output := root / "recorded-navigation-build"
  check (!(← output.pathExists)) "preserve navigation build"
  for name in ["RecordedNavigation","RecordedNavigationAudit"] do
    let target := core / "tools/research" / (name ++ ".lean")
    check (!(← target.pathExists)) "preserve native navigation source"
    let linked ← IO.Process.output {cmd := "/bin/ln",args := #["-s",(project / "tools/research" / (name ++ ".lean")).toString,target.toString]}
    check (linked.exitCode == 0) "cannot bind navigation source"
  let settings := Json.mkObj [("project",toJson core.toString),("core",toJson core.toString),
    ("baselineCore",toJson (root / "query-cache-baseline-core").toString),("output",toJson output.toString),
    ("toolchain",toJson "/Users/ovm/.elan/toolchains/leanprover--lean4---v4.33.0"),
    ("objectModules",toJson (baseline / "object-mapping.json").toString),
    ("baselineResponse",toJson (baseline / "runtime.rsp").toString),("baselineMain",toJson (baseline / "Main.o").toString),
    ("parents",toJson #[baseline.toString]),("force",toJson (#[] : Array String)),
    ("mainModule",toJson "tools.research.RecordedNavigationAudit")]
  let path := root / "recorded-navigation.settings.json"
  IO.FS.writeFile path settings.compress
  IO.FS.writeFile (root / "recorded-navigation-build.guard.settings.json") (Json.mkObj [
    ("cwd",toJson project.toString),("ownedPrefixes",toJson #[root.toString]),
    ("limitRssKiB",toJson (3670016 : Nat)),("minFreeKiB",toJson (2097152 : Nat)),
    ("record",toJson (project / "docs/candidates/recorded-navigation/build.guard.json").toString),
    ("command",toJson #["/usr/bin/env","LEAN_NUM_THREADS=1",
      "/Users/ovm/.elan/toolchains/leanprover--lean4---v4.33.0/bin/lean","-M1024","--run",
      (project / "tools/research/StudyBuildMain.lean").toString,path.toString])]).compress
  IO.FS.writeFile (root / "recorded-navigation.guard.settings.json") (Json.mkObj [
    ("cwd",toJson project.toString),("ownedPrefixes",toJson #[root.toString]),
    ("limitRssKiB",toJson (3670016 : Nat)),("minFreeKiB",toJson (2097152 : Nat)),
    ("record",toJson (project / "docs/candidates/recorded-navigation/audit.guard.json").toString),
    ("command",toJson #["/usr/bin/env","LEAN_NUM_THREADS=1",(output / "StudyMain").toString,
      (project / "docs/candidates/recorded-navigation/audit").toString])]).compress
  IO.println "Prepared one query-free, gold-free source-navigation diagnostic; no product runtime change"
