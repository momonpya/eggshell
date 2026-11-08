module
public import Eggshell.NativePublication
public import Eggshell.ContractAudit
public import Eggshell.PluginHooks
@[expose] public section
namespace Eggshell.Research.DeliveryKnowledgeChecks
open Lean Plugin Synapses Synapses.Extraction

def check (ok : Bool) (message : String) : IO Unit := unless ok do throw (IO.userError message)

#print axioms DeliveryLedger.incomplete_projection_not_fully_verified
#print axioms DeliveryLedger.confirmable_requires_verified
#print axioms PositiveProjection.incomplete_keeps_verified_ranges
#print axioms PositiveProjection.complete_requires_verified
#print axioms Journal.uncertain_knowledge_cannot_label_omission
#print axioms Journal.presentation_preserves_confirmed_positives
#print axioms omitted_requires_stored
#print axioms consumed_omission_requires_stored

run_cmd do
  let env ← getEnv
  for (caller,required) in [(``acknowledge,``DeliveryLedger.confirm),
      (``DeliveryLedger.confirm,``DeliveryLedger.Projection.confirmable),
      (``finishAcknowledgment,``DeliveryLedger.Projection.fullyVerified),
      (``Journal.feedbackGroup,``Journal.completeKnowledge)] do
    let some expression := (env.find? caller).bind (·.value?) | throwError "missing actual consumer {caller}"
    unless expression.getUsedConstants.contains required do throwError "actual consumer bypasses {required}"
  logInfo "Actual ACK, complete-knowledge gate and positive presentation contracts connected"

structure Published where
  source : DB.PageMap.Snapshot
  values : Array Journal.Entry
  occurrence : Occurrence

def query := Sha256.hex "knowledge control".toUTF8
def publish (source : DB.PageMap.Snapshot) (root : System.FilePath) (tool : ToolEvent)
    (session : String) (known : Option Journal.Knowledge := none) : IO Published := do
  let occurrence : Occurrence := ⟨session,"turn",tool.useId⟩
  let known ← match known with
    | some known => pure known
    | none => Journal.knowledge source [] false
  let clock := Sha256.hex (session++":clock").toUTF8
  let values : Array Journal.Entry := #[
    ⟨⟨clock,1⟩,.start occurrence (canonicalToolWork tool) query known,none⟩,
    ⟨⟨clock,2⟩,.finish occurrence tool.name (canonicalJson tool.input) (canonicalJson tool.response)
      (some source.directory.toString),none⟩]
  for value in values do discard <| Journal.append source value
  let pending : PendingTurn := {
    sessionId := session,turnId := "turn",cwd := root.toString,prompt := "knowledge control"
    profile := "work",write := some source.directory.toString,read := [],semanticMatcher := none
    handoffChars := 500000,projection := .none,tools := [tool],finalMessage := none}
  let request ← NativePublication.prepare pending source.directory true
  discard <| NativePublication.runPrepared source.directory #[request]
  return ⟨← DB.PageMap.pin source.directory,values,occurrence⟩

def uses (result : Journal.Replay) (kind : UsageKind) : Array Usage :=
  result.usage.filterMap fun fact => match fact with
    | .used usage => if usage.kind == kind then some usage else none
    | _ => none

def handoff (parts : List DeliveryPart) : Handoff :=
  let packet : DeliveryPacket := {header := "",footer := "",parts}
  {text := packet.render,reason := "knowledge control",deliveredGraphs := parts.flatMap (·.keys),
    completed := 0,advisory := parts.length,localUnions := 0,coveredFragments := [],blocksCurrent := false,packet := some packet}

def acknowledged (root : System.FilePath) (session : String) (body : Handoff) : IO ThreadState := do
  let files ← sessionFiles session
  check (!(← files.directory.pathExists)) "fresh ACK control session required"
  let offer : DeliveryOffer := {
    id := "offered",stamp := ⟨"turn",3,(← IO.monoMsNow)+120000⟩,graphs := body.deliveredGraphs,
    text := body.text,reason := body.reason,projection := body.acknowledgmentProjection}
  writeJson files.state ({profile := "work",epoch := 3,offers := [offer]} : ThreadState)
  writeJson files.pending ({
    sessionId := session,turnId := "turn",cwd := root.toString,
    prompt := "knowledge control",profile := "work",read := [],write := none,semanticMatcher := none,
    handoffChars := 500000,projection := .none} : PendingTurn)
  check (← acknowledge session offer.id) "valid positive original ACK rejected"
  let some state ← readState? files | throw (IO.userError "ACK state disappeared")
  check (state.confirmedDelivery.isSome && state.offers.isEmpty) "accepted positive head was not published"
  return state

