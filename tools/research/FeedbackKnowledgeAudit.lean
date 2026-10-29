import Eggshell.SynapseJournal
import tools.research.ConsumedFileFeedbackFixtures
open Lean Eggshell Eggshell.DB Eggshell.Synapses

#print axioms ObservationContext.locations_requested_exact

private def check (condition : Bool) (message : String) : IO Unit :=
  unless condition do throw (IO.userError message)

private def coordinates (source : PageMap.Snapshot) (occurrence : Occurrence)
    (name input response : String) : IO Json := do
  let tool : Plugin.ToolEvent := {name, useId := occurrence.useId, input, response}
  let expected := (Plugin.compileOperationOutcomes (.text occurrence.session) (.text occurrence.turn) tool).2
  let some id ← Persistence.Store.findNode? source expected | return Json.mkObj [("originalOwnerFound", toJson false)]
  let document ← Build.document (← Persistence.Store.NodeReader.new source) id
  let captured ← ContentMetadata.load? source id document
  let command ← IO.ofExcept (Extraction.invocationData (document.workText.getD ""))
  let raw := document.source.getD ""
  let started ← IO.ofExcept (({} : Extraction.Trace).start occurrence 0 command.1 command.2)
  let trace ← IO.ofExcept (started.finish occurrence 1 raw (if (Json.parse raw).isOk then .json else .text))
  let legacy := Extraction.locateReads source.head.identity document trace
  let original := (ObservationContext.recorded source.head.identity document).getD {}
  let catalog ← ContentMetadata.addFileCoordinates source id document original
  let locations := ObservationContext.locationsUsing source.head.identity document trace catalog
  let files := locations.returned.flatMap (·.originalRows) |>.filter (·.source.file?.isSome)
  if let some row := files[0]? then
    let result := Persistence.selectionKey (.text raw)
    let key := s!"e:{document.owner}:{result}:{row.binding.first}:{row.binding.limit}"
    let known : Journal.Knowledge := {source := source.head, indexed := none, acknowledged := [key], uncertain := false}
    let shown ← Journal.presentation source known
    check (covered row.source shown.ranges) "raw excerpt ACK did not preserve its cached file correspondence"
    let bad : Journal.Knowledge := {known with acknowledged :=
      [s!"e:{document.owner}:wrong-result:{row.binding.first}:{row.binding.limit}"]}
    check ((← Journal.presentation source bad).ranges.isEmpty) "a foreign raw-result ACK acquired file ranges"
  let wrongInput := if command.2 == .json then (Json.mkObj [("unobserved", toJson true)]).compress else "unobserved invocation"
  let wrong ← IO.ofExcept (({} : Extraction.Trace).start occurrence 0 wrongInput command.2)
  let wrong ← IO.ofExcept (wrong.finish occurrence 1 raw (if (Json.parse raw).isOk then .json else .text))
  check ((ObservationContext.returnedUsing source.head.identity document wrong catalog).isEmpty)
    "cached coordinates survived an unrelated complete invocation"
  let changed := {trace with finished := trace.finished.insert occurrence (raw ++ "changed output")}
  check ((ObservationContext.returnedUsing source.head.identity document changed catalog).isEmpty)
    "cached coordinates survived changed output bytes"
  return Json.mkObj [("occurrence", toJson occurrence), ("originalOwnerFound", toJson true),
    ("originalFiles", toJson document.files.size), ("legacyLocated", toJson legacy.isOk),
    ("legacyFileRows", toJson (legacy.toOption.map (·.size) |>.getD 0)),
    ("requestedFileRows", toJson locations.requested.size),
    ("projectedFileRows", toJson ((locations.all.flatMap (·.rows)).countP (·.source.file?.isSome))),
    ("rawExcerptAckProjectionChecked", toJson (!files.isEmpty)),
    ("wrongInvocationAndOutputRejected", toJson true),
    ("capturedInputs", toJson (captured.map (·.inputs.size) |>.getD 0)),
    ("capturedAliases", toJson (captured.map (·.aliases.size) |>.getD 0)),
    ("capturedComplete", toJson (captured.map (·.complete)))]

