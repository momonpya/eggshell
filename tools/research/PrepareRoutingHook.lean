import Lean.Data.Json.FromToJson
open Lean

def main : IO Unit := do
  let project : System.FilePath := "/Users/ovm/.codex/worktrees/hook-deadline-baseline/eggshell"
  let destination := project / "tools/research/RoutingScopeHookArm.lean"
  unless !(← destination.pathExists) do throw (IO.userError "preserve routing hook harness")
  let source ← IO.FS.readFile (project / "tools/research/CanonicalKeyHookArm.lean")
  let source := source.replace "canonical-keys" "routing-scope" |>.replace "canonical-key" "routing-scope"
  IO.FS.writeFile destination source
  IO.println "Reused the same frozen-source, two-session, source-only hook harness"
