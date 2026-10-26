import Lean.Data.Json.Parser
import Lean.Data.Json.FromToJson
open Lean

def main (args : List String) : IO Unit := do
  let [sourceName,toolchainName,outputName] := args |
    throw (IO.userError "Run SOURCE-ROOT LEAN-TOOLCHAIN NEW-OUTPUT")
  let source := System.FilePath.mk sourceName
  let toolchain := System.FilePath.mk toolchainName
  let output := System.FilePath.mk outputName
  unless source.isAbsolute && toolchain.isAbsolute && output.isAbsolute && !(← output.pathExists) do
    throw (IO.userError "absolute paths and unused output directory required")
  IO.FS.createDirAll (output / "lib/tools")
  let library := (output / "lib").toString ++ ":" ++ (toolchain / "lib/lean").toString
  let mut records := #[]
  for (label,arguments) in #[
      ("compile",#["-o",(output / "lib/tools/ContentCorrespondence.olean").toString,
        (source / "tools/ContentCorrespondence.lean").toString]),
      ("checks",#["--run",(source / "Checks.lean").toString]),
      ("axioms",#[(source / "Audit.lean").toString])] do
    let processArgs := #["--root=" ++ source.toString,"-j1","-M1024","-DwarningAsError=true"] ++ arguments
    let result ← IO.Process.output {
      cmd := (toolchain / "bin/lean").toString
      args := processArgs
      env := #[("LEAN_PATH",some library)] }
    IO.FS.writeFile (output / (label ++ ".stdout")) result.stdout
    IO.FS.writeFile (output / (label ++ ".stderr")) result.stderr
    unless result.exitCode == 0 do throw (IO.userError (result.stdout ++ result.stderr))
    records := records.push (Json.mkObj [("label",toJson label),("exitCode",toJson result.exitCode.toNat),
      ("command",toJson processArgs)])
  let mut sources := #[]
  for name in #["tools/ContentCorrespondence.lean","Checks.lean","Audit.lean","Run.lean"] do
    let path := source / name
    let digest ← IO.Process.output {cmd := "/usr/bin/shasum",args := #["-a","256",path.toString]}
    unless digest.exitCode == 0 do throw (IO.userError digest.stderr)
    sources := sources.push (Json.mkObj [("path",toJson path.toString),
      ("sha256",toJson (digest.stdout.take 64).copy)])
  let checks ← IO.ofExcept (Json.parse (← IO.FS.readFile (output / "checks.stdout")))
  let report := Json.mkObj [("sources",toJson sources),("steps",toJson records),("checks",checks),
    ("captureAdapterIntegrated",toJson false),("answeringModelCalls",toJson (0 : Nat)),
    ("productionAdoption",toJson false)]
  IO.FS.writeFile (output / "report.json") (report.pretty ++ "\n")
  IO.println report.compress
