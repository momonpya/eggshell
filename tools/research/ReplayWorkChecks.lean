import Eggshell.NativePublication
import Eggshell.ReplayPreparation
import Eggshell.ContractAudit

open Lean Eggshell Eggshell.Plugin Eggshell.Synapses Eggshell.Synapses.Extraction

#print axioms TurnReplay.changed_bucket_rejected
#print axioms ReplayWork.changed_ticket_cannot_finish
#print axioms DB.PageMap.relevant_replay_write_present
#print axioms ReplayWork.Window.rows_bounded
#print axioms ReplayWork.WatchProgress.rows_bounded
#print axioms ReplayWork.Sync.rows_bounded

private def check (ok : Bool) (message : String) : IO Unit :=
  unless ok do throw (IO.userError message)

private def events (source : DB.PageMap.Snapshot) (tool : ToolEvent)
    (session turn : String) (ordinal : Nat) (archive : String) : IO (Array Journal.Entry) := do
  let occurrence : Occurrence := ⟨session,turn,tool.useId⟩
  let known ← Journal.knowledge source [] false
  let clock := Sha256.hex (session ++ ":" ++ turn).toUTF8
  return #[⟨⟨clock,2*ordinal+1⟩,.start occurrence (canonicalToolWork tool) (Sha256.hex "query".toUTF8) known,none⟩,
    ⟨⟨clock,2*ordinal+2⟩,.finish occurrence tool.name (canonicalJson tool.input)
      (canonicalJson tool.response) (some archive),none⟩]

private def publish (source : DB.PageMap.Snapshot) (root : System.FilePath) (tool : ToolEvent)
    (session turn : String) (ordinal : Nat) : IO (DB.PageMap.Snapshot × Array Journal.Entry) := do
  let values ← events source tool session turn ordinal source.directory.toString
  for value in values do let _ ← Journal.append source value
  let pending : PendingTurn := {
    sessionId := session,turnId := turn,cwd := root.toString,prompt := "query",profile := "work"
    write := some source.directory.toString,read := [],semanticMatcher := none,handoffChars := 500000,
    projection := .none,tools := [tool]}
  let _ ← NativePublication.run pending source.directory true
  return (← DB.PageMap.pin source.directory,values)

private def facts (source : DB.PageMap.Snapshot) : IO (Array Fact × Array Fact) := do
  let some shared ← Index.open? source .database .shared | throw (IO.userError "shared index missing")
  let some usage ← UsageCache.open? source | throw (IO.userError "usage cache missing")
  return (← Index.allFacts shared.index,← Index.allFacts usage.index)

private def queued (source : DB.PageMap.Snapshot) (base : String) : IO (Nat × ReplayWork.Ticket) := do
  let some value ← ReplayWork.first? source base | throw (IO.userError "expected a live replay job")
  return value

private def queueChecks (root : System.FilePath) : IO Json := do
  let source ← Persistence.ensureSnapshot (root / "queue.egg")
  let base := "private-test"
  let a := Index.contentKey "job-a"
  let b := Index.contentKey "job-b"
  let c := Index.contentKey "job-c"
  let (_,head,_) ← DB.PageMap.withWriter source fun writer => ReplayWork.enqueue writer base a
  let source := {source with head}
  let (ordinal,old) ← queued source base
  let (_,head,_) ← DB.PageMap.withWriter source fun writer => do
    ReplayWork.enqueue writer base a
    ReplayWork.enqueue writer base b
  let source := {source with head}
  let (same,current) ← queued source base
  check (same == ordinal && old != current) "new event neither deduplicated nor changed its ticket"
  let (finished,head,_) ← DB.PageMap.withWriter source fun writer =>
    ReplayWork.acknowledge writer base ordinal old true
  check (!finished) "old completion discarded a newer event"
  let source ← DB.PageMap.pin source.directory
  check (source.head == head) "queue head was not durable"
  let (ordinal,ticket) ← queued source base
  check (ticket.name == b) "unfinished first job blocked another job"
  let (finished,head,_) ← DB.PageMap.withWriter source fun writer =>
    ReplayWork.acknowledge writer base ordinal ticket true
  check finished "current completion was rejected"
  let source := {source with head}
  let (ordinal,ticket) ← queued source base
  check (ticket == current) "rotation lost the newer ticket"
  let (finished,head,_) ← DB.PageMap.withWriter source fun writer =>
    ReplayWork.acknowledge writer base ordinal ticket true
  check finished "restarted queue failed to finish its newer event"
  let source := {source with head}
  check (!(← ReplayWork.pending source base)) "finished queue stayed pending"
  let aborted ← try
    let _ ← DB.PageMap.withWriter (α := Unit) source fun writer => do
      ReplayWork.enqueue writer base c
      writer.flush
      throw (IO.userError "intentional queue transaction abort")
    pure false
    catch _ => pure true
  check (aborted && (← DB.PageMap.pin source.directory).head == source.head &&
    !(← ReplayWork.pending (← DB.PageMap.pin source.directory) base)) "aborted queue work became published"
  let (_,head,_) ← DB.PageMap.withWriter source fun writer => ReplayWork.enqueue writer base c
  check ((← queued {source with head} base).2.name == c) "aborted tail prevented later committed work"
  return Json.mkObj [("newerEventSurvivesOldCompletion",toJson true),("waitingJobDoesNotBlockNext",toJson true),
    ("reopenPreservesTickets",toJson true),("abortedFlushedQueueNotPublished",toJson true)]

