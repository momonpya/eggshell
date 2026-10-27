import Lean.Data.Json.Parser
import Lean.Data.Json.FromToJson
open Lean

private def read (path : System.FilePath) : IO Json :=
  IO.FS.readFile path >>= fun text => IO.ofExcept (Json.parse text)

def main : IO Unit := do
  let root := System.FilePath.mk "/Users/ovm/.codex/experiments/eggshell/verified-winner-20261027"
  let output := System.FilePath.mk
    "/Users/ovm/.codex/worktrees/hook-deadline-baseline/eggshell/docs/candidates/compact-native-context"
  let source := root / "checkout/Eggshell/Handoff.lean"
  let baselineSource := output.parent.get! / "verified-winner/final/contracts/Eggshell_Handoff.source"
  let original ← IO.ofExcept ((← read baselineSource).getArr?)
  let some first := original[0]? | throw (IO.userError "missing baseline source")
  let text ← IO.ofExcept first.getStr?
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
