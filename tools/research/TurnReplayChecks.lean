import Eggshell.NativePublication
import Eggshell.ReplayPreparation
import Eggshell.ContractAudit

open Lean Eggshell Eggshell.Plugin Eggshell.Synapses Eggshell.Synapses.Extraction

#print axioms TurnReplay.changed_bucket_rejected

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

def main (args : List String) : IO Unit := do
  let [directory] := args | throw (IO.userError "NEW-PRIVATE-FIXTURE")
  let root := System.FilePath.mk directory
  check (root.isAbsolute && !(← root.pathExists) &&
    (← IO.getEnv "EGGSHELL_DATA_ROOT") == some (root / "data").toString) "new isolated fixture required"
  IO.FS.createDirAll root
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
  check (added.complete && added.reused == 2 && added.turns == 1 && (← calls.get) == 3)
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
  check (!missing.complete && missing.pending == 1 && missing.turns == 1 && missing.reused == 2 &&
    (← calls.get) == 10) "related membership retraction was cached or replayed unrelated work"
  let (_,restoredHead,_) ← DB.PageMap.withWriter removed fun writer => do
    let intern : Persistence.Store.Intern := ⟨writer,← IO.mkRef {}⟩
    let _ ← intern.root relation
    Persistence.Store.writeChange writer {added := [owner],removed := [],unionsChanged := false}
  let restored := {removed with head := restoredHead}
  let repaired ← refresh restored
  check (repaired.complete && repaired.turns == 1 && repaired.reused == 2 && (← calls.get) == 11 &&
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
  check (foreignStable.complete && foreignStable.reused == 1 && foreignStable.turns == 0)
    "stable external dependency replayed its original body"
  let archiveSource ← DB.PageMap.pin archive
  let (archiveLater,_) ← publish archiveSource root unrelated "archive-other" "unrelated" 0
  let foreignUnrelated ← refresh readerDB
  check (foreignUnrelated.complete && foreignUnrelated.reused == 1 && foreignUnrelated.turns == 0)
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
  let report := Json.mkObj [("nativeConsumption",toJson direct.consumed.size),("nativeUsage",toJson direct.usage.size),
    ("unrelatedPublicationHistoricalReplays",toJson (0 : Nat)),("unrelatedPublicationNewTurns",toJson added.turns),
    ("unrelatedRefreshMs",toJson reuseMs),("sameFactsAfterUnrelatedPublication",toJson true),
    ("independentFullReplayAndAllStatusEqual",toJson true),
    ("concurrentMetadataProbes",toJson (80 : Nat)),("concurrentMetadataProbeMs",toJson concurrentMs),
    ("concurrentMetadataProbeOriginalReplays",toJson (0 : Nat)),
    ("fullReplacementRepaired",toJson true),("privateCacheRecreationRepaired",toJson true),
    ("relatedRetractionAndRestorationSelective",toJson true),("foreignPendingThenPublished",toJson true),
    ("stableForeignOriginalNotReplayed",toJson true),("negativeLocalNominationInvalidated",toJson true),
    ("foreignUnrelatedPublicationNotReplayed",toJson true),("foreignRetractionDetectedWithoutReaderChange",toJson true),
    ("nativeCalls",toJson (← calls.get)),("sustained80PersonWorkloadValidated",toJson false),
    ("answeringModelCalls",toJson (0 : Nat)),("adopted",toJson false)]
  IO.FS.writeFile (root / "result.json") report.pretty
  IO.println report.compress
