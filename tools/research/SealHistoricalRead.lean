import Lean.Data.Json.Parser
import Lean.Data.Json.FromToJson
open Lean
private def read (path : System.FilePath) : IO Json := do
  IO.ofExcept (Json.parse (← IO.FS.readFile path))
private def source (path : System.FilePath) : IO String := do
  let entries ← IO.ofExcept (← read path).getArr?
  IO.ofExcept entries[0]!.getStr?
private def sha (path : System.FilePath) : IO String := do
  let value ← IO.Process.output {cmd := "/usr/bin/shasum",args := #["-a","256",path.toString]}
  unless value.exitCode == 0 do throw (IO.userError value.stderr)
  let some digest := (value.stdout.splitOn " ").head? | throw (IO.userError "missing digest")
  return digest
def main : IO Unit := do
  let project : System.FilePath := "/Users/ovm/.codex/worktrees/hook-deadline-baseline/eggshell"
  let candidate : System.FilePath := "/Users/ovm/.codex/experiments/eggshell/scope-token-study-20261028/shared-snapshot"
  let output := project / "docs/candidates/historical-read-evidence"
  unless !(← output.pathExists) do throw (IO.userError "preserve existing historical evidence")
  let before ← read (project / "docs/candidates/shared-read-receipt/historical.json")
  let after ← read (candidate / "historical-read.json")
  unless before.getObjValD "source" == after.getObjValD "source" &&
      before.getObjValD "journal" == after.getObjValD "journal" &&
      after.getObjValD "matchedPersistedEvents" == toJson (51 : Nat) &&
      after.getObjValD "changedPersistedEvents" == toJson (0 : Nat) do
    throw (IO.userError "historical replay did not restore the same frozen events")
  for name in ["historical-read-run.guard.json","historical-evidence-run.guard.json"] do
    let guard ← read (candidate / name)
    unless guard.getObjValD "exitCode" == toJson (0 : Nat) &&
      guard.getObjValD "ownedPids" == toJson (#[] : Array Nat) do
      throw (IO.userError "historical test did not finish cleanly")
  IO.FS.createDirAll output
  let mut patch := ""
  let mut hashes := #[]
  for name in ["StoredReadEvidence","UsageCache","SynapseJournal"] do
    let current := candidate / "core/Eggshell" / (name ++ ".lean")
    let text ← IO.FS.readFile current
    unless text == (← source (candidate / "historical-read-build" / ("Eggshell_" ++ name ++ ".source"))) do
      throw (IO.userError "source changed after historical validation")
    let added := name == "StoredReadEvidence"
    let parent := candidate / ("historical-parent-" ++ name ++ ".lean")
    if !added then
      let previous ← source (candidate / "receipt-fixed-build" / ("Eggshell_" ++ name ++ ".source"))
      IO.FS.writeFile parent previous
    let result ← IO.Process.output {cmd := "/usr/bin/diff",args := #["-u",
      "--label",if added then "/dev/null" else "a/Eggshell/" ++ name ++ ".lean",
      "--label","b/Eggshell/" ++ name ++ ".lean",if added then "/dev/null" else parent.toString,current.toString]}
    unless result.exitCode == 1 do throw (IO.userError "missing expected candidate difference")
    patch := patch ++ result.stdout
    if !added then IO.FS.removeFile parent
    hashes := hashes.push (name,← sha current)
  IO.FS.writeFile (output / "candidate.patch") patch
  for (origin,target) in [
      ("historical-read.json","replay.json"),("historical-read-run.guard.json","replay.guard.json"),
      ("historical-evidence.json","negative-checks.json"),
      ("historical-evidence-run.guard.json","negative-checks.guard.json"),
      ("historical-evidence-build/tools_research_HistoricalReadEvidenceAudit-lean.stdout","proofs-and-boundaries.stdout")] do
    IO.FS.writeFile (output / target) (← IO.FS.readFile (candidate / origin))
  let mut attempts := #[]
  for entry in ← candidate.readDir do
    if ["historical-read-build-","historical-evidence-build-"].any (fun start => entry.fileName.startsWith start) &&
        entry.fileName.endsWith ".guard.json" then attempts := attempts.push (← read entry.path)
  IO.FS.writeFile (output / "build-attempts.json") (Json.arr attempts).pretty
  let baseline ← sha (candidate / "product-build/StudyMain")
  unless baseline == "56a52dd3ecd04fde65b67bfb91e91f0de1b6fe8f62feac153e2402e9398ee0a6" do
    throw (IO.userError "retained delivery runtime changed")
  let report := Json.mkObj [
    ("sources",toJson hashes),("retainedDeliveryRuntimeSha256",toJson baseline),
    ("replayRuntimeSha256",toJson (← sha (candidate / "historical-read-build/StudyMain"))),
    ("negativeAuditRuntimeSha256",toJson (← sha (candidate / "historical-evidence-build/StudyMain"))),
    ("frozenOriginalEventsMatched",toJson (51 : Nat)),("newActualHookCalls",toJson (0 : Nat)),
    ("newAnsweringModelCalls",toJson (0 : Nat)),("tokenImprovementMeasured",toJson false),
    ("deliveryImprovementMeasured",toJson false),("adopted",toJson false),("goalAchieved",toJson false)]
  IO.FS.writeFile (output / "decision.json") report.pretty
  IO.println report.compress