private def feedChecks (root : System.FilePath) : IO Json := do
  let source ← Persistence.ensureSnapshot (root / "feed-source.egg")
  let journal ← Persistence.ensureSnapshot (root / "feed-private.egg")
  let values := (List.range 70).toArray.map fun i => Value.text s!"feed-atom-{i}"
  let mut inputs : TurnReplay.Inputs := {}
  for value in values do inputs ← inputs.observe source value
  let expected := (inputs.sources.flatMap fun source => source.buckets.map (·.key)).qsort (· < ·)
  check (expected.size == 70 && expected.toList.eraseDups.length == 70) "feed fixture needs 70 distinct keys"
  let base := "private-feed"
  let name := Index.contentKey "watched-job"
  let (_,journalHead,_) ← DB.PageMap.withWriter journal fun writer => ReplayWork.register writer base name inputs
  let journal := {journal with head := journalHead}
  let (_,head,_) ← DB.PageMap.withWriter source fun writer => do
    let intern : Persistence.Store.Intern := ⟨writer,← IO.mkRef {}⟩
    let mut ids := []
    for ordinal in [:values.size] do
      let some value := values[ordinal]? | throw (IO.userError "feed fixture lost its source value")
      ids := (← intern.value value) :: ids
      if ordinal == 34 then writer.flush
    Persistence.Store.writeChange writer {added := [],removed := [],unionsChanged := false,affected := ids}
  let source := {source with head}
  check ((← Persistence.Store.getNat source.get Persistence.Store.replayFeedSequenceKey) == 1 &&
    (← Persistence.Store.replayFeedCount source source.head.revision) == expected.size)
    "publication did not retain all writes across flush"
  let first ← Persistence.Store.replayFeedBlock source source.head.revision 0
  let second ← Persistence.Store.replayFeedBlock source source.head.revision 1
  check (first.size == 64 && second.size == 6 && first ++ second == expected)
    "publication feed differs from the complete exact key set"
  let (sync,head,_) ← DB.PageMap.withWriter journal fun writer => do
    ReplayWork.sync journal writer base source ((← IO.monoMsNow)+30000) 1
  check (!sync.complete && sync.blocks == 1 && sync.postings == 64) "bounded sync did not stop at its first block"
  let journal := {journal with head}
  let old ← queued journal base
  let cursorBefore ← journal.get (ReplayWork.sourceKey base source.directory.normalize.toString)
  let aborted ← try
    let _ ← DB.PageMap.withWriter (α := Unit) journal fun writer => do
      let _ ← ReplayWork.sync journal writer base source ((← IO.monoMsNow)+30000) 1
      writer.flush
      throw (IO.userError "intentional cursor transaction abort")
    pure false
    catch _ => pure true
  let reopened ← DB.PageMap.pin journal.directory
  check (aborted && reopened.head == journal.head &&
    (← reopened.get (ReplayWork.sourceKey base source.directory.normalize.toString)) == cursorBefore &&
    (← queued reopened base) == old) "aborted cursor passed work which was not enqueued"
  let (sync,head,_) ← DB.PageMap.withWriter reopened fun writer => do
    ReplayWork.sync reopened writer base source ((← IO.monoMsNow)+30000) 1
  let journal := {reopened with head}
  check (sync.complete && sync.blocks == 1 && sync.postings == 6 &&
    (← queued journal base).1 == old.1 && (← queued journal base).2 != old.2)
    "restart lost, duplicated, or skipped the remainder of a publication"
  let (finished,head,_) ← DB.PageMap.withWriter journal fun writer =>
    ReplayWork.acknowledge writer base old.1 old.2 true
  check (!finished && (← ReplayWork.pending {journal with head} base)) "old block completion lost a later block"
  let journal := {journal with head}
  -- A source writer bypassing GraphStore cannot turn an unknown feed into empty work.
  let (_,badHead,_) ← DB.PageMap.withWriter source fun writer =>
    writer.put "memo:bypassed-publisher" (some "not-a-publication".toUTF8)
  let broken := {source with head := badHead}
  let rejected ← try
    let _ ← DB.PageMap.withWriter journal fun writer => do
      ReplayWork.sync journal writer base broken ((← IO.monoMsNow)+30000) 1
    pure false
    catch _ => pure true
  check (rejected && (← DB.PageMap.pin journal.directory).head == journal.head)
    "missing source feed silently advanced the private cursor"
  let publisherRejected ← try
    let _ ← DB.PageMap.withWriter broken fun writer =>
      Persistence.Store.writeChange writer {added := [],removed := [],unionsChanged := false}
    pure false
    catch _ => pure true
  check (publisherRejected && (← DB.PageMap.pin source.directory).head == badHead)
    "publication concealed an uncovered earlier source root"
  return Json.mkObj [("exactChangedKeys",toJson expected.size),("boundedBlocks",toJson (2 : Nat)),
    ("flushedWritesIncluded",toJson true),("cursorAndQueueAbortTogether",toJson true),
    ("restartResumesRemainingBlock",toJson true),("missingProducerRejected",toJson true),
    ("bypassedPublicationCannotBeConcealed",toJson true)]

