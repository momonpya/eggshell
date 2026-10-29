import Lean.Data.Json.Parser
import Lean.Data.Json.FromToJson
open Lean

private def read (path : System.FilePath) : IO Json :=
  IO.FS.readFile path >>= fun value => IO.ofExcept (Json.parse value)
private def check (value : Bool) (reason : String) : IO Unit :=
  unless value do throw (IO.userError reason)
private def copy (source target : System.FilePath) : IO Unit :=
  IO.FS.readBinFile source >>= IO.FS.writeBinFile target

def main : IO Unit := do
  let root : System.FilePath := "/Users/ovm/.codex/experiments/eggshell/scope-token-study-20261028/shared-snapshot"
  let project : System.FilePath := "/Users/ovm/.codex/worktrees/hook-deadline-baseline/eggshell"
  let output := project / "docs/candidates/available-evidence"
  check (!(← (output / "sealed.json").pathExists)) "preserve sealed evidence"
  let audit ← read (root / "available-evidence-audit/report.json")
  let before ← read (root / "available-evidence-audit/before-body.json")
  let cause ← read (root / "cause-audit-with-offers.json")
  let old := audit.getObjValD "requiredDelivery"
  let current := audit.getObjValD "availableDelivery"
  check (audit.getObjValD "availableEvidence" == before &&
      old.getObjValD "eligible" == toJson (2 : Nat) && old.getObjValD "delivered" == toJson (2 : Nat) &&
      current.getObjValD "eligible" == toJson (3 : Nat) && current.getObjValD "delivered" == toJson (2 : Nat) &&
      current.getObjValD "targetMet" == toJson false) "unexpected actual body audit"
  check (audit.getObjValD "source" == cause.getObjValD "source" &&
      cause.getObjValD "sourceUnchanged" == toJson true && cause.getObjValD "changedCandidate" == toJson false)
    "causal replay changed the source or candidate"
  let pause ← read (root.parent.get! / "measurement-paused.json")
  check (pause.getObjValD "additionalAnsweringModelsAllowed" == toJson false) "answering models must remain paused"
  for (name,target) in #[("available-run.guard.json","native.guard.json"),
      ("cause-run-3.guard.json","cause.guard.json")] do
    let guard ← read (root / name)
    check (guard.getObjValD "state" == toJson "finished" && guard.getObjValD "exitCode" == toJson (0 : Nat) &&
      guard.getObjValD "ownedPids" == toJson (#[] : Array Nat)) "wait for a successful terminal guard"
    copy (root / name) (output / target)
  for name in ["fixtures.json","before-body.json","report.json"] do
    copy (root / "available-evidence-audit" / name) (output / name)
  copy (root / "cause-audit-with-offers.json") (output / "selection-causes.json")
  copy (root / "available-build/tools_research_AvailableDeliveryAudit-lean.stdout") (output / "proofs.stdout")
  for (label,target) in #[("available","build.guard.json"),("cause","cause-build.guard.json")] do
    let settings ← read (root / (label ++ "-build.guard-settings.json"))
    let record ← IO.ofExcept (settings.getObjValAs? String "record")
    let guard ← read (.mk record)
    check (guard.getObjValD "state" == toJson "finished" && guard.getObjValD "exitCode" == toJson (0 : Nat))
      "build is not complete"
    copy (.mk record) (output / target)
  let hashes ← IO.Process.output {cmd := "/usr/bin/shasum",args := #["-a","256",
    (root / "product-build/StudyMain").toString,(root / "available-build/StudyMain").toString,
    (root / "cause-build/StudyMain").toString]}
  check (hashes.exitCode == 0 && hashes.stdout.startsWith
    "56a52dd3ecd04fde65b67bfb91e91f0de1b6fe8f62feac153e2402e9398ee0a6") "candidate runtime changed"
  IO.FS.writeFile (output / "runtime.sha256") hashes.stdout
  let record := Json.mkObj [("retainedActualBody",toJson true),("newHookCalls",toJson (0 : Nat)),
    ("answeringModelCalls",toJson (0 : Nat)),("newDatabaseOrWarmCalls",toJson (0 : Nat)),
    ("sourceUnchanged",toJson true),("candidateUnchanged",toJson true),("productionAdoption",toJson false),
    ("goalAchieved",toJson false),("legacy",old),("allDbBacked",current)]
  IO.FS.writeFile (output / "sealed.json") record.pretty
  IO.println record.compress
