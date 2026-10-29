import Lean.Data.Json.Parser
import Lean.Data.Json.FromToJson
open Lean

private def read (path : System.FilePath) : IO Json :=
  IO.FS.readFile path >>= fun text => IO.ofExcept (Json.parse text)

private def source (path : System.FilePath) : IO String := do
  let entries ← IO.ofExcept (← read path).getArr?
  IO.ofExcept entries[0]!.getStr?

private def sha (path : System.FilePath) : IO String := do
  let result ← IO.Process.output {cmd := "/usr/bin/shasum",args := #["-a","256",path.toString]}
  unless result.exitCode == 0 do throw (IO.userError result.stderr)
  let some digest := result.stdout.splitOn " " |>.head? | throw (IO.userError "missing file digest")
  return digest

def main : IO Unit := do
  let project : System.FilePath := "/Users/ovm/.codex/worktrees/hook-deadline-baseline/eggshell"
  let root : System.FilePath := "/Users/ovm/.codex/experiments/eggshell/scope-token-study-20261028/shared-snapshot"
  let output := project / "docs/candidates/source-knowledge"
  unless !(← output.pathExists) do throw (IO.userError "preserve previous source-knowledge evidence")
  let replay ← read (root / "source-knowledge.json")
  unless replay.getObjValD "matchedPersistedEvents" == toJson (51 : Nat) &&
      replay.getObjValD "changedPersistedEvents" == toJson (0 : Nat) &&
      replay.getObjValD "labelsWithoutCapturedIndex" == toJson (209 : Nat) &&
      replay.getObjValD "sourceAndRawJournalUnchanged" == toJson true do
    throw (IO.userError "source-only replay did not preserve the frozen original events")
  for name in ["source-knowledge-run.guard.json","cached-source-knowledge-run.guard.json",
      "cached-knowledge-contract-run.guard.json","source-knowledge-negative-run.guard.json",
      "prepared-usage-run.guard.json","checked-usage-hook-run.guard.json","native-closure-run.guard.json"] do
    let guard ← read (root / name)
    unless guard.getObjValD "exitCode" == toJson (0 : Nat) &&
        guard.getObjValD "ownedPids" == toJson (#[] : Array Nat) do
      throw (IO.userError "source-knowledge test did not finish cleanly")
  IO.FS.createDirAll output
  let mut patch := ""
  let mut hashes := #[]
  for (name,build) in [("StoredReadEvidence","source-knowledge"),("StoredReadLookup","cached-source-knowledge-pass"),
      ("UsageCache","prepared-usage"),("SynapseJournal","prepared-usage")] do
    let current := root / "core/Eggshell" / (name ++ ".lean")
    unless (← IO.FS.readFile current) == (← source (root / (build ++ "-build") /
        ("Eggshell_" ++ name ++ ".source"))) do
      throw (IO.userError "candidate source changed after replay validation")
    let added := name == "StoredReadLookup"
    let before := root / ("source-knowledge-parent-" ++ name ++ ".lean")
    if !added then
      IO.FS.writeFile before (← source (root / "historical-read-build" / ("Eggshell_" ++ name ++ ".source")))
    let difference ← IO.Process.output {cmd := "/usr/bin/diff",args := #["-u",
      "--label",if added then "/dev/null" else "a/Eggshell/" ++ name ++ ".lean",
      "--label","b/Eggshell/" ++ name ++ ".lean",if added then "/dev/null" else before.toString,current.toString]}
    unless difference.exitCode == 1 do throw (IO.userError "expected source-knowledge delta is missing")
    patch := patch ++ difference.stdout
    if !added then IO.FS.removeFile before
    hashes := hashes.push (name,← sha current)
  IO.FS.writeFile (output / "candidate.patch") patch
  for (origin,target) in [
      ("source-knowledge.json","replay.json"),("source-knowledge-run.guard.json","replay.guard.json"),
      ("cached-source-knowledge.json","cached-replay.json"),
      ("cached-source-knowledge-run.guard.json","cached-replay.guard.json"),
      ("cached-knowledge-contract/result.json","scope-and-recovery.json"),
      ("cached-knowledge-contract-run.guard.json","scope-and-recovery.guard.json"),
      ("source-knowledge-negative.json","negative-checks.json"),
      ("source-knowledge-negative-run.guard.json","negative-checks.guard.json"),
      ("source-knowledge-negative-build/tools_research_HistoricalReadEvidenceAudit-lean.stdout","proofs-and-boundaries.stdout"),
      ("usage-prepared-trial/warm/record.json","failed-warm.json"),
      ("usage-prepared-trial/warm/stderr","failed-warm.stderr"),
      ("usage-prepared-hook-run.guard.json","failed-warm.guard.json"),
      ("prepared-usage.json","usage-preparation.json"),("prepared-usage-run.guard.json","usage-preparation.guard.json"),
      ("source-knowledge-hook/warm/record.json","stale-native-warm.json"),
      ("prepared-usage-hook-run.guard.json","stale-native-warm.guard.json"),
      ("native-closure.json","native-closure.json"),("native-closure-run.guard.json","native-closure.guard.json"),
      ("checked-source-knowledge-hook/body.txt","body.txt"),("checked-source-knowledge-hook/audit.json","audit.json"),
      ("checked-source-knowledge-hook/warm/record.json","warm.json"),
      ("checked-source-knowledge-hook/warm/stdout","warm.stdout"),
      ("checked-source-knowledge-hook/UserPromptSubmit/record.json","hook.json"),
      ("checked-source-knowledge-hook/UserPromptSubmit/stdin","hook.stdin"),
      ("checked-source-knowledge-hook/UserPromptSubmit/stdout","hook.stdout"),
      ("checked-source-knowledge-hook/shutdown.json","shutdown.json"),
      ("checked-source-knowledge-hook/publisher-shutdown.json","publisher-shutdown.json"),
      ("checked-source-knowledge-hook/handoff.trace","handoff.trace"),
      ("checked-usage-hook-run.guard.json","hook.guard.json")] do
    IO.FS.writeFile (output / target) (← IO.FS.readFile (root / origin))
  let baseline ← sha (root / "product-build/StudyMain")
  unless baseline == "56a52dd3ecd04fde65b67bfb91e91f0de1b6fe8f62feac153e2402e9398ee0a6" do
    throw (IO.userError "retained delivery comparison runtime changed")
  let decision := Json.mkObj [("sources",toJson hashes),("retainedRuntimeSha256",toJson baseline),
    ("candidateRuntimeSha256",toJson (← sha (root / "dependency-checked-runtime-build/StudyMain"))),
    ("newAnsweringModelCalls",toJson (0 : Nat)),("tokenImprovementMeasured",toJson false),
    ("adopted",toJson false),("goalAchieved",toJson false)]
  IO.FS.writeFile (output / "decision.json") decision.pretty
  IO.println decision.compress