/-- Read captured metadata from an existing model trial. Build through the
native harness so the descriptor-based file IO uses its actual linked boundary.
No feedback replay, provider, preparation or journal edit occurs. -/
def main (args : List String) : IO Unit := do
  Eggshell.Research.ConsumedFileFeedback.fixtures
  let (database, data, session, destination, replay, inspectCoordinates) ← match args with
    | [database, data, session, destination] => pure (database, data, session, destination, false, false)
    | [database, data, session, destination, "replay"] => pure (database, data, session, destination, true, false)
    | [database, data, session, destination, "coordinates"] => pure (database, data, session, destination, false, true)
    | _ => throw (IO.userError "database, private root, session, report and optional replay/coordinates required")
  let output := System.FilePath.mk destination
  check (!(← output.pathExists) && (← Paths.dataRoot) == System.FilePath.mk data) "fresh report and explicit private root required"
  let source ← PageMap.pin (.mk database)
  let some journal ← Journal.open? source | throw (IO.userError "existing model trial journal missing")
  let count ← Persistence.Store.getNat journal.get "count"
  let mut starts := #[]
  let mut finishes : Std.HashSet Occurrence := {}
  let mut answers := 0
  let mut differentSessionEntries := 0
  let mut observed := #[]
  let mut outputCoordinates := #[]
  for ordinal in [:count] do
    let entry ← Journal.entry journal ordinal
    if entry.payload.occurrence.session != session then
      differentSessionEntries := differentSessionEntries + 1
      continue
    observed := observed.push entry
    match entry.payload with
    | .start occurrence work query known =>
        let inherited ← Journal.originalAt? source known.source
        starts := starts.push (Json.mkObj [("occurrence", toJson occurrence),
          ("query", toJson query), ("tool", toJson ((work.splitOn "\n").headD "")),
          ("invocationReadable", toJson (Extraction.invocationData work).isOk),
          ("source", toJson known.source), ("sourcePrefixReadable", toJson inherited.isSome),
          ("indexCaptured", toJson known.indexed.isSome), ("uncertainDelivery", toJson known.uncertain),
          ("acknowledgedDeliveries", toJson known.acknowledged.length),
          ("archiveRecorded", toJson known.archive.isSome), ("archiveHeadRecorded", toJson known.archived.isSome)])
    | .finish occurrence name input response _ =>
        finishes := finishes.insert occurrence
        if inspectCoordinates then outputCoordinates := outputCoordinates.push (← coordinates source occurrence name input response)
    | .answer .. => answers := answers + 1
  check (!starts.isEmpty && finishes.size > 0) "session selection missed the actual native model trial"
  let missing := starts.filter fun row =>
    !(finishes.toList.any fun occurrence => toJson occurrence == row.getObjValD "occurrence")
  let replayed ← if replay then do
      let began ← IO.monoMsNow
      let hint ← Journal.preparedHint? source
      let locatorCache ← StoredReadLookup.create
      let ordered := observed.qsort fun a b => if a.clock.domain == b.clock.domain then
          a.clock.nanos < b.clock.nanos else a.clock.domain < b.clock.domain
      let result ← Journal.replay source ordered (began + 120000) hint (some locatorCache)
      let locatorState ← locatorCache.state.get
      check (result.usage.size ≤ 65536) "bounded read-only replay report exceeded its fact budget"
      pure (Json.mkObj [("elapsedMs", toJson ((← IO.monoMsNow) - began)),
        ("locatorSource", toJson (hint.map (·.manifest.source))),
        ("locatorIndex", toJson (hint.map (·.index.head))),
        ("pending", toJson result.pending), ("unknown", toJson result.unknown),
        ("consumed", toJson result.consumed.size), ("ambiguousNativeUses", toJson result.ambiguousNativeUses),
        ("fileRangeReferences", toJson (result.consumed.foldl (fun count fact => match fact with
          | .consumed edge => count + edge.rows.countP (·.file?.isSome)
          | _ => count) 0)),
        ("locatorCache", Json.mkObj [("hits", toJson locatorState.hits), ("misses", toJson locatorState.misses),
          ("entries", toJson locatorState.entries.size), ("rows", toJson locatorState.rows), ("bytes", toJson locatorState.bytes)]),
        ("usage", toJson result.usage)])
    else pure Json.null
  let some after ← Journal.open? source | throw (IO.userError "journal disappeared during read-only audit")
  check (after.head == journal.head && (← PageMap.pin source.directory).head == source.head)
    "metadata inspection changed durable source or events"
  let report := Json.mkObj [("nativeMetadataAudit", toJson true),
    ("journal", toJson journal.head), ("source", toJson source.head), ("session", toJson session),
    ("totalJournalEntries", toJson count), ("otherSessionEntries", toJson differentSessionEntries),
    ("starts", Json.arr starts), ("finishes", toJson finishes.size), ("answers", toJson answers),
    ("outputCoordinates", Json.arr outputCoordinates),
    ("startsWithoutFinish", toJson missing.size),
    ("startsWithoutCapturedIndex", toJson (starts.countP fun row => row.getObjValD "indexCaptured" == toJson false)),
    ("startsWithUncertainDelivery", toJson (starts.countP fun row => row.getObjValD "uncertainDelivery" == toJson true)),
    ("sourceAndJournalUnchanged", toJson true), ("feedbackReplayed", toJson replay), ("replay", replayed),
    ("warmCalls", toJson (0 : Nat)), ("answeringModelCalls", toJson (0 : Nat))]
  IO.FS.createDirAll output.parent.get!
  IO.FS.writeFile output report.pretty
  let usageCount := ((replayed.getObjVal? "usage" >>= Json.getArr?).toOption.map (·.size)).getD 0
  IO.println (Json.mkObj [("starts", toJson starts.size), ("finishes", toJson finishes.size),
    ("startsWithoutCapturedIndex", report.getObjValD "startsWithoutCapturedIndex"),
    ("startsWithUncertainDelivery", report.getObjValD "startsWithUncertainDelivery"),
    ("startsWithoutFinish", report.getObjValD "startsWithoutFinish"),
    ("replayedUsage", toJson usageCount), ("replayedUnknown", replayed.getObjValD "unknown"),
    ("replayedPending", replayed.getObjValD "pending")]).compress
