import Lean.Data.Json.FromToJson
open Lean
def workspace : System.FilePath := "/Users/ovm/.codex/worktrees/hook-deadline-baseline/eggshell"
def lean := "/Users/ovm/.elan/toolchains/leanprover--lean4---v4.33.0/bin/lean"
def run (file : String) (args : Array String) : IO Unit := do
  let result ← IO.Process.output {cmd := lean,args := #["-j1","-M1536","--run",(workspace/file).toString]++args}
  unless result.exitCode == 0 do throw (IO.userError (result.stdout++result.stderr))
def main : IO Unit := do
  run "docs/candidates/shared-leases/records.lean" #["hosted-endpoint-build1","hosted-endpoint-build2",
    "hosted-endpoint-component1","hosted-endpoint-smoke1","hosted-endpoint-eighty1"]
  run "docs/candidates/shared-leases/records.lean" #["enrich"]
  run "docs/candidates/shared-leases/records.lean" #["verify","236"]
  let base : System.FilePath := "/Users/ovm/.codex/experiments/eggshell/scope-token-study-20261028/fixed-frame-study"
  IO.FS.writeFile (workspace/"docs/candidates/shared-leases/hosted-component.json")
    (← IO.FS.readFile (base/"hosted-endpoint-component1-result/report.json"))
  run "tools/research/CaptureConcurrentPatches.lean" #[]
