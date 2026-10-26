import Eggshell.NativePublication

open Lean Eggshell Eggshell.Plugin Eggshell.Synapses
open Eggshell.Plugin.NativePublication

private def check (condition : Bool) (message : String) : IO Unit :=
  unless condition do throw (IO.userError message)

private def reject (action : IO α) (message : String) : IO Unit := do
  let rejected ← try let _ ← action; pure false catch _ => pure true
  check rejected message

private def domain : String := String.ofList (List.replicate 64 'a')
private def occurrence (tool : ToolEvent) : Occurrence := ⟨"native-publication","turn",tool.useId⟩

private def pending (path : System.FilePath) (tools : List ToolEvent) : PendingTurn := {
  sessionId := "native-publication",turnId := "turn",cwd := path.parent.get!.toString
  prompt := "inspect the recorded source and remote evidence",profile := "work"
  semanticMatcher := none,read := [path.toString],write := some path.toString
  handoffChars := 120000,projection := .none,tools }

private def tool (name id : String) (input response : Json) : ToolEvent :=
  ⟨name,id,input.compress,response.compress,none⟩

private def entries (source : DB.PageMap.Snapshot) (tool : ToolEvent) (time : Nat) :
    IO (Journal.Entry × Journal.Entry) := do
  let known : Journal.Knowledge := ⟨source.head,none,[],false,none,none⟩
  return (⟨⟨domain,time⟩,.start (occurrence tool) (canonicalToolWork tool)
      (Sha256.hex "query".toUTF8) known,some 1000⟩,
    ⟨⟨domain,time+10⟩,.finish (occurrence tool) tool.name (canonicalJson tool.input)
      (canonicalJson tool.response) none,some 1010⟩)

private def observed (source : DB.PageMap.Snapshot) (tools : List ToolEvent) : IO Unit := do
  let reader ← Persistence.Store.NodeReader.new source
  let origins ← Provenance.records source
  check (origins.size == tools.length) "source receipt lost an original interval"
  for tool in tools do
    let edge := (compileOperationOutcomes (.text "native-publication") (.text "turn") tool).2
    let some edge := OutcomeEdge.fromValue? edge | throw (IO.userError "invalid fixture owner")
    let some origin ← Provenance.lookup? source edge (occurrence tool) |
      throw (IO.userError "acknowledged original has no native interval")
    let doc ← Provenance.checkedDocument reader origin
    check (doc.source == some (canonicalJson tool.response) &&
      doc.workText == some (canonicalToolWork tool)) "acknowledged original bytes changed"
    let some normalized ← ObservedRecords.load? source origin.owner doc |
      throw (IO.userError "ACK omitted its original record directory")
    check (normalized.reads.all (·.source.file?.isNone)) "a generic record fabricated a file alias"
    let raw := doc.source.getD ""
    if !raw.isEmpty then
      check (covered (Range.original (ObservationContext.originalSubject doc.work raw) 0 raw.length)
        (normalized.reads.map (·.source))) "stored original records omitted raw characters"
    for located in normalized.located do
      check (located.text == String.ofList ((raw.toList.drop located.read.binding.first).take
        (located.read.binding.limit-located.read.binding.first))) "stored record changed its original payload"

private def copySource (source : DB.PageMap.Snapshot) (target : System.FilePath) : IO Unit := do
  IO.FS.createDir target
  for item in ← source.directory.readDir do
    if item.fileName == "head" || item.fileName.endsWith ".pages" then
      IO.FS.writeBinFile (target / item.fileName) (← IO.FS.readBinFile item.path)
  IO.FS.writeBinFile (target / "writer") ByteArray.empty

private def wireChecks (source : SourceReceipt) : IO Unit := do
  let saved : SaveReply := .published ⟨source,false⟩
  check ((SaveReply.check? (toJson saved)).isOk) "valid source ACK was rejected"
  let invalid : SaveReply := .published ⟨{source with observations := source.observations+1},true⟩
  check (!(SaveReply.check? (toJson invalid)).isOk) "forged source coverage was accepted"
  let .published decoded ← IO.ofExcept (SaveReply.check? (toJson saved)) |
    throw (IO.userError "source ACK changed its kind")
  check (!decoded.preparationQueued && decoded.publication.complete)
    "source publication was made conditional on background preparation"

