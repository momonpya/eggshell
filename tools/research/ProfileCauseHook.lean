import Lean.Data.Json.Parser
import Lean.Data.Json.FromToJson
open Lean

private def read (path : System.FilePath) : IO Json :=
  IO.FS.readFile path >>= fun text => IO.ofExcept (Json.parse text)

/-- One CPU observation after the immutable candidate domain is recorded.
The sampled hook is not a latency acceptance trial or an answering trial. -/
def main : IO Unit := do
  let root := System.FilePath.mk "/Users/ovm/.codex/experiments/eggshell/evidence-cause-contract-20261027"
  let trial := root / "profile-causal-hook"
  let output := root / "cpu-sampling"
  unless !(← trial.pathExists) && !(← output.pathExists) do throw (IO.userError "preserve previous CPU trial")
  IO.FS.createDir output
  let child ← IO.Process.spawn {
    cmd := "/Users/ovm/.codex/experiments/eggshell/study-services-20261026/assessed-controller"
    args := #["guard",(root / "profile-causal-hook-settings.json").toString]
    stdout := .piped,stderr := .piped}
  let deadline := (← IO.monoMsNow)+30000
  let mut pid := none
  repeat
    if (← child.tryWait).isSome || (← IO.monoMsNow) ≥ deadline then break
    let receipts := trial / "data/receipts"
    if ← receipts.pathExists then
      for entry in ← receipts.readDir do
        let path := entry.path / "delivery-domain.json"
        if !(← path.pathExists) then continue
        let record ← try pure (some (← read path)) catch _ => pure none
        if let some record := record then
          pid := (record.getObjValAs? Nat "pid").toOption
          break
    if pid.isSome then break
    IO.sleep 25
  let sampled ← if let some processId := pid then do
    let state ← read (root / "profile-causal-hook.guard.json")
    let active ← IO.ofExcept (state.getObjValAs? (Array Nat) "ownedPids")
    unless active.contains processId do throw (IO.userError "receipt PID is not owned by this live guard")
    let process ← IO.Process.output {cmd := "/bin/ps",args := #["-p",toString processId,"-o","command="]}
    unless process.exitCode == 0 && (process.stdout.splitOn trial.toString).length > 1 do
      throw (IO.userError "receipt PID is not the current candidate process")
    let sample ← IO.Process.output {cmd := "/usr/bin/sample",args := #[toString processId,"3","1","-file",(output / "worker.sample.txt").toString]}
    IO.FS.writeFile (output / "sample.stderr") sample.stderr
    IO.FS.writeFile (output / "sample.stdout") sample.stdout
    pure (some (processId,sample.exitCode.toNat))
  else pure none
  let exitCode ← child.wait
  IO.FS.writeFile (output / "guard.stdout") (← child.stdout.readToEnd)
  IO.FS.writeFile (output / "guard.stderr") (← child.stderr.readToEnd)
  let terminal ← read (root / "profile-causal-hook.guard.json")
  unless terminal.getObjValD "state" == toJson "finished" &&
      terminal.getObjValD "ownedPids" == toJson (#[] : Array Nat) do
    throw (IO.userError "profiled guard did not terminate cleanly")
  IO.FS.writeFile (output / "result.json") (Json.mkObj [
    ("sampledPidAndExitCode",toJson sampled),("guardExitCode",toJson exitCode.toNat),
    ("samplingMs",toJson (3000 : Nat)),("phase",toJson "after-delivery-domain"),
    ("latencyAcceptance",toJson false),("answeringModelCalls",toJson (0 : Nat))]).pretty
  unless exitCode == 0 && sampled.any (fun row => row.2 == 0) do throw (IO.userError "CPU observation failed")
