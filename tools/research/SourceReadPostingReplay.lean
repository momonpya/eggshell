import Eggshell.NativePublication
import tools.research.StudyRuntime
open Lean Eggshell Eggshell.Plugin Eggshell.Synapses
open Eggshell.Persistence.Store Eggshell.Research
namespace Eggshell.Research.SourceReadPostingReplay

private def check (valid : Bool) (message : String) : IO Unit :=
  unless valid do throw (IO.userError message)

private def document (item : NativePublication.Item) : IO Extraction.Document := do
  let value := (compileOperationOutcomes (.text item.occurrence.session)
    (.text item.occurrence.turn) item.tool).2
  let some edge := OutcomeEdge.fromValue? value | throw (IO.userError "missing native Outcome")
  return {
    owner := Persistence.selectionKey edge.relation,work := Persistence.selectionKey edge.work
    workText := text? edge.work,source := text? edge.outcome
    native := edge.observations.any (Relation.observesOutcomeWork edge.outcome edge.work)
    occurrences := Provenance.identities edge
    files := ← IO.ofExcept (Extraction.fileMap (item.tool.source.toArray.map fun capture => toJson capture.record)) }

/-- Replay the actual rejected source publication into a fresh clone. No
handoff, embedding, ranking or manually reconstructed graph fact is involved. -/
def cliMain (args : List String) : IO Unit := do
  let [database,checkpoints,output] := args |
    throw (IO.userError "SourceReadPostingReplay SOURCE CHECKPOINTS NEW-OUTPUT")
  let root := System.FilePath.mk output
  check (!(← root.pathExists)) "preserve earlier regression results"
  IO.FS.createDir root
  let original := System.FilePath.mk database
  let before ← StudyRuntime.files original
  let target := root/"work.egg"
  discard <| StudyRuntime.checkpoint original target
  let mut reports := #[]
  let mut expanded := false
  let mut terminalRecords := #[]
  let entries := (← (System.FilePath.mk checkpoints).readDir).qsort (fun a b => a.fileName < b.fileName)
  for entry in entries do
    if !entry.fileName.endsWith ".json" then continue
    let pending ← IO.ofExcept (Json.parse (← IO.FS.readFile entry.path) >>= fromJson? (α := PendingTurn))
    if pending.tools.isEmpty then
      terminalRecords := terminalRecords.push entry.fileName
      continue
    let adjusted : PendingTurn := {pending with
      write := some target.toString
      read := pending.read.map (fun path => if path == database then target.toString else path)}
    let source ← DB.PageMap.pin target
    let reader ← SourceReadView.reader source
    let items ← NativePublication.plan adjusted target
    let mut oldRows : Array (SourceReadView.Posting × Read) := #[]
    let mut expected : Array Read := #[]
    for item in items do
      let doc ← document item
      let some raw := doc.source | throw (IO.userError "missing native original")
      let records ← IO.ofExcept (ObservedRecords.prepare raw)
      let prepared ← IO.ofExcept (SourceReadView.prepare source.head.identity doc raw records item.tool.correspondence)
      expected := expected ++ prepared.rows
      for row in prepared.rows do
        let some encoded ← source.get (SourceReadView.postingKey row) | continue
        let posting ← ObservedRecords.decode (α := SourceReadView.Posting) encoded
        let stored ← reader.row posting
        check (stored == row) "the original regression posting already names another Read"
        oldRows := oldRows.push (posting,stored)
    check (!oldRows.isEmpty) "regression needs already published original rows"
    expanded := expanded || expected.size > oldRows.size
    let request ← NativePublication.prepare adjusted target true
    let batched ← NativePublication.runPrepared target #[request,request]
    check (batched.size == 2 && batched.all (·.source.complete)) "same-batch native receipts are incomplete"
    let some published := batched[0]? | throw (IO.userError "native publication lost its receipt")
    let current ← DB.PageMap.pin target
    let currentReader ← SourceReadView.reader current
    let oldPinnedReader ← SourceReadView.reader source
    for (posting,row) in oldRows do
      check ((← currentReader.row posting) == row) "a previously published position moved"
      check ((← oldPinnedReader.row posting) == row) "publication changed an older pinned original"
    let mut positions := #[]
    for row in expected do
      let some encoded ← current.get (SourceReadView.postingKey row) |
        throw (IO.userError "new verified row was not published")
      let posting ← ObservedRecords.decode (α := SourceReadView.Posting) encoded
      check ((← currentReader.row posting) == row) "published position does not restore the verified Read"
      positions := positions.push (SourceReadView.postingKey row,encoded)
    let duplicate ← NativePublication.run adjusted target true
    check duplicate.source.complete "idempotent native publication lost its timing receipt"
    let reopened ← DB.PageMap.pin target
    let reopenedReader ← SourceReadView.reader reopened
    for (name,encoded) in positions do
      check ((← reopened.get name) == some encoded) "duplicate publication changed a row position"
      let posting ← ObservedRecords.decode (α := SourceReadView.Posting) encoded
      let row ← reopenedReader.row posting
      check (expected.contains row) "reopened row has no original witness"
    reports := reports.push (Json.mkObj [
      ("checkpoint",toJson entry.fileName),("oldPositions",toJson oldRows.size),
      ("verifiedRows",toJson expected.size),("sourceReceipt",toJson published.source),
      ("sameBatchDuplicatePassed",toJson true),
      ("oldPositionsPreserved",toJson true),("olderPinnedSnapshotPreserved",toJson true),
      ("allVerifiedRowsPublished",toJson true),("duplicatePositionsUnchanged",toJson true),
      ("reopenPassed",toJson true)])
  check (expanded && !reports.isEmpty) "actual partial-to-complete regression was not exercised"
  check ((← StudyRuntime.files original) == before) "regression changed the retained original source"
  IO.FS.writeFile (root/"result.json") (Json.mkObj [
    ("reports",toJson reports),("sourceUnchanged",toJson true),
    ("terminalRecordsOutsideReadRowRegression",toJson terminalRecords),
    ("actualNativePublicationUsed",toJson true),("answeringModelCalls",toJson (0 : Nat)),
    ("acceptedAsSeed",toJson false),("adopted",toJson false)]).compress

end Eggshell.Research.SourceReadPostingReplay
