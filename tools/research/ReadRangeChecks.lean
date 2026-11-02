import Eggshell.NativePublication

namespace Eggshell.Research.ReadRangeChecks
open Lean Eggshell.Plugin Eggshell.Synapses Eggshell.Synapses.Extraction

#print axioms ReadRangeIndex.Cell.middle
#print axioms ReadRangeIndex.Cell.overlap_candidates

private def check (ok : Bool) (message : String) : IO Unit :=
  unless ok do throw (IO.userError message)

private def ordered (rows : Array Read) : Array Read :=
  (rows.map fun row => (Index.contentKey (Fact.read row),row)).qsort (fun a b => a.1 < b.1) |>.map (·.2)

private def geometry : IO Nat := do
  let mut checks := 0
  for first in [1:100] do
    for last in [first:100] do
      let some cell := ReadRangeIndex.cell? first last | throw (IO.userError "dyadic cell construction failed")
      for point in [first,last,(first+last)/2] do
        check (point/(2^cell.level) == cell.bucket) "a stored interval escaped its coordinate cell"
        checks := checks+1
  for power in [:129] do
    let boundary := 2^power
    let first := boundary-1
    let last := boundary+1
    let some cell := ReadRangeIndex.cell? first last | throw (IO.userError "cell failed at a large binary boundary")
    check (first/(2^cell.level) == cell.bucket && boundary/(2^cell.level) == cell.bucket &&
      last/(2^cell.level) == cell.bucket) "cell truncated a coordinate above machine-word size"
    checks := checks+1
  return checks

structure OriginalFixture where
  value : Value
  document : Document
  raw : String

private def original (useId : String) : IO OriginalFixture := do
  let raw := (Json.mkObj [("text",toJson (String.ofList (List.replicate 131072 'x')))]).compress
  let tool : ToolEvent := {name := "mcp__fixture__range",useId,input := "{}",response := raw}
  let value := (compileOperationOutcomes (.text "ranges") (.text "component") tool).2
  let some edge := OutcomeEdge.fromValue? value | throw (IO.userError "fixture did not compile a native outcome")
  let document : Document := {
    owner := Persistence.selectionKey edge.relation,work := Persistence.selectionKey edge.work
    workText := Persistence.Store.text? edge.work,source := Persistence.Store.text? edge.outcome
    native := edge.observations.any (Relation.observesOutcomeWork edge.outcome edge.work)
    occurrences := Provenance.identities edge,files := #[]}
  check (document.source == some raw && document.native) "component fixture lost its literal original"
  return ⟨value,document,raw⟩

private def savedRead (source : DB.PageMap.Snapshot) (fixture : OriginalFixture)
    (first last : Nat) : Read := {
  occurrence := ⟨"ranges","component",fixture.document.occurrences[0]!.useId⟩
  source := ⟨.original (ObservationContext.originalSubject fixture.document.work fixture.raw),first,last⟩
  binding := ⟨source.head.identity,fixture.document.owner,fixture.document.work,first-1,last⟩}

private def publish (source : DB.PageMap.Snapshot) (fixture : OriginalFixture) (rows : Array Read) : IO (DB.PageMap.Snapshot × Nat) := do
  let (id,head,_) ← DB.PageMap.withWriter source fun writer => do
    let prepared ← if checked : rows.all (SourceReadView.bound writer.base.head.identity fixture.document) = true then
        pure ({rows,checked} : SourceReadView.Prepared writer.base.head.identity fixture.document)
      else throw (IO.userError "synthetic saved byte ranges are not bound to their original")
    let intern : Persistence.Store.Intern := ⟨writer,← IO.mkRef {}⟩
    let id ← intern.root fixture.value
    let _ ← SourceReadView.stage writer id fixture.document fixture.raw prepared
    Persistence.Store.writeChange writer {added := [id],removed := [],unionsChanged := false}
    return id
  return ({source with head},id)

private def compareLabels (requested : Array Range) (full selected : Array Read) : IO Unit := do
  let occurrence : Occurrence := ⟨"range-query","turn","read"⟩
  let presentations := #[#[],requested,requested.map fun range => {range with last := range.first}]
  for delivered in presentations do
    let feedback := (({delivered := {ranges := delivered}} : Feedback).start occurrence)
    let query := Sha256.hex "query".toUTF8
    let all ← IO.ofExcept (feedback.completedRead occurrence query requested (full.map (·.source)))
    let exact ← IO.ofExcept (feedback.completedRead occurrence query requested (selected.map (·.source)))
    check (all.graph.snapshot == exact.graph.snapshot) "range restriction changed read/missing-delivery labels"

def native (source : DB.PageMap.Snapshot) (root : System.FilePath) (tool : ToolEvent)
    (session turn : String) (ordinal : Nat) : IO (DB.PageMap.Snapshot × Array Journal.Entry × Journal.Knowledge) := do
  let known ← Journal.knowledge source [] false
  let occurrence : Occurrence := ⟨session,turn,tool.useId⟩
  let clock := Sha256.hex (session ++ ":" ++ turn).toUTF8
  let values : Array Journal.Entry := #[
    ⟨⟨clock,ordinal*2+1⟩,.start occurrence (canonicalToolWork tool) (Sha256.hex "query".toUTF8) known,none⟩,
    ⟨⟨clock,ordinal*2+2⟩,.finish occurrence tool.name (canonicalJson tool.input)
      (canonicalJson tool.response) (some source.directory.toString),none⟩]
  for value in values do let _ ← Journal.append source value
  let pending : PendingTurn := {
    sessionId := session,turnId := turn,cwd := root.toString,prompt := "query",profile := "work",
    write := some source.directory.toString,read := [],semanticMatcher := none,handoffChars := 500000,
    projection := .none,tools := [tool]}
  let _ ← NativePublication.run pending source.directory true
  return (← DB.PageMap.pin source.directory,values,known)

