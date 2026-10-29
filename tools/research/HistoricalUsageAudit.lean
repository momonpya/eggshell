import Eggshell.SynapseJournal
open Lean Eggshell Eggshell.Synapses

private def check (value : Bool) (message : String) : IO Unit :=
  unless value do throw (IO.userError message)

def main (args : List String) : IO Unit := do
  let [destination] := args | throw (IO.userError "new report path required")
  let output := System.FilePath.mk destination
  check (!(← output.pathExists)) "preserve historical replay evidence"
  let study : System.FilePath := "/Users/ovm/.codex/experiments/eggshell/scope-token-study-20261028"
  check ((← Paths.dataRoot) == study / "study/seed-2/data") "historical audit needs the original read-only cache root"
  let frozen ← DB.PageMap.pin (study / "r0/stage1/history/source.egg")
  let source ← DB.PageMap.pin (study / "study/seed-2/work.egg")
  check (source.head == frozen.head) "original DB differs from the frozen source snapshot"
  let some journal ← Journal.open? source | throw (IO.userError "original native journal missing")
  let count ← Persistence.Store.getNat journal.get "count"
  let hint ← Journal.preparedHint? source
  let mut entries := #[]
  let mut starts := 0
  let mut recordedIndexes := 0
  let mut readableIndexes := 0
  let mut startsWithSharedKeys := 0
  let mut sharedKeys := 0
  let mut uncertain := 0
  let mut preparedStarts := 0
  let mut rejected : Std.HashMap String Nat := {}
  for ordinal in List.range count do
    let entry ← Journal.entry journal ordinal
    entries := entries.push entry
    if let .start _ _ _ known := entry.payload then
      starts := starts+1
      if known.indexed.isSome then recordedIndexes := recordedIndexes+1
      if let some selected ← Journal.readIndex? source known hint then
        if selected.origin == .prepared then preparedStarts := preparedStarts+1
      if (← Journal.indexAt? source known).isSome then readableIndexes := readableIndexes+1
      else if let some saved := known.indexed then
        let current ← DB.PageMap.open? (← Index.directory source saved.storage .shared)
        let reason : String ← match current with
          | none => pure "index_files_missing"
          | some current =>
            if current.head.identity != saved.head.identity || current.head.authority != saved.head.authority ||
                saved.head.bytes > current.head.bytes then pure "saved_index_not_retained"
            else do
              let metadata ← Index.manifest? {current with head := saved.head}
              match metadata with
              | none => pure "saved_manifest_missing"
              | some metadata =>
                if metadata.implementation != saved.producer then pure "saved_producer_mismatch"
                else if saved.producer != Index.implementation then pure "historical_producer_rejected"
                else pure "saved_source_validation_rejected"
        rejected := rejected.insert reason (rejected[reason]?.getD 0 + 1)
      if known.uncertain then uncertain := uncertain+1
      let keys := known.acknowledged.filter (·.startsWith "c:")
      if !keys.isEmpty then startsWithSharedKeys := startsWithSharedKeys+1
      sharedKeys := sharedKeys+keys.length
  let legacy ← Index.open? source .user .usage
  let persisted ← DB.PageMap.open? (← Index.directory source .user .usage)
  let oldFacts ← match persisted with
    | none => pure #[]
    | some persisted => do
      let some metadata ← Index.manifest? persisted | throw (IO.userError "persisted usage has no manifest")
      check (metadata.scope == .usage && metadata.source.identity == source.head.identity &&
        metadata.source.authority == source.head.authority) "persisted private usage has a foreign source"
      Index.allFacts persisted
  let started ← IO.monoMsNow
  let readCache ← StoredReadLookup.create
  let replayed ← Journal.replay source entries (started+60000) none (some readCache)
  let cacheState ← readCache.state.get
  let classify := fun (facts : Array Fact) (kind : UsageKind) => facts.foldl (fun count fact => match fact with
    | .used usage => count + if usage.kind == kind then 1 else 0
    | _ => count) (0 : Nat)
  let comparisons := replayed.usage.filterMap fun fact => match fact with
    | .used current => oldFacts.findSome? fun previous => match previous with
      | .used old => if old.event == current.event then some (old,current) else none
      | _ => none
    | _ => none
  let changed := comparisons.filter (fun (old,current) => old != current)
  let uncaptured := entries.foldl (fun known entry => match entry.payload with
    | .start occurrence _ _ input => if input.indexed.isNone then known.insert occurrence else known
    | _ => known) ({} : Std.HashSet Occurrence)
  let sourceOnlyLabels := replayed.usage.filter (fun fact => match fact with
    | .used value => uncaptured.contains value.event.occurrence
    | _ => false)
  let sourceAfter ← DB.PageMap.pin source.directory
  let journalAfter ← DB.PageMap.pin journal.directory
  check (sourceAfter.head == source.head && journalAfter.head == journal.head)
    "read-only historical replay changed source or journal"
  let mut kinds := #[]
  for kind in [UsageKind.omittedThenRead,.omittedThenConsumed,.deliveredThenCited,.reread,.sourceChanged] do
    kinds := kinds.push (Json.mkObj [("kind",toJson kind.label),
      ("persisted",toJson (classify oldFacts kind)),("replayed",toJson (classify replayed.usage kind))])
  let report := Json.mkObj [
    ("source",toJson source.head),("journal",toJson journal.head),("entries",toJson count),
    ("starts",toJson starts),("recordedPreReadIndexes",toJson recordedIndexes),
    ("readablePreReadIndexes",toJson readableIndexes),("uncertainStarts",toJson uncertain),
    ("preparedHintStarts",toJson preparedStarts),("labelsWithoutCapturedIndex",toJson sourceOnlyLabels.size),
    ("preReadIndexRejections",toJson (rejected.toArray.qsort (fun a b => a.1 < b.1))),
    ("startsWithSharedRowKeys",toJson startsWithSharedKeys),("acknowledgedSharedKeys",toJson sharedKeys),
    ("legacyUsageIndexAvailable",toJson legacy.isSome),("kinds",Json.arr kinds),
    ("matchedPersistedEvents",toJson comparisons.size),("changedPersistedEvents",toJson changed.size),
    ("pending",toJson replayed.pending),("unknown",toJson replayed.unknown),
    ("elapsedMs",toJson ((← IO.monoMsNow)-started)),
    ("lookupCacheHits",toJson cacheState.hits),("lookupCacheMisses",toJson cacheState.misses),
    ("lookupCacheRows",toJson cacheState.rows),("lookupCacheBytes",toJson cacheState.bytes),
    ("usageDigest",toJson (Index.contentKey (replayed.usage.map Index.contentKey |>.qsort (· < ·)))),
    ("sourceAndRawJournalUnchanged",toJson true),("actualHookCalls",toJson (0 : Nat)),
    ("originalIndexLocationUsed",toJson true),("frozenSourceHeadExact",toJson true),
    ("answeringModelCalls",toJson (0 : Nat)),("adopted",toJson false)]
  IO.FS.writeFile output report.pretty
  IO.println report.compress
