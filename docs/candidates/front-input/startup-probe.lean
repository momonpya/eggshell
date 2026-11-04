import Lean.Data.Json.FromToJson
open Lean
def main (args : List String) : IO Unit := do
  let [binary,folder] := args | throw (IO.userError "controlled native binary and fixture required")
  let root : System.FilePath := .mk folder
  let output := root/"startup.sample.txt"
  unless !(← output.pathExists) do throw (IO.userError "preserve earlier startup sample")
  let child ← IO.Process.spawn {
    cmd := binary
    args := #["front-input-key-checks",folder]
    stdin := .null,stdout := .null,stderr := .null }
  let sampled ← IO.Process.output {
    cmd := "/usr/bin/sample"
    args := #[toString child.pid,"1","1","-mayDie","-file",output.toString] }
  let code ← child.wait
  let report := Json.mkObj [("nativePid",toJson child.pid.toNat),("nativeExit",toJson code.toNat),
    ("sampleExit",toJson sampled.exitCode.toNat),("sampleExists",toJson (← output.pathExists)),
    ("answeringModelCalls",toJson (0 : Nat))]
  IO.FS.writeFile (root/"startup-sample.json") (report.pretty++"\n")
  IO.println report.compress
