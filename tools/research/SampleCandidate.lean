import Lean.Data.Json.FromToJson
open Lean

/-- One bounded native CPU sample, scoped to the selected experimental binary.
This is diagnostic overhead and cannot establish a hook latency result. -/
def main (args : List String) : IO Unit := do
  let [rootName] := args | throw (IO.userError "SampleCandidate ROOT")
  let root := System.FilePath.mk rootName
  let destination := root / "cpu-sample.txt"
  unless root.isAbsolute && !(← destination.pathExists) do
    throw (IO.userError "new absolute profile destination required")
  let program := (root / "prefix/libexec/eggshell").toString
  let processes ← IO.Process.output {cmd := "/bin/ps",args := #["-ww","-axo","pid=,pcpu=,comm="]}
  unless processes.exitCode == 0 do throw (IO.userError "cannot inspect candidate CPU")
  let mut selected : Option (Nat × Nat) := none
  for line in processes.stdout.splitOn "\n" do
    let fields := line.splitOn " " |>.filter (!·.isEmpty)
    let pid :: cpu :: rest := fields | continue
    if " ".intercalate rest != program then continue
    let some pid := pid.toNat? | continue
    let some cpu := (cpu.replace "." "").toNat? | continue
    if selected.all (·.2 < cpu) then selected := some (pid,cpu)
  let some (pid,cpu) := selected | throw (IO.userError "no scoped candidate process to sample")
  let sampled ← IO.Process.output {cmd := "/usr/bin/sample",args := #[toString pid,"1","1","-file",destination.toString]}
  IO.FS.writeFile (root / "cpu-sample-process.json") (Json.mkObj [
    ("pid",toJson pid),("psCpuTenthsPercent",toJson cpu),
    ("sampleExitCode",toJson sampled.exitCode.toNat),("diagnosticOnly",toJson true),
    ("latencyAcceptance",toJson false),("answeringModelCalls",toJson (0 : Nat))]).pretty
  unless sampled.exitCode == 0 do throw (IO.userError sampled.stderr)
  IO.println (Json.mkObj [("pid",toJson pid),("sample",toJson destination.toString)]).compress
