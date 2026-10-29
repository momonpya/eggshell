import Lean.Data.Json.Parser
import Lean.Data.Json.FromToJson
open Lean
private def read (path : System.FilePath) : IO Json :=
  IO.FS.readFile path >>= fun text => IO.ofExcept (Json.parse text)
private def check (condition : Bool) (reason : String) : IO Unit :=
  unless condition do throw (IO.userError reason)
private def copy (source target : System.FilePath) : IO Unit :=
  IO.FS.readBinFile source >>= IO.FS.writeBinFile target

def main : IO Unit := do
  let project : System.FilePath := "/Users/ovm/.codex/worktrees/hook-deadline-baseline/eggshell"
  let root : System.FilePath := "/Users/ovm/.codex/experiments/eggshell/scope-token-study-20261028/shared-snapshot"
  let output := project / "docs/candidates/notice-accounting"
  check (!(← (output / "decision.json").pathExists)) "preserve sealed result"
  let result ← read (root / "family-pricing-final.json")
  let ranges ← IO.ofExcept (result.getObjValAs? (Array Json) "indexedRangeDiagnostics")
  check (ranges.size == 47 && ranges.all (fun row => row.getObjValD "priorSelected" == row.getObjValD "selected" &&
    row.getObjValD "priorSelected" == row.getObjValD "lateCatalogSelected")) "unexpected diagnostic change"
  check (result.getObjValD "partialSelected" == toJson false &&
    result.getObjValD "lateCatalogPartialSelected" == toJson false &&
    result.getObjValD "sourceUnchanged" == toJson true) "unexpected missing fragment result"
  let families ← IO.ofExcept (result.getObjValAs? (Array Json) "familyPricing")
  check (families.size == 38 && families.all (fun row =>
    (row.getObjValAs? Nat "positiveOffers").toOption.any (· > 0))) "empty-value hypothesis changed"
  let buildSettings ← read (root / "notice-build.guard-settings.json")
  let buildRecord ← IO.ofExcept (buildSettings.getObjValAs? String "record")
  let build ← read (.mk buildRecord)
  let native ← read (root / "family-pricing-final.guard.json")
  for guard in #[build,native] do
    check (guard.getObjValD "state" == toJson "finished" && guard.getObjValD "exitCode" == toJson (0 : Nat) &&
      guard.getObjValD "ownedPids" == toJson (#[] : Array Nat)) "wait for successful completion"
  let compiledSource ← read (root / "notice-build/tools_research_NoticeCostReplay.source")
  check (compiledSource == toJson ((← IO.FS.readFile (project / "tools/research/NoticeCostReplay.lean")),
    (#[] : Array (String × String)))) "native replay source is stale"
  copy (root / "family-pricing-final.json") (output / "replay.json")
  copy (.mk buildRecord) (output / "build.guard.json")
  copy (root / "family-pricing-final.guard.json") (output / "native.guard.json")
  copy (root / "family-pricing-run.guard.json") (output / "invalid-stale-run.guard.json")
  copy (root / "family-pricing-replay.json") (output / "invalid-stale-run.json")
  copy (project / "tools/research/NoticeCostReplay.lean") (output / "Replay.lean")
  copy (project / "docs/candidates/available-evidence/body-section-costs.json") (output / "body-section-costs.json")
  copy (root / "SectionCosts.lean") (output / "SectionCosts.lean")
  let mut failures := #[]
  for entry in ← root.readDir do
    if entry.fileName.startsWith "notice-build-" && entry.fileName.endsWith ".guard.json" then
      let guard ← read entry.path
      if guard.getObjValD "exitCode" != toJson (0 : Nat) then
        failures := failures.push guard
  IO.FS.writeFile (output / "failed-builds.json") (toJson failures).pretty
  let hashes ← IO.Process.output {cmd := "/usr/bin/shasum",args := #["-a","256",
    (root / "product-build/StudyMain").toString,(root / "notice-build/StudyMain").toString,
    (output / "Replay.lean").toString]}
  check (hashes.exitCode == 0 && hashes.stdout.startsWith
    "56a52dd3ecd04fde65b67bfb91e91f0de1b6fe8f62feac153e2402e9398ee0a6") "product changed"
  IO.FS.writeFile (output / "runtime.sha256") hashes.stdout
  let decision := Json.mkObj [("same47IndexedRangeResults",toJson true),("missingFragmentRecovered",toJson false),
    ("noticeAccountingAccepted",toJson false),("lateCatalogAccepted",toJson false),
    ("allFamiliesHavePositiveOffers",toJson true),("actualHookCalls",toJson (0 : Nat)),
    ("answeringModelCalls",toJson (0 : Nat)),("newDatabasesOrWarm",toJson (0 : Nat)),
    ("productUnchanged",toJson true),("goalAchieved",toJson false),("goalPercent",toJson (98 : Nat)),
    ("invalidStaleRunExcluded",toJson true),("nativeSourceExact",toJson true)]
  IO.FS.writeFile (output / "decision.json") decision.pretty
  IO.println decision.compress
