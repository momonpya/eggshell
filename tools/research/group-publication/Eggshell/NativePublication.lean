module

public import Eggshell.SynapseJournal

@[expose] public section

namespace Eggshell.Plugin.NativePublication
open Lean DB Persistence.Store Synapses

/-- A source publication and derived readiness are separate acknowledgements. -/
structure SourceReceipt where
  head : PageMap.Head
  observations : Nat
  timed : Nat
  awaiting : Nat
  unavailable : Nat
  deriving ToJson, FromJson

def SourceReceipt.accounted (receipt : SourceReceipt) : Bool :=
  receipt.timed + receipt.awaiting + receipt.unavailable == receipt.observations

def SourceReceipt.complete (receipt : SourceReceipt) : Bool :=
  receipt.accounted && receipt.awaiting == 0 && receipt.unavailable == 0

theorem complete_has_all_observations (receipt : SourceReceipt)
    (complete : receipt.complete = true) : receipt.timed = receipt.observations := by
  simp only [SourceReceipt.complete, SourceReceipt.accounted, Bool.and_eq_true,
    beq_iff_eq] at complete
  omega

structure Saved where
  publication : SourceReceipt
  preparationQueued : Bool
  deriving ToJson, FromJson

/-- A wire result must account for every observation before its source ACK is used. -/
def Saved.check? (value : Json) : Except String Saved := do
  let saved ← fromJson? (α := Saved) value
  unless saved.publication.accounted do throw "invalid source publication coverage"
  return saved

inductive SaveReply where
  | noWrite
  | published (saved : Saved)
  deriving ToJson, FromJson

def SaveReply.check? (value : Json) : Except String SaveReply := do
  let reply ← fromJson? (α := SaveReply) value
  if let .published saved := reply then
    unless saved.publication.accounted do throw "invalid source publication coverage"
  return reply

def agrees (occurrence : Occurrence) (tool : ToolEvent)
    (first last : Journal.Entry) : Bool :=
  match first.payload, last.payload with
  | .start before work _ _, .finish after name input response _ =>
      before == occurrence && after == occurrence &&
      work == canonicalToolWork tool && name == tool.name &&
      input == canonicalJson tool.input && response == canonicalJson tool.response &&
      first.clock.domain == last.clock.domain && digest first.clock.domain &&
      first.clock.nanos < last.clock.nanos
  | _, _ => false

theorem agrees_preserves_clock (occurrence : Occurrence) (tool : ToolEvent)
    (first last : Journal.Entry) (accepted : agrees occurrence tool first last = true) :
    first.clock.domain = last.clock.domain ∧ first.clock.nanos < last.clock.nanos := by
  cases first with | mk before first received =>
    cases last with | mk after last receivedAfter =>
      cases first <;> cases last <;> simp_all [agrees, Bool.and_eq_true, beq_iff_eq]

theorem agrees_preserves_observation (occurrence : Occurrence) (tool : ToolEvent)
    (first last : Journal.Entry) (accepted : agrees occurrence tool first last = true) :
    ∃ query known archive, first.payload = .start occurrence (canonicalToolWork tool) query known ∧
      last.payload = .finish occurrence tool.name (canonicalJson tool.input)
        (canonicalJson tool.response) archive := by
  cases first with | mk before first received =>
    cases last with | mk after last receivedAfter =>
      cases first <;> cases last <;> simp_all [agrees, Bool.and_eq_true, beq_iff_eq]

inductive Evidence (occurrence : Occurrence) (tool : ToolEvent) where
  | timed (first last : Journal.Entry) (checked : agrees occurrence tool first last = true)
  | stored (origin : Provenance.Origin) (valid : origin.valid = true)
  | awaiting
  | unavailable

structure Item where
  tool : ToolEvent
  occurrence : Occurrence
  evidence : Evidence occurrence tool

