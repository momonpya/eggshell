module
public import Eggshell.PluginHooks

@[expose] public section
namespace Eggshell.SourceObservationTests
open Lean Plugin SourceEvidence SourceObservation Persistence DB

def require (accepted : Bool) (message : String) : IO Unit :=
  unless accepted do throw (IO.userError message)

def deadline : IO Nat := return (← IO.monoMsNow) + 15000

def completed (path workspace : System.FilePath) (pages : Nat := 256) :
    IO (Snapshot × Option (Observation (128 * 1024))) := do
  for _ in [0:512] do
    match ← step path workspace (128 * 1024) pages (← deadline) with
    | .pending => pure ()
    | .unverified => throw (IO.userError "fixture source unexpectedly became unverified")
    | .complete snapshot observation => return (snapshot, observation)
  throw (IO.userError "resumable source observation did not finish")

def scanTests (root workspace : System.FilePath) : IO Unit := do
  let text := String.ofList (List.replicate (20 * 4096) 'a')
  let path := workspace / "notes.md"
  IO.FS.writeFile path text
  let old ← SourceEvidence.capture workspace (Json.mkObj [("command", toJson "cat notes.md")]) (← deadline)
  let some file := old.record.files.head? | throw (IO.userError "read capture missing source")
  register root workspace file
  let index := entryPath root workspace file.relative
  require (!(← step index workspace (128 * 1024) 0 (← deadline)).finished)
    "zero-work visit became completed evidence"
  require (!(← step index workspace (128 * 1024) 1 (← deadline)).finished)
    "partial read became completed evidence"
  let some progress ← (SourceObservation.readJson index : IO (Option Entry)) |
    throw (IO.userError "partial observation lost cursor")
  require (progress.cursor.any (·.offset == 4096) && progress.snapshot.isNone)
    "partial observation lost its read position or changed completed index"
  -- Crash after appending page hashes but before publishing the cursor.
  let some cursor := progress.cursor | throw (IO.userError "missing cursor")
  let bank := bankDirectory index / (cursor.bank ++ ".pages")
  let writer ← FileSystem.openAppend bank.toString
  FileSystem.appendAt writer 64 (String.ofList (List.replicate 64 'f')).toUTF8
  FileSystem.syncAppend writer
  FileSystem.closeAppend writer
  let (baseline, noChange) ← completed index workspace 2
  require noChange.isNone "saving a read duplicated the same content as a new observation"
  require (baseline.file == file && baseline.stamp.isSome)
    "resumed fingerprint differed from normal command capture"
  acknowledge index baseline
  IO.FS.writeFile path text
  let (identical, duplicate) ← completed index workspace
  require (duplicate.isNone && identical.file == file)
    "same bytes with changed OS metadata lost freshness or duplicated evidence"
  acknowledge index identical
  let intermediate := String.ofList (List.replicate (7 * 4096) 'a' ++ List.replicate 4096 'b' ++
    List.replicate (12 * 4096) 'a')
  IO.FS.writeFile path intermediate
  require (!(← step index workspace (128 * 1024) 1 (← deadline)).finished)
    "partial changed scan was considered complete"
  let updated := String.ofList (List.replicate (7 * 4096) 'a' ++ List.replicate 4096 'c' ++
    List.replicate (12 * 4096) 'a')
  IO.FS.writeFile path updated
  let (next, some observation) ← completed index workspace 1 |
    throw (IO.userError "changed file produced no independent observation")
  require (observation.changedPages == 1 &&
      (observation.window.chunks.map (·.offset)).mergeSort (· ≤ ·) == [6 * 4096, 7 * 4096, 8 * 4096])
    "changed source lost preceding/following natural-language context"
  require ((observation.window.chunks.map (·.bytes.size)).sum == 12288)
    "small edit captured a full body"
  for chunk in observation.window.chunks do
    require (chunk.bytes == updated.toUTF8.extract chunk.offset (chunk.offset + chunk.bytes.size))
      "observation bytes did not come from the current file"
  require (!(← SourceEvidence.verify workspace old.record (← deadline)) &&
      (← SourceEvidence.verify workspace observation.capture.record (← deadline)))
    "old content was refreshed or new content was unverified"
  let ledger := (← SourceEvidence.observeRecords workspace [old.record, observation.capture.record] (← deadline)).ledger
  require ((authorize? [old.record, observation.capture.record] ledger).isNone &&
      (authorize? [observation.capture.record] ledger).isSome)
    "a new file observation refreshed an old dependent conclusion"
  acknowledge index next
  -- Restoring earlier bytes restores that observation's freshness without
  -- replacing the intervening evidence or its certificate with a new hash.
  IO.FS.writeFile path text
  let (restored, some restoration) ← completed index workspace 1 |
    throw (IO.userError "restored source produced no independent observation")
  require (restoration.before == some next.file && restored.file == file &&
      restoration.capture.record.files == old.record.files)
    "restoration rewrote the intervening version or lost the original dependency identity"
  require ((← SourceEvidence.verify workspace old.record (← deadline)) &&
      !(← SourceEvidence.verify workspace observation.capture.record (← deadline)) &&
      (← SourceEvidence.verify workspace restoration.capture.record (← deadline)))
    "restored bytes did not restore old freshness or incorrectly refreshed changed evidence"
  let restoredLedger := (← SourceEvidence.observeRecords workspace
    [old.record, observation.capture.record, restoration.capture.record] (← deadline)).ledger
  require ((authorize? [old.record] restoredLedger).isSome &&
      (authorize? [observation.capture.record] restoredLedger).isNone)
    "restoration gave current authority to the wrong historical observation"
  acknowledge index restored
  let banks ← (bankDirectory index).readDir
  require (banks.size ≤ 2) "completed revisions accumulated disposable page indexes"
  IO.FS.removeFile path
  let (_, some absent) ← completed index workspace |
    throw (IO.userError "deletion produced no absence observation")
  require (absent.window.chunks.isEmpty && absent.capture.record.files.all (·.content.isNone))
    "deletion rewrote old evidence or reused its body"

