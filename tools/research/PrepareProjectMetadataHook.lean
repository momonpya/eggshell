import Lean
open Lean
def main : IO Unit := do
  let project : System.FilePath := "/Users/ovm/.codex/worktrees/hook-deadline-baseline/eggshell"
  let root : System.FilePath := "/Users/ovm/.codex/experiments/eggshell/scope-token-study-20261028/shared-snapshot"
  let core := root / "project-metadata-core"
  let runtime := root / "project-metadata-runtime-build"
  let records := project / "docs/candidates/project-metadata"
  let source ← IO.FS.readFile (project / "tools/research/SourceViewHook.lean")
  let target := core / "tools/research/ProjectMetadataHook.lean"
  unless !(← target.pathExists) do throw (IO.userError "preserve isolated project metadata hook")
  IO.FS.writeFile target (source.replace "prepared-view" "project-metadata")
  let settingsPath := root / "project-metadata-hook.settings.json"
  IO.FS.writeFile settingsPath (Json.mkObj [
    ("project",toJson core.toString),("core",toJson core.toString),
    ("baselineCore",toJson (root / "query-cache-baseline-core").toString),
    ("output",toJson (root / "project-metadata-hook-candidate-build").toString),
    ("toolchain",toJson "/Users/ovm/.elan/toolchains/leanprover--lean4---v4.33.0"),
    ("objectModules",toJson (runtime / "object-mapping.json").toString),
    ("baselineResponse",toJson (runtime / "runtime.rsp").toString),
    ("baselineMain",toJson (runtime / "Main.o").toString),
    ("parents",toJson #[runtime.toString]),("force",toJson (#[] : Array String)),
    ("mainModule",toJson "tools.research.ProjectMetadataHook")]).compress
  let helper := root / "project-metadata-hook-candidate-build/StudyMain"
  for (name,command) in [
    ("hook-build",#["/usr/bin/env","LEAN_NUM_THREADS=1",
      "/Users/ovm/.elan/toolchains/leanprover--lean4---v4.33.0/bin/lean","-M1024","--run",
      (project / "tools/research/StudyBuildMain.lean").toString,settingsPath.toString]),
    ("hook-describe",#["/usr/bin/env","LEAN_NUM_THREADS=1",helper.toString,"describe","candidate"]),
    ("hook-prepare",#["/usr/bin/env","LEAN_NUM_THREADS=1",helper.toString,"prepare","candidate"]),
    ("hook-topic-1",#["/usr/bin/env","LEAN_NUM_THREADS=1",helper.toString,"run","candidate","0","1"])] do
    IO.FS.writeFile (root / ("project-metadata-" ++ name ++ ".guard.settings.json")) (Json.mkObj [
      ("cwd",toJson project.toString),("ownedPrefixes",toJson #[root.toString]),
      ("limitRssKiB",toJson (3670016 : Nat)),("minFreeKiB",toJson (2097152 : Nat)),
      ("record",toJson (records / (name ++ ".guard.json")).toString),("command",toJson command)]).compress
  IO.println "Prepared one original-runtime connection check after the complete metadata batch"
