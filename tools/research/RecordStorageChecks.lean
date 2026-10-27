import Lean.Data.Json.Parser
import Lean.Data.Json.FromToJson
open Lean

private def stopped (path : System.FilePath) : IO Unit := do
  let value ← IO.ofExcept (Json.parse (← IO.FS.readFile path))
  unless value.getObjValD "state" == toJson "finished" &&
      value.getObjValD "ownedPids" == toJson (#[] : Array Nat) do
    throw (IO.userError "do not capture or clean a live verification")
private def copy (source target : System.FilePath) : IO Unit := do
  unless !(← target.pathExists) do throw (IO.userError "preserve captured evidence")
  IO.FS.writeBinFile target (← IO.FS.readBinFile source)
private partial def removeFinished (path : System.FilePath) : IO (Nat × Nat) := do
  let metadata ← path.symlinkMetadata
  if metadata.type == .dir then
    let mut files := 0
    let mut bytes := 0
    for entry in ← path.readDir do
      let (count,size) ← removeFinished entry.path
      files := files+count
      bytes := bytes+size
    IO.FS.removeDir path
    return (files,bytes)
  else if metadata.type == .file then
    IO.FS.removeFile path
    return (1,metadata.byteSize.toNat)
  else if metadata.type == .symlink then
    IO.FS.removeFile path
    return (1,0)
  else throw (IO.userError "cleanup is restricted to files, directories and links themselves")

def main (args : List String) : IO Unit := do
  let active : System.FilePath := "/Users/ovm/.codex/experiments/eggshell/feedback-pilot-20261028"
  let base : System.FilePath := "/Users/ovm/.codex/experiments/eggshell/verified-winner-20261027"
  let target : System.FilePath := "/Users/ovm/.codex/worktrees/hook-deadline-baseline/eggshell/docs/candidates/storage-row/checks"
  let resume := args == ["cleanup"]
  unless args.isEmpty || resume do throw (IO.userError "optional cleanup resumes only recorded removals")
  unless resume || !(← target.pathExists) do throw (IO.userError "preserve verification reports")
  unless !resume || (← target.pathExists) do throw (IO.userError "capture evidence before cleanup")
  for path in #[active / "storage-pending.guard.json",base / "metadata-io.guard.json",
      base / "metadata-proofs.guard.json"] do stopped path
  if !resume then
    IO.FS.createDirAll target
    copy (active / "storage-pending.guard.json") (target / "pending-guard.json")
    copy (active / "storage-pending/result.json") (target / "pending-result.json")
    copy (base / "metadata-payload-checks/result.json") (target / "io-result.json")
    copy (base / "metadata-build/build.json") (target / "io-build.json")
    for name in #["metadata-io.guard.json","metadata-proofs.guard.json",
        "compile-metadata-checks.guard.json","compile-metadata-checks-fixed.guard.json"] do
      copy (base / name) (target / name)
    let digest ← IO.Process.output {
      cmd := (active / "controller/StudyMain").toString
      args := #["artifacts",(base / "metadata-build/StudyMain").toString]}
    unless digest.exitCode == 0 do throw (IO.userError digest.stderr)
    IO.FS.writeFile (target / "io-native-digest.json") digest.stdout
  let batch := target / "pending"
  if !resume then IO.FS.createDirAll batch
  let mut cleanup := #[active / "row-replay-payload/before.egg",base / "metadata-payload-checks/source.egg",
    active / "storage-baseline/StudyMain",active / "storage-payload/StudyMain",base / "metadata-build"]
  for entry in ← (active / "storage-pending").readDir do
    if (← entry.path.symlinkMetadata).type != .dir then continue
    let saved := batch / entry.fileName
    if !resume then
      IO.FS.createDirAll saved
      for name in #["input.json","result.json","readback.json","staged-rows.json",
          "correspondence-validation.json"] do copy (entry.path / name) (saved / name)
    cleanup := cleanup.push (entry.path / "before.egg")
  let mut deleted := #[]
  IO.FS.writeFile (target / "cleanup-plan.json") (Json.mkObj [
    ("paths",toJson (cleanup.map System.FilePath.toString)),("resumedAfterLinkRefusal",toJson resume),
    ("removeLinkTargets",toJson false)]).compress
  for path in cleanup do
    if !(← path.pathExists) then
      deleted := deleted.push (Json.mkObj [("path",toJson path.toString),("alreadyAbsent",toJson true)])
      continue
    let (files,bytes) ← removeFinished path
    deleted := deleted.push (Json.mkObj [("path",toJson path.toString),
      ("files",toJson files),("logicalBytes",toJson bytes)])
    IO.FS.writeFile (target / "cleanup-progress.json") (toJson deleted).compress
  let result := Json.mkObj [("deleted",toJson deleted),("archiveCreated",toJson false),
    ("originalFailureSnapshotRetained",toJson (active / "row-replay-baseline/before.egg").toString),
    ("activeSourceAndCheckpointsRetained",toJson true),("answeringModelCalls",toJson (0 : Nat))]
  IO.FS.writeFile (target / "cleanup.json") result.compress
  IO.println result.compress
