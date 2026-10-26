import Lean.Data.Json.Parser
import Lean.Data.Json.FromToJson
open Lean

def main (args : List String) : IO Unit := do
  let [sourceRoot,toolchain,output] := args |
    throw (IO.userError "Run SOURCE TOOLCHAIN UNUSED-OUTPUT")
  let source := System.FilePath.mk sourceRoot
  let target := System.FilePath.mk output
  unless source.isAbsolute && target.isAbsolute && !(← target.pathExists) do
    throw (IO.userError "absolute source and unused output required")
  IO.FS.createDirAll (target / "lib/tools")
  let library := (target / "lib").toString ++ ":" ++ toolchain ++ "/lib/lean"
  let mut records := #[]
  for (label,arguments) in #[
      ("compile",#["-o",(target / "lib/tools/LiteralSearch.olean").toString,(source / "tools/LiteralSearch.lean").toString]),
      ("checks",#["--run",(source / "Checks.lean").toString]),
      ("audit",#[(source / "Audit.lean").toString])] do
    let arguments := #["--root=" ++ source.toString,"-j1","-M1024","-DwarningAsError=true"] ++ arguments
    let result ← IO.Process.output {
      cmd := toolchain ++ "/bin/lean"
      args := arguments
      env := #[("LEAN_PATH",some library)] }
    IO.FS.writeFile (target / (label ++ ".stdout")) result.stdout
    IO.FS.writeFile (target / (label ++ ".stderr")) result.stderr
    records := records.push (Json.mkObj [("label",toJson label),("arguments",toJson arguments),
      ("exitCode",toJson result.exitCode.toNat)])
    IO.FS.writeFile (target / "commands.json") (toJson records).pretty
    unless result.exitCode == 0 do throw (IO.userError (result.stdout ++ result.stderr))
  IO.println (← IO.FS.readFile (target / "checks.stdout"))
  IO.println (← IO.FS.readFile (target / "audit.stdout"))
