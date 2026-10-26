import Eggshell.SynapticTransport
open Lean Eggshell Eggshell.Synapses

private def check (valid : Bool) (reason : String) : IO Unit :=
  unless valid do throw (IO.userError reason)

private def rejected (action : IO α) : IO Bool := do
  try let _ ← action; return false catch _ => return true

private def file : File := ⟨"source.cpp",Sha256.hex "synthetic source".toUTF8,1000⟩
private def occurrence (name : String) : Occurrence := ⟨"publication-fixture","turn",name⟩
private def range (line : Nat) : Range := ⟨file,line,line⟩
private def query := Sha256.hex "synthetic query".toUTF8

private def reader (source : DB.PageMap.Snapshot) (scope : Index.Scope) : IO Index.Reader := do
  let some basis ← Index.open? source .user scope | throw (IO.userError "published index unavailable")
  return basis

private def equivalent (shared : Index.Reader) (usage : Option Index.Reader) : IO Json := do
  let some routes ← Routing.Store.open? shared | throw (IO.userError "integer projection missing from its fact commit")
  check (routes.snapshot.head == shared.index.head) "integer projection acquired a separate publication"
  let privateRoutes ← usage.mapM fun basis => do
    let some routes ← Routing.Store.open? basis | throw (IO.userError "usage delta omitted integer projection")
    return routes
  let roots := #[ (Index.Key.answer shared.manifest.source.identity "answer",7),(.query query,0)]
  let before ← IO.monoMsNow
  let walked ← Routing.Store.walk routes privateRoutes roots (before+60000)
  let elapsed := (← IO.monoMsNow)-before
  let reference ← Recommend.collect shared usage #[("answer",7)] #[] query ((← IO.monoMsNow)+60000)
    {requests := 65536,facts := 262144,bytes := 32*1024*1024}
  let actual := (Routed.preferOmissions walked.hints).map (fun hint => hint.json.compress)
  let expected := reference.admitted.map (fun offer => offer.json.compress)
  check (walked.complete && reference.complete && actual == expected)
    s!"atomic projection differs from independent original postings: {actual.size}/{expected.size}"
  return Json.mkObj [("hints",toJson actual.size),("exactOrderedHints",toJson true),
    ("elapsedMs",toJson elapsed),("nodes",toJson walked.nodes),("arcs",toJson walked.arcs),
    ("counts",toJson routes.manifest.counts),("sameHeadAsFacts",toJson true)]

