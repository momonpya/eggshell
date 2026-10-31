import Lean
open Lean
def main : IO Unit := do
  let project : System.FilePath := "/Users/ovm/.codex/worktrees/hook-deadline-baseline/eggshell"
  let root : System.FilePath := "/Users/ovm/.codex/experiments/eggshell/scope-token-study-20261028/shared-snapshot"
  let core := root / "project-metadata-core"
  IO.FS.writeFile (core / "tools/research/RecoverMetadataProfile.lean") (← IO.FS.readFile (project / "tools/research/RecoverMetadataProfile.lean"))
  let settings ← IO.ofExcept (Json.parse (← IO.FS.readFile (root / "metadata-profile-hook.settings.json")))
  let parent := root / "metadata-profile-hook-candidate-build"
  let settings := settings.setObjVal! "mainModule" (toJson "tools.research.RecoverMetadataProfile")
    |>.setObjVal! "output" (toJson (root / "metadata-profile-recovery-build").toString)
    |>.setObjVal! "parents" (toJson #[parent.toString])
    |>.setObjVal! "objectModules" (toJson (parent / "object-mapping.json").toString)
    |>.setObjVal! "baselineResponse" (toJson (parent / "runtime.rsp").toString)
    |>.setObjVal! "baselineMain" (toJson (parent / "tools_research_MetadataProfileHook.o").toString)
  IO.FS.writeFile (root / "metadata-profile-recovery.settings.json") settings.compress
  let guard ← IO.ofExcept (Json.parse (← IO.FS.readFile (root / "metadata-profile-build-final.guard.settings.json")))
  for (label,command) in [
    ("recovery-build",#["/usr/bin/env","LEAN_NUM_THREADS=1","/Users/ovm/.elan/toolchains/leanprover--lean4---v4.33.0/bin/lean",
      "-M1024","--run",(project / "tools/research/StudyBuildMain.lean").toString,(root / "metadata-profile-recovery.settings.json").toString]),
    ("recover",#["/usr/bin/env","LEAN_NUM_THREADS=1",(root / "metadata-profile-recovery-build/StudyMain").toString])] do
    IO.FS.writeFile (root / ("metadata-profile-" ++ label ++ ".guard.settings.json")) ((guard.setObjVal! "command" (toJson command))
      |>.setObjVal! "record" (toJson (project / "docs/candidates/metadata-profile" / (label ++ ".guard.json")).toString)).compress