def unavailableTests (root workspace : System.FilePath) : IO Unit := do
  let relative := "lookup-root"
  let path := workspace / relative
  IO.FS.createDirAll path
  register root workspace ⟨relative, none⟩
  let index := entryPath root workspace relative
  require (!(← index.pathExists)) "a search directory was registered as a source file"
  IO.FS.removeDirAll path
  IO.FS.writeFile path "now a real file"
  register root workspace ⟨relative, none⟩
  let (baseline, some first) ← completed index workspace |
    throw (IO.userError "later regular file was not observed")
  acknowledge index baseline
  IO.FS.removeFile path
  IO.FS.createDirAll path
  let unavailable ← step index workspace (128 * 1024) 256 (← deadline)
  require (unavailable.finished && unavailable.observation?.isNone &&
      !(← SourceEvidence.verify workspace first.capture.record (← deadline)))
    "replacing a recorded file with a directory remained fresh or blocked saving"
  let some retained ← (SourceObservation.readJson index : IO (Option Entry)) |
    throw (IO.userError "unavailable source lost its prior snapshot")
  require (retained.snapshot == some baseline)
    "unavailable source rewrote its prior evidence index"
  IO.FS.removeDirAll path
  IO.FS.writeFile path "a different actual file"
  let (_, some restored) ← completed index workspace |
    throw (IO.userError "restored source was not retried")
  require (restored.before == some baseline.file &&
      (← SourceEvidence.verify workspace restored.capture.record (← deadline)))
    "restoration lost prior history or did not capture the new bytes"

