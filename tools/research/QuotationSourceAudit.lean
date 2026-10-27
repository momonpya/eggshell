import Eggshell.SynapseBuild
open Lean Eggshell Eggshell.Synapses
open Eggshell.Synapses.Extraction Eggshell.Persistence.Store

/-- The exact previous presence-only attachment on the same prepared data.
This reference never supplies retrieval inputs or human reference ranges. -/
private def legacy (index : LiteralSearch.Index patterns)
    (spellings : Array ObservationContext.Quotation) : Array ObservationContext.Quotation := Id.run do
  let mut seen : Std.HashSet (Read × String) := {}
  let mut result := #[]
  for item in spellings do
    for hit in LiteralSearch.first index item.text do
      let text := patterns[hit.pattern]
      if seen.contains (item.read,text) then continue
      seen := seen.insert (item.read,text)
      result := result.push ⟨item.read,text,none,none⟩
  return result

private def origins (items : Array ObservationContext.Quotation) :
    Std.HashSet (Occurrence × String × String × String × String) :=
  items.foldl (fun found item => found.insert
    (item.read.occurrence,item.read.binding.database,item.read.binding.owner,item.read.binding.work,item.text)) {}

private def metrics (items : Array ObservationContext.Quotation) : Json := Id.run do
  let mut intervals : Std.HashMap (String × String) (Array (Nat × Nat)) := {}
  for item in items do
    let key := (item.read.binding.database,item.read.binding.owner)
    intervals := intervals.insert key (intervals[key]?.getD #[] |>.push
      (item.read.binding.first,item.read.binding.limit))
  let mut unionChars := 0
  for (_,spans) in intervals do
    let ordered := spans.qsort fun a b => if a.1 == b.1 then a.2 < b.2 else a.1 < b.1
    let mut cursor := 0
    for (first,limit) in ordered do
      unionChars := unionChars+(limit-max first cursor)
      cursor := max cursor limit
  return Json.mkObj [("matches",toJson items.size),
    ("originQuotePairs",toJson (origins items).size),("unionCharsByOwner",toJson unionChars),
    ("maxContextChars",toJson (items.foldl (fun n item => max n
      (item.read.binding.limit-item.read.binding.first)) 0)),
    ("over2048",toJson (items.filter (fun item => item.read.binding.limit-item.read.binding.first > 2048)).size),
    ("unmapped",toJson (items.filter (·.anchor.isNone)).size)]

def main (args : List String) : IO Unit := do
  let [output] := args | throw (IO.userError "output directory required")
  let root := System.FilePath.mk output
  unless !(← root.pathExists) do throw (IO.userError "preserve existing source audit")
  IO.FS.createDirAll root
  let source ← DB.PageMap.pin (.mk "/Users/ovm/.codex/experiments/eggshell/study-services-20261026/common-seed-1/source.egg")
  unless source.head.identity == "76352b67a9c35002bff67dc3d3c3a01b7bd194e43e09f5f54714dde75df5a8de" &&
      source.head.revision == 31 && source.head.bytes == 45216846 do throw (IO.userError "wrong fixed source")
  let started ← IO.monoMsNow
  let entries ← Build.entries source
  let topology ← Build.topology source
  let documents : Build.Documents source := ⟨← NodeReader.new source,← IO.mkRef {},← IO.mkRef {}⟩
  let mut natives : Array (Build.Entry × Document) := #[]
  let mut answers : Array (Build.Entry × Document) := #[]
  let mut metadataPresent := 0
  let mut metadataCompatible := 0
  let mut metadataAliases := 0
  for entry in entries do
    let doc ← documents.get entry.id
    if doc.native then
      natives := natives.push (entry,doc)
      if let some bytes ← source.get (ContentMetadata.ownerKey entry.id) then
        let header ← ObservedRecords.decode (α := ContentMetadata.Header) bytes
        metadataPresent := metadataPresent+1
        metadataAliases := metadataAliases+header.aliases
        if header.implementation == ContentCapture.implementation then metadataCompatible := metadataCompatible+1
    else answers := answers.push (entry,doc)
  let mut summaries := #[]
  for (entry,answer) in answers do
    let route := Build.closure topology #[entry.work]
    let .ok decoded := layout (answer.source.getD "") | throw (IO.userError "invalid stored answer")
    let patterns := hashDistinct (decoded.text.splitOn "\n\n" |>.flatMap fun paragraph =>
      (Quotes.extract paragraph).toList.map (·.text)) |>.toArray
    if patterns.isEmpty then continue
    let mut spellings := #[]
    let mut reachable := 0
    for (original,_) in natives do
      unless route.contains original.work do continue
      let catalog ← documents.catalog original.id
      spellings := spellings ++ catalog.quotations
      reachable := reachable+1
    let index := LiteralSearch.prepare patterns
    let beforeStart ← IO.monoMsNow
    let before := legacy index spellings
    IO.FS.writeFile (root / (answer.owner ++ "-before.json")) (metrics before).compress
    let beforeMs := (← IO.monoMsNow)-beforeStart
    let afterStart ← IO.monoMsNow
    let after := ObservationContext.quoteMatches index spellings
    IO.FS.writeFile (root / (answer.owner ++ "-after.json")) (metrics after).compress
    let afterMs := (← IO.monoMsNow)-afterStart
    let oldOrigins := origins before
    let newOrigins := origins after
    unless oldOrigins.size == newOrigins.size && oldOrigins.toArray.all newOrigins.contains do
      throw (IO.userError "refining quotation contexts lost an origin/Work/quoted-text pair")
    let graph ← IO.ofExcept (ObservationContext.addQuotedAnswer source.head.identity answer after {})
    let supports := graph.facts.toArray.filterMap fun fact => match fact with
      | .supports support => some support | _ => none
    unless supports.all Support.valid do throw (IO.userError "refined support is outside its stored observation")
    summaries := summaries.push (Json.mkObj [("answer",toJson answer.owner),("patterns",toJson patterns.size),
      ("reachableOriginalOwners",toJson reachable),("spellingEntries",toJson spellings.size),
      ("before",metrics before),("after",metrics after),
      ("beforeIncludingMetricsAndWriteMs",toJson beforeMs),("afterIncludingMetricsAndWriteMs",toJson afterMs),
      ("originQuotePairsPreserved",toJson true),("supportsValid",toJson true),("supports",toJson supports.size)])
  unless (← DB.PageMap.pin source.directory).head == source.head do throw (IO.userError "source changed")
  IO.FS.writeFile (root / "result.json") (Json.mkObj [("source",toJson source.head),("answers",toJson summaries),
    ("contentMetadata",Json.mkObj [("nativeOwners",toJson natives.size),("present",toJson metadataPresent),
      ("compatible",toJson metadataCompatible),("aliases",toJson metadataAliases)]),
    ("elapsedMs",toJson ((← IO.monoMsNow)-started)),("sourceUnchanged",toJson true),
    ("warmCalls",toJson (0 : Nat)),("modelCalls",toJson (0 : Nat)),("actualHook",toJson false),
    ("deliveryRecallMeasured",toJson false),("adopted",toJson false)]).pretty
  IO.println (toJson summaries).pretty
