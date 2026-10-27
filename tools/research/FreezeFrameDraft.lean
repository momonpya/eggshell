import Lean.Data.Json.Parser
import Lean.Data.Json.FromToJson
open Lean

private def read (path : System.FilePath) : IO Json :=
  IO.FS.readFile path >>= fun text => IO.ofExcept (Json.parse text)

def main (args : List String) : IO Unit := do
  let root := System.FilePath.mk "/Users/ovm/.codex/experiments/eggshell/verified-winner-20261027"
  let baseline := System.FilePath.mk
    "/Users/ovm/.codex/worktrees/hook-deadline-baseline/eggshell/docs/candidates/compact-native-context"
  let roles := args == ["reject-roles"] || args == ["verify-roles"]
  let output := if roles then baseline.parent.get! / "current-focus-credit" else baseline
  let measured := if roles then "candidate" else "compact"
  let source := root / "checkout/Eggshell/Handoff.lean"
  let baselineSource := baseline.parent.get! / "verified-winner/final/contracts/Eggshell_Handoff.source"
  let original ← IO.ofExcept ((← read baselineSource).getArr?)
  let some first := original[0]? | throw (IO.userError "missing baseline source")
  let text ← IO.ofExcept first.getStr?
  if args == ["verify"] || args == ["verify-roles"] then
    let artifacts ← IO.Process.output {
      cmd := "/Users/ovm/.codex/experiments/eggshell/study-services-20261026/assessed-controller"
      args := #["artifacts",(root / "product-build/StudyMain").toString,
        (root / "controller-build/StudyMain").toString,source.toString]}
    unless artifacts.exitCode == 0 do throw (IO.userError artifacts.stderr)
    IO.FS.createDirAll (output / "restored")
    IO.FS.writeFile (output / "restored/digests.json") artifacts.stdout
    unless (← IO.ofExcept (Json.parse artifacts.stdout)) == (← read (baseline / "baseline/digests.json")) &&
        (← read (root / "product-build/Eggshell_Handoff.source")) == (← read baselineSource) &&
        (← IO.FS.readFile source) == text do
      throw (IO.userError "baseline differs after rebuild; actual delivery replay is required")
    let buildGuard ← read (root / (if roles then "compile-baseline-after-roles.guard.json" else "compile-baseline-after-frame.guard.json"))
    unless buildGuard.getObjValD "state" == toJson "finished" &&
        buildGuard.getObjValD "exitCode" == toJson (0 : Nat) &&
        buildGuard.getObjValD "ownedPids" == toJson (#[] : Array Nat) do
      throw (IO.userError "baseline build is not terminal and successful")
    IO.FS.writeFile (output / "restored/build.guard.json") buildGuard.pretty
    let result := (← read (output / "outcome.json"))
      |>.setObjVal! "nativeBaselineRestorationVerified" (toJson true)
      |>.setObjVal! "sameBaselineRuntimeHarnessAndSourceSha256" (toJson true)
    IO.FS.writeFile (output / "outcome.json") result.pretty
    return
  if args == ["reject"] || args == ["reject-roles"] then
    let summary ← read (output / measured / "summary.json")
    let comparisons ← IO.ofExcept (summary.getObjValAs? (Array Json) "comparisons")
    unless comparisons.size == 3 && comparisons.all (fun row =>
        row.getObjValD "sameFrozenRequirementsSourceAndIndexes" == toJson true) do
      throw (IO.userError "capture all fixed-source comparisons before rejecting")
    unless !(← (output / "outcome.json").pathExists) do throw (IO.userError "preserve the rejection record")
    let temporary := root / "baseline-context-source.tmp"
    unless !(← temporary.pathExists) do throw (IO.userError "unexpected temporary source")
    IO.FS.writeFile temporary text
    let patch ← IO.Process.output {
      cmd := "/usr/bin/diff"
      args := #["-u","--label","a/Eggshell/Handoff.lean","--label","b/Eggshell/Handoff.lean",
        temporary.toString,source.toString]}
    unless patch.exitCode == 1 do throw (IO.userError "expected the measured rendering change")
    IO.FS.writeFile (output / "measured.patch") patch.stdout
    IO.FS.removeFile temporary
    let records := if roles then ["compile-current-focus-credit.guard.json",
        "current-focus-proofs.guard.json","current-focus-proofs.stdout","current-focus-proofs.stderr"] else
      ["compile-compact-native-context-available.guard.json",
        "compile-compact-native-context-proved.guard.json","compact-context-proofs.guard.json",
        "compact-context-proofs.stdout","compact-context-proofs.stderr",
        "compact-context-proofs-expanded.guard.json","compact-context-proofs-expanded.stdout",
        "compact-context-proofs-expanded.stderr"]
    for name in records do
      IO.FS.writeBinFile (output / measured / name) (← IO.FS.readBinFile (root / name))
    IO.FS.writeFile source text
    unless (← IO.FS.readFile source) == text do throw (IO.userError "source restoration failed")
    IO.FS.writeFile (output / "outcome.json") (Json.mkObj [
      ("state",toJson (if roles then "rejected-no-delivery-improvement" else "rejected-delivery-regression")),
      ("comparisons",toJson comparisons),
      ("sourceRestored",toJson true),("nativeBaselineRestorationVerified",toJson false),
      ("candidateNativeBuildPassed",toJson true),
      (if roles then "focusedCueRolesProofsChecked" else "displayPreservationProofsChecked",toJson true),
      ("candidateTokenImprovementMeasured",toJson false),("answeringModelCalls",toJson (0 : Nat)),
      ("newSeedStudy",toJson false),("adopted",toJson false)]).pretty
    return
  unless args.isEmpty do throw (IO.userError "no arguments | reject | verify | reject-roles | verify-roles")
  let guard ← read (root / "compile-compact-native-context.guard.json")
  unless guard.getObjValD "state" == toJson "finished" &&
      guard.getObjValD "ownedPids" == toJson (#[] : Array Nat) &&
      guard.getObjValD "reason" == toJson "disk-space" do
    throw (IO.userError "capture the terminal interrupted build")
  let buildSource ← read (root / "product-build/Eggshell_Handoff.source")
  unless buildSource == (← read baselineSource) do
    throw (IO.userError "Handoff was compiled; this is not an unbuilt draft")
  let unchanged ← IO.Process.output {
    cmd := "/Users/ovm/.codex/experiments/eggshell/study-services-20261026/assessed-controller"
    args := #["artifacts",(root / "product-build/StudyMain").toString,
      (root / "controller-build/StudyMain").toString,source.toString]}
  unless unchanged.exitCode == 0 do throw (IO.userError unchanged.stderr)
  let before ← IO.ofExcept (Json.parse unchanged.stdout >>= Json.getArr?)
  let expected ← IO.ofExcept ((← read (output / "baseline/digests.json")).getArr?)
  unless before[0]! == expected[0]! && before[1]! == expected[1]! do
    throw (IO.userError "baseline runtime or fixed harness changed")
  let temporary := root / "baseline-context-source.tmp"
  unless !(← temporary.pathExists) do throw (IO.userError "unexpected temporary source")
  IO.FS.writeFile temporary text
  let patch ← IO.Process.output {
    cmd := "/usr/bin/diff"
    args := #["-u","--label","a/Eggshell/Handoff.lean","--label","b/Eggshell/Handoff.lean",
      temporary.toString,source.toString]}
  unless patch.exitCode == 1 do throw (IO.userError "expected a single prospective display change")
  IO.FS.writeFile (output / "draft.patch") patch.stdout
  IO.FS.writeFile (output / "draft-digests.json") unchanged.stdout
  IO.FS.writeFile (output / "interrupted-build.guard.json") guard.pretty
  IO.FS.removeFile temporary
  IO.FS.writeFile source text
  unless (← IO.FS.readFile source) == text do throw (IO.userError "source restoration failed")
  IO.FS.writeFile (output / "draft-status.json") (Json.mkObj [
    ("state",toJson "unbuilt-isolated-draft"),("reason",toJson "disk-space"),
    ("baselineRuntimeAndHarnessUnchanged",toJson true),("baselineSourceRestored",toJson true),
    ("candidateNativeBuildPassed",toJson false),("candidateProofsChecked",toJson false),
    ("candidateHookRan",toJson false),("candidateTokenImprovementMeasured",toJson false),
    ("answeringModelCalls",toJson (0 : Nat)),("adopted",toJson false)]).pretty