/-- Exact native event keys only. Preparing a source ACK never replays the
turn, extracts source rows, constructs embeddings or opens a derived index. -/
def plan (pending : PendingTurn) (target : System.FilePath) : IO (Array Item) := do
  let published ← PageMap.open? target
  let canonical := System.FilePath.mk (pending.write.getD target.toString)
  let journal ← match ← PageMap.open? canonical with
    | none => pure none
    | some source => Journal.open? source
  pending.tools.toArray.mapM fun tool => do
    let occurrence : Occurrence := ⟨pending.sessionId,pending.turnId,tool.useId⟩
    if let some source := published then
      let owner := (compileOperationOutcomes (.text pending.sessionId) (.text pending.turnId) tool).2
      let some edge := OutcomeEdge.fromValue? owner | throw (IO.userError "invalid native owner")
      if let some origin ← Provenance.lookup? source edge occurrence then
        if valid : origin.valid = true then return ⟨tool,occurrence,.stored origin valid⟩
        else throw (IO.userError "invalid stored native interval")
    let evidence ← match journal with
      | none => pure .unavailable
      | some journal => do
          let first ← Journal.lookup? journal "start" occurrence
          let last ← Journal.lookup? journal "finish" occurrence
          match first, last with
          | some first, some last =>
              if checked : agrees occurrence tool first last = true then
                pure (.timed first last checked)
              else pure .unavailable
          | some _, none => pure .awaiting
          | _, _ => pure .unavailable
    return ⟨tool,occurrence,evidence⟩

def stage (items : Array Item) (intern : Persistence.Store.Intern) : IO Bool := do
  let mut bindings := #[]
  for item in items do
    let owner := (compileOperationOutcomes (.text item.occurrence.session)
      (.text item.occurrence.turn) item.tool).2
    let some edge := OutcomeEdge.fromValue? owner |
      throw (IO.userError "native publication did not compile an Outcome")
    let id ← intern.value owner
    let origin : Option Provenance.Origin := match item.evidence with
      | .timed first last _ => some ⟨id,item.occurrence,first.clock.domain,
          first.clock.nanos,last.clock.nanos,last.receivedUnixMs⟩
      | .stored origin _ => some origin
      | _ => none
    let some origin := origin | continue
    let some binding := Provenance.Binding.check? edge origin |
      throw (IO.userError "native publication has an invalid observed interval")
    bindings := bindings.push binding
  Provenance.stage intern bindings

structure TimingCounts where
  timed : Nat := 0
  awaiting : Nat := 0
  unavailable : Nat := 0

def receipt (items : Array Item) (head : PageMap.Head) : SourceReceipt :=
  let counts := items.foldl (fun result item => match item.evidence with
    | .timed .. | .stored .. => {result with timed := result.timed+1}
    | .awaiting => {result with awaiting := result.awaiting+1}
    | .unavailable => {result with unavailable := result.unavailable+1}) ({} : TimingCounts)
  {head,observations := items.size,timed := counts.timed,
    awaiting := counts.awaiting,unavailable := counts.unavailable}

theorem receipt_is_at_publication (items : Array Item) (head : PageMap.Head) :
    (receipt items head).head = head := rfl

structure Published where
  promotion : CommittedPromotion
  source : SourceReceipt

def matchesPending (pending : PendingTurn) (items : Array Item) : Bool :=
  items.size == pending.tools.length && (items.zip pending.tools.toArray).all (fun (item,tool) =>
    item.occurrence == (⟨pending.sessionId,pending.turnId,tool.useId⟩ : Occurrence) &&
    item.tool.useId == tool.useId && item.tool.name == tool.name &&
    item.tool.input == tool.input && item.tool.response == tool.response)

/-- Private ingress is inspected before admission. Only query-free intervals
are staged into the source DB. This is an in-memory publisher input, not a
wire format for sending private journal entries to another machine. -/
structure Prepared where
  pending : PendingTurn
  target : System.FilePath
  identity : Option String
  checkpoint : Bool
  items : Array Item
  matching : matchesPending pending items = true

