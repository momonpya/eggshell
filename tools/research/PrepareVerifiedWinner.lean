import Lean.Data.Json.Parser
import Lean.Data.Json.FromToJson
open Lean

def main (args : List String) : IO Unit := do
  let base := System.FilePath.mk "/Users/ovm/.codex/experiments/eggshell"
  let root := base / "verified-winner-20261027"
  let project := "/Users/ovm/.codex/worktrees/hook-deadline-baseline/eggshell"
  let lean := "/Users/ovm/.elan/toolchains/leanprover--lean4---v4.33.0/bin/lean"
  let [moduleName,label] := args | throw (IO.userError "MODULE LABEL")
  unless moduleName.startsWith "tools." && moduleName.toList.all (fun c => c.isAlphanum || c == '.') &&
      !label.isEmpty && label.toList.all (fun c => c.isAlphanum || c == '-') do
    throw (IO.userError "known module and simple label required")
  if !(← (root / "interfaces").pathExists) then
    let copied ← IO.Process.output {cmd := "/bin/cp",args := #["-cR",(root / "product-build/lib").toString,(root / "interfaces").toString]}
    unless copied.exitCode == 0 do throw (IO.userError copied.stderr)
  let target := root / "interfaces" / System.FilePath.mk (moduleName.replace "." "/" ++ ".olean")
  IO.FS.createDirAll target.parent.get!
  let moduleFile := (moduleName.splitOn ".").getLast!
  for entry in ← target.parent.get!.readDir do
    if entry.fileName.startsWith (moduleFile ++ ".") && (← entry.path.symlinkMetadata).type == .symlink then
      IO.FS.removeFile entry.path
  let command := #["/usr/bin/env","LEAN_NUM_THREADS=1",
    "LEAN_PATH=" ++ (root / "interfaces").toString ++ ":" ++ (root / "product-build/lib").toString,
    lean,"--root=" ++ (root / "checkout").toString,"-j1","-M1536","-DwarningAsError=true",
    "-o",(root / "interfaces" / System.FilePath.mk (moduleName.replace "." "/" ++ ".olean")).toString,
    (root / "checkout" / System.FilePath.mk (moduleName.replace "." "/" ++ ".lean")).toString]
  IO.FS.writeFile (root / (label ++ "-settings.json")) (Json.mkObj [
    ("command",toJson command),("cwd",toJson project),("limitRssKiB",toJson (3670016 : Nat)),
    ("minFreeKiB",toJson (2097152 : Nat)),("ownedPrefixes",toJson #[root.toString]),
    ("record",toJson (root / (label ++ ".guard.json")).toString)]).pretty
