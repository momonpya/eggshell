import tools.research.ReplayWorkChecks
import tools.research.ReadRangeChecks

open Lean Eggshell Eggshell.Plugin Eggshell.Synapses Eggshell.Synapses.Extraction

#print axioms Journal.FeedbackProgress.rebase_keeps_next
#print axioms Journal.FeedbackProgress.rebase_keeps_result

private def check (ok : Bool) (message : String) : IO Unit :=
  unless ok do throw (IO.userError message)

private def same (a b : Journal.Replay) : Bool :=
  a.consumed == b.consumed && a.usage == b.usage && a.consumers == b.consumers &&
  a.origins == b.origins && a.pending == b.pending && a.unknown == b.unknown &&
  a.ambiguousNativeUses == b.ambiguousNativeUses

private def feedbackChecks (root : System.FilePath) : IO Json := do
  let original ← Persistence.ensureSnapshot (root / "feedback.egg")
  let mut source := original
  let producers : Array ToolEvent := (List.range 8).toArray.map fun i => {
    name := "mcp__fixture__fetch",useId := s!"seed-{i}",
    input := (Json.mkObj [("uri",toJson s!"fixture://item/{i}")]).compress,
    response := (Json.mkObj [("identifier",toJson s!"unique_evidence_{i}")]).compress}
  for (tool,i) in producers.zipIdx do
    let (next,_,_) ← Eggshell.Research.ReadRangeChecks.native source root tool "feedback-seed" "seed" i
    source := next
  let mut entries : Array Journal.Entry := #[]
  for (tool,i) in producers.zipIdx do
    let producer := {tool with useId := s!"fetch-{i}"}
    let consumer : ToolEvent := {
      name := "mcp__fixture__inspect",useId := s!"inspect-{i}",
      input := (Json.mkObj [("identifier",toJson s!"unique_evidence_{i}")]).compress,response := "{}"}
    let (next,values,_) ← Eggshell.Research.ReadRangeChecks.native source root producer "feedback-analysis" "analysis" (2*i)
    source := next; entries := entries ++ values
    let (next,values,_) ← Eggshell.Research.ReadRangeChecks.native source root consumer "feedback-analysis" "analysis" (2*i+1)
    source := next; entries := entries ++ values
  let initial := source
  let cursor ← Journal.beginReplay initial entries
  check (← Journal.advanceReplay cursor ((← IO.monoMsNow)+30000)) "fixture events did not advance"
  let state ← cursor.state.get
  check (state.position.val == entries.size && state.result.pending == 0) "fixture lost published native outputs"
  let observed ← IO.ofExcept (state.observed.locate state.observedLocations)
  let mut progress := Journal.prepareFeedback initial state.starts observed.graph.snapshot state.usage
  check (progress.groups.size == 8 && progress.result.ambiguous == 0) "fixture lacks eight unambiguous native producer groups"
  for ordinal in [:2] do
    let (producer,uses) := progress.groups[ordinal]!
    let result ← Journal.feedbackGroup initial state.starts producer uses progress.result
      ((← IO.monoMsNow)+30000) (some cursor.cache) none
    progress := {progress with next := ordinal+1,result}
  cursor.feedback.set (some progress)
  cursor.metrics.modify fun metrics => {metrics with feedbackGroups := 2}
  let some journal ← Journal.open? initial | throw (IO.userError "fixture has no private journal")
  let turn : Journal.Turn := ⟨"feedback-analysis","analysis"⟩
  let latest ← Persistence.Store.getNat journal.get ("latest:" ++ turn.name)
  let input : Journal.ReplayInput := {journal,turn,latest}
  let frontier ← Journal.frontier? journal turn
  check (frontier.any (·.count == entries.size)) "native append frontier differs from the fixture's entries"
  let mut slot : ReplayPreparation.Slot := {input,frontier,cursor}
  let started ← IO.monoMsNow
  for i in [:80] do
    let (_,head,_) ← DB.PageMap.withWriter source fun writer => do
      writer.put s!"memo:unrelated-feedback:{i}" (some "derived".toUTF8)
      Persistence.Store.writeChange writer {added := [],removed := [],unionsChanged := false}
    source := {source with head}
    let cache ← StoredReadLookup.create source
    let some resumed ← slot.reusable source input frontier cache ((← IO.monoMsNow)+30000) |
      throw (IO.userError "unrelated publication rejected unchanged actual input dependencies")
    let some kept ← resumed.feedback.get | throw (IO.userError "unrelated publication discarded completed feedback groups")
    check (kept.next == 2 && kept.input == progress.input && kept.initial == progress.initial &&
      kept.result.graph.snapshot == progress.result.graph.snapshot && kept.source == source.head)
      "feedback rebase changed its completed position, input or accumulated facts"
    slot := {slot with cursor := resumed}
  let rebaseMs := (← IO.monoMsNow)-started
  let _ ← Build.refresh source .database
  let some index ← Index.open? source .database .shared | throw (IO.userError "feedback locator is missing")
  let pool ← ReplayPreparation.new
  pool.state.set {slots := #[slot],created := 1}
  let beforeExpired ← pool.stats
  check ((← pool.run source input index (← StoredReadLookup.create source) 0).isNone &&
    (← pool.stats) == beforeExpired) "an expired request replaced or evicted retained feedback work"
  let some retained := (← pool.state.get).slots[0]? | throw (IO.userError "expired request discarded its slot")
  check ((← retained.cursor.feedback.get).any (·.next == 2)) "expired request lost a completed producer prefix"
  let before ← slot.cursor.metrics.get
  let some completed ← pool.run source input index (← StoredReadLookup.create source) ((← IO.monoMsNow)+30000) |
    throw (IO.userError "resumed feedback did not finish")
  let after ← slot.cursor.metrics.get
  check (after.events == before.events && after.originals == before.originals &&
    after.feedbackGroups-before.feedbackGroups == 6 &&
    after.feedbackPreparations == before.feedbackPreparations)
    "unrelated publication re-executed a completed native group or rebuilt its grouping"
  let expected ← Journal.replay source entries ((← IO.monoMsNow)+30000)
  check (same completed expected && completed.usage.size == 8 && completed.unknown == 0)
    "resumed feedback differs from independent complete replay or lost useful omission labels"
  let some producer := producers[0]? | throw (IO.userError "missing fixture producer")
  let producer := {producer with useId := "fetch-0"}
  let value := (compileOperationOutcomes (.text "feedback-analysis") (.text "analysis") producer).2
  let some owner ← Persistence.Store.findNode? source value | throw (IO.userError "missing native owner")
  let (_,head,_) ← DB.PageMap.withWriter source fun writer => do
    Persistence.Store.removeRoot writer owner
    Persistence.Store.writeChange writer {added := [],removed := [owner],unionsChanged := false}
  let changed := {source with head}
  let invalid ← Journal.rebaseCursor? cursor changed (← StoredReadLookup.create changed) ((← IO.monoMsNow)+30000)
  check invalid.isNone "changed native membership reused completed feedback"
  let other ← Persistence.ensureSnapshot (root / "foreign-feedback.egg")
  let crossed ← try
    let _ ← Journal.rebaseCursor? cursor other (← StoredReadLookup.create other) ((← IO.monoMsNow)+30000)
    pure false
    catch _ => pure true
  check crossed "feedback continuation crossed its project scope"
  let saved ← IO.mkRef (some progress)
  let changedFacts ← try
    let _ ← Journal.nativeFeedback initial state.starts #[] state.usage ((← IO.monoMsNow)+30000)
      (some cursor.cache) none (some saved)
    pure false
    catch _ => pure true
  check changedFacts "changed consumption input reused old native feedback"
  return Json.mkObj [("actualNativeOperations",toJson (24 : Nat)),("analysisEvents",toJson entries.size),
    ("producerGroups",toJson progress.groups.size),("completedBeforeRebase",toJson progress.next),
    ("unrelatedPublications",toJson (80 : Nat)),("unrelatedPublicationAndValidationMs",toJson rebaseMs),
    ("remainingGroupsExecuted",toJson (after.feedbackGroups-before.feedbackGroups)),
    ("oldEventsAndOriginalsReloaded",toJson (0 : Nat)),("groupingRebuilt",toJson (0 : Nat)),
    ("allFactsAndStatusEqual",toJson true),("genuineMissingDeliveryLabels",toJson completed.usage.size),
    ("expiredRequestPreservesWork",toJson true),("normalWorkerPoolCompleted",toJson true),
    ("changedMembershipRejected",toJson true),("foreignScopeRejected",toJson crossed),
    ("changedFeedbackInputRejected",toJson changedFacts),("actualDeadlineSuspensionMeasured",toJson false),
    ("sustained80PersonWorkloadValidated",toJson false)]

def main (args : List String) : IO Unit := do
  let [directory,"feedback"] := args | throw (IO.userError "NEW-PRIVATE-FIXTURE feedback")
  Eggshell.Research.ReplayWorkChecks.run [directory,"prefix"]
  let root := System.FilePath.mk directory
  let feedback ← feedbackChecks root
  let report ← IO.ofExcept (Json.parse (← IO.FS.readFile (root / "result.json")))
  let report := report.setObjVal! "feedbackProgress" feedback
  IO.FS.writeFile (root / "result.json") report.pretty
  IO.println report.compress