private def mcpFlow (root : System.FilePath) : IO Json := do
  let body := Json.mkObj ((List.range 2048).map fun i => (s!"field{i}",toJson s!"unique_{i}_marker"))
  let fetch : ToolEvent := {name := "mcp__fixture__fetch",useId := "seed",input := "{\"uri\":\"fixture://item\"}",response := body.compress}
  let empty ← Persistence.ensureSnapshot (root / "range-native.egg")
  let (seed,_,_) ← native empty root fetch "range-seed" "seed" 0
  let fetch := {fetch with useId := "fetch"}
  let (first,producer,known) ← native seed root fetch "range-analysis" "analysis" 0
  let inspect : ToolEvent := {name := "mcp__fixture__inspect",useId := "inspect",input := "{\"identifier\":\"unique_1000_marker\"}",response := "{}"}
  let (source,consumer,_) ← native first root inspect "range-analysis" "analysis" 1
  let cache ← StoredReadLookup.create source
  let result ← Journal.replay source (producer ++ consumer) ((← IO.monoMsNow)+30000) (some cache)
  let uses := result.usage.filterMap fun fact => match fact with
    | .used usage => if usage.kind == .omittedThenConsumed then some usage else none
    | _ => none
  check (!uses.isEmpty && result.pending == 0)
    "native structured-output consumption did not retain its genuine missing-delivery evidence"
  let wanted := uses.map (·.source)
  let subjects := wanted.foldl (fun (found : Std.HashSet Subject) range => found.insert range.subject) {}
  let excluded : Occurrence := ⟨"range-analysis","analysis","fetch"⟩
  let some all ← Journal.storedReadsAt? source known subjects excluded ((← IO.monoMsNow)+30000) |
    throw (IO.userError "native MCP pre-source is missing")
  let some selected ← Journal.storedReadsAt? source known subjects excluded ((← IO.monoMsNow)+30000) (some cache) none (some wanted) |
    throw (IO.userError "native MCP interval lookup lost its original pre-source")
  check (selected == all.filter (fun row => ReadRangeIndex.wanted wanted row.source) && selected.size < all.size &&
    (← cache.stats).getObjValD "indexed" != toJson (0 : Nat)) "native journal did not use the exact interval projection"
  let mut reference : Synapses.Graph := .empty
  let mut exact : Synapses.Graph := .empty
  let starts : Journal.Starts := ({} : Journal.Starts).insert excluded
    (Sha256.hex "query".toUTF8,known,canonicalToolWork fetch)
  let grouped := Journal.prepareFeedback source starts result.consumed .empty
  for (_,ranges) in grouped.groups do
    for (edge,range) in ranges do
      let some checked := consumedSource? edge range | continue
      reference ← IO.ofExcept (recordConsumed reference checked (Sha256.hex "query".toUTF8) (all.map (·.source)) #[])
      exact ← IO.ofExcept (recordConsumed exact checked (Sha256.hex "query".toUTF8) (selected.map (·.source)) #[])
  check (reference.snapshot == exact.snapshot && reference.snapshot == result.usage)
    "native interval lookup changed the full stored-domain consumption labels"
  return Json.mkObj [("jsonFields",toJson (2048 : Nat)),("fullStoredRows",toJson all.size),
    ("selectedStoredRows",toJson selected.size),("usageFacts",toJson result.usage.size),
    ("ambiguousNativeUses",toJson result.ambiguousNativeUses),
    ("fullDomainLabelsEqual",toJson true),("cache",← cache.stats),
    ("runtimeUsesNativeJournalProjection",toJson true),("realExternalMcpServer",toJson false)]

def run (root : System.FilePath) : IO Json := do
  let geometryChecks ← geometry
  let mcp ← mcpFlow root
  let source ← Persistence.ensureSnapshot (root / "range-source.egg")
  let fixture ← original "first"
  let mut rows := (List.range 4096).toArray.map fun index => savedRead source fixture (20+index*7) (20+index*7)
  for (first,last) in [(1,100),(17,30000),(16380,16400),(32760,32780),(65520,65540)] do
    rows := rows.push (savedRead source fixture first last)
  rows := ordered rows
  let (first,owner) ← publish source fixture rows
  let subject := (ObservationContext.originalSubject fixture.document.work fixture.raw : Original)
  let subject := Subject.original subject
  let all ← SourceReadView.reader first
  let fullStarted ← IO.monoMsNow
  let full ← all.lookup subject 100000 ((← IO.monoMsNow)+30000)
  let fullMs := (← IO.monoMsNow)-fullStarted
  check (full.complete && full.rows == rows) "component source differs from its entire saved original domain"
  let requests : Array (Array Range) := #[#[⟨subject,1000,1000⟩],#[⟨subject,30001,30001⟩],
    #[⟨subject,16382,16401⟩],#[⟨subject,32767,32769⟩],
    #[⟨subject,1000,1005⟩,⟨subject,16380,16385⟩,⟨subject,1000,1005⟩]]
  let mut records := #[]
  for wanted in requests do
    let reader ← SourceReadView.reader first
    let started ← IO.monoMsNow
    let actual ← reader.lookupRanges subject wanted 100000 ((← IO.monoMsNow)+30000)
    let ms := (← IO.monoMsNow)-started
    let expected := rows.filter (fun row => ReadRangeIndex.wanted wanted row.source)
    check (actual.complete && actual.indexed && actual.rows == expected && actual.inspected < full.inspected)
      "coordinate lookup lost a saved row, changed order, or still inspected the whole subject"
    compareLabels wanted full.rows actual.rows
    records := records.push (Json.mkObj [("requested",toJson wanted),("rows",toJson actual.rows.size),
      ("inspected",toJson actual.inspected),("probes",toJson actual.probes),("pages",toJson actual.pages),
      ("ms",toJson ms),("orderedSubsetEqual",toJson true),("allUsageLabelsEqual",toJson true)])
  let wide := #[({subject,first := 1,last := fixture.raw.length} : Range)]
  let wideReader ← SourceReadView.reader first
  let wideResult ← wideReader.lookupRanges subject wide 100000 ((← IO.monoMsNow)+30000)
  check (wideResult.complete && !wideResult.indexed && wideResult.rows == full.rows)
    "broad request did not use its cheaper exact whole-subject path"
  let emptyReader ← SourceReadView.reader source
  let before ← emptyReader.lookupRanges subject #[⟨subject,1000,1000⟩] 100000 ((← IO.monoMsNow)+30000)
  check (before.complete && before.rows.isEmpty) "coordinate lookup borrowed a future publication"
  let secondFixture ← original "second"
  check (secondFixture.document.work == fixture.document.work) "fixture changed its canonical work"
  let extra := ordered #[savedRead first secondFixture 1000 1000]
  let (second,secondOwner) ← publish first secondFixture extra
  let reader ← SourceReadView.reader second
  let delta ← reader.lookupRanges subject #[⟨subject,1000,1000⟩] 100000 ((← IO.monoMsNow)+30000)
  let expected := ordered (rows ++ extra) |>.filter (fun row => ReadRangeIndex.wanted #[⟨subject,1000,1000⟩] row.source)
  check (delta.complete && delta.indexed && delta.rows == expected) "publication delta rewrote or omitted earlier coordinate cells"
  let oldReader ← SourceReadView.reader first
  let old ← oldReader.lookupRanges subject #[⟨subject,1000,1000⟩] 100000 ((← IO.monoMsNow)+30000)
  check (old.rows == rows.filter (fun row => ReadRangeIndex.wanted #[⟨subject,1000,1000⟩] row.source))
    "a later coordinate delta changed an old source pin"
  let (_,head,_) ← DB.PageMap.withWriter second fun writer => do
    let some raw ← writer.get (SourceReadView.coordinateMeta subject) | throw (IO.userError "missing coordinate metadata")
    let metadata ← ObservedRecords.decode (α := SourceReadView.Coordinates) raw
    writer.put (SourceReadView.coordinateMeta subject) (some (toJson {metadata with complete := false}).compress.toUTF8)
    Persistence.Store.writeChange writer {added := [],removed := [],unionsChanged := false}
  let incomplete := {second with head}
  let reader ← SourceReadView.reader incomplete
  let fallbackRows ← reader.lookupRanges subject #[⟨subject,1000,1000⟩] 100000 ((← IO.monoMsNow)+30000)
  check (fallbackRows.complete && !fallbackRows.indexed && fallbackRows.rows == expected)
    "unprepared coordinate coverage was silently treated as complete"
  let (_,head,_) ← DB.PageMap.withWriter incomplete fun writer => do
    let some raw ← writer.get (SourceReadView.coordinateMeta subject) | throw (IO.userError "missing coordinate metadata")
    let metadata ← ObservedRecords.decode (α := SourceReadView.Coordinates) raw
    writer.put (SourceReadView.coordinateMeta subject) (some (toJson {metadata with complete := true}).compress.toUTF8)
    Persistence.Store.removeRoot writer owner
    Persistence.Store.writeChange writer {added := [],removed := [owner],unionsChanged := false}
  let retired := {incomplete with head}
  let reader ← SourceReadView.reader retired
  let onlySecond ← reader.lookupRanges subject #[⟨subject,1000,1000⟩] 100000 ((← IO.monoMsNow)+30000)
  check (onlySecond.complete && onlySecond.rows == extra) "retired owner retained a positive coordinate witness"
  let expired ← reader.lookupRanges subject #[⟨subject,1000,1000⟩] 100000 0
  check (!expired.complete) "expired coordinate query was reported complete"
  let (_,head,_) ← DB.PageMap.withWriter retired fun writer => do
    let row := extra[0]!
    let bad := SourceReadView.coordinateCell subject 0 1001 ++ ":" ++ row.binding.owner ++ ":" ++ Index.contentKey (Fact.read row)
    writer.put bad (some (toJson ({owner := secondOwner,ordinal := 0} : SourceReadView.Posting)).compress.toUTF8)
    Persistence.Store.writeChange writer {added := [],removed := [],unionsChanged := false}
  let corrupted := {retired with head}
  let reader ← SourceReadView.reader corrupted
  let rejected ← try
    let _ ← reader.lookupRanges subject #[⟨subject,1001,1001⟩] 100000 ((← IO.monoMsNow)+30000)
    pure false
    catch _ => pure true
  check rejected "misplaced coordinate posting escaped its original endpoint check"
  return Json.mkObj [("geometryChecks",toJson geometryChecks),("nativeMcp",mcp),("syntheticOriginalRows",toJson rows.size),
    ("fullSubjectInspected",toJson full.inspected),("fullSubjectMs",toJson fullMs),("queries",toJson records),
    ("deltaAndOldPinExact",toJson true),("broadRequestExact",toJson true),
    ("incompleteCoverageUsesFullOriginals",toJson true),("retiredOwnerExcluded",toJson true),
    ("expiredQueryIncomplete",toJson true),("misplacedCoordinateRejected",toJson true),
    ("actualHookOr80PersonWorkload",toJson false)]

end Eggshell.Research.ReadRangeChecks
