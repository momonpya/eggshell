import Lean.Data.Json.FromToJson
open Lean

/-- One unchanged-runtime diagnostic. Sample the actual worker after focus;
no model, repeated warm, synthetic selector or product instrumentation. -/
def main (args : List String) : IO Unit := do
  let (candidate,trial,prepared,delay) ← match args with
    | [candidate,trial,prepared] => pure (candidate,trial,prepared,4000)
    | [candidate,trial,prepared,delay] =>
        let some delay := delay.toNat? | throw (IO.userError "numeric sampling delay required")
        unless delay ≤ 5000 do throw (IO.userError "sampling delay exceeds bounded interval")
        pure (candidate,trial,prepared,delay)
    | _ => throw (IO.userError "candidate, new trial, prepared checkpoint, optional sampling delay")
  let root := System.FilePath.mk candidate
  let output := System.FilePath.mk trial
  unless !(← output.pathExists) do throw (IO.userError "preserve prior profile")
  let child ← IO.Process.spawn {
    cmd := (root / "controller-build/StudyMain").toString,args := #[candidate,trial,prepared]
    env := #[("EGGSHELL_DATA_ROOT",some (output / "data").toString),("LEAN_NUM_THREADS",some "1")]
    stdout := .inherit,stderr := .inherit}
  let deadline := (← IO.monoMsNow)+60000
  let mut pid := none
  repeat
    if (← child.tryWait).isSome then break
    if (← IO.monoMsNow) ≥ deadline then throw (IO.userError "profile worker did not reach focus")
    let trace ← try IO.FS.readFile (output / "handoff-trace.txt") catch _ => pure ""
    if (trace.splitOn "source focus").length > 1 then
      let processes ← IO.Process.output {cmd := "/bin/ps",args := #["-axo","pid=,command="]}
      unless processes.exitCode == 0 do throw (IO.userError "cannot locate owned search worker")
      let expected := (output / "prefix/libexec/eggshell").toString ++ " codex-worker search"
      for row in processes.stdout.splitOn "\n" do
        if row.trimAscii.toString.endsWith expected then
          pid := ((row.trimAscii.toString.splitOn " ").head?.bind String.toNat?)
      if pid.isSome then break
    IO.sleep 100
  let some worker := pid | throw (IO.userError "search ended before actual CPU profile")
  IO.sleep delay.toUInt32
  let sampled ← IO.Process.output {
    cmd := "/usr/bin/sample",args := #[toString worker,"5","2","-file",(output / "search.sample.txt").toString]}
  IO.FS.writeFile (output / "sample.stdout") sampled.stdout
  IO.FS.writeFile (output / "sample.stderr") sampled.stderr
  let exit ← child.wait
  IO.FS.writeFile (output / "profile.json") (Json.mkObj [
    ("worker",toJson worker),("sampleExitCode",toJson sampled.exitCode.toNat),("trialExitCode",toJson exit.toNat),
    ("delayAfterFocusMs",toJson delay),("sampleSeconds",toJson (5 : Nat)),
    ("profiledTiming",toJson true),("modelCalls",toJson (0 : Nat))]).pretty
  unless exit == 0 && sampled.exitCode == 0 do throw (IO.userError "profile or actual hook failed")