private def fixture (root : System.FilePath) : IO Unit := do
  check (root.isAbsolute && !(← root.pathExists)) "new absolute test directory required"
  IO.FS.createDir root
  let path := root / "source.egg"
  let _ ← Persistence.create path
  let source ← DB.PageMap.pin path
  let shell := tool "shell" "read"
    (Json.mkObj [("command",toJson "nl -ba src/source.cpp | sed -n '10,12p'")])
    (Json.mkObj [("output",toJson "  10\talpha\n  11\tNEEDED_SYMBOL\n  12\tomega\n")])
  let shellUse := tool "shell" "use"
    (Json.mkObj [("command",toJson "printf NEEDED_SYMBOL")])
    (Json.mkObj [("output",toJson "done")])
  let remote := tool "mcp__catalog__lookup" "lookup" (Json.mkObj [])
    (toJson #[Json.mkObj [("id",toJson "RECORD_42"),
      ("uri",toJson "smb://customer/logs/boot.txt"),("details",toJson "recorded evidence")]])
  let remoteUse := tool "mcp__catalog__inspect" "inspect"
    (Json.mkObj [("request",Json.mkObj [("record",toJson "RECORD_42")])])
    (Json.mkObj [("status",toJson "available")])
  let unstructured : ToolEvent := ⟨"arbitrary_provider","opaque","read opaque evidence",
    "\"not canonical JSON\nPRIVATE_RECORD_TEXT_MUST_NOT_BE_COPIED\nopaque tail",none⟩
  let large := tool "mcp__records__fetch" "large" (Json.mkObj [("id",toJson "snapshot")])
    (Json.mkObj [("records",toJson #[Json.mkObj [("message",toJson
      (String.ofList (List.replicate 6000 '界') ++ "\nLARGE_FIELD_TAIL")),("status",toJson true)]])])
  let unstructuredUse : ToolEvent := ⟨"unknown_provider","use-opaque",
    "consume PRIVATE_RECORD_TEXT_MUST_NOT_BE_COPIED", "arbitrary response",none⟩
  let tools := [shell,shellUse,remote,remoteUse,unstructured,unstructuredUse,large]
  for (tool,index) in tools.zipIdx do
    let (first,last) ← entries source tool (index*30+10)
    check (agrees (occurrence tool) tool first last) "valid native pair was rejected"
    check (!agrees (occurrence tool) {tool with name := "other"} first last &&
      !agrees (occurrence tool) {tool with response := "null"} first last &&
      !agrees (occurrence tool) {tool with input := "null"} first last &&
      !agrees (occurrence tool) tool first {last with clock := first.clock} &&
      !agrees (occurrence tool) tool first {last with clock := ⟨Sha256.hex "other".toUTF8,1000⟩})
      "tool, input, output or clock mismatch acquired source authority"
    let _ ← Journal.append source first
    let _ ← Journal.append source last
  let native := pending path tools
  let items ← plan native path
  -- Real body and metadata writes are attempted, then cancelled before the
  -- head publication. Neither is visible to a new pinned reader.
  reject (Persistence.appendPrepared path (fun graph => do
      let roots ← stagedGraphValues native
      let some transaction := (Transaction.begin graph).stageValues? roots | throw "invalid test roots"
      pure (transaction, ()))
    (fun intern _ => do
      let _ ← stage items intern
      throw (IO.userError "injected before commit"))) "injected source cancellation returned an ACK"
  let cancelled ← DB.PageMap.pin path
  check (cancelled.head == source.head && (← Provenance.records cancelled).isEmpty &&
    (← Persistence.Store.rootIds cancelled).isEmpty) "failed transaction partially published originals or intervals"
  let cancelledRows ← cancelled.foldRange ⟨ObservedRecords.keyPrefix,ObservedRecords.keyPrefix ++ "~"⟩
    (fun count _ => pure (count+1)) (0 : Nat)
  check (cancelledRows == 0) "failed transaction partially published record metadata"
  let committed ← NativePublication.run native path true
  check (committed.source.complete && committed.source.timed == tools.length &&
    committed.source.head.revision == source.head.revision+1)
    "body and native intervals were not acknowledged in one source publication"
  let source ← DB.PageMap.pin path
  observed source tools
  let metadataBytes ← source.foldRange ⟨ObservedRecords.keyPrefix,ObservedRecords.keyPrefix ++ "~"⟩
    (fun count row => do
      let bytes := row.2.getD ByteArray.empty
      let some text := String.fromUTF8? bytes | throw (IO.userError "invalid fixture metadata")
      check ((text.splitOn "PRIVATE_RECORD_TEXT_MUST_NOT_BE_COPIED").length == 1)
        "record metadata duplicated original plaintext"
      pure (count+bytes.size)) (0 : Nat)
  check (!(← (path / "derived").pathExists)) "source ACK opened derived preparation"
  let derived ← Provenance.derive source
  check (derived.originals == tools.length && derived.ignored == 0)
    "generic provider data disappeared during source-only reconstruction"
  let facts := derived.graph.snapshot
  let consumed := facts.filterMap fun fact => match fact with | .consumed edge => some edge | _ => none
  check (consumed.any (fun edge => edge.producer == occurrence shell && edge.consumer == occurrence shellUse) &&
    consumed.any (fun edge => edge.producer == occurrence remote && edge.consumer == occurrence remoteUse) &&
    consumed.any (fun edge => edge.producer == occurrence unstructured && edge.consumer == occurrence unstructuredUse))
    "source-only originals cannot reconstruct shell, MCP and arbitrary provider consumption"
  let retried ← NativePublication.run native path true
  check (retried.source.complete && retried.source.head == source.head &&
    (← Provenance.records (← DB.PageMap.pin path)).size == tools.length)
    "lost-ACK retry duplicated an original, interval or source publication"
  wireChecks retried.source
  copySource source (root / "copied.egg")
  IO.FS.writeFile (root / "tools.json") (toJson tools).compress
  IO.FS.writeFile (root / "expected-facts.json") (toJson facts).compress
  -- A raw Post result may arrive at the save queue before its finish journal
  -- event. The source ACK must expose the pending interval and permit repair.
  let delayedPath := root / "delayed.egg"
  let _ ← Persistence.create delayedPath
  let delayed ← DB.PageMap.pin delayedPath
  let (first,last) ← entries delayed shell 10
  let _ ← Journal.append delayed first
  let delayedTurn := pending delayedPath [shell]
  let incomplete ← NativePublication.run delayedTurn delayedPath true
  check (!incomplete.source.complete && incomplete.source.awaiting == 1 && incomplete.source.timed == 0)
    "missing finish event was acknowledged as complete provenance"
  let _ ← Journal.append delayed last
  let completed ← NativePublication.run delayedTurn delayedPath true
  check (completed.source.complete && completed.source.head.revision == incomplete.source.head.revision+1)
    "delayed finish could not complete its existing original publication"
  observed (← DB.PageMap.pin delayedPath) [shell]
  let absentPath := root / "absent.egg"
  let _ ← Persistence.create absentPath
  let absent ← NativePublication.run (pending absentPath [shell]) absentPath true
  check (!absent.source.complete && absent.source.unavailable == 1)
    "unobserved chronology was invented from DB insertion order"
  -- Corrupt only derived record metadata in a disposable source copy. A
  -- verified body/owner does not make a changed block trustworthy.
  let corruptPath := root / "corrupt.egg"
  copySource source corruptPath
  let corrupt ← DB.PageMap.pin corruptPath
  let some first := (← Provenance.records corrupt)[0]? | throw (IO.userError "missing native origin")
  let doc ← Provenance.checkedDocument (← Persistence.Store.NodeReader.new corrupt) first.origin
  let some encoded ← corrupt.get (ObservedRecords.ownerKey first.origin.owner) |
    throw (IO.userError "missing record directory")
  let header ← ObservedRecords.decode (α := ObservedRecords.Header) encoded
  let some digest := header.chunks[0]? | throw (IO.userError "missing record block")
  let _ ← DB.PageMap.withWriter corrupt fun writer => writer.put (ObservedRecords.chunkKey digest) (some "[]".toUTF8)
  reject (ObservedRecords.load? (← DB.PageMap.pin corruptPath) first.origin.owner doc)
    "changed record metadata was accepted as the original data"
  IO.println (Json.mkObj [("atomicRollback",toJson true),("portableOriginals",toJson tools.length),
    ("consumptionWitnesses",toJson consumed.size),("onePublication",toJson true),
    ("lostAckRetryIdempotent",toJson true),("delayedFinishRecovered",toJson true),
    ("absentTimingExplicit",toJson true),("derivedIndexOpened",toJson false),
    ("originalRecordDirectories",toJson tools.length),("recordMetadataBytes",toJson metadataBytes),
    ("metadataContainsNoPlaintextCopy",toJson true),("completeOriginalDomain",toJson true),
    ("changedMetadataRejected",toJson true),("answeringModelCalls",toJson (0 : Nat)),
    ("productionAdoption",toJson false)]).compress

