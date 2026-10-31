import Lean
open Lean
private def ensure (ok : Bool) (message : String) : IO Unit := unless ok do throw (IO.userError message)

def main : IO Unit := do
  let project : System.FilePath := "/Users/ovm/.codex/worktrees/hook-deadline-baseline/eggshell"
  let root : System.FilePath := "/Users/ovm/.codex/experiments/eggshell/scope-token-study-20261028/shared-snapshot"
  let records := project / "docs/candidates/owner-palette"
  let build := root / "owner-palette-build"
  let closure ← IO.Process.output {
    cmd := "/Users/ovm/.elan/toolchains/leanprover--lean4---v4.33.0/bin/lean"
    args := #["-M3072","--run",(project / "tools/research/StudyBuildClosureAudit.lean").toString,
      "inspect",build.toString,(records / "native-closure.json").toString]}
  ensure (closure.exitCode == 0) ("palette native closure is inconsistent: " ++ closure.stderr)
  let result ← IO.Process.output {cmd := (build / "StudyMain").toString,env := #[("LEAN_NUM_THREADS",some "1")]}
  IO.FS.writeFile (records / "exit.json") (Json.mkObj [
    ("exitCode",toJson result.exitCode.toNat),("stdout",toJson result.stdout),("stderr",toJson result.stderr)]).pretty
  ensure (result.exitCode == 0) ("palette/fetch audit failed: " ++ result.stderr)
  IO.println result.stdout
