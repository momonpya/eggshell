import Eggshell.NativePublication
import Eggshell.PluginHooks
import Eggshell.ContractAudit

open Lean Eggshell Eggshell.Plugin Eggshell.Synapses Eggshell.Synapses.Extraction

private def check (ok : Bool) (message : String) : IO Unit :=
  unless ok do throw (IO.userError message)

private def containing (raw : String) (read : Read) (needle : String) : Bool :=
  decide ((((raw.drop read.binding.first).take (read.binding.limit-read.binding.first)).copy.splitOn needle).length > 1)

private def offered (pending : PendingTurn) (files : SessionFiles) (handoff : Handoff) (id : String)
    (deadline : Nat) : IO Unit := do
  let state : ThreadState := (← readState? files).getD {profile := "work"}
  let offer : DeliveryOffer := {
    id,stamp := {turn := pending.turnId,epoch := state.epoch,deadline},graphs := handoff.deliveredGraphs
    text := handoff.text,reason := handoff.reason,projection := handoff.acknowledgmentProjection}
  writeJson files.pending pending
  writeJson files.state {state with offers := [offer]}

def main (args : List String) : IO Unit := do
  let [directory] := args | throw (IO.userError "NEW-PRIVATE-FIXTURE")
  let root := System.FilePath.mk directory
  check (root.isAbsolute && !(← root.pathExists) &&
    (← IO.getEnv "EGGSHELL_DATA_ROOT") == some (root / "data").toString) "new isolated fixture required"
  IO.FS.createDirAll root
  let codeText := "/* 日本語😀 */ int alpha = 1;\nint beta = 2;\n"
  IO.FS.writeFile (root / "specimen.c") codeText
  let sourceCapture ← SourceEvidence.capture root
    (Json.mkObj [("command",toJson "nl -ba specimen.c | sed -n '1,2p'")]) ((← IO.monoMsNow)+10000)
  let response := (Json.mkObj [("code",toJson codeText),
    ("unrelated",toJson "hidden sibling value")]).compress
  let capture ← ContentCapture.finish root sourceCapture response ((← IO.monoMsNow)+10000)
  check (capture.complete && !capture.aliases.isEmpty) "real content correspondence missing"
  let tool : ToolEvent := {
    name := "mcp__fixture__read",useId := "native-read",input := "{}",response
    source := some sourceCapture,correspondence := some capture}
  let pending : PendingTurn := {
    sessionId := "delivery-session",turnId := "delivery-turn",cwd := root.toString,prompt := "inspect alpha"
    profile := "work",write := some (root / "project.egg").toString,read := [(root / "project.egg").toString]
    semanticMatcher := none,handoffChars := 500000,projection := .automatic,tools := [tool]}
  let empty ← Persistence.ensureSnapshot (root / "project.egg")
  let occurrence : Occurrence := ⟨pending.sessionId,pending.turnId,tool.useId⟩
  let nativeClock := Sha256.hex "native publication".toUTF8
  let initialKnowledge ← Journal.knowledge empty [] false
  let _ ← Journal.append empty ⟨⟨nativeClock,1⟩,
    .start occurrence (canonicalToolWork tool) (Sha256.hex pending.prompt.toUTF8) initialKnowledge,none⟩
  let _ ← Journal.append empty ⟨⟨nativeClock,2⟩,
    .finish occurrence tool.name (canonicalJson tool.input) (canonicalJson tool.response) pending.write,none⟩
  let _ ← NativePublication.run pending empty.directory true
  let source ← DB.PageMap.pin empty.directory
  let originalHead := source.head
  let relation := (compileOperationOutcomes (.text pending.sessionId) (.text pending.turnId) tool).2
  let some id ← Persistence.Store.findNode? source relation | throw (IO.userError "native owner missing")
  let doc ← Build.document (← Persistence.Store.NodeReader.new source) id
  let some raw := doc.source | throw (IO.userError "native response missing")
  let catalog ← Journal.observedCatalog source id doc
  let rows := catalog.reads ++ catalog.located.flatMap (·.originalRows)
  let some code := rows.find? (fun row => row.source.file?.isNone && containing raw row "alpha" &&
    !containing raw row "hidden") | throw (IO.userError "native JSON code field not located")
  let some firstFile := rows.find? (fun row => row.source.file?.isSome && row.source.first == 1 &&
    code.binding.first ≤ row.binding.first && row.binding.limit ≤ code.binding.limit) |
    throw (IO.userError "native code field has no first file row")
  let some hidden := rows.find? (fun row => row.source.file?.isNone && containing raw row "hidden" &&
    !containing raw row "alpha") | throw (IO.userError "native sibling field not located")
  let fragment : DeliveryFragment := {
    first := code.binding.first,original := ((raw.drop code.binding.first).take
      (code.binding.limit-code.binding.first)).copy,decoded := true}
  let context : ContextDelivery := {
    owner := doc.owner,outcome := Persistence.selectionKey (.text raw),sourceChars := raw.length,
    cues := [(code.binding.first,code.binding.limit)],leading := "BEGIN ORIGINAL\n",trailing := "\nEND ORIGINAL",
    fragments := [fragment]}
  let part : DeliveryPart := {keys := context.keys,text := context.render,context := some context}
  let packet : DeliveryPacket := {header := "",footer := "",parts := [part]}
  let handoff : Handoff := {
    text := packet.render,reason := "native fixture",deliveredGraphs := part.keys,completed := 0,advisory := 1,
    localUnions := 0,coveredFragments := [],blocksCurrent := false,packet := some packet}
  let (verified,diagnostic) := handoff.prepareDelivery {documents := #[doc],rows}
  let ready := verified.val
  check (ready.text == handoff.text && diagnostic.getObjValD "unverifiedParts" == toJson ([] : List Nat))
    "preparation changed the actual body or failed its native witness"
  let projection := ready.acknowledgmentProjection
  check (projection.complete && projection.rows.any (·.source == firstFile.source) &&
    !(projection.rows.any (·.source == hidden.source))) "ACK included an undelivered sibling or lost actual evidence"
  let removeKey := s!"e:{doc.owner}:{context.outcome}:{firstFile.binding.first}:{firstFile.binding.limit}"
  let some fitted := ready.reconcileDelivery [removeKey] 500000 2000000 |
    throw (IO.userError "partial packet reconciliation failed")
  let projected := fitted.handoff.acknowledgmentProjection
  check (projected.complete && !projected.rows.isEmpty &&
    !(projected.rows.any (·.source == firstFile.source))) "reconciliation acknowledged removed original bytes"
  check (← DeliveryLedger.capture pending.sessionId 0).isNone "an offer was already an ACK"
  let files ← sessionFiles pending.sessionId
  offered pending files fitted.handoff "first" ((← IO.monoMsNow)+60000)
  check (← DeliveryLedger.capture pending.sessionId 0).isNone "staging an offer published its projection"
  check (← acknowledge pending.sessionId "first") "native ACK was rejected"
  let some first ← DeliveryLedger.capture pending.sessionId 0 | throw (IO.userError "ACK did not publish a projection")
  let ranges ← DeliveryLedger.lookup first source.head.identity
  check (ranges.size == (projected.rows.map (·.source)).toList.eraseDups.length &&
    projected.rows.all (fun row => ranges.contains row.source) && !(ranges.contains firstFile.source) &&
    !(ranges.contains hidden.source)) "confirmed ranges differ from the actual reconciled packet"
  let known ← Journal.knowledge source [] false pending.write (some first)
  let shown ← Journal.presentation source known
  check (shown.ranges.all (fun range => ranges.any (·.contains range))) "journal presentation reconstructed other evidence"
  offered pending files ready "second" ((← IO.monoMsNow)+60000)
  check (← acknowledge pending.sessionId "second") "second native ACK was rejected"
  let some second ← DeliveryLedger.capture pending.sessionId 0 | throw (IO.userError "second ACK missing")
  check (second.head != first.head && (← DeliveryLedger.lookup first source.head.identity) == ranges &&
    (← DeliveryLedger.lookup second source.head.identity).contains firstFile.source)
    "later ACK changed the historical presentation"
  let cut := (firstFile.binding.first+firstFile.binding.limit)/2
  check (firstFile.binding.first < cut && cut < firstFile.binding.limit) "native first row is too short for split control"
  let key := fun first last => s!"e:{doc.owner}:{context.outcome}:{first}:{last}"
  let some left := ready.reconcileDelivery
      [key code.binding.first firstFile.binding.first,key cut code.binding.limit] 500000 2000000 |
    throw (IO.userError "left split did not reconcile")
  let some right := ready.reconcileDelivery
      [key code.binding.first cut,key firstFile.binding.limit code.binding.limit] 500000 2000000 |
    throw (IO.userError "right split did not reconcile")
  check (!(left.handoff.acknowledgmentProjection.rows.any (·.source == firstFile.source)) &&
    !(right.handoff.acknowledgmentProjection.rows.any (·.source == firstFile.source)))
    "a partial original row was acknowledged whole"
  let split := {pending with sessionId := "split-session"}
  let splitFiles ← sessionFiles split.sessionId
  offered split splitFiles left.handoff "left" ((← IO.monoMsNow)+60000)
  check (← acknowledge split.sessionId "left") "left split ACK rejected"
  let some leftRef ← DeliveryLedger.capture split.sessionId 0 | throw (IO.userError "left split ACK missing")
  let leftKnown ← Journal.knowledge source [] false pending.write (some leftRef)
  let subjects : Std.HashSet Subject := ({} : Std.HashSet Subject).insert firstFile.source.subject
  check (!((← Journal.presentation source leftKnown (some subjects) #[firstFile]).ranges.contains firstFile.source))
    "half of a native row was treated as fully delivered"
  offered split splitFiles right.handoff "right" ((← IO.monoMsNow)+60000)
  check (← acknowledge split.sessionId "right") "right split ACK rejected"
  let some joinedRef ← DeliveryLedger.capture split.sessionId 0 | throw (IO.userError "joined split ACK missing")
  let joined ← Journal.knowledge source [] false pending.write (some joinedRef)
  check ((← Journal.presentation source joined (some subjects) #[firstFile]).ranges.contains firstFile.source &&
    !((← Journal.presentation source leftKnown (some subjects) #[firstFile]).ranges.contains firstFile.source))
    "separate ACK fragments failed to compose or rewrote the historical half"
  let other ← Persistence.ensureSnapshot (root / "other-project.egg")
  check ((← DeliveryLedger.lookup second other.head.identity).isEmpty &&
    (← DeliveryLedger.capture pending.sessionId 1).isNone) "project or compaction epoch leaked ACK evidence"
  let _ ← stop (Json.mkObj [("session_id",toJson pending.sessionId),("turn_id",toJson pending.turnId)])
  let state ← readState? files
  let some state := state | throw (IO.userError "ACK state missing")
  check (state.epoch == 1 && state.confirmedDelivery == some second)
    "ordinary Stop discarded evidence still present in model context"
  let nextTurn := {pending with turnId := "next-turn",tools := []}
  writeJson files.pending nextTurn
  let clock := Sha256.hex "fixture ingress".toUTF8
  let liveInput := Json.mkObj [("_eggshell_synapse_clock",toJson clock),("_eggshell_synapse_nanos",toJson (100 : Nat))]
  let consumer : ToolEvent := {name := "mcp__fixture__inspect",useId := "after-ack",input := "{}",response := "{}"}
  Synapses.Live.start liveInput files nextTurn state consumer
  let some journal ← Journal.open? source | throw (IO.userError "live pre journal missing")
  let some entry ← Journal.lookup? journal "start" ⟨pending.sessionId,nextTurn.turnId,consumer.useId⟩ |
    throw (IO.userError "live pre entry missing")
  let .start _ _ _ captured := entry.payload | throw (IO.userError "wrong native event kind")
  check (captured.delivery == some second && !captured.uncertain) "Pre did not capture the immutable ACK head"
  offered nextTurn files ready "next-turn-ack" ((← IO.monoMsNow)+60000)
  check (← acknowledge pending.sessionId "next-turn-ack") "next-turn ACK rejected"
  check ((← readState? files).any (fun current => current.confirmedDelivery == some second))
    "request epoch replaced the confirmed model context"
  let _ ← postCompact (Json.mkObj [("session_id",toJson pending.sessionId)])
  let some compacted ← readState? files | throw (IO.userError "compacted state missing")
  check (compacted.confirmedDelivery.isNone && compacted.epoch == 2 &&
    (← DeliveryLedger.lookup second source.head.identity).contains firstFile.source)
    "compaction failed to discard current delivery or destroyed historical evidence"
  offered nextTurn files ready "new-context" ((← IO.monoMsNow)+60000)
  check (← acknowledge pending.sessionId "new-context") "new context ACK rejected"
  let some fresh ← DeliveryLedger.capture pending.sessionId 2 | throw (IO.userError "new context ledger missing")
  check (fresh.head.identity != second.head.identity) "new compacted context reused the old ledger"
  offered nextTurn files ready "expired" ((← IO.monoMsNow)-1)
  check (!(← acknowledge pending.sessionId "expired") &&
    (← DeliveryLedger.capture pending.sessionId 2) == some fresh &&
    (← Synapses.Live.uncertain files ((← readState? files).getD state))) "expired offer became confirmed evidence"
  let uncertain := {known with uncertain := true}
  check ((← Journal.presentation source uncertain).ranges.isEmpty) "unconfirmed delivery acquired positive presentation"
  let legacy := {known with delivery := none,acknowledged := [removeKey]}
  check (!Journal.completeKnowledge legacy true) "missing projection was interpreted as absence"
  let unvalidated := {known with delivery := some {second with producer := "unvalidated"},acknowledged := [removeKey]}
  check (!Journal.completeKnowledge unvalidated true && (← Journal.presentation source unvalidated).ranges.isEmpty)
    "an unvalidated projection compiler acquired positive presentation"
  check ((← DB.PageMap.pin source.directory).head == originalHead) "private ACK mutated the shared source DB"
  let report := Json.mkObj [("actualNativePublication",toJson true),("selectedRows",toJson projection.rows.size),
    ("reconciledRows",toJson projected.rows.size),("bodyUnchangedByProjection",toJson true),
    ("undeliveredSiblingExcluded",toJson true),("removedOriginalExcluded",toJson true),
    ("offerNotAcknowledgment",toJson true),("nativeAcknowledgmentPublishesProjection",toJson true),
    ("historicalAckHeadStable",toJson true),("projectAndEpochIsolation",toJson true),
    ("separateAckFragmentsComposeWithoutSourceBody",toJson true),
    ("unicodeOriginalCoordinates",toJson true),
    ("ordinaryStopPreservesConfirmedContext",toJson true),("compactionStartsNewConfirmedContext",toJson true),
    ("nativePreCapturesAckHead",toJson true),("expiredOrUnconfirmedCannotGrantPresentation",toJson true),
    ("legacyMissingProjectionIsUnknown",toJson true),("sharedSourceUnchanged",toJson true),
    ("closedTurnCheckpointFixed",toJson false),("answeringModelCalls",toJson (0 : Nat)),("adopted",toJson false)]
  IO.FS.writeFile (root / "result.json") report.pretty
  IO.println report.compress
