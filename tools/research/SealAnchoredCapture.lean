import Lean.Data.Json.Parser
import Lean.Data.Json.FromToJson
open Lean

private def read (path : System.FilePath) : IO Json :=
  IO.FS.readFile path >>= fun text => IO.ofExcept (Json.parse text)
private def check (condition : Bool) (message : String) : IO Unit :=
  unless condition do throw (IO.userError message)
private def copy (source target : System.FilePath) : IO Unit := do
  IO.FS.createDirAll target.parent.get!
  IO.FS.writeBinFile target (← IO.FS.readBinFile source)

def main : IO Unit := do
  let root : System.FilePath := "/Users/ovm/.codex/experiments/eggshell/scope-token-study-20261028/shared-snapshot"
  let project : System.FilePath := "/Users/ovm/.codex/worktrees/hook-deadline-baseline/eggshell"
  let base : System.FilePath := "/Users/ovm/.codex/experiments/eggshell/bounded-source-replies-20261028/scope-hook-checkout"
  let output := project / "docs/candidates/anchored-capture"
  let trial := root / "anchored-prepared-hook"
  check (!(← (output / "comparison.json").pathExists)) "keep sealed evidence"
  let guard ← read (root / "anchored-hook.guard.json")
  check (guard.getObjValD "state" == toJson "finished" && guard.getObjValD "exitCode" == toJson (0 : Nat) &&
    guard.getObjValD "ownedPids" == toJson (#[] : Array Nat)) "trial has not finished successfully"
  let current ← read (trial / "audit.json")
  let prior ← read (project / "docs/candidates/aggregate-delta/hook/audit.json")
  let original ← read (root.parent.get! / "all-citations-original-audit.json")
  check (current.getObjValD "frozenEvidence" == prior.getObjValD "frozenEvidence" &&
    current.getObjValD "frozenEvidence" == original.getObjValD "frozenEvidence") "frozen alternatives changed"
  for name in ["sameSourceFacts","samePublishedPagePrefix"] do
    check (current.getObjValD name == toJson true) s!"{name} failed"
  let requirements ← IO.ofExcept ((current.getObjValD "requirements").getArr?)
  let previous ← IO.ofExcept ((prior.getObjValD "requirements").getArr?)
  let delivered := fun (row : Json) => row.getObjValD "bodyDelivered" == toJson true
  let names := fun (rows : Array Json) => rows.filter delivered |>.map (·.getObjValD "name")
  let beforeNames := names previous
  let afterNames := names requirements
  let gained := afterNames.filter (!beforeNames.contains ·)
  let lost := beforeNames.filter (!afterNames.contains ·)
  let timing ← read (trial / "UserPromptSubmit/record.json")
  let elapsed ← IO.ofExcept (timing.getObjValAs? Nat "elapsedMs")
  check (0 < elapsed && elapsed < 30000) "actual hook missed its deadline"
  let report := Json.mkObj [("sameFrozenEvidenceAndAlternatives",toJson true),
    ("sameOriginalFactsAndPagePrefix",toJson true),("parentDiagnostic",prior.getObjValD "requiredDelivery"),
    ("candidateDiagnostic",current.getObjValD "requiredDelivery"),("gained",toJson gained),("lost",toJson lost),
    ("elapsedMs",toJson elapsed),("sampledPeakRssKiB",guard.getObjValD "sampledPeakRssKiB"),
    ("mandatoryDenominatorRedefined",toJson false),("goalPercent",toJson (98 : Nat)),
    ("answeringModelCalls",toJson (0 : Nat)),("productionAdoption",toJson false),("goalAchieved",toJson false)]
  IO.FS.createDirAll output
  for name in ["audit.json","body.txt","cache-lifecycle.json","supplement-publication.json", "handoff.trace",
      "warm/record.json","warm/stdout","warm/stderr","UserPromptSubmit/record.json",
      "shutdown.json","publisher-shutdown.json"] do
    copy (trial / name) (output / "hook" / name)
  copy (root / "anchored-hook.guard.json") (output / "hook.guard.json")
  copy (root / "anchored-capture/prepared-fixtures/result.json") (output / "native-result.json")
  copy (root / "capture-prepared-native.guard.json") (output / "native.guard.json")
  copy (root / "capture-prepared-build/tools_research_AnchoredCaptureContract-lean.stdout") (output / "proofs.stdout")
  let buildConfig ← read (root / "product-build.guard-settings.json")
  let buildGuard ← IO.ofExcept (buildConfig.getObjValAs? String "record")
  copy (.mk buildGuard) (output / "build.guard.json")
  let refinement ← read (root / "anchored-capture/seed-refinement.json")
  IO.FS.writeFile (output / "source-refinement.json") (refinement.setObjVal! "supplements" Json.null).pretty
  let files := #["Eggshell/ContentCapture.lean","Eggshell/ContentMetadata.lean","Eggshell/SynapseBuild.lean",
    "Eggshell/CanonicalSource.lean","Eggshell/CanonicalSourceCache.lean","Eggshell/PublicationService.lean"]
  let parent := root / "anchored-capture/patch-parent"
  IO.FS.createDirAll parent
  for name in files do copy (base / name) (parent / name)
  let earlier ← IO.FS.readFile (project / "docs/candidates/published-snapshot/core.patch")
  let sections := earlier.splitOn "--- a/" |>.drop 1
  let patch := String.join (sections.filterMap fun part =>
    if files.any (fun name => part.startsWith (name ++ "\n")) then some ("--- a/" ++ part) else none)
  IO.FS.writeFile (parent / "prepared-parent.patch") patch
  let applied ← IO.Process.output {cmd := "/usr/bin/patch",args := #["--batch","-p1","-d",parent.toString,
    "-i",(parent / "prepared-parent.patch").toString]}
  check (applied.exitCode == 0) s!"cannot reconstruct selected parent modules: {applied.stdout} {applied.stderr}"
  copy (root / "anchored-capture/parent-ContentCapture.lean") (parent / "Eggshell/ContentCapture.lean")
  let mut changes := ""
  for name in files.push "Eggshell/ContentRuns.lean" do
    let before := if name == "Eggshell/ContentRuns.lean" then "/dev/null" else (parent / name).toString
    let difference ← IO.Process.output {cmd := "/usr/bin/diff",args := #["-u","-L","a/" ++ name,
      "-L","b/" ++ name,before,(root / "core" / name).toString]}
    check (difference.exitCode ≤ 1) s!"source diff failed: {difference.stderr}"
    changes := changes ++ difference.stdout
  IO.FS.writeFile (output / "core.patch") changes
  let hashes ← IO.Process.output {cmd := "/usr/bin/shasum",args := #["-a","256",
    (root / "product-build/StudyMain").toString,(root / "anchored-capture/parent-runtime").toString]}
  check (hashes.exitCode == 0) "runtime hashing failed"
  IO.FS.writeFile (output / "runtimes.sha256") hashes.stdout
  IO.FS.writeFile (output / "comparison.json") report.pretty
  IO.println report.compress
