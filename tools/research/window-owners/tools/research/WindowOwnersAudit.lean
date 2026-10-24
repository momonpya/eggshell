import Eggshell.WindowOwners
import Eggshell.PluginModel
import Lean

open Lean Eggshell Eggshell.DB Eggshell.Persistence.Store

private def check (condition : Bool) (message : String) : IO Unit :=
  unless condition do throw (IO.userError message)

private def failed (action : IO α) : IO Bool := do
  try let _ ← action; return false catch _ => return true

open Lean in
run_meta do
  for name in #[``WindowOwners.occurrence_roundtrip, ``WindowOwners.entries_original,
      ``WindowOwners.lookup_rows_bounded, ``WindowOwners.Slice.consume_conserves] do
    for axiomName in ← Lean.collectAxioms name do
      unless #[``propext, ``Classical.choice, ``Quot.sound].contains axiomName do
        throwError "Unapproved window-owner axiom: {name}, {axiomName}"
  logInfo "Audited original window identity, codec and nomination row allowance"

private def outcome (name : String) : IO Value :=
  IO.ofExcept (Plugin.relation? .outcome [
    .semantic (.text ("timer question "++name)),
    .semantic (.text ("timer observation "++name++" "++String.ofList (List.replicate 1100 'x')))])

private def publish (source : Snapshot) (values : List Value) (removed : List Nat := []) : IO Snapshot := do
  let _ ← PageMap.withWriter source fun writer => do
    for id in removed do removeRoot writer id
    let intern : Intern := ⟨writer,← IO.mkRef {}⟩
    let ids ← values.mapM intern.root
    writeChange writer ⟨ids,removed,false⟩
  PageMap.pin source.directory

private def ordered (rows : List (String × WindowOwners.Occurrence)) :=
  rows.mergeSort (fun a b => WindowOwners.postingKey a.1 a.2 ≤ WindowOwners.postingKey b.1 b.2)

private def oracle (source : Snapshot) : IO (List (String × WindowOwners.Occurrence)) := do
  ordered <$> WindowOwners.documentEntries source (← searchDocuments source)

private def compareOriginal (source : Snapshot) (ready : WindowOwners.Ready) : IO Unit := do
  let expected ← oracle source
  let keys := hashDistinct (expected.map Prod.fst)
  let got ← WindowOwners.lookup ready keys 8192
  check (got.val.partialKeys.isEmpty && ordered got.val.occurrences == expected)
    "index differs from the complete original owner/window enumeration"
  let resolved ← WindowOwners.resolve source got.val
  check (resolved.length == (hashDistinct (expected.map (·.2.owner))).length)
    "original nomination validation changed owners"

