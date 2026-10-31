import tools.research.BindingPageScan
import Eggshell.CanonicalSourceCache
open Lean Eggshell Eggshell.Synapses
private def ensure (ok : Bool) (message : String) : IO Unit := unless ok do throw (IO.userError message)
private def rejected (action : IO α) : IO Bool := do
  try let _ ← action; return false
  catch _ => return true

private def sample (database : String) (i : Nat) : Read :=
  let first := i*20
  let work := "work-調査"
  let source := if i%16 == 0 then
    Range.mk (.original ⟨work,String.ofList (List.replicate 64 'b'),1000000000⟩) (first+1) (first+17)
    else Range.mk (.file ⟨"解析/école🧪.cpp",String.ofList (List.replicate 64 'a'),5000000⟩) (i%4096+1) (i%4096+1)
  ⟨⟨"session-한글","turn",s!"use-{i}-α"⟩,source,⟨database,s!"owner-{i%7}",work,first,first+17⟩,
    #[String.ofList (List.replicate 64 'd')]⟩

private def normalized (wanted : Array Range) (result : IndexedBindings.Resolved) : Json :=
  toJson ((hashDistinct wanted.toList).toArray.map fun source => (source,result.rows[source]?.getD #[]))

private def expectedRows (expected : Std.HashMap Range (List (String × Read)))
    (wanted : Array Range) (allowed : Std.HashSet String) : Json := Id.run do
  let mut values := #[]
  for source in (hashDistinct wanted.toList).toArray do
    let entries := (expected[source]?.getD []).toArray.qsort fun a b => a.1 < b.1
    let mut seen : Std.HashSet Read := {}
    let mut rows := #[]
    for (_,read) in entries do
      if !allowed.contains read.binding.owner || seen.contains read then continue
      seen := seen.insert read
      rows := rows.push read
    values := values.push (source,rows)
  return toJson values

private def codecCases (database : String) : IO Json := do
  let mut encoded := 0
  let mut jsonBytes := 0
  for i in [0,1,16,127,4096] do
    let read := sample database i
    ensure read.valid "fixture Read is invalid"
    let value : Index.StoredBinding := ⟨Index.contentKey (Fact.read read),read⟩
    let bytes ← Index.bindingBytes value
    let decoded ← Index.decodeBinding bytes
    ensure (toJson decoded == toJson value) "binary binding changed fields or quotations"
    ensure (← rejected (Index.decodeBinding (bytes.push 0))) "trailing binary bytes were accepted"
    ensure (← rejected (Index.decodeBinding (bytes.extract 0 (bytes.size-1)))) "truncated binary bytes were accepted"
    encoded := encoded+bytes.size
    jsonBytes := jsonBytes+(toJson value).compress.utf8ByteSize
  return Json.mkObj [("cases",toJson (5 : Nat)),("binaryBytes",toJson encoded),("jsonBytes",toJson jsonBytes),
    ("unicodeOriginalFileAndQuotationsExact",toJson true),("truncatedAndTrailingRejected",toJson true)]

private def producerReplacement (root : System.FilePath) : IO Json := do
  let source ← DB.PageMap.create (root / "producer-source") "binding producer fixture"
  let index ← Index.prepare source .database .shared
  let fact : Fact := .read (sample source.head.identity 1)
  let some read := Index.bindingCandidate? fact | throw (IO.userError "fixture has no binding")
  let stored : Index.StoredBinding := ⟨Index.contentKey fact,read⟩
  let legacy := (toJson stored).compress.toUTF8
  let _ ← DB.PageMap.withWriter index fun writer => do
    writer.put (Index.factName fact) (some (toJson fact).compress.toUTF8)
    writer.put (Index.bindingName read.source stored.fact) (some legacy)
    writer.put "manifest" (some (toJson (⟨source.head,"prior-producer",.shared,1⟩ : Index.Manifest)).compress.toUTF8)
  let old ← DB.PageMap.pin index.directory
  let _ ← Index.replace source .database .shared #[fact]
  let current ← DB.PageMap.pin index.directory
  let some bytes ← current.get (Index.bindingName read.source stored.fact) | throw (IO.userError "rebuild lost binding")
  ensure (bytes != legacy && toJson (← Index.decodeBinding bytes) == toJson stored) "producer replacement retained incompatible payload"
  ensure ((← old.get (Index.bindingName read.source stored.fact)) == some legacy) "replacement changed an old immutable pin"
  ensure (CanonicalSource.Cache.producerDependencies.1 == Index.implementation &&
    CanonicalSource.Cache.producerDependencies.2 == PublishedPlanMetadata.implementation) "upstream producer identity is not composed"
  return Json.mkObj [("incompatibleProjectionRebuilt",toJson true),("oldPinRetained",toJson true),
    ("upstreamIndexAndCostBound",toJson true)]

def main (args : List String) : IO Unit := do
  let [rootArg,resultArg] := args | throw (IO.userError "binding trial and result required")
  let root : System.FilePath := .mk rootArg
  let output : System.FilePath := .mk resultArg
  ensure (!(← root.pathExists) && !(← output.pathExists)) "preserve binding audit"
  IO.FS.createDirAll root
  let source ← DB.PageMap.create (root / "source") "binding batch source fixture"
  let initial ← DB.PageMap.create (root / "index") "binding batch metadata fixture"
  let codec ← codecCases source.head.identity
  let replacement ← producerReplacement root
  let population := 50000
  let buildStarted ← IO.monoMsNow
  let ((expected,sources,records),_,_) ← DB.PageMap.withWriter initial fun writer => do
    let mut expected : Std.HashMap Range (List (String × Read)) := {}
    let mut sources : Array Range := #[]
    let mut seenSources : Std.HashSet Range := {}
    let mut records := 0
    for i in [:population] do
      let read := sample source.head.identity i
      ensure read.valid "large fixture Read is invalid"
      let candidates : Array Fact := if i%127 == 0 then
        let support : Support := {read,source := read.source,claim := ⟨source.head.identity,s!"answer-{i}",0,1⟩,binding := read.binding}
        #[.read read,.supports support]
        else #[.read read]
      for fact in candidates do
        ensure fact.valid "large fixture Fact is invalid"
        Index.prepareBinding writer fact
        let some projected := Index.bindingCandidate? fact | throw (IO.userError "fixture projection missing")
        expected := expected.insert projected.source ((Index.contentKey fact,projected) :: expected[projected.source]?.getD [])
        records := records+1
        if !seenSources.contains projected.source then
          seenSources := seenSources.insert projected.source
          sources := sources.push projected.source
      if i%512 == 511 then writer.flush
    writer.put "manifest" (some (toJson (⟨source.head,Index.implementation,.shared,records⟩ : Index.Manifest)).compress.toUTF8)
    return (expected,sources,records)
  let publicationMs := (← IO.monoMsNow)-buildStarted
  let index ← DB.PageMap.pin initial.directory
  let old := index
  let all := Std.HashSet.ofArray ((Array.range 7).map fun i => s!"owner-{i}")
  let someOwners := Std.HashSet.ofArray #["owner-0","owner-3"]
  let rawReader : Index.Reader := ⟨index,⟨source.head,Index.implementation,.shared,records⟩⟩
  let mut measurements := #[]
  for size in [0,1,64,512,2139] do
    let wanted := ((Array.range size).map fun i => sources[(i*37)%sources.size]!) ++
      (if size == 0 then #[] else #[⟨.file ⟨"missing.cpp",String.ofList (List.replicate 64 'c'),9⟩,1,1⟩])
    for (label,allowed) in [("all",all),("partial",someOwners),("none",({} : Std.HashSet String))] do
      let pointPool ← DB.PageMap.PagePool.new
      let batchPool ← DB.PageMap.PagePool.new
      let pointReader := {rawReader with index := ← index.sharePages pointPool "point"}
      let batchReader := {rawReader with index := ← index.sharePages batchPool "batch"}
      for repetition in [0:3] do
        let started ← IO.monoMsNow
        let point ← IndexedBindings.resolve pointReader wanted allowed (started+30000)
        let pointMs := (← IO.monoMsNow)-started
        let started ← IO.monoMsNow
        let batch ← BindingPageScan.resolveReport batchReader wanted allowed (started+30000)
        let batchMs := (← IO.monoMsNow)-started
        ensure (point.complete && batch.resolved.complete && normalized wanted point == normalized wanted batch.resolved &&
          normalized wanted point == expectedRows expected wanted allowed && point.requests == batch.resolved.requests &&
          point.inspected == batch.resolved.inspected && point.bytes == batch.resolved.bytes &&
          point.unresolved == batch.resolved.unresolved) "batch differs from ordered point lookup or publication facts"
        measurements := measurements.push (Json.mkObj [("targets",toJson wanted.size),("owners",toJson label),
          ("repetition",toJson repetition),("pointMs",toJson pointMs),("batchMs",toJson batchMs),
          ("batchPages",toJson batch.pages),("batchLeaves",toJson batch.leaves),
          ("inspected",toJson point.inspected),("orderedResultsExact",toJson true)])
  let expired ← BindingPageScan.resolveReport rawReader #[sources[0]!] all 0
  ensure (!expired.resolved.complete) "expired batch reported a completed empty result"
  let invalid : Range := ⟨.file ⟨"invalid",String.ofList (List.replicate 64 'a'),0⟩,0,0⟩
  ensure (← rejected (BindingPageScan.resolve rawReader #[invalid] all ((← IO.monoMsNow)+1000))) "invalid range accepted"
  let sharedPool ← DB.PageMap.PagePool.new
  let shared := {rawReader with index := ← index.sharePages sharedPool "shared"}
  let wanted := (Array.range 64).map fun i => sources[(i*37)%sources.size]!
  let expectedShared := expectedRows expected wanted all
  let started ← IO.monoMsNow
  let tasks ← (Array.range 80).mapM fun _ => IO.asTask (do
    let began ← IO.monoMsNow
    let result ← BindingPageScan.resolve shared wanted all (started+30000)
    ensure (result.complete && normalized wanted result == expectedShared) "shared batch changed its original results"
    return (← IO.monoMsNow)-began) .dedicated
  let latencies ← tasks.mapM fun task => do IO.ofExcept (← IO.wait task)
  let sorted := latencies.qsort (· < ·)
  let extra := sample source.head.identity (population+1)
  let _ ← DB.PageMap.withWriter index fun writer => Index.prepareBinding writer (.read extra)
  let next ← DB.PageMap.pin index.directory
  let extraStored := Index.contentKey (Fact.read extra)
  ensure ((← old.get (Index.bindingName extra.source extraStored)).isNone &&
    (← next.get (Index.bindingName extra.source extraStored)).isSome) "incremental projection changed an old pin"
  let pointCurrent : Index.Reader := {rawReader with index := next}
  let point ← IndexedBindings.resolve pointCurrent #[extra.source] all ((← IO.monoMsNow)+5000)
  let batch ← BindingPageScan.resolve pointCurrent #[extra.source] all ((← IO.monoMsNow)+5000)
  ensure (point.complete && batch.complete && normalized #[extra.source] point == normalized #[extra.source] batch)
    "one-publication delta changed batch semantics"
  let _ ← DB.PageMap.withWriter next fun writer => writer.put (Index.bindingPrefix sources[0]! ++ "bad") (some (ByteArray.mk #[255,255]))
  let corrupt : Index.Reader := {rawReader with index := ← DB.PageMap.pin index.directory}
  ensure (← rejected (BindingPageScan.resolve corrupt #[sources[0]!] all ((← IO.monoMsNow)+5000))) "corrupt metadata became a valid empty result"
  IO.FS.createDirAll output.parent.get!
  IO.FS.writeFile output (Json.mkObj [("bindingRows",toJson records),("readObservations",toJson population),
    ("sourceRanges",toJson sources.size),("publicationMs",toJson publicationMs),("codec",codec),
    ("producerReplacement",replacement),("measurements",toJson measurements),
    ("sharedTasks",toJson (80 : Nat)),("sharedP99Ms",toJson sorted[79]!),
    ("sharedMaximumMs",toJson (sorted.back?.getD 0)),("oldPinsDeltaExpiryCorruption",toJson true),
    ("bindingRowsAreNotEmbeddingWindows",toJson true),("actualHooks",toJson (0 : Nat)),
    ("answeringModelCalls",toJson (0 : Nat)),("adopted",toJson false)]).pretty
  IO.println "Lossless binding codec, complete ordered batch lookup, producer replacement, delta and shared-read checks passed"
