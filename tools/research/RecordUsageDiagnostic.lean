import Lean.Data.Json.Parser
import Lean.Data.Json.FromToJson
open Lean

private def root : System.FilePath := "/Users/ovm/.codex/experiments/eggshell/feedback-pilot-20261028"
private def target : System.FilePath := "/Users/ovm/.codex/worktrees/hook-deadline-baseline/eggshell/docs/candidates/usage-feedback/observed"
private def read (path : System.FilePath) : IO Json :=
  IO.FS.readFile path >>= fun text => IO.ofExcept (Json.parse text)
private def copy (source destination : System.FilePath) : IO Unit := do
  unless (← source.symlinkMetadata).type == .file do throw (IO.userError "capture plain files only")
  IO.FS.createDirAll destination.parent.get!
  IO.FS.writeBinFile destination (← IO.FS.readBinFile source)
private partial def capture (source destination : System.FilePath) : IO Unit := do
  if source.toString.endsWith ".egg" || source.fileName == some "data" then return
  if (← source.symlinkMetadata).type == .dir then
    for entry in ← source.readDir do capture entry.path (destination / entry.fileName)
  else copy source destination
private partial def erase (path : System.FilePath) : IO (Nat × Nat) := do
  let metadata ← path.symlinkMetadata
  if metadata.type == .dir then
    let mut removed := (0,0)
    for entry in ← path.readDir do
      let next ← erase entry.path
      removed := (removed.1+next.1,removed.2+next.2)
    IO.FS.removeDir path
    return removed
  IO.FS.removeFile path
  return (1,if metadata.type == .file then metadata.byteSize.toNat else 0)
private def artifacts (paths : Array System.FilePath) : IO (Array Json) := do
  let result ← IO.Process.output {
    cmd := (root / "controller/StudyMain").toString
    args := #["artifacts"] ++ paths.map System.FilePath.toString}
  unless result.exitCode == 0 do throw (IO.userError result.stderr)
  IO.ofExcept (Json.parse result.stdout >>= Json.getArr?)
private def verifyFiles (directory : System.FilePath) (manifest : Json) : IO Unit := do
  let files ← IO.ofExcept (fromJson? (α := Array (String × String)) manifest)
  let hashes ← artifacts (files.map fun row => directory / row.1)
  for ((name,digest),actual) in files.zip hashes do
    unless actual.getObjValD "sha256" == toJson digest &&
        actual.getObjValD "path" == toJson (directory / name).toString do
      throw (IO.userError "preserve a checkpoint whose bytes changed")
def main : IO Unit := do
  unless !(← target.pathExists) do throw (IO.userError "keep captured results")
  let run := root / "usage-run"
  let guard ← read (root / "usage-run.guard.json")
  unless guard.getObjValD "state" == toJson "finished" &&
      guard.getObjValD "ownedPids" == toJson (#[] : Array Nat) do
    throw (IO.userError "preserve a live run")
  let failure ← read (run / "failure.json")
  let usage := failure.getObjValD "usage"
  let session ← IO.ofExcept (usage.getObjVal? "scope" >>= (·.getObjValAs? String "threadId"))
  unless session.toList.all (fun c => c.isAlphanum || c == '-') do throw (IO.userError "invalid observed session")
  let inputFiles ← read (run / "input-files.json")
  let outputFiles ← read (run / "output-files.json")
  verifyFiles (run / "input.egg") inputFiles
  verifyFiles (run / "output.egg") outputFiles
  verifyFiles "/Users/ovm/.codex/experiments/eggshell/study-services-20261026/common-seed-1/source.egg" inputFiles
  verifyFiles (root / "usage-history-start/work.egg") outputFiles
  capture run (target / "run")
  for name in ["usage-run.guard.json","usage-run.settings.json","usage-limits.json",
      "usage-authorized-plan.json","usage-sealed-plan.json","usage-input.json","usage-reseal.json",
      "usage-admission.json","usage-prepare.guard.json","usage-transport-checks.guard.json",
      "usage-close.guard.json","usage-evidence.json","usage-evidence.guard.json"] do
    copy (root / name) (target / name)
  for name in ["audit-input.json","audit-report.json","preparation-mode.json","plan.json"] do
    copy (root / "usage-prepared" / name) (target / "preparation" / name)
  for chat in ["chat-0","chat-1"] do
    for name in ["body.txt","shutdown.json","UserPromptSubmit/record.json"] do
      copy (root / "usage-prepared" / chat / name) (target / "preparation" / chat / name)
  capture (root / "usage-closed") (target / "closure")
  let prepared ← read (root / "usage-prepared/plan.json")
  let p := prepared.getObjValD "preparation"
  let files ← IO.ofExcept (p.getObjValAs? (Array Json) "numerical")
  for entry in files do
    let path := System.FilePath.mk (← IO.ofExcept (entry.getObjValAs? String "path"))
    copy path (target / "numerical" / path.fileName.get!)
  let search := System.FilePath.mk (← IO.ofExcept (p.getObjVal? "search" >>= (·.getObjValAs? String "path")))
  copy search (target / "preparation/search.json")
  let checkpoints := root / "usage-history-start/data/sessions" / session / "checkpoints"
  let mut pending := #[]
  if ← checkpoints.pathExists then
    for entry in ← checkpoints.readDir do
      if entry.fileName.endsWith ".json" then
        copy entry.path (target / "uncommitted" / entry.fileName)
        pending := pending.push entry.path
  IO.FS.writeFile (target / "checkpoint-digests.json") (toJson (← artifacts pending)).pretty
  copy (root / "repair-permission-profile.lean") (target / "permission-repair.lean")
  let mut removed := (0,0)
  for path in #[run / "input.egg",run / "output.egg",root / "usage-transport-checks",root / "usage-transport-checks-overlap"] do
    let next ← erase path
    removed := (removed.1+next.1,removed.2+next.2)
  let outcome := Json.mkObj [
    ("generationCalls",toJson (1 : Nat)),("freshCalls",toJson (0 : Nat)),("newSeed",toJson false),
    ("model",toJson "gpt-5.6-luna"),("effort",toJson "xhigh"),
    ("inputBodyMatched",usage.getObjValD "initialBodyMatched"),
    ("observedInclusiveTokens",usage.getObjValD "observedInclusiveTokens"),
    ("finalUsageKnown",usage.getObjValD "finalUsageKnown"),("terminalStatus",usage.getObjValD "terminalStatus"),
    ("pendingCheckpoints",toJson pending.size),("usageContrastPerformed",toJson false),
    ("causalConclusion",toJson "not evaluable: source publication failed"),
    ("productionAdoption",toJson false),("extraAnsweringCallsAllowed",toJson (0 : Nat)),
    ("guardPeakRssKiB",guard.getObjValD "sampledPeakRssKiB"),
    ("removedFilesAndLogicalBytes",toJson removed),("compressedArchiveCreated",toJson false),
    ("activeBugInputs",toJson #[(root / "usage-history-start/work.egg").toString,checkpoints.toString]),
    ("rowErrorObservedInTerminal",toJson "one indexed row exceeds page budget; chunk its payload"),
    ("exactOffendingKeyNotYetKnown",toJson true)]
  IO.FS.writeFile (target / "outcome.json") outcome.pretty
  IO.println outcome.pretty