def nativeTests (root workspace : System.FilePath) : IO Unit := do
  let session := "related-source-observation"
  let files ← sessionFiles session
  let target := root / "memory"
  let pending : PendingTurn := {
    sessionId := session, turnId := "read-and-arbitrary-script", cwd := workspace.toString,
    prompt := "investigate notes", profile := "work", semanticMatcher := none,
    read := [target.toString], write := some target.toString,
    handoffChars := 24000, projection := .none }
  Plugin.writeJson files.state ({profile := "work"} : ThreadState)
  Plugin.writeJson files.pending pending
  IO.FS.writeFile (workspace / "notes.md") "original notes\n"
  let readInput := Json.mkObj [("command", toJson "cat notes.md")]
  let readResult := Json.mkObj [("output", toJson "original notes\n")]
  let eventFor := fun turn name tool id input result => Json.mkObj [
    ("hook_event_name", toJson name), ("session_id", toJson session),
    ("turn_id", toJson turn), ("tool_name", toJson tool),
    ("tool_use_id", toJson id), ("tool_input", input), ("tool_response", result)]
  let event := eventFor pending.turnId
  let _ ← preToolUse (event "PreToolUse" "Bash" "read" readInput readResult)
  captureTerminal (event "PostToolUse" "Bash" "read" readInput readResult)
  let some old ← recordedTool? files pending.turnId
      ⟨"Bash", "read", readInput.compress, readResult.compress, none⟩ |
    throw (IO.userError "native command read was not saved")
  require (old.source.any (·.record.valid)) "actual command read lost its original freshness certificate"
  let body := toolReceiptPath files pending.turnId "read"
  let certificate := sourceCertificatePath files pending.turnId "read"
  let originalBody ← IO.FS.readFile body
  let originalCertificate ← IO.FS.readFile certificate
  require (← observeRelatedFiles files {pending with tools := [old]} (← deadline))
    "initial related-file observation did not finish"
  let scriptInput := Json.mkObj [("cmd", toJson "python update.py")]
  let failed := Json.mkObj [("output", toJson "partial modification"), ("exit_code", toJson (1 : Nat))]
  let _ ← preToolUse (event "PreToolUse" "exec_command" "script" scriptInput failed)
  IO.FS.writeFile (workspace / "notes.md") "actual changed content from an arbitrary program\n"
  let started ← IO.monoMsNow
  captureTerminal (event "PostToolUse" "exec_command" "script" scriptInput failed)
  let hookMs := (← IO.monoMsNow) - started
  let script : ToolEvent := ⟨"exec_command", "script", scriptInput.compress, failed.compress, none⟩
  require (hookMs < 250) "terminal capture synchronously waited for source scanning"
  let hydratedBefore ← loadToolReceipts files pending
  require (!(hydratedBefore.tools.any (·.name == "eggshell.observe_file")))
    "hook performed heavy observation before the save worker"
  require (!(← observeRelatedFiles files {pending with tools := [script]} 0))
    "expired observer claimed all work completed"
  IO.FS.createDirAll (workspace / "native-search-root")
  queueCheckpoint files {pending with
    tools := [script], inFlight := [],
    sources := [⟨"native-search-root", none⟩]}
  let readyStarted ← IO.monoMsNow
  -- Exercise the real independent save worker, including the newly queued
  -- observation's own publication. The hook itself performs no scan.
  for _ in [0:8] do
    flushDeferred session (← deadline)
  let queued := files.directory / "checkpoints"
  require ((← queued.readDir).isEmpty)
    "source observation queue did not finish in the actual save worker"
  require (!(← (entryPath files.directory workspace "native-search-root").pathExists))
    "a native directory search accumulated a permanent file-observation entry"
  let readyMs := (← IO.monoMsNow) - readyStarted
  let hydrated ← loadToolReceipts files pending
  require (hydrated.tools.length == 2 && !(hydrated.tools.any (·.name == "eggshell.observe_file")))
    "an independent background observation changed the model's native answer dependencies"
  let persisted ← Persistence.load target
  let observed := fun (graph : Graph) => (graph.values.filterMap OutcomeEdge.fromValue?).filter fun edge =>
    match edge.work with
    | .atom bytes => (String.fromUTF8? bytes).any (·.startsWith "eggshell.observe_file\n")
    | _ => false
  let observations := observed persisted
  require (observations.length == 1 && observations.all (fun edge => match edge.outcome with
      | .atom bytes => (String.fromUTF8? bytes).any (·.contains "actual changed content")
      | _ => false))
    "current actual contents were lost, duplicated or attributed to the failed script"
  require (originalBody == (← IO.FS.readFile body) && originalCertificate == (← IO.FS.readFile certificate))
    "new observation mutated original command evidence or its hash"
  require (← observeRelatedFiles files {pending with tools := [script]} (← deadline))
    "unchanged replay failed"
  require ((observed (← Persistence.load target)).length == 1 && (← queued.readDir).isEmpty)
    "unchanged replay duplicated source contents"
  let some changed := observations.head? | throw (IO.userError "missing new observation")
  let pinned ← PageMap.pin target
  let some ownerId ← Store.findNode? pinned changed.relation | throw (IO.userError "new source owner missing")
  let sources ← (← Store.NodeReader.new pinned).sources ownerId
  let some source := sources.head? | throw (IO.userError "new source certificate missing")
  require (sources.length == 1 && sources.all (·.valid) &&
      (← SourceEvidence.verify workspace source (← deadline)))
    "DB publication lost the new observation's own source certificate"
  let current ← SourceEvidence.capture workspace readInput (← deadline)
  let conflict ← try
    recordTool files pending.turnId {old with source := some current}
    pure false
    catch _ => pure true
  require (conflict && originalCertificate == (← IO.FS.readFile certificate))
    "new hash overwrote a previously saved certificate"
  -- A native read may finish after compaction/closure. Its pre-tool capture
  -- remains in the archived turn and must retain the same source binding.
  let lateResult := Json.mkObj [("output", toJson "actual changed content from an arbitrary program\n")]
  let _ ← preToolUse (event "PreToolUse" "Bash" "late-read" readInput lateResult)
  let some active ← readPendingBase? files | throw (IO.userError "late fixture lost active turn")
  deferPending files active
  captureTerminal (event "PostToolUse" "Bash" "late-read" readInput lateResult)
  let some late ← recordedTool? files pending.turnId
      ⟨"Bash", "late-read", readInput.compress, lateResult.compress, none⟩ |
    throw (IO.userError "late command result missing")
  require (late.source.any (·.record.valid)) "closure lost a previously confirmed read certificate"
  let second := {pending with turnId := "late-changed", tools := [], inFlight := []}
  Plugin.writeJson files.pending second
  let _ ← preToolUse (eventFor second.turnId "PreToolUse" "Bash" "changed-late-read" readInput lateResult)
  let some active ← readPendingBase? files | throw (IO.userError "changed late fixture lost turn")
  deferPending files active
  IO.FS.writeFile (workspace / "notes.md") "newer state after the actual read\n"
  captureTerminal (eventFor second.turnId "PostToolUse" "Bash" "changed-late-read" readInput lateResult)
  let some changedLate ← recordedTool? files second.turnId
      ⟨"Bash", "changed-late-read", readInput.compress, lateResult.compress, none⟩ |
    throw (IO.userError "changed late result missing")
  require (changedLate.response == lateResult.compress && changedLate.source.any (! ·.record.valid))
    "late changed read was lost or acquired authority for a later file version"
  IO.println ((Json.mkObj [("kind", toJson "related_source_observation"),
    ("terminal_capture_ms", toJson hookMs), ("observation_ready_ms", toJson readyMs),
    ("observations", toJson observations.length)]).compress)

def run : IO Unit := do
  let root ← PageMap.absolute ".lake/source-observation-tests"
  if ← root.pathExists then IO.FS.removeDirAll root
  let workspace := root / "workspace"
  IO.FS.createDirAll workspace
  require (targets workspace "mcp__remote__write" (Json.mkObj [("file_path", toJson "notes.md")]) == [])
    "remote provider acquired local file identity"
  require (targets workspace "exec_command" (Json.mkObj [("cmd", toJson "python update.py")]) == [])
    "opaque script was classified by guessed write targets"
  scanTests (root / "scan") workspace
  unavailableTests (root / "unavailable") workspace
  nativeTests root workspace
  IO.println "PASS related-source observations: resumable streamed scans, changed ranges/context, command-read freshness, opaque/failed writes, unchanged replay, immutable evidence/certificates and DB publication"

end Eggshell.SourceObservationTests
