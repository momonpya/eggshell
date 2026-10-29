import Lean.Data.Json.Parser
import Lean.Data.Json.FromToJson
open Lean

private def read (path : System.FilePath) : IO Json := do
  IO.ofExcept (Json.parse (← IO.FS.readFile path))
private def sha (path : System.FilePath) : IO String := do
  let result ← IO.Process.output {cmd := "/usr/bin/shasum",args := #["-a","256",path.toString]}
  unless result.exitCode == 0 do throw (IO.userError result.stderr)
  let some value := (result.stdout.splitOn " ").head? | throw (IO.userError "missing digest")
  return value
private def compiledSource (path : System.FilePath) : IO String := do
  let value ← read path
  let entries ← IO.ofExcept value.getArr?
  IO.ofExcept entries[0]!.getStr?

def main : IO Unit := do
  let project : System.FilePath := "/Users/ovm/.codex/worktrees/hook-deadline-baseline/eggshell"
  let study : System.FilePath := "/Users/ovm/.codex/experiments/eggshell/scope-token-study-20261028"
  let candidate := study / "shared-snapshot"
  let destination := project / "docs/candidates/shared-read-receipt"
  unless !(← destination.pathExists) do throw (IO.userError "evidence already exists")
  for name in ["receipt-fixed-run.guard.json","historical-usage-original-run.guard.json"] do
    let value ← read (candidate / name)
    unless value.getObjValD "exitCode" == toJson (0 : Nat) &&
      value.getObjValD "ownedPids" == toJson (#[] : Array Nat) do
      throw (IO.userError "audit has not completed cleanly")
  let body := project / "docs/candidates/anchored-capture/hook/body.txt"
  unless (← sha body) == "098a283dac9194d1c83196fba0ad8c4f601cfca6bb7b37bf8cbc16e88d11d481" do
    throw (IO.userError "retained actual delivery changed")
  IO.FS.createDirAll destination
  let mut patch := ""
  let mut sources := #[]
  for (name,build,added) in [
      ("SharedReadReceipt","project-query",true),("UsageCache","receipt-fixed",true),
      ("SynapseJournal","receipt-fixed",false),("SynapseRecommend","receipt-contract",false)] do
    let source := candidate / "core/Eggshell" / (name ++ ".lean")
    let text ← IO.FS.readFile source
    unless (← compiledSource (candidate / (build ++ "-build") / ("Eggshell_" ++ name ++ ".source"))) == text do
      throw (IO.userError "candidate changed after its successful build")
    let parent := candidate / ("receipt-parent-" ++ name ++ ".lean")
    if !added then
      IO.FS.writeFile parent (← compiledSource (candidate / "product-build" / ("Eggshell_" ++ name ++ ".source")))
    let result ← IO.Process.output {cmd := "/usr/bin/diff",args := #["-u",
      "--label",if added then "/dev/null" else "a/Eggshell/" ++ name ++ ".lean",
      "--label","b/Eggshell/" ++ name ++ ".lean",if added then "/dev/null" else parent.toString,source.toString]}
    unless result.exitCode == 1 do throw (IO.userError "expected isolated candidate differences")
    patch := patch ++ result.stdout
    if !added then IO.FS.removeFile parent
    sources := sources.push (name,← sha source)
  IO.FS.writeFile (destination / "candidate.patch") patch
  for (origin,target) in [
      ("receipt-fixed-run.guard.json","native.guard.json"),
      ("shared-receipt-fixed/result.json","result.json"),
      ("historical-usage-original.json","historical.json"),
      ("historical-usage-original-run.guard.json","historical.guard.json"),
      ("historical-usage.json","invalid-source-only-index-audit.json"),
      ("historical-usage-run.guard.json","invalid-source-only-index-audit.guard.json"),
      ("receipt-fixed-build/tools_research_SharedReadReceiptAudit-lean.stdout","proof-axioms.stdout"),
      ("receipt-contract-build/tools_research_SharedReadReceiptContract-lean.stdout","contract.stdout")] do
    IO.FS.writeFile (destination / target) (← IO.FS.readFile (candidate / origin))
  let mut attempts := #[]
  for entry in ← candidate.readDir do
    if ["receipt-fixed-build-","receipt-contract-build-","historical-usage-build-"].any (fun start => entry.fileName.startsWith start) &&
        entry.fileName.endsWith ".guard.json" then attempts := attempts.push (← read entry.path)
  IO.FS.writeFile (destination / "build-attempts.json") (Json.arr attempts).pretty
  let baseline ← sha (candidate / "product-build/StudyMain")
  unless baseline == "56a52dd3ecd04fde65b67bfb91e91f0de1b6fe8f62feac153e2402e9398ee0a6" do
    throw (IO.userError "retained delivery runtime changed")
  let report := Json.mkObj [
    ("candidateSources",toJson sources),("auditRuntimeSha256",toJson (← sha (candidate / "receipt-fixed-build/StudyMain"))),
    ("historicalAuditRuntimeSha256",toJson (← sha (candidate / "historical-usage-build/StudyMain"))),
    ("retainedDeliveryRuntimeSha256",toJson baseline),("originalSourceAndRawJournalUnchanged",toJson true),
    ("sourceOnlyIndexAuditExcluded",toJson "It used the copied source snapshot path for DB-owned indexes; use historical.json with the original owning DB and an exactly equal frozen head."),
    ("newActualHookCalls",toJson (0 : Nat)),("newAnsweringModelCalls",toJson (0 : Nat)),
    ("deliveryImprovementMeasured",toJson false),("tokenImprovementMeasured",toJson false),
    ("adopted",toJson false),("goalAchieved",toJson false)]
  IO.FS.writeFile (destination / "decision.json") report.pretty
  IO.println report.compress