private def scenario (root : System.FilePath) (population : Nat) : IO Json := do
  IO.FS.createDir root
  let source ← DB.PageMap.create (root / "source.egg") (Persistence.valueToJson (.text "authority")).compress
  let database := source.head.identity
  let a : Read := ⟨occurrence "a",range 1,⟨database,"owner-a","work-a",0,10⟩,#[]⟩
  let b : Read := ⟨occurrence "b",range 2,⟨database,"owner-b","work-b",0,10⟩,#[]⟩
  let support ← IO.ofExcept (Support.checked a a.source ⟨database,"answer",0,10⟩)
  let consumed : Consumption := {
    producer := b.occurrence,consumer := a.occurrence,producerFinish := 10,consumerStart := 20
    kind := .identifier,term := "NEEDED",inputFirst := 0,inputLimit := 6,outputFirst := 0,outputLimit := 6
    rows := #[b.source]}
  let group := Group.answer database "bulk"
  let original : Array Fact := #[.read a,.read b,.supports support,.consumed consumed,.coquoted group a.source] ++
    (Array.range population).map (fun number => .coquoted group (range (number+10)))
  let used := fun name source kind => Fact.used ⟨⟨occurrence name,0,none⟩,query,source,kind⟩
  let privateFacts := #[used "omitted" a.source .omittedThenRead,used "positive" a.source .deliveredThenCited,
    used "other-positive" b.source .deliveredThenCited]
  let started ← IO.monoMsNow
  let _ ← Index.replace source .user .shared original
  let initialMs := (← IO.monoMsNow)-started
  let _ ← Index.replace source .user .usage privateFacts
  let shared ← reader source .shared
  let usage ← reader source .usage
  let baseline ← equivalent shared (some usage)
  let some oldRoutes ← Routing.Store.open? shared | throw (IO.userError "missing old route pin")
  let oldNode ← oldRoutes.locate (.group group)
  let addition := Fact.coquoted group (range (population+20))
  -- Source fact and projection changes must both remain invisible on abort.
  check (← rejected (DB.PageMap.withWriter (α := Unit) shared.index fun writer => do
    let _ ← Index.insert writer database .shared addition
    throw (IO.userError "cancel after fact and projection writes"))) "cancelled index transaction returned success"
  check ((← reader source .shared).index.head == shared.index.head) "cancel exposed a partial projected delta"
  let deltaStart ← IO.monoMsNow
  let _ ← Index.publishDelta source .user .shared (some source.head) {added := #[addition]}
  let deltaMs := (← IO.monoMsNow)-deltaStart
  let current ← reader source .shared
  let afterAddition ← equivalent current (some usage)
  let oldAfter ← equivalent shared (some usage)
  check ((baseline.getObjValD "hints") == (oldAfter.getObjValD "hints")) "old pinned index saw a later delta"
  let some routes ← Routing.Store.open? current | throw (IO.userError "delta projection unavailable")
  check ((← routes.locate (.group group)).1 == oldNode.1) "incremental update moved an existing node handle"
  let addedBytes := current.index.head.bytes-shared.index.head.bytes
  let _ ← Index.publishDelta source .user .shared (some source.head) {added := #[addition,addition]}
  let duplicate ← reader source .shared
  check (duplicate.index.head == current.index.head) "duplicate delta wrote another source or routing publication"
  let _ ← Index.publishDelta source .user .shared (some source.head) {removed := #[addition]}
  let removed ← reader source .shared
  let afterRemoval ← equivalent removed (some usage)
  check (afterRemoval.getObjValD "hints" == baseline.getObjValD "hints") "removed fact retained routed targets"
  let _ ← Index.publishDelta source .user .shared (some source.head) {added := #[addition]}
  let readded ← reader source .shared
  let some readdedRoutes ← Routing.Store.open? readded | throw (IO.userError "re-added projection unavailable")
  check (readdedRoutes.manifest.counts.nodes == routes.manifest.counts.nodes &&
    readdedRoutes.manifest.counts.targets == routes.manifest.counts.targets)
    "re-addition reused neither stable nodes nor destinations"
  let _ ← equivalent readded (some usage)
  let feedback := used "later-omission" (range 10) .omittedThenConsumed
  let _ ← Index.publishDelta source .user .usage (some source.head) {added := #[feedback]}
  let newerUsage ← reader source .usage
  let afterFeedback ← equivalent readded (some newerUsage)
  check (usage.index.head != newerUsage.index.head) "usage feedback did not advance its private projection"
  check (← rejected (Index.publishDelta source .user .shared (some source.head) {added := #[feedback]}))
    "private usage was accepted in shared facts or integer projection"
  check (← rejected (Index.publishDelta source .database .usage none {added := #[feedback]}))
    "private usage created a projection in the project DB"
  check ((← DB.PageMap.pin source.directory).head == source.head) "derived projection mutated authoritative source"
  -- A mismatched projection seal is not an empty successful graph walk.
  let _ ← DB.PageMap.withWriter readded.index fun writer => do
    writer.put "route:implementation" (some (← Index.checkedBytes ("foreign implementation" : String)))
  let damaged ← reader source .shared
  check ((← Routing.Store.open? damaged).isNone) "foreign projection seal opened"
  let request : Recommend.Prepared := {source,shared := some damaged,usage := some newerUsage}
  let unavailable ← Routed.collect request #[("answer",0)] query ((← IO.monoMsNow)+10000) #[]
  check (!unavailable.complete && !unavailable.available && unavailable.admitted.isEmpty)
    "unprepared routing admitted hints or claimed a complete empty result"
  return Json.mkObj [("population",toJson population),("initialMs",toJson initialMs),
    ("singleFactDeltaMs",toJson deltaMs),("singleFactAppendedBytes",toJson addedBytes),
    ("baseline",baseline),("afterAddition",afterAddition),("afterRemoval",afterRemoval),
    ("afterFeedback",afterFeedback),("cancelAtomic",toJson true),("oldPinStable",toJson true),
    ("duplicateNoPublication",toJson true),("stableHandles",toJson true),("scopeRejected",toJson true)]

def main (args : List String) : IO UInt32 := do
  try
    let [destination] := args | throw (IO.userError "SynapticPublicationAudit NEW-DIRECTORY")
    let root := System.FilePath.mk destination
    check (root.isAbsolute && !(← root.pathExists)) "new absolute atomic topology fixture required"
    IO.FS.createDir root
    let mut results := #[]
    for population in [64,1024,4096] do
      let result ← scenario (root / toString population) population
      IO.println result.compress
      results := results.push result
    let report := Json.mkObj [("scenarios",toJson results),("synthetic",toJson true),
      ("answeringModelCalls",toJson (0 : Nat)),("productionAdoption",toJson false),
      ("millionWindowScaleMeasured",toJson false)]
    IO.FS.writeFile (root / "results.json") report.pretty
    return 0
  catch error => IO.eprintln error.toString; return 1