theorem Prepared.tool_count (request : Prepared) : request.items.size = request.pending.tools.length := by
  have matching := request.matching
  simp only [matchesPending, Bool.and_eq_true, beq_iff_eq] at matching
  exact matching.1

def prepare (pending : PendingTurn) (target : System.FilePath) (checkpoint : Bool) : IO Prepared := do
  let pinned ← PageMap.open? target
  let items ← plan pending target
  if matching : matchesPending pending items = true then
    return ⟨pending,target.normalize,pinned.map (·.head.identity),checkpoint,items,matching⟩
  else throw (IO.userError "publication input disagrees with its native observations")

def compilePrepared (source : Graph) (target : System.FilePath) (request : Prepared) :
    Except String (Transaction × Promotion) := do
  if request.checkpoint then
    let roots ← stagedGraphValues request.pending
    let some transaction := (Transaction.begin source).stageValues? (roots.filter (!source.values.contains ·)) |
      throw "observation compiler produced an invalid Value"
    return (transaction,{outcomeRelations := observedRoots request.pending})
  else
    let compiled ← compile source request.pending target.toString
    return (compiled.transaction,compiled.promotion)

def maxBatchRequests : Nat := 128
def maxBatchBytes : Nat := 8*1024*1024

/-- One DB publisher commits a bounded group under one writer/root/fsync.
Every reply refers to that one durable head. A failed group acknowledges none.
No queue, model, derived work or remote-policy promise is hidden here. -/
def runPrepared (target : System.FilePath) (requests : Array Prepared) : IO (Array Published) := do
  unless !requests.isEmpty && requests.size ≤ maxBatchRequests do
    throw (IO.userError "publication group exceeds its request bound")
  unless requests.all (fun request => request.items.size == request.pending.tools.length) do
    throw (IO.userError "publication group changed its observed tool count")
  unless requests.all (fun request => request.target == target.normalize) do
    throw (IO.userError "publication group mixed database targets")
  let payloadBytes := requests.foldl (fun total request =>
    total+(toJson request.pending).compress.utf8ByteSize) 0
  unless payloadBytes ≤ maxBatchBytes do throw (IO.userError "publication group exceeds its byte bound")
  let committed ← Persistence.appendPrepared target (fun graph => do
    let prepared ← requests.mapM (compilePrepared graph target)
    let roots := (prepared.toList.flatMap (·.1.stagedValues)).eraseDups
    let some transaction := (Transaction.begin graph).stageValues? roots |
      throw "publication group contains an invalid Value"
    return (transaction,prepared.map (·.2)))
    (fun intern _ => do
      let pinned ← intern.writer.snapshot
      unless requests.all (fun request => request.identity.all (· == pinned.head.identity)) do
        throw (IO.userError "publication group database was replaced before commit")
      stage (requests.flatMap (·.items)) intern)
  unless committed.value.size == requests.size do throw (IO.userError "publication group changed its request count")
  (requests.zip committed.value).mapM fun (request,value) => do
    let promotion ← prepareCommitted committed.graph value
    let source := receipt request.items committed.head
    unless source.accounted do throw (IO.userError "native publication coverage disagrees")
    return ⟨promotion,source⟩

def run (pending : PendingTurn) (target : System.FilePath) (checkpoint : Bool) : IO Published := do
  let request ← prepare pending target checkpoint
  let results ← runPrepared target #[request]
  let some result := results[0]? | throw (IO.userError "publication group lost its single request")
  return result

end Eggshell.Plugin.NativePublication

namespace Eggshell.Plugin

def promote (pending : PendingTurn) (target : System.FilePath) : IO NativePublication.Published :=
  NativePublication.run pending target false

def promoteObservations (pending : PendingTurn) (target : System.FilePath) : IO NativePublication.Published :=
  NativePublication.run pending target true

end Eggshell.Plugin
