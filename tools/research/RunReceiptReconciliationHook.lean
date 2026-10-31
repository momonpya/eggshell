import Lean
open Lean
private def ensure (ok : Bool) (message : String) : IO Unit := unless ok do throw (IO.userError message)
private def read (path : System.FilePath) : IO Json := IO.FS.readFile path >>= fun text => IO.ofExcept (Json.parse text)

def main : IO Unit := do
  let project : System.FilePath := "/Users/ovm/.codex/worktrees/hook-deadline-baseline/eggshell"
  let root : System.FilePath := "/Users/ovm/.codex/experiments/eggshell/scope-token-study-20261028/shared-snapshot"
  let records := project / "docs/candidates/receipt-reconciliation"
  let helper := root / "receipt-reconciliation-hook-build"
  let runtime := root / "receipt-reconciliation-runtime-build"
  let actual : Array (String × String) ← IO.ofExcept
    (fromJson? (← read (helper / "tools_research_ReceiptReconciliationHook.dependencies")))
  let expected : Array (String × String) ← IO.ofExcept (fromJson? (← read (runtime / "Main.dependencies")))
  let expected := Std.HashMap.ofArray expected
  for (name,stamp) in actual do
    if let some saved := expected[name]? then ensure (saved == stamp) ("fixed runtime/helper disagree on " ++ name)
  for (name,directory) in [("runtime",runtime),("helper",helper)] do
    let result ← IO.Process.output {
      cmd := "/Users/ovm/.elan/toolchains/leanprover--lean4---v4.33.0/bin/lean"
      args := #["-M3072","--run",(project / "tools/research/StudyBuildClosureAudit.lean").toString,
        "inspect",directory.toString,(records / ("hook-" ++ name ++ "-native-closure.json")).toString]}
    ensure (result.exitCode == 0) "fixed replay native closure failed"
  let result ← IO.Process.output {cmd := (helper / "StudyMain").toString,env := #[("LEAN_NUM_THREADS",some "1")]}
  IO.FS.writeFile (records / "hook-exit.json") (Json.mkObj [
    ("exitCode",toJson result.exitCode.toNat),("stdout",toJson result.stdout),("stderr",toJson result.stderr)]).pretty
  ensure (result.exitCode == 0) ("fixed actual hook failed: " ++ result.stderr)
  IO.println result.stdout
