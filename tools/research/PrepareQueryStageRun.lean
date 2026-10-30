import Lean.Data.Json.Parser
import Lean.Data.Json.FromToJson
open Lean

private def check (ok : Bool) (message : String) : IO Unit := unless ok do throw (IO.userError message)

def main : IO Unit := do
  let project : System.FilePath := "/Users/ovm/.codex/worktrees/hook-deadline-baseline/eggshell"
  let path := project / "tools/research/QueryStageHookArm.lean"
  check (!(← path.pathExists)) "preserve stage hook harness"
  let source ← IO.FS.readFile (project / "tools/research/RoutingScopeHookArm.lean")
  let source := source.replace "routing-scope" "query-stage"
    |>.replace "check ([\"baseline\",\"candidate\"].contains arm)" "check (arm == \"candidate\")"
    |>.replace "check ([\"0\",\"1\"].contains repetition)" "check (repetition == \"0\")"
  IO.FS.writeFile path source
  IO.println "Reused fixed R40 source, same real first hook and frozen original evidence; one diagnostic invocation only"
