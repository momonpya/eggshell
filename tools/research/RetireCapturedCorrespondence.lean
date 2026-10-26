import Lean.Data.Json.Parser
import Lean.Data.Json.FromToJson
open Lean

private partial def bytes (path : System.FilePath) : IO Nat := do
  let metadata ← path.symlinkMetadata
  if metadata.type != .dir then return if metadata.type == .file then metadata.byteSize.toNat else 0
  let mut total := 0
  for entry in ← path.readDir do total := total+(← bytes entry.path)
  return total

private partial def remove (path : System.FilePath) : IO Unit := do
  if (← path.symlinkMetadata).type == .dir then
    for entry in ← path.readDir do remove entry.path
    IO.FS.removeDir path
  else IO.FS.removeFile path

private partial def protectLinks (path : System.FilePath) (targets : Array System.FilePath) : IO Unit := do
  for entry in ← path.readDir do
    let metadata ← entry.path.symlinkMetadata
    if metadata.type == .dir then protectLinks entry.path targets
    else if metadata.type == .symlink then
      let actual ← IO.FS.realPath entry.path
      if targets.any (fun target => actual.toString.startsWith (target.toString ++ "/")) then
        throw (IO.userError "active product interface depends on a retirement target")

def main (args : List String) : IO Unit := do
  let [mode] := args | throw (IO.userError "RetireCapturedCorrespondence checks|finished")
  let root := System.FilePath.mk "/Users/ovm/.codex/experiments/eggshell/captured-correspondence-20261026"
  let evidence := System.FilePath.mk "/Users/ovm/.codex/worktrees/hook-deadline-baseline/eggshell/docs/candidates/captured-correspondence/records"
  let names ← match mode with
    | "checks" => pure #["audit-build","publication-build","hooks-build","contract-build","probe"]
    | "finished" => do
        unless ← (evidence / "collection.json").pathExists do throw (IO.userError "small capture evidence not collected")
        pure #["audit-build","publication-build","hooks-build","contract-build","capture-native","final-capture",
          "presentation-capture","atomic-source","atomic-affected","atomic-owner-delta","native-captured",
          "native-generation","native-literal-usage","native-owned-readers","native-dependency-closed",
          "capture-dependency-closed","atomic-dependency-closed","build-resume"]
    | _ => throw (IO.userError "fixed retirement set required")
  let report := root / (mode ++ "-retirement.json")
  unless !(← report.pathExists) do throw (IO.userError "keep prior retirement record")
  let mut targets := #[]
  for name in names do
    let path := root / name
    if ← path.pathExists then targets := targets.push path
  let processes ← IO.Process.output {cmd := "/bin/ps",args := #["-axo","pid=,command="]}
  unless processes.exitCode == 0 do throw (IO.userError "cannot inspect live trial ownership")
  let response ← IO.FS.readFile (root / "product-build/runtime.rsp")
  protectLinks (root / "product-build/lib") targets
  let mut retired := #[]
  for path in targets do
    unless (processes.stdout.splitOn path.toString).length == 1 && (response.splitOn path.toString).length == 1 do
      throw (IO.userError "retirement target is live or a product link input")
    if mode == "checks" then
      for entry in ← path.readDir do
        if entry.fileName.endsWith "-lean.stdout" || entry.fileName == "link.stderr" then
          let text ← IO.FS.readFile entry.path
          if text.contains "error" then
            let saved := root / "check-reset-errors" / path.fileName.get! / entry.fileName
            IO.FS.createDirAll saved.parent.get!
            IO.FS.writeFile saved text
    retired := retired.push (Json.mkObj [("path",toJson path.toString),("logicalBytes",toJson (← bytes path))])
  IO.FS.writeFile report (Json.mkObj [("targets",toJson retired),("archiveCreated",toJson false),
    ("sourceSeedAndActiveProductRetained",toJson true)]).pretty
  for path in targets do remove path
  IO.println s!"Deleted {targets.size} ended capture targets without archives"
