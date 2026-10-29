import Eggshell.SynapseJournal
import Eggshell.ContentMetadata
open Lean Eggshell Eggshell.Synapses

#print axioms SharedReadReceipt.Witness.original
#print axioms SharedReadReceipt.Witness.confirmed_key
#print axioms Journal.shared_presentation_keeps_raw_bindings
#print axioms Journal.shared_presentation_keeps_uncertainty
#print axioms Journal.unconfirmed_shared_presentation

private def check (condition : Bool) (reason : String) : IO Unit :=
  unless condition do throw (IO.userError reason)

private def fixtures (head : DB.PageMap.Head) : IO Json := do
  let file : File := ⟨"src/data.txt",String.ofList (List.replicate 64 'a'),100⟩
  let range := fun first last => (⟨file,first,last⟩ : Range)
  let stored : Read := {
    occurrence := ⟨"previous","turn","read"⟩
    source := range 10 12
    binding := ⟨head.identity,"old-owner","old-work",0,30⟩}
  check stored.valid "fixture stored read is invalid"
  let key := fun line => CanonicalSource.Delivery.rowKey ⟨file,line⟩
  let known : Journal.Knowledge := {
    source := head,indexed := none,acknowledged := [key 10,key 12,key 10],uncertain := false}
  let base : Extraction.Presentation := {bindings := #[("raw-owner",2,5)]}
  let recovered := Journal.presentationWithShared known #[stored,stored] base
  check ((SharedReadReceipt.collect known.acknowledged #[stored,stored]).size == 2 &&
      covered (range 10 10) recovered.ranges && covered (range 12 12) recovered.ranges &&
      !covered (range 11 11) recovered.ranges && !covered (range 10 12) recovered.ranges)
    "shared receipt expanded beyond acknowledged rows or counted duplicate footprints"
  check (recovered.bindings == base.bindings) "row receipt became a whole raw-output ACK"
  check ((Journal.presentationWithShared {known with uncertain := true} #[stored] base).ranges == base.ranges)
    "unconfirmed delivery supplied shared rows"
  check (!(Journal.completeKnowledge known false)) "missing pre-read index was silently promoted"
  for invalid in [["p:shared:any"],["f:locations:any"],["h:old-owner"],
      ["c:" ++ Index.contentKey file ++ ":010"],[key 0],[key 13]] do
    check ((SharedReadReceipt.collect invalid #[stored]).isEmpty) "plan, malformed or out-of-range key supplied a row"
  let changed : File := {file with fingerprint := String.ofList (List.replicate 64 'b')}
  let changedRead := {stored with source := ⟨changed,10,12⟩}
  check ((SharedReadReceipt.collect [key 10] #[changedRead]).isEmpty) "old fingerprint supplied changed file content"
  let oldKind := readKind (range 10 10) #[stored.source] #[] true
  let newKind := readKind (range 10 10) #[stored.source] recovered.ranges true
  let missingKind := readKind (range 11 11) #[stored.source] recovered.ranges true
  check (oldKind == .omittedThenRead && newKind == .reread && missingKind == .omittedThenRead)
    "shared delivery did not correct the missing/read labels independently"
  let overlapping := #[(1,4),(2,8),(10,12),(6,15),(25,26)].map fun (first,last) =>
    {stored with source := range first last}
  let allKeys := (List.range 30).map key
  let allRecovered := (SharedReadReceipt.collect allKeys overlapping).map (·.range)
  for line in List.range 30 do
    check (covered (range line line) allRecovered ==
      (decide (0 < line) && overlapping.any (fun read => read.source.contains (range line line))))
      "interval directory differs from independent original-range membership"
  return Json.mkObj [("partialRowsExact",toJson true),("duplicateFootprintsDoNotInflate",toJson true),
    ("wrongFingerprintRejected",toJson true),("locatorAndPlanRejected",toJson true),
    ("rawBindingsPreserved",toJson true),("preReadGatePreserved",toJson true),
    ("unconfirmedRejected",toJson true),("overlapMembershipExact",toJson true),
    ("oldClassification",toJson oldKind.label),("newClassification",toJson newKind.label),
    ("undeliveredClassification",toJson missingKind.label)]

private def realBody (source : DB.PageMap.Snapshot) (body : String) : IO Json := do
  let reader ← Persistence.Store.NodeReader.new source
  let mut documents := #[]
  let mut reads := #[]
  for entry in ← Build.entries source do
    let doc ← Build.document reader entry.id
    documents := documents.push doc
    if let some captured ← ContentMetadata.load? source entry.id doc then
      let catalog ← IO.ofExcept (ContentMetadata.catalog source.head.identity doc captured)
      reads := reads ++ catalog.located.map (·.read)
  let shown := Extraction.presented body documents reads
  let delivered := reads.filter fun read => read.source.file?.isSome && covered read.source shown.ranges
  check (!delivered.isEmpty) "retained real body did not verify against original reads"
  let keys := (delivered.filterMap fun read => read.source.file?.map fun file =>
    CanonicalSource.Delivery.rowKey ⟨file,read.source.first⟩).toList.eraseDups
  -- Confirmed receipt keys are simulated from independently verified actual
  -- body rows. This does not claim that a historical live event earned a label.
  let known : Journal.Knowledge := {source := source.head,indexed := none,acknowledged := keys,uncertain := false}
  let before ← Journal.presentation source known
  let after := Journal.presentationWithShared known reads before
  let priorCount := delivered.countP fun read => covered read.source before.ranges
  let afterCount := delivered.countP fun read => covered read.source after.ranges
  check (priorCount == 0 && afterCount == delivered.size) "actual shared rows did not expose and repair receipt recovery"
  check ((← DB.PageMap.pin source.directory).head == source.head) "read-only receipt audit changed the source"
  return Json.mkObj [("originalReadWitnesses",toJson delivered.size),("uniqueConfirmedRowKeys",toJson keys.length),
    ("beforeRecovered",toJson priorCount),("afterRecovered",toJson afterCount),
    ("simulatedConfirmedKeys",toJson true),("actualBodyBytesVerified",toJson true),
    ("historicalUsageLabelsMeasured",toJson false),("sourceUnchanged",toJson true)]

private def scale (head : DB.PageMap.Head) : IO (Array Json) := do
  let file : File := ⟨"any/large-source",String.ofList (List.replicate 64 'c'),10000000⟩
  let mut results := #[]
  for size in #[1000,10000,50000] do
    let reads := (Array.range size).map fun index => ({
      occurrence := ⟨"previous","turn","read" ++ toString index⟩
      source := ⟨file,index+1,index+1⟩
      binding := ⟨head.identity,"owner","work",0,1⟩} : Read)
    let keys := (Array.range ((size+24)/25)).toList.map fun index =>
      CanonicalSource.Delivery.rowKey ⟨file,index*25+1⟩
    let started ← IO.monoMsNow
    let cell ← IO.mkRef (SharedReadReceipt.collect keys reads)
    let receipts ← cell.get
    let elapsed := (← IO.monoMsNow)-started
    check (receipts.size == keys.length) "scale receipt recovery lost an acknowledged point"
    results := results.push (Json.mkObj [("storedReads",toJson size),("confirmedKeys",toJson keys.length),
      ("recovered",toJson receipts.size),("elapsedMs",toJson elapsed)])
  return results

private def cacheLifecycle (output : System.FilePath) : IO Json := do
  check ((← Paths.dataRoot) == output / "private") "usage audit needs an isolated private root"
  let source ← DB.PageMap.create (output / "usage-fixture.egg") "usage-fixture"
  let file : File := ⟨"source.txt",String.ofList (List.replicate 64 'd'),100⟩
  let old : Usage := {
    event := {occurrence := ⟨"session","turn","read"⟩,ordinal := 0}
    query := String.ofList (List.replicate 64 'e'),source := ⟨file,10,10⟩,kind := .omittedThenRead}
  let corrected := {old with kind := .reread}
  let input : UsageCache.Input := {
    session := "session",turn := "turn",source := source.head,
    view := String.ofList (List.replicate 64 'a'),count := 1}
  check old.valid "invalid persisted usage fixture"
  let _ ← Index.replace source .user .usage #[.used old]
  let some legacy ← Index.open? source .user .usage | throw (IO.userError "legacy usage cache missing")
  check (← UsageCache.open? source).isNone "new reader accepted an old classifier"
  let _ ← UsageCache.publish source input #[.used corrected]
  let some current ← UsageCache.open? source | throw (IO.userError "current usage classifier missing")
  check ((← Index.allFacts current.index) == #[.used corrected]) "corrected classification did not persist"
  check ((← Index.allFacts legacy.index) == #[.used old]) "old pinned classifier was rewritten"
  let _ ← UsageCache.publish source input #[.used corrected,.used corrected]
  let some repeated ← UsageCache.open? source | throw (IO.userError "replayed usage cache missing")
  check (repeated.manifest.facts == 1 && (← Index.allFacts repeated.index) == #[.used corrected])
    "replaying the same event inflated usage counts"
  let conflictRejected ← try
      let _ ← UsageCache.publish source input #[.used old]
      pure false
    catch _ => pure true
  check conflictRejected "one classifier relabelled its own immutable event"
  let some after ← UsageCache.open? source | throw (IO.userError "conflict removed current cache")
  check (after.index.head == repeated.index.head) "failed classification conflict published partial data"
  let found ← after.lookup (.query old.query) 100 ((← IO.monoMsNow)+5000)
  check (found.complete && found.facts == #[.used corrected]) "private usage postings differ from the corrected label"
  let changedInput := {input with count := 2}
  let _ ← UsageCache.publish source changedInput #[.used old]
  let some changed ← UsageCache.open? source | throw (IO.userError "updated scope missing")
  check (changed.manifest.facts == 1 && (← Index.allFacts changed.index) == #[.used old])
    "changed evidence appended to old classification instead of replacing it"
  check ((← Index.allFacts repeated.index) == #[.used corrected]) "scope replacement changed an old pin"
  let other : Usage := {corrected with event := {corrected.event with occurrence := ⟨"session","other","read"⟩}}
  let _ ← UsageCache.publish source {input with turn := "other"} #[.used other]
  let _ ← UsageCache.publish source {changedInput with count := 3} #[]
  let some emptied ← UsageCache.open? source | throw (IO.userError "empty scope publication missing")
  check (emptied.manifest.facts == 1 && (← Index.allFacts emptied.index) == #[.used other])
    "empty replay failed to retire its scope or erased another turn"
  let badScope ← try
      let _ ← UsageCache.publish source {input with turn := "not-this-turn"} #[.used old]
      pure false
    catch _ => pure true
  check badScope "a replay rewrote another turn's event"
  let conflictAtomic ← try
      let _ ← UsageCache.publish source {input with count := 4} #[.used corrected,.used old]
      pure false
    catch _ => pure true
  let some intact ← UsageCache.open? source | throw (IO.userError "failed replacement lost the cache")
  check (conflictAtomic && intact.index.head == emptied.index.head) "failed scope replacement changed publication"
  check ((← DB.PageMap.pin source.directory).head == source.head) "usage cache changed the source DB"
  check (!(← (source.directory / "derived").pathExists)) "usage labels entered a shared DB sidecar"
  return Json.mkObj [("legacyClassifierRejected",toJson true),("correctedLabelPersisted",toJson true),
    ("legacyPinPreserved",toJson true),("idempotentCount",toJson repeated.manifest.facts),
    ("sameClassifierConflictRejected",toJson true),("failedWriteAtomic",toJson true),
    ("changedInputReplacesScope",toJson true),("emptyScopeRetired",toJson true),
    ("otherTurnsPreserved",toJson true),("crossTurnRejected",toJson true),("replacementFailureAtomic",toJson true),
    ("postingsUseCorrectedLabel",toJson true),("sourceUnchanged",toJson true),("privateOnly",toJson true)]

private def locatorCacheLifecycle (output : System.FilePath) : IO Json := do
  let source ← DB.PageMap.create (output / "locator-fixture.egg") "locator-fixture"
  let file : File := ⟨"source.txt",String.ofList (List.replicate 64 'd'),100⟩
  let row : Read := {
    occurrence := ⟨"session","turn","old"⟩,source := ⟨file,10,10⟩,
    binding := ⟨source.head.identity,"owner","work",0,1⟩}
  let _ ← Index.replace source .database .shared #[.read row]
  let some before ← Index.openShared? source | throw (IO.userError "locator fixture index missing")
  let cache ← StoredReadLookup.create
  let deadline := (← IO.monoMsNow)+10000
  let first ← cache.lookup before row.source.subject deadline
  let second ← cache.lookup before row.source.subject deadline
  check (first == #[row] && second == first && (← cache.state.get).hits == 1 &&
      (← cache.state.get).misses == 1) "identical pinned lookup did not reuse verified locator rows"
  let additional := {row with occurrence := ⟨"session","turn","new"⟩}
  let _ ← Index.replace source .database .shared #[.read row,.read additional]
  let some after ← Index.openShared? source | throw (IO.userError "updated locator index missing")
  let changed ← cache.lookup after row.source.subject deadline
  let retained ← cache.lookup before row.source.subject deadline
  check (changed.size == 2 && changed.contains row && changed.contains additional && retained == first &&
      (← cache.state.get).misses == 2) "locator cache ignored the pinned head or invalidated an old reader"
  let uncached ← StoredReadLookup.create
  let uncached := {uncached with maxRows := 0}
  check ((← uncached.lookup after row.source.subject deadline) == changed &&
      (← uncached.lookup after row.source.subject deadline) == changed &&
      (← uncached.state.get).entries.isEmpty && (← uncached.state.get).misses == 2)
    "locator cache capacity changed lookup results"
  return Json.mkObj [("samePinReused",toJson true),("changedPinMisses",toJson true),
    ("oldPinPreserved",toJson true),("boundedCacheMatchesUncached",toJson true)]

private def replayRecovery (output : System.FilePath) : IO Json := do
  let source ← DB.PageMap.create (output / "replay-fixture.egg") "replay-fixture"
  let query := String.ofList (List.replicate 64 'f')
  let mut originals := #[]
  for number in List.range 12 do
    let entry : Journal.Entry := {
      clock := ⟨query,number+1⟩
      payload := .answer ⟨"recovery",s!"turn-{number}","answer"⟩ query "No citation."
        {source := source.head,indexed := none,acknowledged := [],uncertain := false}}
    check (← Journal.append source entry) "failed to record an immutable source event"
    originals := originals.push entry
  let first ← Journal.refresh source .database ((← IO.monoMsNow)+30000) 8
  let second ← Journal.refresh source .database ((← IO.monoMsNow)+30000) 8
  check (first.turns == 8 && !first.complete && second.turns == 4 && second.complete)
    "initial bounded journal replay did not process 8 then 4 turns"
  check (!(← Journal.required source)) "completed replay remained pending"
  let some old ← UsageCache.open? source | throw (IO.userError "replay did not initialize its derived usage cache")
  let path ← UsageCache.directory source
  check (path.toString.startsWith ((output / "private").toString ++ "/")) "refuse non-fixture cache retirement"
  IO.FS.removeDirAll path
  check (← Journal.required source) "missing derived cache was hidden by old journal checkpoints"
  let recoveredFirst ← Journal.refresh source .database ((← IO.monoMsNow)+30000) 8
  let recoveredSecond ← Journal.refresh source .database ((← IO.monoMsNow)+30000) 8
  check (recoveredFirst.turns == 8 && !recoveredFirst.complete &&
      recoveredSecond.turns == 4 && recoveredSecond.complete)
    "cache recreation skipped unreplayed turns because of old per-turn checkpoints"
  let some recreated ← UsageCache.open? source | throw (IO.userError "recreated usage cache missing")
  check (old.index.head.identity != recreated.index.head.identity) "fixture did not actually recreate the derived cache"
  check (!(← Journal.required source)) "recovered replay did not close its debt"
  let some journal ← Journal.open? source | throw (IO.userError "original journal was lost")
  check ((← Persistence.Store.getNat journal.get "count") == originals.size) "replay added or removed original events"
  for index in List.finRange originals.size do
    check ((← Journal.entry journal index.val) == originals[index]) "replay rewrote immutable original evidence"
  check ((← DB.PageMap.pin source.directory).head == source.head) "journal recovery changed the source DB"
  return Json.mkObj [("turns",toJson originals.size),("initialBatches",toJson #[first.turns,second.turns]),
    ("recoveryBatches",toJson #[recoveredFirst.turns,recoveredSecond.turns]),
    ("derivedIdentityChanged",toJson true),("allOriginalEntriesExact",toJson true),
    ("replayDebtClosed",toJson true),("sourceUnchanged",toJson true)]

def main (args : List String) : IO Unit := do
  let [destination] := args | throw (IO.userError "SharedReadReceiptAudit NEW-DIRECTORY")
  let output := System.FilePath.mk destination
  check (!(← output.pathExists)) "preserve previous receipt audit"
  IO.FS.createDir output
  let study : System.FilePath := "/Users/ovm/.codex/experiments/eggshell/scope-token-study-20261028"
  let source ← DB.PageMap.pin (study / "r0/stage1/history/source.egg")
  let bodyPath : System.FilePath := "/Users/ovm/.codex/worktrees/hook-deadline-baseline/eggshell/docs/candidates/anchored-capture/hook/body.txt"
  let tested ← fixtures source.head
  IO.FS.writeFile (output / "fixtures.json") tested.pretty
  let actual ← realBody source (← IO.FS.readFile bodyPath)
  IO.FS.writeFile (output / "actual-body.json") actual.pretty
  let times ← scale source.head
  let persistence ← cacheLifecycle output
  let locators ← locatorCacheLifecycle output
  let recovery ← replayRecovery output
  let report := Json.mkObj [("fixtures",tested),("realBody",actual),("scale",toJson times),
    ("persistence",persistence),("locators",locators),("recovery",recovery),
    ("answeringModelCalls",toJson (0 : Nat)),("actualHookCalls",toJson (0 : Nat)),
    ("productionAdoption",toJson false),("goalAchieved",toJson false)]
  IO.FS.writeFile (output / "result.json") report.pretty
  IO.println report.compress
