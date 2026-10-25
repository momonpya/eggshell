import Eggshell.NativePublication
import Eggshell.Warm

open Lean Eggshell Eggshell.Plugin Eggshell.Synapses

private def check (condition : Bool) (message : String) : IO Unit :=
  unless condition do throw (IO.userError message)

private def domain := Sha256.hex "source-authority-checks".toUTF8

private def observation (id : String) : ToolEvent :=
  ⟨"mcp__records__get",id,(Json.mkObj [("id",toJson id)]).compress,
    (Json.mkObj [("id",toJson id),("data",toJson s!"original bytes of {id}")]).compress,none⟩

private def pending (path : System.FilePath) (id : String) : PendingTurn := {
  sessionId := "source-owner",turnId := id,cwd := path.parent.get!.toString
  prompt := "inspect recorded data",profile := "work",semanticMatcher := none
  read := [path.toString],write := some path.toString,handoffChars := 120000,projection := .none
  tools := [observation id] }

private def events (source : DB.PageMap.Snapshot) (turn : PendingTurn) : IO (Journal.Entry × Journal.Entry) := do
  let some tool := turn.tools.head? | throw (IO.userError "missing test observation")
  let use : Occurrence := ⟨turn.sessionId,turn.turnId,tool.useId⟩
  let known : Journal.Knowledge := ⟨source.head,none,[],false,none,none⟩
  return (⟨⟨domain,10⟩,.start use (canonicalToolWork tool) (Sha256.hex turn.prompt.toUTF8) known,some 1000⟩,
    ⟨⟨domain,20⟩,.finish use tool.name (canonicalJson tool.input) (canonicalJson tool.response) none,some 1010⟩)

private def publish (path : System.FilePath) (id : String) : IO DB.PageMap.Snapshot := do
  let source ← DB.PageMap.pin path
  let input := pending path id
  let (first,last) ← events source input
  let _ ← Journal.append source first
  let _ ← Journal.append source last
  let ack ← NativePublication.run input path true
  check ack.source.complete "native source publication omitted its interval"
  DB.PageMap.pin path

private def withSourceWriter (source : DB.PageMap.Snapshot) (action : IO α) : IO α := do
  let guard ← FileSystem.openRead (source.directory / "writer").toString
  check (← FileSystem.tryReadLock guard true) "test could not own source writer"
  try action finally FileSystem.unlockRead guard

private def fixture (root : System.FilePath) (candidate : Bool) : IO Json := do
  check (root.isAbsolute && !(← root.pathExists)) "new absolute source-owner fixture required"
  IO.FS.createDir root
  let path := root / "source.egg"
  let _ ← Persistence.ensureSnapshot path
  let first ← publish path "first"
  let before := first.head
  let replay ← withSourceWriter first do
    try pure (.ok (← Journal.refresh first .database ((← IO.monoMsNow)+10000)) : Except String Journal.Result)
    catch error => pure (.error error.toString)
  check ((← DB.PageMap.pin path).head == before) "background replay changed the source head"
  if !candidate then
    let .error error := replay | throw (IO.userError "baseline unexpectedly avoided redundant source writer")
    check ((error.splitOn "DB writer is busy").length > 1) "baseline failed for a different reason"
    return Json.mkObj [("sourceWriterHeld",toJson true),("baselineError",toJson error),
      ("sourceHeadUnchanged",toJson true),("answeringModelCalls",toJson (0 : Nat))]
  let result ← IO.ofExcept replay
  check result.complete "read-only replay did not finish"
  let later ← publish path "later"
  let (captured,progress) ← Warm.refreshSource first .database ((← IO.monoMsNow)+10000)
  let nativeDebt ← Build.required later .database
  let journalDebt ← Journal.required later .database
  let prepared ← Index.open? captured .database .shared
  IO.FS.writeFile (root / "prefix-observation.json") (Json.mkObj [
    ("captured",toJson captured.head),("later",toJson later.head),("replay",toJson progress),
    ("nativeDebt",toJson nativeDebt),("journalDebt",toJson journalDebt),
    ("viewSource",toJson (prepared.map (·.manifest.source)))]).pretty
  check (captured.head == first.head && later.head != first.head &&
    prepared.any (·.manifest.source == first.head) && (nativeDebt || journalDebt))
    "prefix preparation changed its captured watermark or hid later publication debt"
  let (current,finished) ← withSourceWriter later (Warm.refreshSource later .database ((← IO.monoMsNow)+10000))
  check (current.head == later.head && finished.complete) "later source prefix did not catch up"
  -- A finished private event must not silently repair a source ACK whose
  -- original interval was not committed. The source producer owns that debt.
  let delayed := root / "delayed.egg"
  let start ← Persistence.ensureSnapshot delayed
  let input := pending delayed "delayed"
  let (beforeEvent,afterEvent) ← events start input
  let _ ← Journal.append start beforeEvent
  let ack ← NativePublication.run input delayed true
  check (ack.source.awaiting == 1 && !ack.source.complete) "missing finish was certified complete"
  let source ← DB.PageMap.pin delayed
  let _ ← Journal.append source afterEvent
  let unready ← try
    let _ ← Journal.refresh source .database ((← IO.monoMsNow)+10000)
    pure false
    catch error => pure ((error.toString.splitOn "source-published").length > 1 ||
      (error.toString.splitOn "source publication").length > 1)
  check (unready && (← DB.PageMap.pin delayed).head == source.head && (← Journal.required source))
    "background preparation created missing source authority or acknowledged its debt"
  let repaired ← NativePublication.run input delayed true
  check repaired.source.complete "source producer did not resolve its delayed interval"
  let source ← DB.PageMap.pin delayed
  let finished ← withSourceWriter source (Journal.refresh source .database ((← IO.monoMsNow)+10000))
  check (finished.complete && (← Provenance.records source).size == 1) "source retry lost or duplicated its interval"
  return Json.mkObj [("sourceWriterHeld",toJson true),("replayComplete",toJson true),
    ("sourceHeadUnchanged",toJson true),("capturedPrefixPreserved",toJson true),
    ("laterPublicationDebtVisible",toJson true),("laterPrefixCaughtUp",toJson true),
    ("missingIntervalNotBackfilled",toJson true),("sourceProducerResolvedInterval",toJson true),
    ("retryDuplicates",toJson (0 : Nat)),("answeringModelCalls",toJson (0 : Nat))]

def main (args : List String) : IO UInt32 := do
  try
    let [directory,mode] := args | throw (IO.userError "SourceAuthorityChecksMain NEW-DIRECTORY baseline|candidate")
    check (#["baseline","candidate"].contains mode) "unknown source-owner mode"
    let result ← fixture (.mk directory) (mode == "candidate")
    IO.FS.writeFile (System.FilePath.mk directory / "result.json") result.pretty
    IO.println result.compress
    return 0
  catch error => IO.eprintln error.toString; return 1
