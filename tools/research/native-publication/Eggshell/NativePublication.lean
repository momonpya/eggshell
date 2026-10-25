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

def receipt (items : Array Item) (head : PageMap.Head) : SourceReceipt := Id.run do
  let mut result : SourceReceipt := ⟨head,items.size,0,0,0⟩
  for item in items do
    result := match item.evidence with
      | .timed .. => {result with timed := result.timed+1}
      | .stored .. => {result with timed := result.timed+1}
      | .awaiting => {result with awaiting := result.awaiting+1}
      | .unavailable => {result with unavailable := result.unavailable+1}
  return result

structure Published where
  promotion : CommittedPromotion
  source : SourceReceipt

def run (pending : PendingTurn) (target : System.FilePath) (checkpoint : Bool) : IO Published := do
  let items ← plan pending target
  let committed ← Persistence.appendPrepared target (fun graph => do
    if checkpoint then
      let roots ← stagedGraphValues pending
      let some transaction := (Transaction.begin graph).stageValues? (roots.filter (!graph.values.contains ·)) |
        throw "observation compiler produced an invalid Value"
      pure (transaction, ({outcomeRelations := observedRoots pending} : Promotion))
    else
      let compiled ← compile graph pending target.toString
      pure (compiled.transaction, compiled.promotion))
    (fun intern _ => stage items intern)
  let promotion ← prepareCommitted committed.graph committed.value
  let source := receipt items committed.head
  unless source.accounted do throw (IO.userError "native publication coverage disagrees")
  return ⟨promotion,source⟩

end Eggshell.Plugin.NativePublication

namespace Eggshell.Plugin

def promote (pending : PendingTurn) (target : System.FilePath) : IO NativePublication.Published :=
  NativePublication.run pending target false

def promoteObservations (pending : PendingTurn) (target : System.FilePath) : IO NativePublication.Published :=
  NativePublication.run pending target true

end Eggshell.Plugin
