import Lean
open Lean
private def ensure (ok : Bool) (message : String) : IO Unit := unless ok do throw (IO.userError message)
private def read (path : System.FilePath) : IO Json := IO.FS.readFile path >>= fun text => IO.ofExcept (Json.parse text)
private def once (source before after : String) : IO String := do
  ensure ((source.splitOn before).length == 2) "receipt replay anchor changed"
  return source.replace before after

def main : IO Unit := do
  let project : System.FilePath := "/Users/ovm/.codex/worktrees/hook-deadline-baseline/eggshell"
  let root : System.FilePath := "/Users/ovm/.codex/experiments/eggshell/scope-token-study-20261028/shared-snapshot"
  let records := project / "docs/candidates/receipt-reconciliation"
  let audit ← read (records / "result.json")
  ensure (audit.getObjValD "sameActualLegacySurvivors" == toJson true &&
    audit.getObjValD "reconciledOriginalOwners" == toJson (38 : Nat)) "source receipt audit did not pass"
  let generated := project / "tools/research/ReceiptReconciliationHook.lean"
  ensure (!(← generated.pathExists)) "preserve previous receipt hook producer"
  let mut hook ← IO.FS.readFile (project / "tools/research/CheckedOriginalReplay.lean")
  hook ← once hook "docs/candidates/checked-original/replay" "docs/candidates/receipt-reconciliation/hook"
  hook ← once hook "checked-original-replay-trial" "receipt-reconciliation-hook-trial"
  hook ← once hook "checked-original-fixed-runtime-build/StudyMain" "receipt-reconciliation-runtime-build/StudyMain"
  hook ← once hook "checked-original-fixed-replay" "receipt-reconciliation-fresh"
  IO.FS.writeFile generated hook
  let mut runner ← IO.FS.readFile (project / "tools/research/RunCheckedOriginalReplay.lean")
  runner ← once runner "docs/candidates/checked-original" "docs/candidates/receipt-reconciliation"
  runner ← once runner "checked-original-replay-build" "receipt-reconciliation-hook-build"
  runner ← once runner "checked-original-fixed-runtime-build" "receipt-reconciliation-runtime-build"
  runner ← once runner "tools_research_CheckedOriginalReplay.dependencies" "tools_research_ReceiptReconciliationHook.dependencies"
  runner := runner.replace "replay-" "hook-"
  runner := runner.replace "replay-exit.json" "hook-exit.json"
  IO.FS.writeFile (project / "tools/research/RunReceiptReconciliationHook.lean") runner
  let original ← read (root / "receipt-reconciliation.settings.json")
  let previous := root / "receipt-reconciliation-build"
  let runtime := root / "receipt-reconciliation-runtime-build"
  let settings := original.setObjVal! "output" (toJson runtime.toString)
    |>.setObjVal! "objectModules" (toJson (previous / "object-mapping.json").toString)
    |>.setObjVal! "baselineResponse" (toJson (previous / "runtime.rsp").toString)
    |>.setObjVal! "baselineMain" (toJson (previous / "tools_research_ReceiptReconciliationAudit.o").toString)
    |>.setObjVal! "parents" (toJson #[previous.toString])
    |>.setObjVal! "mainModule" (toJson "Main")
  let helper := settings.setObjVal! "output" (toJson (root / "receipt-reconciliation-hook-build").toString)
    |>.setObjVal! "objectModules" (toJson (runtime / "object-mapping.json").toString)
    |>.setObjVal! "baselineResponse" (toJson (runtime / "runtime.rsp").toString)
    |>.setObjVal! "baselineMain" (toJson (runtime / "Main.o").toString)
    |>.setObjVal! "parents" (toJson #[runtime.toString])
    |>.setObjVal! "mainModule" (toJson "tools.research.ReceiptReconciliationHook")
  let guard ← read (root / "receipt-reconciliation-build.guard.settings.json")
  for (name,settings) in [("runtime",settings),("hook-build",helper)] do
    let file := root / ("receipt-reconciliation-" ++ name ++ ".settings.json")
    IO.FS.writeFile file settings.compress
    IO.FS.writeFile (root / ("receipt-reconciliation-" ++ name ++ ".guard.settings.json"))
      (guard.setObjVal! "record" (toJson (records / (name ++ ".guard.json")).toString)
        |>.setObjVal! "command" (toJson #["/usr/bin/env","LEAN_NUM_THREADS=1",
          "/Users/ovm/.elan/toolchains/leanprover--lean4---v4.33.0/bin/lean","-M1024","--run",
          (project / "tools/research/StudyBuildMain.lean").toString,file.toString])).compress
  IO.FS.writeFile (root / "receipt-reconciliation-hook-run.guard.settings.json")
    (guard.setObjVal! "record" (toJson (records / "hook-run.guard.json").toString)
      |>.setObjVal! "command" (toJson #["/usr/bin/env","LEAN_NUM_THREADS=1",
        "/Users/ovm/.elan/toolchains/leanprover--lean4---v4.33.0/bin/lean","-M3072","--run",
        (project / "tools/research/RunReceiptReconciliationHook.lean").toString])).compress
  IO.println "Prepared one normal-hook regression with the same frozen source, question and packet limit"
