import Lean.Data.Json.Parser
import Lean.Data.Json.FromToJson
open Lean
private def read (path : System.FilePath) : IO Json :=
  IO.FS.readFile path >>= fun text => IO.ofExcept (Json.parse text)
private def check (condition : Bool) (message : String) : IO Unit :=
  unless condition do throw (IO.userError message)
def main : IO Unit := do
  let root : System.FilePath := "/Users/ovm/.codex/experiments/eggshell/scope-token-study-20261028/shared-snapshot"
  let project : System.FilePath := "/Users/ovm/.codex/worktrees/hook-deadline-baseline/eggshell"
  let baseline := project / "docs/candidates/optional-inference"
  let output := project / "docs/candidates/aggregate-delta"
  let trial := root / "distinct-hook-trial"
  let prior ← read (baseline / "candidate-audit.json")
  let current ← read (trial / "audit.json")
  let original ← read "/Users/ovm/.codex/experiments/eggshell/scope-token-study-20261028/all-citations-original-audit.json"
  check (current.getObjValD "frozenEvidence" == prior.getObjValD "frozenEvidence" &&
    current.getObjValD "frozenEvidence" == original.getObjValD "frozenEvidence") "original evidence changed"
  check ((← IO.FS.readBinFile (baseline / "candidate-body.txt")) ==
    (← IO.FS.readBinFile (trial / "body.txt"))) "delivery body changed"
  for field in ["requiredDelivery","requirements"] do
    check (current.getObjValD field == prior.getObjValD field) s!"{field} changed"
  for field in ["sameSourceFacts","samePublishedPagePrefix"] do
    check (current.getObjValD field == toJson true) s!"{field} failed"
  let mut traces := #[]
  for entry in ← (trial / "data/receipts").readDir do
    let path := entry.path / "selection-plan.json"
    if ← path.pathExists then traces := traces.push (← read path)
  let some trace := traces.find? (fun row => ((row.getObjValD "data").getObjVal? "selectorInput").isOk) |
    throw (IO.userError "selector input missing")
  let expected ← read (baseline / "candidate-selector.json")
  check ((trace.getObjValD "data").getObjValD "selectorInput" ==
    (expected.getObjValD "data").getObjValD "selectorInput") "selector input changed"
  let guard ← read (root / "distinct-hook.guard.json")
  check (guard.getObjValD "state" == toJson "finished" && guard.getObjValD "exitCode" == toJson (0 : Nat) &&
    guard.getObjValD "ownedPids" == toJson (#[] : Array Nat)) "hook guard is not terminal"
  let timing ← read (trial / "UserPromptSubmit/record.json")
  let elapsed ← IO.ofExcept (timing.getObjValAs? Nat "elapsedMs")
  check (0 < elapsed && elapsed < 30000) "hook missed deadline"
  let report := Json.mkObj [("sameBodyBytes",toJson true),("sameSelectorInput",toJson true),
    ("sameFrozenEvidenceAndAlternatives",toJson true),("sameOriginalFactsAndPagePrefix",toJson true),
    ("elapsedMs",toJson elapsed),("citationDiagnostic",current.getObjValD "requiredDelivery"),
    ("currentGoalPercent",toJson (98 : Nat)),("allDiagnosticCitationsAreMandatory",toJson false),
    ("sampledPeakRssKiB",guard.getObjValD "sampledPeakRssKiB"),("answeringModelCalls",toJson (0 : Nat)),
    ("productionAdoption",toJson false),("goalAchieved",toJson false)]
  IO.FS.writeFile (output / "hook-comparison.json") report.pretty
  for name in ["audit.json","body.txt","warm/record.json","warm/stdout","warm/stderr",
      "UserPromptSubmit/record.json","shutdown.json","publisher-shutdown.json"] do
    let path := output / "hook" / name
    IO.FS.createDirAll path.parent.get!
    IO.FS.writeBinFile path (← IO.FS.readBinFile (trial / name))
  IO.FS.writeFile (output / "hook.guard.json") guard.pretty
  IO.println report.compress