private def copied (root : System.FilePath) : IO Unit := do
  let path := root / "copied.egg"
  let source ← DB.PageMap.pin path
  check ((← Journal.open? source).isNone) "source-only test inherited a private journal"
  let tools ← IO.ofExcept (Json.parse (← IO.FS.readFile (root / "tools.json")) >>= fromJson? (α := List ToolEvent))
  let expected ← IO.ofExcept (Json.parse (← IO.FS.readFile (root / "expected-facts.json")) >>= fromJson? (α := Array Fact))
  let repeated ← NativePublication.run (pending path tools) path true
  check (repeated.source.complete && repeated.source.head == source.head)
    "source-only retry required the previous chat's private native events"
  observed (← DB.PageMap.pin path) tools
  let rebuilt ← Provenance.derive (← DB.PageMap.pin path)
  check (rebuilt.graph.snapshot == expected && (← Journal.open? source).isNone &&
    !(← (path / "derived").pathExists)) "independent source-only reconstruction changed its facts or opened preparation"
  IO.println (Json.mkObj [("sourceOnlyCopy",toJson true),("privateJournalAbsent",toJson true),
    ("originals",toJson rebuilt.originals),("sameSynapticFacts",toJson true),
    ("retryPublicationUnchanged",toJson true)]).compress

def main (args : List String) : IO UInt32 := do
  try
    match args with
    | ["create",path] => fixture (.mk path)
    | ["copy",path] => copied (.mk path)
    | _ => throw (IO.userError "ObservedRecordPublicationChecks create|copy ROOT")
    return 0
  catch error => IO.eprintln error.toString; return 1
