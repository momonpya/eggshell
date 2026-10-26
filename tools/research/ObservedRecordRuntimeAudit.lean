import Eggshell.SynapseJournal

open Lean Eggshell Eggshell.Synapses

/-- Inspect the actual source publication without a derived index, transcript,
reference workspace or answering model. Fail rather than silently regenerating
a missing native record directory. -/
def main (args : List String) : IO UInt32 := do
  try
    let [path,expected] := args | throw (IO.userError "ObservedRecordRuntimeAudit DB EXPECTED")
    let some count := expected.toNat? | throw (IO.userError "expected count required")
    let source ← DB.PageMap.pin (.mk path)
    let originals ← Provenance.records source
    unless originals.size == count do throw (IO.userError "actual native origin count changed")
    let reader ← Persistence.Store.NodeReader.new source
    let mut records := 0
    let mut characters := 0
    let mut metadataBytes := 0
    for item in originals do
      let doc ← Provenance.checkedDocument reader item.origin
      let some catalog ← ObservedRecords.load? source item.origin.owner doc |
        throw (IO.userError "actual source ACK omitted its original record directory")
      let raw := doc.source.getD ""
      unless raw.isEmpty || covered
          (Range.original (ObservationContext.originalSubject doc.work raw) 0 raw.length) (catalog.reads.map (·.source)) do
        throw (IO.userError "actual native record directory omits raw data")
      for record in catalog.located do
        unless record.text == String.ofList ((raw.toList.drop record.read.binding.first).take
            (record.read.binding.limit-record.read.binding.first)) do
          throw (IO.userError "actual record payload is not its original data")
      records := records+catalog.located.size
      characters := characters+raw.length
    metadataBytes ← source.foldRange ⟨ObservedRecords.keyPrefix,ObservedRecords.keyPrefix ++ "~"⟩
      (fun count row => pure (count+(row.2.getD ByteArray.empty).size)) metadataBytes
    let result := Json.mkObj [("sourceOnlyAudit",toJson true),("originals",toJson originals.size),
      ("recordUnits",toJson records),("originalCharacters",toJson characters),
      ("metadataBytes",toJson metadataBytes),("completeOriginalDomain",toJson true),
      ("allPayloadsOriginal",toJson true),("answeringModelCalls",toJson (0 : Nat)),
      ("productionAdoption",toJson false)]
    IO.println result.compress
    return 0
  catch error => IO.eprintln error.toString; return 1