private def bootstrapChecks (root : System.FilePath) : IO Json := do
  let journal ← Persistence.ensureSnapshot (root / "bootstrap.egg")
  let names := (#[(0 : Nat),1,2].map Index.contentKey).qsort (· < ·)
  let (_,head,_) ← DB.PageMap.withWriter journal fun writer => do
    for name in names do writer.put ("turn:" ++ name) (some "catalog".toUTF8)
  let journal := {journal with head}
  let (complete,head,_) ← DB.PageMap.withWriter journal fun writer =>
    ReplayWork.bootstrap journal writer "database" "backend" 1
  check (!complete) "bootstrap ignored its window bound"
  let mut journal := {journal with head}
  for ordinal in [1:3] do
    journal ← DB.PageMap.pin journal.directory
    let (complete,head,_) ← DB.PageMap.withWriter journal fun writer =>
      ReplayWork.bootstrap journal writer "database" "backend" 1
    check (complete == (ordinal == 2)) "bootstrap restart failed to advance its exact window"
    journal := {journal with head}
  check (!(← ReplayWork.pending journal "user")) "database bootstrap leaked into user lane"
  for expected in names do
    let (ordinal,ticket) ← queued journal "database"
    check (ticket.name == expected) "bootstrap lost or duplicated a turn"
    let (complete,head,_) ← DB.PageMap.withWriter journal fun writer =>
      ReplayWork.acknowledge writer "database" ordinal ticket true
    check complete "bootstrap produced an unfinishable job"
    journal := {journal with head}
  check (!(← ReplayWork.pending journal "database")) "bootstrap enqueued duplicate jobs"
  return Json.mkObj [("windowBoundRespected",toJson true),("restartVisitsEachTurnOnce",toJson true),
    ("storageLanesIsolated",toJson true)]

private def publishAtom (source : DB.PageMap.Snapshot) (value : Value) : IO DB.PageMap.Snapshot := do
  let (_,head,_) ← DB.PageMap.withWriter source fun writer => do
    let intern : Persistence.Store.Intern := ⟨writer,← IO.mkRef {}⟩
    let id ← intern.value value
    Persistence.Store.writeChange writer {added := [],removed := [],unionsChanged := false,affected := [id]}
  return {source with head}

private def queueTickets (journal : DB.PageMap.Snapshot) (base : String) : IO (Array (Nat × ReplayWork.Ticket)) := do
  let head ← Persistence.Store.getNat journal.get (base ++ ":head")
  let tail ← Persistence.Store.getNat journal.get (base ++ ":tail")
  let mut found := #[]
  for ordinal in [head:tail] do
    let some raw ← journal.get (ReplayWork.queueKey base ordinal) | throw (IO.userError "queue has a hole")
    found := found.push (ordinal,← Index.decode raw)
  return found

private def highFanoutChecks (root : System.FilePath) : IO Json := do
  let started ← IO.monoMsNow
  let source ← Persistence.ensureSnapshot (root / "fanout-source.egg")
  let foreign ← Persistence.ensureSnapshot (root / "fanout-foreign.egg")
  let journal ← Persistence.ensureSnapshot (root / "fanout-private.egg")
  let value := Value.text "many jobs watch this exact structural bucket"
  let otherValue := Value.text "independent archive must make progress too"
  let inputs ← TurnReplay.Inputs.observe {} source value
  let otherInputs ← TurnReplay.Inputs.observe {} foreign otherValue
  let base := "private-fanout"
  let count := 4096
  let names := (List.range count).toArray.map fun i => Index.contentKey ("fanout",i)
  let foreignName := Index.contentKey "fanout-foreign-job"
  let lateName := String.ofList (List.replicate 64 '0')
  check (!names.contains lateName && !names.contains foreignName) "fixture task identities collide"
  let (_,head,_) ← DB.PageMap.withWriter journal fun writer => do
    for ordinal in [:names.size] do
      let some name := names[ordinal]? | throw (IO.userError "missing fan-out fixture task")
      ReplayWork.register writer base name inputs
      if ordinal % 128 == 127 then writer.flush
    for ordinal in [:names.size] do
      if ordinal % 4 != 0 then continue
      let some name := names[ordinal]? | throw (IO.userError "missing retired fan-out fixture task")
      ReplayWork.register writer base name {}
    ReplayWork.register writer base foreignName otherInputs
  let mut journal := {journal with head}
  check (!(← ReplayWork.pending journal base)) "registration of idle dependencies unexpectedly enqueued every job"
  let published ← publishAtom source value
  let _ ← publishAtom foreign otherValue
  let batch := 37
  let sourceCursor := ReplayWork.sourceKey base source.directory.normalize.toString
  let originalCursor ← journal.get sourceCursor
  let (expired,head,_) ← DB.PageMap.withWriter journal fun writer =>
    ReplayWork.sync journal writer base published 0 32 batch
  journal := {journal with head}
  check (!expired.complete && expired.rows == 0 && (← journal.get sourceCursor) == originalCursor &&
    !(← ReplayWork.pending journal base)) "expired sync advanced a dependency continuation"
  let mut complete := false
  let mut slices := 0
  let mut rows := 0
  let mut postings := 0
  let mut maxRows := 0
  let mut maxSliceMs := 0
  while !complete do
    check (slices < count) "bounded fan-out sync made no eventual progress"
    journal ← DB.PageMap.pin journal.directory
    let sliceStarted ← IO.monoMsNow
    let (result,head,_) ← DB.PageMap.withWriter journal fun writer => do
      ReplayWork.sync journal writer base published ((← IO.monoMsNow)+30000) 32 batch
    let elapsed := (← IO.monoMsNow)-sliceStarted
    maxSliceMs := max maxSliceMs elapsed
    check (result.rows ≤ batch && result.postings ≤ result.rows) "fan-out escaped its complete row bound"
    journal := {journal with head}
    complete := result.complete
    rows := rows+result.rows
    postings := postings+result.postings
    maxRows := max maxRows result.rows
    slices := slices+1
    if slices == 1 then
      check (!complete) "large dependency set ignored its bounded quantum"
      let cursorBefore ← journal.get sourceCursor
      let queueBefore ← queueTickets journal base
      let aborted ← try
        let _ ← DB.PageMap.withWriter (α := Unit) journal fun writer => do
          let _ ← ReplayWork.sync journal writer base published ((← IO.monoMsNow)+30000) 32 batch
          writer.flush
          throw (IO.userError "intentional partial posting transaction abort")
        pure false
        catch _ => pure true
      let reopened ← DB.PageMap.pin journal.directory
      check (aborted && reopened.head == journal.head && (← reopened.get sourceCursor) == cursorBefore &&
        (← queueTickets reopened base) == queueBefore) "partial posting abort lost the cursor/queue atomicity"
      let (_,head,_) ← DB.PageMap.withWriter reopened fun writer => ReplayWork.register writer base lateName inputs
      journal := {reopened with head}
      check ((← journal.get (ReplayWork.jobKey base lateName)).isSome)
        "a dependency inserted behind an active posting cursor was lost"
    if slices == 2 then
      check ((← journal.get (ReplayWork.jobKey base foreignName)).isSome)
        "high fan-out in one archive starved the independent archive"
  let tickets ← queueTickets journal base
  let expected := ((names.zipIdx.filterMap fun (name,i) => if i % 4 == 0 then none else some name)
    ++ #[lateName,foreignName]).qsort (· < ·)
  let actual := (tickets.map (·.2.name)).qsort (· < ·)
  check (actual == expected && rows == count+1 && postings == expected.size-1)
    "bounded continuation differs from the full live-dependency set or rescans tombstones"
  let (_,head,_) ← DB.PageMap.withWriter journal fun writer => do
    for (ordinal,ticket) in tickets do
      check (← ReplayWork.acknowledge writer base ordinal ticket true) "current queued job could not finish"
  journal := {journal with head}
  check (!(← ReplayWork.pending journal base)) "completed fan-out left duplicate queue entries"
  -- The same bounded mechanism must cover a missing/replaced source, not
  -- just ordinary publication deltas.
  IO.FS.rename source.directory (root / "retired-fanout-source.egg")
  let replacement ← Persistence.ensureSnapshot source.directory
  let mut resetComplete := false
  let mut resetRows := 0
  let mut resetSlices := 0
  while !resetComplete do
    check (resetSlices < count) "source reset made no eventual progress"
    journal ← DB.PageMap.pin journal.directory
    let (result,head,_) ← DB.PageMap.withWriter journal fun writer => do
      ReplayWork.sync journal writer base replacement ((← IO.monoMsNow)+30000) 32 batch
    check (result.rows ≤ batch) "source reset bypassed the posting bound"
    resetRows := resetRows+result.rows
    resetSlices := resetSlices+1
    resetComplete := result.complete
    journal := {journal with head}
  let resetTickets ← queueTickets journal base
  check ((resetTickets.map (·.2.name)).qsort (· < ·) == expected.filter (· != foreignName) &&
    resetRows == count+1) "bounded reset differs from all live primary-source subscribers"
  return Json.mkObj [("registeredDependencies",toJson count),("retiredDependencies",toJson (count/4)),
    ("liveTasksQueued",toJson actual.size),("visitedRowsIncludingTombstones",toJson rows),
    ("rowLimit",toJson batch),("maximumRowsPerSlice",toJson maxRows),("slices",toJson slices),
    ("maximumSliceMs",toJson maxSliceMs),("wholeCheckMs",toJson ((← IO.monoMsNow)-started)),
    ("lateRegistrationBehindCursorPreserved",toJson true),("unrelatedArchiveNotStarved",toJson true),
    ("partialPostingAbortReopensExactly",toJson true),("fullLiveSubscriberSetEqual",toJson true),
    ("replacementSourceRows",toJson resetRows),("replacementSourceSlices",toJson resetSlices),
    ("replacementSourceSubscriberSetEqual",toJson true),("expiredSyncDoesNotAdvance",toJson true)]

def main (args : List String) : IO Unit := do
  let [directory] := args | throw (IO.userError "NEW-PRIVATE-FIXTURE")
  let root := System.FilePath.mk directory
  check (root.isAbsolute && !(← root.pathExists) &&
    (← IO.getEnv "EGGSHELL_DATA_ROOT") == some (root / "data").toString) "new isolated fixture required"
  IO.FS.createDirAll root
  let queue ← queueChecks root
  let feed ← feedChecks root
  let bootstrap ← bootstrapChecks root
  let fanout ← highFanoutChecks root
  IO.FS.writeFile (root / "specimen.c") "int alpha = 1;\nint beta = 2;\n"
  let input := Json.mkObj [("command",toJson "nl -ba specimen.c | sed -n '1,2p'")]
  let capture ← SourceEvidence.capture root input ((← IO.monoMsNow)+10000)
  let response := (Json.mkObj [("output",toJson "1\tint alpha = 1;\n2\tint beta = 2;\n")]).compress
  let correspondence ← ContentCapture.finish root capture response ((← IO.monoMsNow)+10000)
  let read : ToolEvent := {
    name := "arbitrary_reader",useId := "read",input := input.compress,response,
    source := some capture,correspondence := some correspondence}
  let inspect : ToolEvent := {
    name := "mcp__fixture__inspect",useId := "inspect",input := "{\"identifier\":\"alpha\"}",response := "{}"}
  let empty ← Persistence.ensureSnapshot (root / "project.egg")
  let (first,_) ← publish empty root read "session" "seed" 0
  let (second,a) ← publish first root read "session" "analysis" 0
  let (source,b) ← publish second root inspect "session" "analysis" 1
  let calls ← IO.mkRef (0 : Nat)
  let replayed ← IO.mkRef ([] : List Journal.Replay)
  let runner : Journal.ReplayRunner := fun source values _ cache deadline => do
    calls.modify (·+1)
    let result ← Journal.replay source values deadline (some cache)
    replayed.modify (result :: ·)
    return some result
  let refresh := fun source => do
    Journal.refresh source .database ((← IO.monoMsNow)+30000) (runner := some runner)
  let initial ← refresh source
  check (initial.complete && initial.turns == 2 && initial.reused == 0 && (← calls.get) == 2)
    "initial native turn replay did not complete"
  let direct ← Journal.replay source (a ++ b) ((← IO.monoMsNow)+30000)
  check (!direct.consumed.isEmpty && !direct.usage.isEmpty) "fixture has no real consumption or usage"
  let analysis := (← replayed.get).find? (fun value => !value.consumed.isEmpty)
  check (analysis.any (fun value => value.consumed == direct.consumed && value.usage == direct.usage &&
    value.unknown == direct.unknown && value.pending == direct.pending)) "checkpoint capture changed native facts or status"
  let before ← facts source
  let unrelated : ToolEvent := {name := "mcp__fixture__unrelated",useId := "other",input := "{}",response := "{\"other\":13}"}
  let (later,_) ← publish source root unrelated "another" "unrelated" 0
  let started ← IO.monoMsNow
  let added ← refresh later
  let reuseMs := (← IO.monoMsNow)-started
  check (added.complete && added.reused == 0 && added.checked == 1 && added.turns == 1 && (← calls.get) == 3)
    "unrelated source publication replayed historical turns"
  let after ← facts later
  check (before.1.all after.1.contains && before.2 == after.2) "unrelated publication lost historical facts"
  let independent ← Journal.replay later (a ++ b) ((← IO.monoMsNow)+30000)
  check (independent.consumed == direct.consumed && independent.usage == direct.usage &&
    independent.origins == direct.origins && independent.consumers == direct.consumers &&
    independent.pending == direct.pending && independent.unknown == direct.unknown &&
    independent.ambiguousNativeUses == direct.ambiguousNativeUses)
    "independent full replay disagreed with the retained historical result"
  check (!(← Journal.required later)) "completed local checkpoint stayed dirty"
  let stable ← refresh later
  check (stable.turns == 0 && (← calls.get) == 3) "unchanged completed work replayed"
  let some shared ← Index.open? later .database .shared | throw (IO.userError "shared index missing")
  let originalFacts ← Index.allFacts shared.index
  let stripped := originalFacts.filter fun fact => match fact with | .consumed _ => false | _ => true
  check (stripped.size < originalFacts.size) "replacement control did not remove any native consumption"
  let _ ← Index.replace later .database .shared stripped
  check (← Journal.required later) "same-file full replacement was hidden by the global checkpoint"
  let reset ← refresh later
  check (reset.complete && reset.turns == 3 && reset.reused == 0 && (← calls.get) == 6 &&
    (← facts later) == after) "full replacement was not repaired exactly"
  let usagePath ← UsageCache.directory later
  IO.FS.rename usagePath (root / "retired-usage.egg")
  let _ ← UsageCache.ensure later
  check (← Journal.required later) "private cache recreation did not require replay"
  let usageReset ← refresh later
  check (usageReset.complete && usageReset.turns == 3 && (← calls.get) == 9 &&
    (← facts later) == after) "private cache recreation lost exact facts"
  let relation := (compileOperationOutcomes (.text "session") (.text "analysis") inspect).2
  let some owner ← Persistence.Store.findNode? later relation | throw (IO.userError "consumer owner missing")
  let (_,removedHead,_) ← DB.PageMap.withWriter later fun writer => do
    Persistence.Store.removeRoot writer owner
    Persistence.Store.writeChange writer {added := [],removed := [owner],unionsChanged := false}
  let removed := {later with head := removedHead}
  let missing ← refresh removed
  check (!missing.complete && missing.pending == 1 && missing.turns == 1 && missing.reused == 0 && missing.checked == 1 &&
    (← calls.get) == 10) "related membership retraction was cached or replayed unrelated work"
  let (_,restoredHead,_) ← DB.PageMap.withWriter removed fun writer => do
    let intern : Persistence.Store.Intern := ⟨writer,← IO.mkRef {}⟩
    let _ ← intern.root relation
    Persistence.Store.writeChange writer {added := [owner],removed := [],unionsChanged := false}
  let restored := {removed with head := restoredHead}
  let repaired ← refresh restored
  check (repaired.complete && repaired.turns == 1 && repaired.reused == 0 && repaired.checked == 1 && (← calls.get) == 11 &&
    (← facts restored) == after) "related restoration did not repair exactly one turn"
  let journalBefore ← Journal.open? restored
  let concurrentStart ← IO.monoMsNow
  let clients ← (List.range 80).mapM fun _ => IO.asTask (do
    let result ← refresh restored
    check (result.complete && result.turns == 0) "concurrent metadata probe replayed a completed turn") .dedicated
  for client in clients do let _ ← IO.ofExcept client.get
  let concurrentMs := (← IO.monoMsNow)-concurrentStart
  check ((← calls.get) == 11 && (← Journal.open? restored).map (·.head) == journalBefore.map (·.head))
    "concurrent reuse changed the private journal or ran an original replay"
  let readerDB ← Persistence.ensureSnapshot (root / "reader.egg")
  let archive := root / "writer.egg"
  let foreign : ToolEvent := {name := "mcp__fixture__foreign",useId := "foreign",input := "{}",response := "{\"value\":17}"}
  let waiting ← events readerDB foreign "foreign" "turn" 0 archive.toString
  for value in waiting do let _ ← Journal.append readerDB value
  let pending ← refresh readerDB
  check (!pending.complete && pending.pending == 1) "unpublished foreign observation was marked complete"
  let writerDB ← Persistence.ensureSnapshot archive
  let _ ← publish writerDB root foreign "foreign" "turn" 0
  let foreignReady ← refresh readerDB
  check (foreignReady.complete && foreignReady.turns == 1 && foreignReady.external &&
    foreignReady.pending == 0) "foreign publication was hidden by an unchanged read DB"
  let foreignStable ← refresh readerDB
  check (foreignStable.complete && foreignStable.reused == 0 && foreignStable.checked == 0 && foreignStable.turns == 0)
    "stable external dependency replayed its original body"
  let archiveSource ← DB.PageMap.pin archive
  let (archiveLater,_) ← publish archiveSource root unrelated "archive-other" "unrelated" 0
  let foreignUnrelated ← refresh readerDB
  check (foreignUnrelated.complete && foreignUnrelated.reused == 0 && foreignUnrelated.checked == 0 && foreignUnrelated.turns == 0)
    "unrelated foreign publication replayed a historical body"
  let foreignRelation := (compileOperationOutcomes (.text "foreign") (.text "turn") foreign).2
  let some foreignOwner ← Persistence.Store.findNode? archiveLater foreignRelation |
    throw (IO.userError "foreign owner missing")
  let (_,archiveRemovedHead,_) ← DB.PageMap.withWriter archiveLater fun writer => do
    Persistence.Store.removeRoot writer foreignOwner
    Persistence.Store.writeChange writer {added := [],removed := [foreignOwner],unionsChanged := false}
  let foreignRemoved ← refresh readerDB
  check (!foreignRemoved.complete && foreignRemoved.pending == 1 && foreignRemoved.turns == 1)
    "unchanged reader head hid a foreign membership retraction"
  let (_,_,_) ← DB.PageMap.withWriter {archiveLater with head := archiveRemovedHead} fun writer => do
    let intern : Persistence.Store.Intern := ⟨writer,← IO.mkRef {}⟩
    let _ ← intern.root foreignRelation
    Persistence.Store.writeChange writer {added := [foreignOwner],removed := [],unionsChanged := false}
  let foreignRestored ← refresh readerDB
  check (foreignRestored.complete && foreignRestored.turns == 1 && foreignRestored.external)
    "foreign restoration resurrected a checkpoint for removed output"
  -- Publish the same observation locally without rewriting the earlier
  -- journal's explicit foreign-archive receipt.
  let localPending : PendingTurn := {
    sessionId := "foreign",turnId := "turn",cwd := root.toString,prompt := "query",profile := "work"
    write := some readerDB.directory.toString,read := [],semanticMatcher := none,handoffChars := 500000,
    projection := .none,tools := [foreign]}
  let _ ← NativePublication.run localPending readerDB.directory true
  let localSource ← DB.PageMap.pin readerDB.directory
  let localReady ← refresh localSource
  check (localReady.complete && localReady.turns == 1 && localReady.reused == 0 && !localReady.external)
    "a former negative local nomination hid newly published local ownership"
  let journal ← Journal.prepare localSource
  let leasePath := journal.directory.parent.get! / "replay.guard"
  let lease ← FileSystem.openRead leasePath.toString
  check (← FileSystem.tryReadLock lease true) "fixture could not claim the worker lease"
  let beforeBusy ← calls.get
  let leaseStarted ← IO.monoMsNow
  let leaseMs ← try
    let newEvents ← events localSource unrelated "lease" "append" 0 localSource.directory.toString
    for value in newEvents do check (← Journal.append localSource value) "event acceptance was blocked by replay ownership"
    let busy ← refresh localSource
    check (!busy.complete && (← calls.get) == beforeBusy) "busy worker reported completion or replayed without ownership"
    pure ((← IO.monoMsNow)-leaseStarted)
    finally FileSystem.unlockRead lease
  let accepted ← refresh localSource
  check (!accepted.complete && accepted.pending == 1 && accepted.turns == 1 && (← calls.get) == beforeBusy+1)
    s!"accepted event was lost or an unpublished Post was certified: {(toJson accepted).compress}"
  let (leasePublished,_) ← publish localSource root unrelated "lease" "append" 0
  let leaseCompleted ← refresh leasePublished
  check (leaseCompleted.complete && leaseCompleted.pending == 0 && leaseCompleted.turns == 1 &&
    (← calls.get) == beforeBusy+2) "accepted event did not complete after its source publication"
  let report := Json.mkObj [("queue",queue),("feed",feed),("bootstrap",bootstrap),("fanout",fanout),
    ("nativeConsumption",toJson direct.consumed.size),("nativeUsage",toJson direct.usage.size),
    ("unrelatedPublicationHistoricalReplays",toJson (0 : Nat)),("unrelatedPublicationNewTurns",toJson added.turns),
    ("unrelatedPublicationHistoricalCheckpointsRead",toJson (added.checked-added.turns)),
    ("unrelatedRefreshMs",toJson reuseMs),("sameFactsAfterUnrelatedPublication",toJson true),
    ("independentFullReplayAndAllStatusEqual",toJson true),
    ("concurrentMetadataProbes",toJson (80 : Nat)),("concurrentMetadataProbeMs",toJson concurrentMs),
    ("concurrentMetadataProbeOriginalReplays",toJson (0 : Nat)),
    ("fullReplacementRepaired",toJson true),("privateCacheRecreationRepaired",toJson true),
    ("relatedRetractionAndRestorationSelective",toJson true),("foreignPendingThenPublished",toJson true),
    ("stableForeignOriginalNotReplayed",toJson true),("negativeLocalNominationInvalidated",toJson true),
    ("foreignUnrelatedPublicationNotReplayed",toJson true),("foreignRetractionDetectedWithoutReaderChange",toJson true),
    ("workerLeaseAllowsEventAcceptance",toJson true),("busyWorkerDoesNotClaimCompletion",toJson true),
    ("acceptedPostWaitsForSourcePublication",toJson true),
    ("eventAcceptedWhileWorkerOwnedMs",toJson leaseMs),
    ("nativeCalls",toJson (← calls.get)),("sustained80PersonWorkloadValidated",toJson false),
    ("answeringModelCalls",toJson (0 : Nat)),("adopted",toJson false)]
  IO.FS.writeFile (root / "result.json") report.pretty
  IO.println report.compress
