import Lean.Data.Json.Parser
import Lean.Data.Json.FromToJson
open Lean
private def read (path : System.FilePath) : IO Json :=
  IO.FS.readFile path >>= fun text => IO.ofExcept (Json.parse text)
private def copy (source target : System.FilePath) : IO Unit := do
  IO.FS.createDirAll target.parent.get!
  IO.FS.writeBinFile target (← IO.FS.readBinFile source)

def main : IO Unit := do
  let root := System.FilePath.mk "/Users/ovm/.codex/experiments/eggshell/range-postings-20261027"
  let trial := root / "profile-range-hook"
  let project := System.FilePath.mk "/Users/ovm/.codex/worktrees/hook-deadline-baseline/eggshell"
  let output := project / "docs/candidates/range-postings/profile"
  unless !(← output.pathExists) do throw (IO.userError "preserve recorded CPU evidence")
  let guard ← read (root / "profile-range-hook.guard.json")
  unless guard.getObjValD "state" == toJson "finished" &&
      guard.getObjValD "ownedPids" == toJson (#[] : Array Nat) do
    throw (IO.userError "CPU trial is still live")
  let actual ← read (trial / "result.json")
  let reference := project / "docs/candidates/range-postings/final/hook"
  unless actual.getObjValD "runtimeSha256" == (← read (reference / "result.json")).getObjValD "runtimeSha256" &&
      (← IO.FS.readBinFile (trial / "body.txt")) == (← IO.FS.readBinFile (reference / "body.txt")) do
    throw (IO.userError "profiled runtime or delivered bytes differ")
  let sample ← IO.FS.readFile (trial / "search.sample.txt")
  let observations := [
    "l_Eggshell_Numerical_withDefaultKeeper___redArg",
    "l_SharedCoverage_Deferred_Sparse_choose_x3f",
    "l_SharedCoverage_Deferred_Sparse_best",
    "l_Eggshell_PreparedCueIndex_Prepared_many___redArg"].map fun symbol =>
      let count := (sample.splitOn "\n").foldl (fun total line =>
        let separator := " " ++ symbol ++ "  (in "
        if (line.splitOn separator).length == 1 then total else
          let before := (line.splitOn separator).head!
          total+((before.splitOn " ").filterMap String.toNat? |>.getLast?).getD 0) 0
      (symbol,count)
  IO.FS.createDirAll output
  for file in ["search.sample.txt","sample.stdout","sample.stderr","profile.json","handoff-trace.txt","result.json"] do
    copy (trial / file) (output / file)
  copy (trial / "hook/record.json") (output / "command-record.json")
  IO.FS.writeFile (output / "observation.json") (Json.mkObj [
    ("terminalGuard",guard),("sameRuntimeAndBodyAsUninstrumented",toJson true),
    ("functionInclusiveSamples",toJson observations),("samplingMs",toJson (5000 : Nat)),
    ("samplingDelayAfterFocusMs",toJson (4000 : Nat)),("wholeRuntimeCpuDistribution",toJson false),
    ("latencyAcceptance",toJson false),("answeringModelCalls",toJson (0 : Nat))]).pretty