private def scenario (output : System.FilePath) : IO Json := do
  let source ← PageMap.create (output / "source.egg") (Persistence.valueToJson (.text "test-authority")).compress
  let values ← (List.range 70).mapM (fun n => outcome (toString n))
  let source ← publish source values
  check ((← WindowOwners.openShared? source).isNone) "cold index was accepted"
  let prepared ← WindowOwners.refresh source .user
  check (prepared.mode == "full-source" && prepared.changedOwners == 70) "initial preparation lost owners"
  let some ready ← WindowOwners.openShared? source | throw (IO.userError "prepared window owners missing")
  compareOriginal source ready
  let repeated ← WindowOwners.refresh source .user
  check (repeated.mode == "warm" && repeated.writtenBytes == 0) "unchanged index was rewritten"
  let expected ← oracle source
  let common := expected.find? fun row => (expected.filter (·.1 == row.1)).length > 64
  let some (key,_) := common | throw (IO.userError "fixture needs a high-fanout window")
  ready.snapshot.cache.set {}
  ready.snapshot.reads.set 0
  let limited ← WindowOwners.lookup ready [key] 1
  let limitedReads ← ready.snapshot.reads.get
  check (limited.val.physicalRows == 1 && limited.val.occurrences.length == 1 &&
    limited.val.partialKeys == [key] && limitedReads ≤ 8)
    "bounded nomination scanned the whole fanout or claimed complete coverage"
  let zero ← WindowOwners.lookup ready [key] 0
  check (zero.val.physicalRows == 0 && zero.val.visitedKeys == 0 && zero.val.partialKeys == [key])
    "zero allowance became a complete empty result"
  check (← failed (WindowOwners.lookup ready [key] 8193)) "excess row allowance accepted"
  check (← failed (WindowOwners.lookup ready [key,key] 8)) "duplicate keys spent a second allowance"
  check (← failed (WindowOwners.lookup ready ["../not-a-window"] 8)) "foreign window key accepted"
  let absent := Sha256.hex "absent-window".toUTF8
  let empty ← WindowOwners.lookup ready [absent] 8
  check (empty.val.occurrences.isEmpty && empty.val.partialKeys.isEmpty && empty.val.visitedKeys == 1)
    "authenticated absent window became unavailable"
  let forged := {limited.val with occurrences := limited.val.occurrences.map fun (key,row) =>
    (key,{row with position := row.position+10000})}
  check (← failed (WindowOwners.resolve source forged)) "invented original position was trusted"
  let _ ← PageMap.withWriter source fun writer => do
    writer.put "memo:window-owner-test" (some "derived".toUTF8)
    writeChange writer ⟨[],[],false⟩
  let memo ← PageMap.pin source.directory
  check (← (WindowOwners.openShared? memo).map Option.isSome) "neutral publication invalidated nominations"
  let neutral ← WindowOwners.refresh memo .user
  check (neutral.mode == "publication-delta" && neutral.changedOwners == 0 &&
    neutral.added == 0 && neutral.removed == 0) "neutral refresh enumerated original windows"
  let extra ← outcome "new-owner"
  let appended ← publish memo [extra]
  check ((← WindowOwners.openShared? appended).isNone) "changed source used an incomplete index"
  appended.trace.set (some {})
  let delta ← WindowOwners.refresh appended .user
  let trace ← appended.trace.get
  check (delta.mode == "publication-delta" && delta.changedOwners == 1 && delta.removed == 0 && delta.added > 0 &&
    trace.any (fun trace => trace.complete && trace.operations.all fun operation => match operation with
      | .range .. => false
      | _ => true)) "owner addition scanned the source catalogue"
  appended.trace.set none
  let some current ← WindowOwners.openShared? appended | throw (IO.userError "updated window owners missing")
  compareOriginal appended current
  let some removed := expected.head? | throw (IO.userError "empty fixture")
  let retracted ← publish appended [] [removed.2.owner]
  check ((← WindowOwners.openShared? retracted).isNone) "retracted source used old coverage"
  let withdrawal ← WindowOwners.refresh retracted .user
  check (withdrawal.mode == "publication-delta" && withdrawal.changedOwners == 1 &&
    withdrawal.removed > 0 && withdrawal.added == 0) "retraction was not incremental"
  let some withdrawn ← WindowOwners.openShared? retracted | throw (IO.userError "retracted index missing")
  compareOriginal retracted withdrawn
  compareOriginal source ready
  check (← failed (WindowOwners.resolve retracted
    {limited.val with occurrences := [removed]})) "withdrawn source owner was authoritative"
  let _ ← PageMap.withWriter withdrawn.snapshot fun writer =>
    writer.put (WindowOwners.postingKey removed.1 removed.2) (some ⟨#[255]⟩)
  let some corrupt ← WindowOwners.openShared? retracted | throw (IO.userError "corrupt fixture header missing")
  check (← failed (WindowOwners.lookup corrupt [removed.1] 8192)) "malformed posting was accepted as a miss"
  compareOriginal retracted withdrawn
  let other ← PageMap.create (output / "other.egg") (Persistence.valueToJson (.text "test-authority")).compress
  let other ← publish other values
  check ((← WindowOwners.openShared? other).isNone) "another DB inherited an index from equal local IDs"
  let separate ← Sidecar.withIndexClaim (Sidecar.Owner.ofSnapshot retracted) (fun _ => do
    check (← failed (WindowOwners.refresh retracted .user)) "competing index writer did not respect its claim"
    WindowOwners.refresh other .user) .user
  check (separate.mode == "full-source" && separate.changedOwners == 70) "one DB's claim blocked another DB"
  let some otherReady ← WindowOwners.openShared? other | throw (IO.userError "second DB index missing")
  check (otherReady.snapshot.directory != ready.snapshot.directory &&
    otherReady.manifest.source.identity != ready.manifest.source.identity) "DB scopes were collapsed"
  compareOriginal other otherReady
  return Json.mkObj [("originalOwners",toJson 70),("originalOccurrences",toJson expected.length),
    ("fullOriginalOracleEqual",toJson true),("physicalFanoutBound",toJson true),
    ("limitedPageReads",toJson limitedReads),("emptyDistinctFromUnavailable",toJson true),
    ("unpublishedAndWithdrawnPositionsRejected",toJson true),("neutral",toJson neutral),
    ("addition",toJson delta),("retraction",toJson withdrawal),
    ("oldPinnedIndexPreserved",toJson true),("malformedPostingRejected",toJson true),
    ("busyWriterRejected",toJson true),("otherDatabaseIndependent",toJson true)]

def main (args : List String) : IO Unit := do
  match args with
  | ["fixture",output] =>
    let output := System.FilePath.mk output
    check (!(← output.pathExists)) "preserve earlier fixture"
    FileSystem.privateDirectory output
    let result ← scenario output
    IO.FS.writeFile (output / "result.json") result.pretty
    IO.println result.compress
  | ["prepare",database,output] =>
    let source ← PageMap.pin (.mk database)
    let result ← WindowOwners.refresh source .user
    let repeated ← WindowOwners.refresh source .user
    let some ready ← WindowOwners.openShared? source | throw (IO.userError "prepared reverse index missing")
    let result := Json.mkObj [("source",toJson source.head),("prepared",toJson result),
      ("repeated",toJson repeated),("index",toJson ready.snapshot.head)]
    IO.FS.writeFile (.mk output) result.pretty
    IO.println result.compress
  | ["query",database,request,output] =>
    let request ← IO.ofExcept (Json.parse (← IO.FS.readFile (.mk request)))
    let documents ← IO.ofExcept (request.getObjValAs? (Array Json) "documents")
    let mut keys := []
    let mut expectedOwners := []
    for document in documents do
      keys := keys ++ (← IO.ofExcept (document.getObjValAs? (List String) "windows"))
      expectedOwners := (← IO.ofExcept (document.getObjValAs? Nat "id")) :: expectedOwners
    keys := hashDistinct keys
    let source ← PageMap.pin (.mk database)
    source.trace.set (some {})
    let start ← IO.monoMsNow
    let some ready ← WindowOwners.openShared? source | throw (IO.userError "window-owner index unavailable")
    let opened ← IO.monoMsNow
    let prefixTrace ← source.trace.get
    check (prefixTrace.any (fun trace => trace.complete && trace.operations.all fun operation => match operation with
      | .range .. => false
      | _ => true)) "opening the index scanned the original source domain"
    let result ← WindowOwners.lookup ready keys 8192
    let lookedUp ← IO.monoMsNow
    let resolved ← WindowOwners.resolve source result.val
    let done ← IO.monoMsNow
    let trace ← source.trace.get
    check (result.val.partialKeys.isEmpty && resolved.length == expectedOwners.length &&
      (resolved.map (·.owner)).mergeSort == expectedOwners.mergeSort)
      "key-only lookup lost original routed owners"
    -- The product's memo trace deliberately stops at 64 KiB. Never interpret
    -- that overflow as evidence of either a full scan or its absence. Audit
    -- every owner separately after the timed call, retaining the same strict
    -- trace limit and the actual original-position resolver.
    let mut groups : Std.HashMap Nat (List (String × WindowOwners.Occurrence)) := {}
    for row in result.val.occurrences do
      groups := groups.insert row.2.owner (row :: groups.getD row.2.owner [])
    let mut largestTrace := 0
    let auditStarted ← IO.monoMsNow
    for (_,rows) in groups.toList do
      source.trace.set (some {})
      let _ ← WindowOwners.resolve source {result.val with occurrences := rows.reverse}
      let some part ← source.trace.get | throw (IO.userError "missing original owner audit trace")
      check (part.complete && part.operations.all fun operation => match operation with
        | .range .. => false
        | _ => true) "owner validation scanned a source directory or exhausted its trace"
      largestTrace := max largestTrace part.encodedBytes
    let auditMs := (← IO.monoMsNow)-auditStarted
    let result := Json.mkObj [("source",toJson source.head),("keys",toJson keys.length),
      ("indexOpenMs",toJson (opened-start)),("lookupMs",toJson (lookedUp-opened)),
      ("originalValidationMs",toJson (done-lookedUp)),("totalMs",toJson (done-start)),
      ("lookup",toJson result.val),("resolvedOwners",toJson (resolved.map (·.owner))),
      ("originalReads",toJson (← source.reads.get)),("indexReads",toJson (← ready.snapshot.reads.get)),
      ("unsegmentedTraceComplete",toJson (trace.any (·.complete))),
      ("separateTraceAuditOwners",toJson groups.size),("largestOwnerTraceBytes",toJson largestTrace),
      ("separateTraceAuditMs",toJson auditMs),
      ("noOriginalCatalogueScan",toJson true),("adopted",toJson false)]
    IO.FS.writeFile (.mk output) result.pretty
    IO.println (Json.mkObj [("keys",toJson keys.length),("resolvedOwners",toJson resolved.length),
      ("totalMs",toJson (done-start)),("noOriginalCatalogueScan",toJson true)]).compress
  | ["full-check",database,output] =>
    let source ← PageMap.pin (.mk database)
    let expected ← oracle source
    let some ready ← WindowOwners.openShared? source | throw (IO.userError "window-owner index unavailable")
    let mut remaining := hashDistinct (expected.map Prod.fst)
    let mut found := []
    let mut batches := 0
    let start ← IO.monoMsNow
    while !remaining.isEmpty do
      let selected := remaining.take 2048
      remaining := remaining.drop 2048
      let rows ← WindowOwners.lookup ready selected 8192
      check rows.val.partialKeys.isEmpty "full audit encountered bounded fanout; preserve its partial result"
      found := rows.val.occurrences.reverse ++ found
      batches := batches+1
    let elapsed := (← IO.monoMsNow)-start
    found := ordered found.reverse
    check (expected == found && expected.length == ready.manifest.occurrences)
      "full reverse postings disagree with original positions or complete coverage"
    let result := Json.mkObj [("source",toJson source.head),("occurrences",toJson found.length),
      ("batches",toJson batches),("lookupMs",toJson elapsed),
      ("originalDigest",toJson (Sha256.hex (toJson expected).compress.toUTF8)),
      ("indexDigest",toJson (Sha256.hex (toJson found).compress.toUTF8)),
      ("allOriginalOccurrencesEqual",toJson true),("scope",toJson "offline full-index audit, not foreground/native")]
    IO.FS.writeFile (.mk output) result.pretty
    IO.println result.compress
  | _ => throw (IO.userError "WindowOwnersAudit fixture OUT | prepare DB OUT | query DB REQUEST OUT")
