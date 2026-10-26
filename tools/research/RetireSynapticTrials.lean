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
        throw (IO.userError "active product interface depends on an ended helper")

def main (args : List String) : IO Unit := do
  let ended := args == ["prepared-ended"]
  let payload := args == ["payload-checks"]
  let prepared := args == ["prepared-checks"] || ended
  unless prepared || payload || args.isEmpty do throw (IO.userError "RetireSynapticTrials [prepared-checks|prepared-ended|payload-checks]")
  let base := System.FilePath.mk "/Users/ovm/.codex/experiments/eggshell"
  let project := System.FilePath.mk "/Users/ovm/.codex/worktrees/hook-deadline-baseline/eggshell"
  let report := project / "docs/candidates" / (if payload then "nonempty-source-payload" else if prepared then "receipt-preparation" else "receipt-row-postings") /
    (if ended then "records/retirement-finished.json" else "records/retirement.json")
  unless !(← report.pathExists) do throw (IO.userError "keep retirement evidence")
  let mut targets := #[]
  let runs := if ended then #[("receipt-preparation",#["fixed-source-hooks","missing-unit-explanation","source-build","explain-build"])]
    else if payload then #[("nonempty-source-payload",#["original-domain-regression","audit-build","canonical-build","contract-build","source-build","profile-build"])]
    else if prepared then #[ ("receipt-preparation",#["keyed-receipt","forced-receipt","missing-explanation",
      "receipt-audit-build","contract-build"])] else #[
      ("synaptic-publication-delta",#["atomic-projection","actual-checkpoint","native-atomic-routing","fixed-source-hooks",
        "audit-build","hooks-build","contract-build","checkpoint-build","source-build","profile-build"]),
      ("receipt-row-postings",#["span-receipt","fixed-source-hooks","receipt-audit-build","source-build","profile-build","contract-build"])]
  for (name,runs) in runs do
    let root := base / (name ++ "-20261027")
    unless ← (project / "docs/candidates" / name / "records/collection.json").pathExists do
      throw (IO.userError "collect small evidence before deleting an ended trial")
    for entry in ← root.readDir do
      if entry.fileName.endsWith ".guard.json" then
        let guard ← IO.ofExcept (Json.parse (← IO.FS.readFile entry.path))
        unless (guard.getObjValAs? String "state").toOption == some "finished" &&
          (guard.getObjValAs? (Array Nat) "ownedPids").toOption == some #[] do
          throw (IO.userError "candidate guard is still live")
    for run in runs do
      let path := root / run
      if ← path.pathExists then targets := targets.push path
  let processes ← IO.Process.output {cmd := "/bin/ps",args := #["-axo","pid=,command="]}
  unless processes.exitCode == 0 do throw (IO.userError "cannot inspect trial ownership")
  for name in ["captured-correspondence-20261026","synaptic-publication-delta-20261027",
      "receipt-row-postings-20261027","receipt-preparation-20261027","nonempty-source-payload-20261027",
      "selector-weight-fold-20261027"] do
    let root := base / name
    protectLinks (root / "product-build/lib") targets
    let response ← IO.FS.readFile (root / "product-build/runtime.rsp")
    for target in targets do
      unless (processes.stdout.splitOn target.toString).length == 1 &&
        (response.splitOn target.toString).length == 1 do
        throw (IO.userError "ended target is live or still needed by a product")
  let mut retired := #[]
  for target in targets do
    retired := retired.push (Json.mkObj [("path",toJson target.toString),("logicalBytes",toJson (← bytes target))])
  IO.FS.writeFile report (Json.mkObj [("targets",toJson retired),("archiveCreated",toJson false),
    ("originalSeedAndActiveProductDependenciesRetained",toJson true)]).pretty
  for target in targets do remove target
  IO.println s!"Deleted {targets.size} ended synaptic trial targets without archives"
