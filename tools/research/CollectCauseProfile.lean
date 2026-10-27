import Lean.Data.Json.Parser
import Lean.Data.Json.FromToJson
open Lean

private def read (path : System.FilePath) : IO Json :=
  IO.FS.readFile path >>= fun text => IO.ofExcept (Json.parse text)
private def copy (source target : System.FilePath) : IO Unit := do
  IO.FS.createDirAll target.parent.get!
  IO.FS.writeBinFile target (← IO.FS.readBinFile source)

def main : IO Unit := do
  let root := System.FilePath.mk "/Users/ovm/.codex/experiments/eggshell/evidence-cause-contract-20261027"
  let project := System.FilePath.mk "/Users/ovm/.codex/worktrees/hook-deadline-baseline/eggshell"
  let trial := root / "profile-causal-hook"
  let output := project / "docs/candidates/evidence-cause-contract/cpu-profile"
  unless !(← output.pathExists) do throw (IO.userError "preserve CPU evidence")
  let guard ← read (root / "profile-causal-hook.guard.json")
  unless guard.getObjValD "state" == toJson "finished" && guard.getObjValD "ownedPids" == toJson (#[] : Array Nat) do
    throw (IO.userError "sampled hook has not ended")
  let actual ← read (trial / "result.json")
  let reference := project / "docs/candidates/evidence-cause-contract/fixed-topic2/hook"
  unless actual.getObjValD "runtimeSha256" == (← read (reference / "result.json")).getObjValD "runtimeSha256" &&
      (← IO.FS.readBinFile (trial / "body.txt")) == (← IO.FS.readBinFile (reference / "body.txt")) do
    throw (IO.userError "profiled product or body changed")
  IO.FS.createDirAll output
  for file in ["worker.sample.txt","sample.stdout","sample.stderr","result.json"] do
    copy (root / "cpu-sampling" / file) (output / file)
  copy (trial / "handoff-trace.txt") (output / "handoff-trace.txt")
  copy (trial / "hook/record.json") (output / "command-record.json")
  IO.FS.writeFile (output / "observation.json") (Json.mkObj [
    ("instrumentedHook",actual),("terminalGuard",guard),
    ("sameRuntimeAndBodyAsUninstrumented",toJson true),
    ("latencyAcceptance",toJson false),("wholeRuntimeCpuDistribution",toJson false),
    ("samplingWindowMs",toJson (3000 : Nat)),("modelCalls",toJson (0 : Nat))]).pretty
