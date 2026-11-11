import Main
import Eggshell.ContractAudit
import tools.research.StudyRuntime
open Lean Eggshell Eggshell.Plugin
open Eggshell.Research
namespace ReadonlySaveChecks
def check (ok : Bool) (message : String) : IO Unit := unless ok do throw (IO.userError message)
def pending (root : System.FilePath) : PendingTurn := {
  sessionId := "readonly-save-control",turnId := "readonly-turn",cwd := root.toString,
  prompt := "Use the existing source history.",profile := "readonly",semanticMatcher := none,
  read := [],write := none,handoffChars := 500000,projection := .automatic }

def run (directory : String) : IO Unit := do
  let root : System.FilePath := .mk directory
  check (root.isAbsolute && !(← root.pathExists)) "fresh isolated native control required"
  check ((← Paths.dataRoot) == root/"data") "control data root differs from process environment"
  IO.FS.createDirAll root
  IO.FS.writeFile (root/"example.cpp") "int ORIGINAL_VALUE = 1;\n"
  let turn := {pending root with sources := [⟨"example.cpp",none⟩]}
  let files ← sessionFiles turn.sessionId
  queueCheckpoint files turn
  check (!(← files.directory.pathExists)) "readonly checkpoint wrote session files"
  check (← observeRelatedFiles files turn ((← IO.monoMsNow)+1000)) "readonly observer did not finish"
  check (!(← files.directory.pathExists)) "readonly observer touched the filesystem"
  for checkpoint in [false,true] do
    let restored ← pendingForSave files turn checkpoint
    check (toJson restored == toJson turn) "readonly save reconstructed tool receipts"

  -- Retain closed-turn correlation and late native results while eliding only
  -- the source-publication job. These records have private usage consumers.
  writeJson files.state ({profile := "readonly"} : ThreadState)
  writeJson files.pending turn
  let native : ToolEvent := {
    name := "mcp.example.lookup"
    useId := "private-result"
    input := "{}"
    response := "private native result remains recorded" }
  recordTool files turn.turnId native
  deferPending files turn
  check ((← readClosedTurn? files turn.turnId).isSome && !(← files.pending.pathExists))
    "readonly close lost its original turn metadata"
  check (!(← (files.directory/"deferred").pathExists)) "readonly close created a source job"
  let stopped ← stop (Json.mkObj [("session_id",toJson turn.sessionId),("turn_id",toJson turn.turnId),
    ("last_assistant_message",toJson "Late final answer retained privately.")])
  check (stopped == "{}") "readonly late Stop failed"
  let some closed ← readClosedTurn? files turn.turnId | throw (IO.userError "late Stop lost closed turn")
  check (closed.finalMessage == some "Late final answer retained privately.") "late answer was lost"
  let some (recorded,_) ← readNativeTool? (toolReceiptPath files turn.turnId native.useId) |
    throw (IO.userError "native readonly receipt was lost")
  check (recorded.response == native.response) "native readonly result changed"

  -- Retire an old no-write queue without launching the publication worker.
  let legacy := files.directory/"checkpoints/legacy.json"
  writeJson legacy turn
  flushDeferred turn.sessionId ((← IO.monoMsNow)+3000)
  check (!(← legacy.pathExists)) "legacy no-write job remained queued"
  check (!(← (root/"data/publisher").pathExists)) "no-write retirement contacted a publisher"

  -- Independent delivery freshness still rejects changed original contents.
  let source := root/"example.cpp"
  IO.FS.writeFile source "int ORIGINAL_VALUE = 1;\n"
  let capture ← SourceEvidence.capture root (Json.mkObj [("file_path",toJson source.toString)])
    ((← IO.monoMsNow)+3000)
  check capture.record.valid "freshness control failed to capture source"
  check (← SourceEvidence.verify root capture.record ((← IO.monoMsNow)+3000)) "unchanged source was rejected"
  IO.FS.writeFile source "int MODIFIED_VALUE = 9;\n"
  check (!(← SourceEvidence.verify root capture.record ((← IO.monoMsNow)+3000))) "changed source was accepted"

  -- A new read-only turn cannot revoke an older captured writer grant.
  let answer := "The older captured writer target must still receive this answer."
  let target := root/"old-target.egg"
  let older := {turn with
    turnId := "older-writable-turn"
    profile := "writable"
    sources := []
    write := some target.toString
    finalMessage := some answer
    closed := true }
  queueCheckpoint files older
  writeJson files.pending turn
  let queued ← (files.directory/"checkpoints").readDir
  check (queued.size == 1) "expected exactly the older writable queue entry"
  let some entry := queued[0]? | throw (IO.userError "older writer queue disappeared")
  let publisher ← StudyRuntime.startPublisher (← IO.appPath) (root/"data")
    #[("EGGSHELL_DATA_ROOT",some (root/"data").toString)]
  try
    flushDeferred turn.sessionId ((← IO.monoMsNow)+10000)
    check (!(← entry.path.pathExists)) "older writable queue was not acknowledged"
    let graph ← Persistence.load target
    check (graph.values.contains (.text answer)) "current readonly profile lost the older writable answer"
    check ((← readPendingBase? files).any (·.write.isNone)) "saving old work changed current readonly target"
  finally
    Worker.shutdown
    StudyRuntime.stopManaged publisher (root/"publisher-stop.json")
  IO.FS.writeFile (root/"result.json") (Json.mkObj [
    ("readonlyCheckpointNoEffect",toJson true),("readonlyObserverNoEffect",toJson true),
    ("readonlyReceiptLoadingElided",toJson true),("closedMetadataRetained",toJson true),
    ("lateStopAndNativeReceiptRetained",toJson true),("legacyNoWriteRetiredWithoutPublisher",toJson true),
    ("changedSourceRejected",toJson true),("olderCapturedWriterPublished",toJson true),
    ("currentReadonlyTargetRetained",toJson true),("answeringModelCalls",toJson (0 : Nat))]).compress
end ReadonlySaveChecks
def main (args : List String) : IO UInt32 := do
  match args with
  | ["checks",directory] => ReadonlySaveChecks.run directory; return 0
  | _ => sourceRouteEngine args
