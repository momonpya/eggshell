import Eggshell.NativePublication
import tools.research.StudyRuntime

open Lean Eggshell Eggshell.Plugin Eggshell.Synapses
open Eggshell.Persistence.Store Eggshell.Research

/-- Inspect rejected publications without opening a writer or changing a
source. Report physical posting positions separately from original identity. -/
def main (args : List String) : IO Unit := do
  let [database,checkpoints,report] := args |
    throw (IO.userError "SourceReadPostingAudit SOURCE CHECKPOINT-DIRECTORY NEW-REPORT")
  let output := System.FilePath.mk report
  unless !(← output.pathExists) do throw (IO.userError "preserve an earlier posting diagnosis")
  let source ← DB.PageMap.pin (.mk database)
  let before ← StudyRuntime.files source.directory
  let reader ← SourceReadView.reader source
  let mut reports := #[]
  for entry in ← (System.FilePath.mk checkpoints).readDir do
    if !entry.fileName.endsWith ".json" then continue
    let pending ← IO.ofExcept (Json.parse (← IO.FS.readFile entry.path) >>= fromJson? (α := PendingTurn))
    let items ← NativePublication.plan pending source.directory
    for item in items do
      let owner := (compileOperationOutcomes (.text item.occurrence.session)
        (.text item.occurrence.turn) item.tool).2
      let some edge := OutcomeEdge.fromValue? owner |
        throw (IO.userError "native publication did not compile an Outcome")
      let document : Extraction.Document := {
        owner := Persistence.selectionKey edge.relation
        work := Persistence.selectionKey edge.work
        workText := text? edge.work
        source := text? edge.outcome
        native := edge.observations.any (Relation.observesOutcomeWork edge.outcome edge.work)
        occurrences := Provenance.identities edge
        files := ← IO.ofExcept (Extraction.fileMap (item.tool.source.toArray.map fun capture => toJson capture.record)) }
      let some raw := document.source | throw (IO.userError "native source is missing")
      let records ← IO.ofExcept (ObservedRecords.prepare raw)
      let compiled ← IO.ofExcept (SourceReadView.prepare source.head.identity document raw records item.tool.correspondence)
      let candidates ← getIds source.get ("owner:"++toString (hash edge.relation).toNat)
      let live ← candidates.filterM fun id => return (← source.get (key "member" id)).isSome
      let mut differences := #[]
      let mut existing := 0
      for ordinal in [:compiled.rows.size] do
        let row := compiled.rows[ordinal]!
        let some bytes ← source.get (SourceReadView.postingKey row) | continue
        existing := existing+1
        let posting ← ObservedRecords.decode (α := SourceReadView.Posting) bytes
        if posting.ordinal == ordinal && live == [posting.owner] then continue
        let stored ← reader.row posting
        let some headerBytes ← MetadataBytes.get? source (SourceReadView.ownerKey posting.owner) |
          throw (IO.userError "posting has no owner header")
        let header ← ObservedRecords.decode (α := SourceReadView.Header) headerBytes.bytes
        differences := differences.push (Json.mkObj [
          ("existing",toJson posting),("newOrdinal",toJson ordinal),("liveOwnerIds",toJson live),
          ("sameRead",toJson (stored == row)),("sameOriginalOwner",toJson (header.owner == document.owner)),
          ("oldRows",toJson header.rows),("newRows",toJson compiled.rows.size),
          ("subject",toJson row.source.subject),("range",toJson (row.source.first,row.source.last)),
          ("binding",toJson row.binding)])
      reports := reports.push (Json.mkObj [
        ("checkpoint",toJson entry.fileName),("occurrence",toJson item.occurrence),
        ("owner",toJson document.owner),("compiledRows",toJson compiled.rows.size),
        ("existingPostings",toJson existing),("differences",toJson differences)])
  unless (← StudyRuntime.files source.directory) == before do
    throw (IO.userError "read-only diagnosis changed the source")
  IO.FS.writeFile output (Json.mkObj [("database",toJson database),("sourceFiles",toJson before),
    ("reports",toJson reports),("sourceUnchanged",toJson true),
    ("writerOpened",toJson false),("answeringModelCalls",toJson (0 : Nat))]).compress
