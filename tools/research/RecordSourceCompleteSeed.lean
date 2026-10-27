import Lean.Data.Json.Parser
import Lean.Data.Json.FromToJson
open Lean
def main : IO Unit := do
  let root : System.FilePath := "/Users/ovm/.codex/experiments/eggshell/source-complete-seed-20261028"
  let target : System.FilePath := "/Users/ovm/.codex/worktrees/hook-deadline-baseline/eggshell/docs/candidates/source-complete-seed/pre-generation"
  unless !(← target.pathExists) && !(← (root / "seed-1.guard.json").pathExists) do
    throw (IO.userError "seal this evidence only before the one actual seed starts")
  for label in #["setup-install","setup-probe","budget-checks","native-gate"] do
    let report ← IO.ofExcept (Json.parse (← IO.FS.readFile (root / (label ++ ".guard.json"))))
    unless report.getObjValD "state" == toJson "finished" && report.getObjValD "exitCode" == toJson (0 : Nat) &&
        report.getObjValD "ownedPids" == toJson (#[] : Array Nat) do
      throw (IO.userError "finish all native prerequisites before sealing a model call")
  IO.FS.createDirAll target
  for name in #["frozen-native.json","admission-controller.json","seed-1.plan.json","seed-1.limits.json",
      "seed-1.settings.json","setup-install.guard.json","setup-probe.guard.json","budget-checks.guard.json",
      "native-gate.guard.json","hooks-trusted.json","native-gate-input.json",
      "budget-checks/result.json","native-gate/result.json","native-gate/recovery.json",
      "native-gate/source-ancestry.json","native-gate/shutdown.json","native-gate/publisher-shutdown.json",
      "native-gate/recall-audit.json","native-gate/recall-body.txt"] do
    IO.FS.createDirAll (target / name).parent.get!
    IO.FS.writeBinFile (target / name) (← IO.FS.readBinFile (root / name))
  for label in #["normal","limit","unrelated","time"] do
    for name in #["rpc/exchange.jsonl","budget-stop.json"] do
      let source := root / "budget-checks" / label / name
      if !(← source.pathExists) then continue
      let saved := target / "budget-checks" / label / name
      IO.FS.createDirAll saved.parent.get!
      IO.FS.writeBinFile saved (← IO.FS.readBinFile source)
  let models ← IO.ofExcept (Json.parse (← IO.FS.readFile (root / "discovery/models.json")) >>= (·.getObjValAs? (Array Json) "data"))
  let some model := models.find? (fun row => row.getObjValD "model" == toJson "gpt-5.6-luna") |
    throw (IO.userError "fixed model missing from actual model/list")
  IO.FS.writeFile (target / "advertised-model.json") model.pretty
  IO.FS.writeFile (target / "state.json") (Json.mkObj [("answeringModelCalls",toJson (0 : Nat)),
    ("seedAttemptsAllowed",toJson (1 : Nat)),("automaticAnswerRetry",toJson false),
    ("runtimeChangedFromVerifiedStorageCandidate",toJson false),
    ("productionAdoption",toJson false)]).compress