def answer (source : DB.PageMap.Snapshot) (known : Journal.Knowledge) (line : Nat) : IO Journal.Replay := do
  let some delivery := known.delivery | throw (IO.userError "answer control has no accepted delivery")
  let entry : Journal.Entry := ⟨⟨Sha256.hex "answer-clock".toUTF8,1⟩,
    .answer ⟨delivery.session,"answer-turn","answer"⟩ query
      s!"Evidence: [specimen.c:{line}](specimen.c:{line})" known,none⟩
  Journal.replay source #[entry] ((← IO.monoMsNow)+15000)

def run (root : System.FilePath) : IO Unit := do
  check (root.isAbsolute && !(← root.pathExists) &&
    (← IO.getEnv "EGGSHELL_DATA_ROOT") == some (root/"data").toString) "fresh private knowledge control required"
  IO.FS.createDirAll root
  IO.FS.writeFile (root/"specimen.c") "int alpha = 1;\nint beta = 2;\nint gamma = 3;\n"
  let input := Json.mkObj [("command",toJson "nl -ba specimen.c | sed -n '1,3p'")]
  let captured ← SourceEvidence.capture root input ((← IO.monoMsNow)+15000)
  let response := Json.mkObj [("output",toJson "1\tint alpha = 1;\n2\tint beta = 2;\n3\tint gamma = 3;\n")]
  let mapped ← ContentCapture.finish root captured response.compress ((← IO.monoMsNow)+15000)
  check (captured.record.valid && mapped.complete && !mapped.aliases.isEmpty) "source capture failed"
  let tool : ToolEvent := {
    name := "arbitrary_reader",useId := "read",input := input.compress,
    response := response.compress,source := some captured,correspondence := some mapped}
  let empty ← Persistence.ensureSnapshot (root/"project.egg")
  let first ← publish empty root tool "seed"
  let owner := (compileOperationOutcomes (.text "seed") (.text "turn") tool).2
  let some id ← Persistence.Store.findNode? first.source owner | throw (IO.userError "native source owner missing")
  let doc ← Build.document (← Persistence.Store.NodeReader.new first.source) id
  let initial ← Journal.knowledge first.source [] false
  let files ← IO.ofExcept (fileMap #[toJson captured.record])
  let some file := files[0]? | throw (IO.userError "captured file missing")
  let subjects := Std.HashSet.ofList [Subject.file file]
  let targetOccurrence : Occurrence := ⟨"partial-ack","turn","read"⟩
  let some stored ← Journal.storedReadsAt? first.source initial subjects targetOccurrence ((← IO.monoMsNow)+15000) none |
    throw (IO.userError "pre-read stored originals unavailable")
  let some original := stored.find? (fun read => read.source == ⟨.file file,1,1⟩) |
    throw (IO.userError "first native code row missing")
  let row : CanonicalSource.StoredRow := ⟨⟨file,1⟩,"int alpha = 1;",#[⟨original.occurrence,original.binding⟩]⟩
  let some shared := CanonicalSource.Delivery.Part.check? #[row] | throw (IO.userError "nonempty source part rejected")
  let part : DeliveryPart := {keys := shared.keys,text := shared.render,shared := some shared}
  let plan : Transport.Plan := {documents := #[doc],rows := stored}
  let full := ((handoff [part]).prepareDelivery plan).1.val
  let partialBody := ((handoff [part,{keys := ["g:opaque"],text := "unverified advisory"}]).prepareDelivery plan).1.val
  check (full.acknowledgmentProjection.verified && full.acknowledgmentProjection.fullyVerified &&
    partialBody.acknowledgmentProjection.verified && !partialBody.acknowledgmentProjection.complete &&
    partialBody.acknowledgmentProjection.rows.size == 1) "positive validation and complete coverage were conflated"
  let partialState ← acknowledged root "partial-ack" partialBody
  let partialUnknown ← Live.uncertain (← sessionFiles "partial-ack") partialState
  check partialUnknown "partial ACK lost its unknown-coverage marker"
  let partialKnown ← Journal.knowledge first.source partialState.deliveredGraphs partialUnknown none partialState.confirmedDelivery
  check (!Journal.completeKnowledge partialKnown true) "partial knowledge can earn an omission label"
  let shown ← Journal.presentation first.source partialKnown (some subjects) stored
  check (covered original.source shown.ranges) "unknown coverage discarded confirmed positive evidence"
  let second ← publish first.source root tool "partial-ack" (some partialKnown)
  let partialRead ← Journal.replay second.source second.values ((← IO.monoMsNow)+15000)
  check ((uses partialRead .omittedThenRead).isEmpty && (uses partialRead .omittedThenConsumed).isEmpty && partialRead.unknown > 0)
    "partial original knowledge manufactured a negative label"
  let cited ← answer second.source partialKnown 1
  check (!(uses cited .deliveredThenCited).isEmpty) "confirmed citation was suppressed by unrelated unknown data"
  let uncited ← answer second.source partialKnown 2
  check ((uses uncited .deliveredThenCited).isEmpty) "unconfirmed source range acquired a citation label"
  let completeState ← acknowledged root "complete-ack" full
  check (!(← Live.uncertain (← sessionFiles "complete-ack") completeState)) "fully verified ACK became unknown"
  let completeKnown ← Journal.knowledge first.source completeState.deliveredGraphs false none completeState.confirmedDelivery
  let completeRead ← publish second.source root tool "complete-ack" (some completeKnown)
  let missingRead ← Journal.replay completeRead.source completeRead.values ((← IO.monoMsNow)+15000)
  let missing := uses missingRead .omittedThenRead
  check (!missing.isEmpty && missing.all (fun usage => !usage.source.contains original.source))
    "fully known omission did not retain its native missing-read label"
  let wanted : Range := ⟨.file file,2,2⟩
  let edge : Consumption := {
    producer := second.occurrence,consumer := ⟨"consumer","turn","use"⟩,
    producerFinish := 2,consumerStart := 3,kind := .identifier,term := "beta",inputFirst := 0,inputLimit := 4,
    outputFirst := 0,outputLimit := 4,rows := #[wanted]}
  check edge.valid "invalid located-consumption control"
  let starts := fun occurrence (known : Journal.Knowledge) => Std.HashMap.ofArray #[(occurrence,(query,known,"work"))]
  let unknownConsumption ← Journal.feedbackGroup second.source (starts second.occurrence partialKnown) second.occurrence #[(edge,wanted)] {graph := .empty}
    ((← IO.monoMsNow)+15000) none none
  let completeEdge := {edge with producer := completeRead.occurrence}
  let knownConsumption ← Journal.feedbackGroup completeRead.source (starts completeRead.occurrence completeKnown)
    completeRead.occurrence #[(completeEdge,wanted)] {graph := .empty}
    ((← IO.monoMsNow)+15000) none none
  check (unknownConsumption.graph.snapshot.isEmpty && unknownConsumption.unknown > 0 && !knownConsumption.graph.snapshot.isEmpty)
    "located consumption ignored complete-knowledge eligibility"
  let pendingFiles ← sessionFiles "complete-ack"
  let pending : DeliveryOffer := {
    id := "unacknowledged",stamp := ⟨"turn",3,(← IO.monoMsNow)+120000⟩,
    graphs := [],text := "pending",reason := "pending"}
  writeJson pendingFiles.state {completeState with offers := [pending]}
  let pendingKnown ← Journal.knowledge first.source completeState.deliveredGraphs
    (← Live.uncertain pendingFiles {completeState with offers := [pending]}) none completeState.confirmedDelivery
  check (!Journal.completeKnowledge pendingKnown true && !(uses (← answer second.source pendingKnown 1) .deliveredThenCited).isEmpty)
    "unacknowledged offer revoked prior positive evidence or enabled absence"
  let unverified := {pending with id := "unverified",projection := {
    rows := full.acknowledgmentProjection.rows,verified := false,complete := true}}
  writeJson pendingFiles.state {completeState with offers := [unverified]}
  check (← acknowledge "complete-ack" unverified.id) "unverified advisory ACK failed"
  let some afterUnverified ← readState? pendingFiles | throw (IO.userError "unverified ACK lost state")
  check (afterUnverified.confirmedDelivery == completeState.confirmedDelivery &&
    (← Live.uncertain pendingFiles afterUnverified)) "unverified complete flag published evidence or removed uncertainty"
  IO.FS.writeFile (root/"report.json") (Json.mkObj [("allPassed",toJson true),
    ("partialAckKeepsUnknownAndConfirmedHead",toJson true),("partialReadOmissions",toJson (uses partialRead .omittedThenRead).size),
    ("confirmedCitationsWhileUnknown",toJson (uses cited .deliveredThenCited).size),
    ("unknownCitationLabels",toJson (uses uncited .deliveredThenCited).size),
    ("completeKnowledgeMissingReads",toJson missing.size),
    ("unknownConsumptionLabels",toJson unknownConsumption.graph.snapshot.size),
    ("knownConsumptionLabels",toJson knownConsumption.graph.snapshot.size),
    ("syntheticLocatedConsumptionControl",toJson true),("pendingOfferPreservesPriorPositives",toJson true),
    ("unverifiedCompleteFlagCannotPublishOrClearUnknown",toJson true),
    ("answeringModelCalls",toJson (0 : Nat)),("adopted",toJson false)]).compress
end Eggshell.Research.DeliveryKnowledgeChecks
