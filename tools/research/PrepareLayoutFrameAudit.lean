import Lean
open Lean
def main : IO Unit := do
  let project : System.FilePath := "/Users/ovm/.codex/worktrees/hook-deadline-baseline/eggshell"
  let study : System.FilePath := "/Users/ovm/.codex/experiments/eggshell/scope-token-study-20261028"
  let root := study / "shared-snapshot"
  let runtime := root / "query-cache-baseline-build"
  let records := project / "docs/candidates/layout-frame-dependencies"
  IO.FS.createDirAll records
  let toolchain := "/Users/ovm/.elan/toolchains/leanprover--lean4---v4.33.0"
  let config := Json.mkObj [("project",toJson project.toString),
    ("core",toJson (root / "query-cache-baseline-core").toString),
    ("baselineCore",toJson (root / "query-cache-baseline-core").toString),
    ("output",toJson (root / "layout-frame-build").toString),("toolchain",toJson toolchain),
    ("baselineResponse",toJson (runtime / "runtime.rsp").toString),
    ("baselineMain",toJson (runtime / "Main.o").toString),
    ("objectModules",toJson (root / "query-cache-baseline-objects.json").toString),
    ("parents",toJson (#[] : Array String)),("force",toJson (#[] : Array String)),
    ("mainModule",toJson "tools.research.LayoutFrameAudit")]
  let settings := root / "layout-frame-build.settings.json"
  IO.FS.writeFile settings config.pretty
  let guard := Json.mkObj [("cwd",toJson project.toString),("limitRssKiB",toJson (3670016 : Nat)),
    ("minFreeKiB",toJson (2097152 : Nat)),("ownedPrefixes",toJson #[root.toString])]
  for (kind,command) in [
      ("build",#["/usr/bin/env","LEAN_NUM_THREADS=1",toolchain ++ "/bin/lean","-M1024","--run",
        (project / "tools/research/StudyBuildMain.lean").toString,settings.toString]),
      ("run",#[(root / "layout-frame-build/StudyMain").toString,(records / "audit").toString])] do
    let config := guard.setObjVal! "command" (toJson command)
      |>.setObjVal! "record" (toJson (records / (kind ++ ".guard.json")).toString)
    IO.FS.writeFile (root / ("layout-frame-" ++ kind ++ ".guard.settings.json")) config.pretty
  IO.println "Prepared guarded label-independent layout diagnostic only"
