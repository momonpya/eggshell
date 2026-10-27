import Lean.Data.Json.Parser
import Lean.Data.Json.FromToJson
open Lean

private def copy (source target : System.FilePath) : IO Unit := do
  unless !(← target.pathExists) do throw (IO.userError "preserve captured integration evidence")
  IO.FS.createDirAll target.parent.get!
  IO.FS.writeBinFile target (← IO.FS.readBinFile source)
private def stopped (path : System.FilePath) : IO Unit := do
  let report ← IO.ofExcept (Json.parse (← IO.FS.readFile path))
  unless report.getObjValD "state" == toJson "finished" &&
      report.getObjValD "ownedPids" == toJson (#[] : Array Nat) do
    throw (IO.userError "do not capture or clean live owned work")
private partial def erase (path : System.FilePath) : IO (Nat × Nat) := do
  let metadata ← path.symlinkMetadata
  if metadata.type == .dir then
    let mut total := (0,0)
    for entry in ← path.readDir do
      let next ← erase entry.path
      total := (total.1+next.1,total.2+next.2)
    IO.FS.removeDir path
    return total
  else if metadata.type == .file || metadata.type == .symlink then
    IO.FS.removeFile path
    return (1,if metadata.type == .file then metadata.byteSize.toNat else 0)
  else throw (IO.userError "do not remove special files")

def main : IO Unit := do
  let active : System.FilePath := "/Users/ovm/.codex/experiments/eggshell/feedback-pilot-20261028"
  let base : System.FilePath := "/Users/ovm/.codex/experiments/eggshell/verified-winner-20261027"
  let root := active / "storage-integration"
  let target : System.FilePath := "/Users/ovm/.codex/worktrees/hook-deadline-baseline/eggshell/docs/candidates/storage-row/integration"
  unless !(← target.pathExists) do throw (IO.userError "preserve earlier integration reports")
  let lanes := #["generic","service-replay","preparation","preparation-resume","journal-read",
    "publication-boundaries","ancestry-checks"]
  for label in lanes do stopped (root / (label ++ ".guard.json"))
  unless !(← (root / "current-held.egg").pathExists) && (← (root / "restored.json").pathExists) do
    throw (IO.userError "restore the real current DB before cleaning temporary publications")
  IO.FS.createDirAll target
  for label in lanes do
    copy (root / (label ++ ".guard.json")) (target / (label ++ ".guard.json"))
    for entry in ← (root / label).readDir do
      if (← entry.path.symlinkMetadata).type != .file then continue
      if entry.fileName == "endpoint.json" then throw (IO.userError "never capture an endpoint capability")
      if entry.path.extension == some "json" || entry.path.extension == some "txt" then
        copy entry.path (target / label / entry.fileName)
  for entry in ← (root / "generic").readDir do
    if (← entry.path.symlinkMetadata).type != .dir then continue
    if entry.fileName.endsWith "-Pre" || entry.fileName.endsWith "-Post" ||
        #["SessionStart","UserPromptSubmit","Stop","keep","recall-hook","recall-warm","recover-warm"].contains entry.fileName then
      for name in #["stdin","stdout","stderr","record.json"] do
        if ← (entry.path / name).pathExists then copy (entry.path / name) (target / "generic" / entry.fileName / name)
  copy (root / "restored.json") (target / "restored.json")
  copy (root / "input.json") (target / "fixture-input.json")
  copy (root / "preparation.sample.txt") (target / "preparation.sample.txt")
  for label in #["storage-product","storage-controller","storage-preparation","storage-service","storage-journal"] do
    copy (base / (label ++ "-build/build.json")) (target / "builds" / (label ++ ".json"))
  for label in #["storage-product-build","storage-product-entrypoint-build","storage-controller-build",
      "storage-controller-ancestry-build","storage-preparation-build","storage-preparation-typed-result-build",
      "storage-preparation-coverage-build","storage-service-build","storage-service-installation-build",
      "storage-journal-build","storage-journal-boundaries-build"] do
    copy (base / (label ++ ".guard.json")) (target / "builds" / (label ++ ".guard.json"))
  let hashes ← IO.Process.output {
    cmd := (active / "controller/StudyMain").toString
    args := #["artifacts",(root / "prefix/libexec/eggshell").toString,
      (base / "storage-controller-build/StudyMain").toString,(active / "prefix/libexec/eggshell").toString]}
  unless hashes.exitCode == 0 do throw (IO.userError hashes.stderr)
  IO.FS.writeFile (target / "native-digests.json") hashes.stdout
  IO.FS.writeFile (target / "verification-correction.json") (Json.mkObj [
    ("firstPreparationSummaryCompleteFieldInvalid",toJson true),
    ("reason",toJson "journal returned complete=false after the initial source build consumed its budget"),
    ("correctedVerifierDoesNotTreatNoExceptionAsReadiness",toJson true),
    ("subsequentJournalReplayFailed",toJson true),("answeringModelCalls",toJson (0 : Nat))]).compress
  let paths := #[root / "generic",root / "service-output.egg",root / "service-replay/before.egg",
    base / "storage-product-build",base / "storage-preparation-build",base / "storage-service-build",base / "storage-journal-build"]
  IO.FS.writeFile (target / "cleanup-plan.json") (toJson (paths.map System.FilePath.toString)).compress
  let mut removed := #[]
  for path in paths do
    let (files,bytes) ← erase path
    removed := removed.push (Json.mkObj [("path",toJson path.toString),("files",toJson files),("logicalBytes",toJson bytes)])
    IO.FS.writeFile (target / "cleanup-progress.json") (toJson removed).compress
  IO.FS.writeFile (target / "cleanup.json") (Json.mkObj [("removed",toJson removed),
    ("archiveCreated",toJson false),("currentCandidateRuntimeAndAdmissionControllerRetained",toJson true),
    ("unreadableRealSourceInputsRetainedForCurrentAncestryIssue",toJson true)]).compress
  IO.println (toJson removed).compress
