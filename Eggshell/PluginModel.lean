module

public import Eggshell.Config
public import Eggshell.Blake3
public import Eggshell.Lifecycle
public import Eggshell.SourceEvidence
public import Lean.Data.Json.FromToJson

@[expose] public section

namespace Eggshell.Plugin

open Lean

inductive Projection where
  | automatic
  | none
  | roots (values : List String)
  deriving Repr, DecidableEq, ToJson, FromJson

structure DeliveryOffer where
  id : String
  stamp : RequestStamp
  graphs : List String
  text : String
  reason : String
  deriving Repr, ToJson, FromJson

structure ThreadState where
  profile : String
  /-- When false, hooks neither stage work nor read or send graph context. -/
  enabled : Bool := true
  nextProfile : Option String := none
  nextProjection : Option Projection := none
  deliveredGraphs : List String := []
  /-- Native history may have discarded previously visible staged Outcomes. -/
  afterCompaction : Bool := false
  lastHandoff : String := ""
  lastReason : String := ""
  epoch : Nat := 0
  offers : List DeliveryOffer := []
  deriving Repr, ToJson, FromJson

structure ToolEvent where
  name : String
  useId : String
  input : String
  response : String
  source : Option SourceEvidence.Capture := none
  deriving Repr, ToJson, FromJson

structure PendingTurn where
  sessionId : String
  turnId : String
  cwd : String
  prompt : String
  profile : String
  semanticMatcher : Option (List String)
  read : List String
  write : Option String
  handoffChars : Nat
  localUnion : Bool := true
  projection : Projection
  /--
  Native occurrences awaiting a possible PostToolUse result. Codex may omit the
  terminal hook, so this state is correlation only and never execution authority.
  -/
  inFlight : List ToolEvent := []
  tools : List ToolEvent := []
  finalMessage : Option String := none
  closed : Bool := false
  deriving Repr, ToJson, FromJson

structure Promotion where
  outcomeRelations : List Value

/-- The indexer receives the bounded owner view returned after DB publication,
    never from a merely compiled or staged turn. It is not a whole DB image. -/
structure CommittedPromotion where
  snapshot : Graph
  outcomeRelations : List Value
  owners_in_snapshot : ∀ owner ∈ outcomeRelations, owner ∈ snapshot.values

def committedPromotion? (snapshot : Graph) (promotion : Promotion) :
    Option CommittedPromotion :=
  if members : promotion.outcomeRelations ⊆ snapshot.values then
    some {
      snapshot := snapshot
      outcomeRelations := promotion.outcomeRelations
      owners_in_snapshot := members }
  else none

theorem committedPromotion?_identity {snapshot : Graph} {promotion : Promotion}
    {committed : CommittedPromotion}
    (accepted : committedPromotion? snapshot promotion = some committed) :
    committed.snapshot = snapshot ∧
      committed.outcomeRelations = promotion.outcomeRelations := by
  unfold committedPromotion? at accepted
  split at accepted
  · cases accepted
    exact ⟨rfl, rfl⟩
  · cases accepted

theorem committed_index_owner_present (promotion : CommittedPromotion)
    (owner : Value) (present : owner ∈ promotion.outcomeRelations) :
    owner ∈ promotion.snapshot.values := promotion.owners_in_snapshot owner present

def prepareCommitted (snapshot : Graph)
    (promotion : Promotion) : IO CommittedPromotion := do
  let some committed := committedPromotion? snapshot promotion |
    throw (IO.userError "published snapshot is missing a promoted outcome")
  pure committed

structure SessionFiles where
  directory : System.FilePath
  state : System.FilePath
  pending : System.FilePath
  lock : System.FilePath

def safeSession (session : String) : Except String String :=
  if session != "" && session.toList.all fun character =>
      character.isAlphanum || character == '-' || character == '_' then
    pure session
  else throw "Codex session ID contains a path-unsafe character"

/--
Shared control-plane state must be visible to both Codex hooks and `!egg`.
`PLUGIN_DATA` is hook-only on some hosts, so using it would split one session
across two directories. This root stores session state, daemon coordination,
and disposable matcher data; project-selected `.egg` authorities remain the
per-turn paths snapshotted in `PendingTurn`.
-/
def dataRoot : IO System.FilePath := do
  Paths.dataRoot

def sessionFiles (session : String) : IO SessionFiles := do
  let safe ← match safeSession session with
    | .ok safe => pure safe
    | .error message => throw (IO.userError message)
  let directory := (← dataRoot) / "sessions" / safe
  pure {
    directory
    state := directory / "state.json"
    pending := directory / "pending.json"
    lock := directory / "state"
  }

def stateJsonDefaults : List (String × Json) :=
  [("epoch", toJson (0 : Nat)), ("offers", toJson ([] : List DeliveryOffer))]

def pendingJsonDefaults : List (String × Json) := [("closed", toJson false)]

/-- Add only fields introduced by this runtime. Existing malformed fields must
    still fail validation rather than being silently replaced. -/
def readJson? [FromJson α] (path : System.FilePath)
    (defaults : List (String × Json) := []) : IO (Option α) := do
  if !(← path.pathExists) then pure none
  else
    let text ← IO.FS.readFile path
    let parsed ← match Json.parse text with
      | .ok json => pure json
      | .error message => throw (IO.userError s!"{path}: {message}")
    let parsed := match parsed with
      | .obj _ => defaults.foldl (fun json (key, value) =>
          if (json.getObjVal? key).isOk then json else json.setObjVal! key value) parsed
      | _ => parsed
    match fromJson? parsed with
    | .ok value => pure (some value)
    | .error message => throw (IO.userError s!"{path}: {message}")

def writeJson [ToJson α] (path : System.FilePath) (value : α) : IO Unit := do
  let path := ((← IO.currentDir) / path).normalize
  if let some parent := path.parent then Persistence.privateDirectory parent
  -- The receipt must survive a client or manager exit before its queued work
  -- is consumed. Publish only after the temporary bytes have been synced.
  FileSystem.atomicBytes path (toJson value |>.compress |>.toUTF8)

def removeIfExists (path : System.FilePath) : IO Unit := do
  if ← path.pathExists then IO.FS.removeFile path

def withSession (session : String) (action : SessionFiles → IO α) : IO α := do
  let files ← sessionFiles session
  Persistence.privateDirectory files.directory
  Persistence.withLockWithin files.lock 100 (action files)

/-- Corrupt control state is retained for diagnosis, never repeatedly parsed. -/
def quarantine (path : System.FilePath) : IO Unit := do
  if ← path.pathExists then
    let suffix := toString (← IO.monoNanosNow)
    IO.FS.rename path (.mk (path.toString ++ ".corrupt-" ++ suffix))

def readState? (files : SessionFiles) : IO (Option ThreadState) := do
  try readJson? files.state stateJsonDefaults
  catch error =>
    quarantine files.state
    let disabled : ThreadState := {
      profile := "work", enabled := false,
      lastReason := s!"memory disabled after invalid session state: {error}" }
    writeJson files.state disabled
    pure (some disabled)

def readPendingBase? (files : SessionFiles) : IO (Option PendingTurn) := do
  try readJson? files.pending pendingJsonDefaults
  catch error =>
    quarantine files.pending
    IO.eprintln s!"Eggshell preserved an unreadable staged turn: {error}"
    pure none

def toolDirectory (files : SessionFiles) (turn : String) : System.FilePath :=
  files.directory / "tools" / (Blake3.hex (Blake3.digest "eggshell.turn".toUTF8 [turn.toUTF8]))

/-- Point-addressed lifecycle metadata, retained after a save job is consumed.
A late Stop/result must still have its original turn's destination and scope;
it must never borrow the currently active turn's metadata. -/
def closedTurnPath (files : SessionFiles) (turn : String) : System.FilePath :=
  files.directory / "closed" /
    ((Blake3.hex (Blake3.digest "eggshell.closed-turn".toUTF8 [turn.toUTF8])) ++ ".json")

def readClosedTurn? (files : SessionFiles) (turn : String) : IO (Option PendingTurn) := do
  let record ← (readJson? (closedTurnPath files turn) pendingJsonDefaults : IO (Option PendingTurn))
  pure (record.filter (fun pending => pending.turnId == turn && pending.closed))

def toolReceiptPath (files : SessionFiles) (turn useId : String) : System.FilePath :=
  toolDirectory files turn /
    (Blake3.hex (Blake3.digest "eggshell.tool".toUTF8 [useId.toUTF8]) ++ ".json")

def ToolEvent.native (tool : ToolEvent) : ToolEvent := {tool with source := none}

theorem native_receipt_ignores_source (tool : ToolEvent) (source : Option SourceEvidence.Capture) :
    ({tool with source}.native) = tool.native := rfl

structure SourceCertificate where
  stamp : String
  bytes : Nat
  source : SourceEvidence.Capture
  deriving ToJson, FromJson

def sourceCertificatePath (files : SessionFiles) (turn useId : String) : System.FilePath :=
  files.directory / "sources" / (toolDirectory files turn).fileName.getD "" /
    (toolReceiptPath files turn useId).fileName.getD ""

/-- Parse bytes and observe their version through the same held descriptor.
A replaced or concurrently edited native receipt cannot authorize a companion. -/
def readNativeTool? (path : System.FilePath) : IO (Option (ToolEvent × FileSystem.ReadVersion)) := do
  if (← FileSystem.regularMetadata? path).isNone then return none
  let handle ← FileSystem.openRead path.toString
  let before ← FileSystem.readVersion handle
  let mut bytes := ByteArray.empty
  while bytes.size < before.bytes do
    let count := min 4096 (before.bytes - bytes.size)
    let page ← FileSystem.readPage handle bytes.size.toUInt64 ⟨count, Nat.min_le_left _ _⟩
    if page.size != count then throw (IO.userError "short native receipt read")
    bytes := bytes ++ page
  let after ← FileSystem.readVersion handle
  let current ← FileSystem.readVersion (← FileSystem.openRead path.toString)
  unless FileSystem.stableRead before after current bytes.size do
    throw (IO.userError "native receipt changed during read")
  let some text := String.fromUTF8? bytes | throw (IO.userError "native receipt is not UTF-8")
  let tool ← IO.ofExcept (Json.parse text >>= fromJson? (α := ToolEvent))
  pure (some (tool.native, before))

def attachCertificate (files : SessionFiles) (turn : String)
    (tool : ToolEvent) (version : FileSystem.ReadVersion) : IO ToolEvent := do
  try
    if let some certificate ← (readJson? (sourceCertificatePath files turn tool.useId) :
        IO (Option SourceCertificate)) then
      if certificate.stamp == version.stamp && certificate.bytes == version.bytes then
        return {tool with source := some certificate.source}
  catch _ => pure () -- Optional provenance never discards the native result.
  pure tool.native

/-- Journal the immutable body first; provenance is a small, version-bound
companion. An identical replay performs no body publication. Reusing a native
ID for different bytes is an error, never replacement of an earlier result. -/
def recordTool (files : SessionFiles) (turn : String) (tool : ToolEvent) : IO Unit := do
  let path := toolReceiptPath files turn tool.useId
  if let some (previous, _) ← readNativeTool? path then
    unless toJson previous == toJson tool.native do
      throw (IO.userError "conflicting native tool receipt ID")
  else
    if let some parent := path.parent then FileSystem.durableDirectory parent
    FileSystem.immutableBytes path (toJson tool.native |>.compress |>.toUTF8)
  if let some source := tool.source then
    let some (previous, version) ← readNativeTool? path |
      throw (IO.userError "native receipt disappeared before source publication")
    unless toJson previous == toJson tool.native do
      throw (IO.userError "source certificate belongs to another native result")
    let certificate : SourceCertificate := ⟨version.stamp, version.bytes, source⟩
    let certificatePath := sourceCertificatePath files turn tool.useId
    let equal ← try
      pure ((← (readJson? certificatePath : IO (Option SourceCertificate))).any
        (fun old => toJson old == toJson certificate))
      catch _ => pure false
    unless equal do writeJson certificatePath certificate

def recordedTool? (files : SessionFiles) (turn : String) (tool : ToolEvent) : IO (Option ToolEvent) := do
  let some (previous, version) ← readNativeTool? (toolReceiptPath files turn tool.useId) | return none
  unless toJson previous == toJson tool.native do return none
  some <$> attachCertificate files turn previous version

/-- Tool bodies are separate immutable receipts, not a growing JSON rewrite per hook. -/
def loadToolReceipts (files : SessionFiles) (pending : PendingTurn) : IO PendingTurn := do
  let directory := toolDirectory files pending.turnId
  let mut tools := pending.tools
  if ← directory.pathExists then
    let entries := (← directory.readDir).toList.mergeSort (fun a b => a.fileName ≤ b.fileName)
    for entry in entries do
      if entry.fileName.endsWith ".json" then
        try
          if let some (native, version) ← readNativeTool? entry.path then
            let tool ← attachCertificate files pending.turnId native version
            tools := tools.filter (·.useId != tool.useId) ++ [tool]
        catch error =>
          IO.eprintln s!"Eggshell retained an unreadable tool receipt: {error}"
  pure { pending with tools }

def readPending? (files : SessionFiles) : IO (Option PendingTurn) := do
  (← readPendingBase? files).mapM (loadToolReceipts files)

/-- Immutable queue entries are removed only after the .egg commit succeeds. -/
def queueCheckpoint (files : SessionFiles) (pending : PendingTurn) : IO Unit := do
  let key := Blake3.hex (Blake3.digest "eggshell.checkpoint".toUTF8
    [(toJson pending).compress.toUTF8])
  writeJson (files.directory / "checkpoints" / (key ++ ".json")) pending

def pendingSelection (pending : PendingTurn) : Config.Selection := {
  label := pending.profile
  semanticMatcher := pending.semanticMatcher
  read := pending.read.map fun raw => { name := raw, path := System.FilePath.mk raw }
  write := pending.write.map fun raw => { name := raw, path := System.FilePath.mk raw }
  handoffChars := pending.handoffChars
  localUnion := pending.localUnion
}

def valueEncoding (value : Value) : String :=
  Persistence.valueToJson value |>.compress

def indexOwnerKey (owner : Value) : String :=
  "owner:" ++ toString (hash owner)

/-- A small durable indexing ticket references published owners, not another
    copy of their bodies. Digests locate candidates; the index worker verifies
    unique owners in the authoritative graph before using them. -/
structure IndexTicket where
  target : String
  command : List String
  authority : String
  roots : List String
  deriving ToJson, FromJson, BEq

def indexTicket (target : String) (command : List String)
    (promotion : CommittedPromotion) : IndexTicket := {
  target, command
  authority := valueEncoding promotion.snapshot.authority
  roots := promotion.outcomeRelations.map indexOwnerKey |>.eraseDups
}

theorem index_ticket_root_is_published (target : String) (command : List String)
    (promotion : CommittedPromotion) (key : String)
    (present : key ∈ (indexTicket target command promotion).roots) :
    ∃ owner ∈ promotion.snapshot.values, indexOwnerKey owner = key := by
  simp only [indexTicket, List.mem_eraseDups, List.mem_map] at present
  obtain ⟨owner, member, equal⟩ := present
  exact ⟨owner, promotion.owners_in_snapshot owner member, equal⟩

def queueIndex (files : SessionFiles) (target : String) (command : List String)
    (promotion : CommittedPromotion) : IO Unit := do
  let ticket := indexTicket target command promotion
  let key := Blake3.hex (Blake3.digest "eggshell.index-ticket".toUTF8
    [(toJson ticket).compress.toUTF8])
  let path := files.directory / "indexes" / (key ++ ".json")
  -- Exact comparison, rather than a hash alone, decides duplicate identity.
  if let some previous ← (readJson? path : IO (Option IndexTicket)) then
    if previous == ticket then return
    throw (IO.userError "conflicting index ticket digest")
  writeJson path ticket

def resolveIndexTicket (snapshot : Graph) (ticket : IndexTicket) : IO CommittedPromotion := do
  if valueEncoding snapshot.authority != ticket.authority then
    throw (IO.userError "index ticket belongs to a different authority")
  let candidates := snapshot.values.map fun owner => (indexOwnerKey owner, owner)
  let owners ← ticket.roots.mapM fun key => do
    match candidates.filter (fun candidate => candidate.1 == key) with
    | [(_, owner)] => pure owner
    | [] => throw (IO.userError "published index owner is missing")
    | _ => throw (IO.userError "ambiguous index owner digest")
  prepareCommitted snapshot { outcomeRelations := owners }

def valueKey (value : Value) : String :=
  Persistence.selectionKey value

def allNodes (composite : Persistence.Composite) : List Value :=
  composite.values.flatMap Value.nodes |>.eraseDups

def resolveKey (composite : Persistence.Composite) (key : String) : Except String Value :=
  match (allNodes composite).filter (valueKey · == key) with
  | [value] => pure value
  | [] => throw s!"unknown Value {key}"
  | _ => throw s!"ambiguous display key {key}; inspect the full graph"

/-
Native JSON is identity-bearing data, not display framing. Lean's JSON object is
an ordered map, so parse-and-compress preserves keys, types, containers, array
order, and null while making object-key order irrelevant.
-/
def canonicalJson (encoded : String) : String :=
  match Json.parse encoded with
  | .ok json => json.compress
  | .error _ => encoded

/--
The whole native invocation remains the reservation identity. Object-key order
is normalized, while every semantic distinction in the native input is retained.
-/
def canonicalToolWork (tool : ToolEvent) : String :=
  tool.name ++ "\n" ++ canonicalJson tool.input

/--
Remember an admitted native occurrence for later PostToolUse correlation.
Reservations never control execution because Codex does not emit a terminal
hook for every failed or externally blocked tool.
-/
def reserveTool (pending : PendingTurn) (tool : ToolEvent) : PendingTurn :=
  { pending with
    inFlight := pending.inFlight.filter (·.useId != tool.useId) ++ [tool] }

/-- Close exactly one native occurrence and retain one completed tool record. -/
def finishTool (pending : PendingTurn) (tool : ToolEvent) : PendingTurn :=
  { pending with
    inFlight := pending.inFlight.filter (fun current => current.useId != tool.useId)
    tools := pending.tools.filter (fun current => current.useId != tool.useId) ++ [tool] }

/-- A denied or failed PreToolUse releases only its own transient reservation. -/
def cancelTool (pending : PendingTurn) (useId : String) : PendingTurn :=
  { pending with inFlight := pending.inFlight.filter (·.useId != useId) }

/-- A session owns one pending turn; an omitted hook turn ID denotes that turn. -/
def matchesHookTurn (pending : PendingTurn) : Option String → Bool
  | none => true
  | some turn => turn == pending.turnId

@[simp] theorem matchesHookTurn_omitted (pending : PendingTurn) :
    matchesHookTurn pending none = true := rfl

theorem cancelTool_removes_useId (pending : PendingTurn) (useId : String) :
    (cancelTool pending useId).inFlight.all (·.useId != useId) := by
  simp [cancelTool]

def relation? (operator : Operator) (arguments : List Ref) : Except String Value :=
  match Relation.apply? operator arguments with
  | some relation => pure relation
  | none => throw s!"invalid {Persistence.operatorName operator} relation"

/-- One native invocation owns exactly one observed Work→Outcome edge. -/
def observedWorkOutcome (work observed occurrence : Value) : Value × Value :=
  let edge := OutcomeEdge.make work observed [occurrence]
    (by simp) (by simp [maxOutcomeObservations])
  (work, edge.relation)

@[simp]
theorem observedWorkOutcome_work (work observed occurrence : Value) :
    (observedWorkOutcome work observed occurrence).1 = work := rfl

/--
One native occurrence cites its Work and Outcome once. Session, turn, and the
native tool-use ID are the exact occurrence identity; repeating the raw input
and response here would retain the same payload twice without adding authority.
-/
def nativeOccurrenceArguments (session turn : Value) (tool : ToolEvent) : List Ref :=
  [
    .semantic (.text (canonicalJson tool.response)),
    .semantic (.text (canonicalToolWork tool)),
    .exact session,
    .exact turn,
    .exact (.text tool.useId)]

def nativeOccurrence (session turn : Value) (tool : ToolEvent) : Value :=
  .applyList .occurrence (nativeOccurrenceArguments session turn tool)

theorem nativeOccurrence_valid (session turn : Value) (tool : ToolEvent) :
    Relation.validArguments .occurrence
      (nativeOccurrenceArguments session turn tool) := by
  have semantic : (Authority.semantic == Authority.semantic) = true := by decide
  have exact : (Authority.exact == Authority.semantic) = false := by decide
  simp [nativeOccurrenceArguments, Relation.validArguments,
    Relation.splitOccurrence, Relation.semanticValues, Relation.exactValues,
    Ref.semantic, Ref.exact, List.takeWhile, semantic, exact]

theorem nativeOccurrence_exactFootprint (session turn : Value) (tool : ToolEvent) :
    (nativeOccurrence session turn tool).exactFootprint =
      session :: session.exactFootprint ++
      turn :: turn.exactFootprint ++ [.text tool.useId] := by
  simp [nativeOccurrence, nativeOccurrenceArguments, Value.applyList,
    Refs.ofList, Value.exactFootprint, Value.refsExactFootprint,
    Ref.semantic, Ref.exact, Value.text]

/-
Native tool facts have one compiler regardless of whether they are still
staged or are being promoted.  The active turn can therefore join the same
run-local WorkGraph as committed `.egg` authorities without inventing a
second trace format or granting the stage persistent authority.
-/
def compileOperationOutcomes (session turn : Value) (tool : ToolEvent) :
    Value × Value :=
  let work := Value.text (canonicalToolWork tool)
  let observed := Value.text (canonicalJson tool.response)
  observedWorkOutcome work observed (nativeOccurrence session turn tool)

def operationChildren (pending : PendingTurn) : List Value :=
  ((pending.tools.map fun tool =>
    (compileOperationOutcomes (.text pending.sessionId) (.text pending.turnId) tool).1).eraseDups) ++
    [HandoffRemainder.value pending.prompt]

theorem operation_checkpoint_keeps_open_remainder (pending : PendingTurn) :
    HandoffRemainder.value pending.prompt ∈ operationChildren pending := by
  simp [operationChildren]

def compileOperationGraph (pending : PendingTurn) : Except String (List Value × Value) := do
  let facts := pending.tools.map (compileOperationOutcomes (.text pending.sessionId) (.text pending.turnId))
  let all ← relation? .all
    (.semantic (.text pending.prompt) :: (operationChildren pending).map Ref.semantic)
  pure (facts.map (·.2), all)

def operationSourceReceipts (pending : PendingTurn) : List Value :=
  pending.tools.filterMap fun tool => tool.source.map fun capture =>
    let owner := (compileOperationOutcomes (.text pending.sessionId) (.text pending.turnId) tool).2
    SourceEvidence.receipt (.text pending.sessionId) (.text pending.turnId)
      (.text tool.useId) owner capture.record

theorem operation_owner_ignores_source (session turn : Value) (tool : ToolEvent)
    (source : Option SourceEvidence.Capture) :
    compileOperationOutcomes session turn {tool with source} =
      compileOperationOutcomes session turn tool := rfl

/--
An unresolved native occurrence and a missing final message cannot affect the
observed operation graph.  Recovery may therefore retain exactly the terminal
tool outcomes while leaving the parent Work open.
-/
theorem compileOperationGraph_ignores_unobserved (pending : PendingTurn)
    (inFlight : List ToolEvent) (finalMessage : Option String) :
    compileOperationGraph {
      pending with inFlight := inFlight, finalMessage := finalMessage
    } = compileOperationGraph pending := by
  rfl

/-- The active turn joins the same positive graph shape later promoted to `.egg`. -/
def stagedGraphValues (pending : PendingTurn) : Except String (List Value) := do
  let (outcomes, all) ← compileOperationGraph pending
  pure (outcomes ++ [all] ++ operationSourceReceipts pending)

def turnSources (pending : PendingTurn) : SourceEvidence.Record :=
  let records := pending.tools.map fun tool =>
    tool.source.map (·.record) |>.getD SourceEvidence.unverified
  { workspace := (System.FilePath.mk pending.cwd).fileName.getD pending.cwd
    files := records.flatMap (·.files) |>.eraseDups
    uris := records.flatMap (·.uris) |>.eraseDups
    complete := !records.isEmpty && records.all (·.complete) }

structure CompiledTurn (source : Graph) where
  transaction : Transaction
  promotion : Promotion
  transaction_authority : transaction.authority = source.authority
  transaction_revision : transaction.baseRevision = source.revision

def compile (graph : Graph) (pending : PendingTurn) (target : String) :
    Except String (CompiledTurn graph) := do
  let session := Value.text pending.sessionId
  let turn := Value.text pending.turnId
  let cwd := Value.text pending.cwd
  let task := Value.text pending.prompt
  let (outcomeRelations, all) ← compileOperationGraph pending
  let targetValue := Value.text target
  let (values, promotedOutcomes) ← match pending.finalMessage with
    | some finalMessage =>
        let result := Value.text finalMessage
        let turnOccurrence ← relation? .occurrence [
          .semantic task, .semantic result, .exact session, .exact turn, .exact cwd]
        let parentOutcome ← relation? .outcome [
          .semantic task, .semantic result, .exact turnOccurrence]
        let receipt ← relation? .receipt [
          .exact session, .exact turn, .exact task, .exact result,
          .exact parentOutcome, .exact all, .exact targetValue]
        let sourceReceipts := if pending.tools.any (·.source.isSome) then
          [SourceEvidence.receipt session turn (.text "parent") parentOutcome (turnSources pending)] else []
        pure
          ((outcomeRelations ++ [all, parentOutcome, receipt] ++ sourceReceipts ++ operationSourceReceipts pending).eraseDups,
            outcomeRelations ++ [parentOutcome])
    | none =>
        if pending.tools.isEmpty then
          throw "cannot promote an interrupted turn without observed outcomes"
        let receipt ← relation? .receipt [
          .exact session, .exact turn, .exact task, .exact cwd,
          .exact all, .exact targetValue, .exact (.text "interrupted before final response")]
        pure ((outcomeRelations ++ [all, receipt] ++ operationSourceReceipts pending).eraseDups, outcomeRelations)
  /-
  Only authoritative relation roots are stored. Their structural Values contain
  every Atom and occurrence, so duplicating that closure as top-level records
  changes no semantics and only inflates `.egg`.
  -/
  match accepted : (Transaction.begin graph).stageValues? (values.filter (!graph.values.contains ·)) with
  | none => throw "turn compiler produced an invalid Value"
  | some transaction =>
      have source := Transaction.stageValues?_preserves_source accepted
      pure {
        transaction
        promotion := {
          outcomeRelations := promotedOutcomes
        }
        transaction_authority := source.1
        transaction_revision := source.2
      }

theorem compiled_transaction_belongs_to_source {graph pending target compiled}
    (_accepted : compile graph pending target = .ok compiled) :
    compiled.transaction.authority = graph.authority ∧
      compiled.transaction.baseRevision = graph.revision :=
  ⟨compiled.transaction_authority, compiled.transaction_revision⟩

theorem compiled_values_are_well_formed {graph : Graph}
    (compiled : CompiledTurn graph) :
    ∀ value, value ∈ compiled.transaction.stagedValues →
      Relation.wellFormed value :=
  compiled.transaction.stagedValues_wellFormed

def promote (pending : PendingTurn) (target : System.FilePath) : IO CommittedPromotion := do
  let (snapshot, promotion) ← Persistence.appendPrepared target fun graph => do
    let compiled ← compile graph pending target.toString
    pure (compiled.transaction, compiled.promotion)
  prepareCommitted snapshot promotion

/-- Outcome roots in a live checkpoint come only from observed native operations. -/
def observedRoots (pending : PendingTurn) : List Value :=
  pending.tools.map fun tool =>
    (compileOperationOutcomes (.text pending.sessionId) (.text pending.turnId) tool).2

theorem checkpoint_ignores_parent_status (pending : PendingTurn)
    (finalMessage : Option String) (inFlight : List ToolEvent) :
    observedRoots { pending with finalMessage, inFlight } = observedRoots pending := by
  rfl

theorem checkpoint_has_only_observed_roots (pending : PendingTurn) (root : Value)
    (present : root ∈ observedRoots pending) :
    ∃ tool ∈ pending.tools,
      (compileOperationOutcomes (.text pending.sessionId) (.text pending.turnId) tool).2 = root := by
  simpa [observedRoots] using present

def promoteObservations (pending : PendingTurn) (target : System.FilePath) : IO CommittedPromotion := do
  -- Persist precisely the existing staged graph, including its open All edge.
  -- This makes operations reusable children without completing the parent.
  let roots ← IO.ofExcept (stagedGraphValues pending)
  let (snapshot, _) ← Persistence.appendPrepared target fun graph => do
    let some transaction := (Transaction.begin graph).stageValues? (roots.filter (!graph.values.contains ·)) |
      throw "observation compiler produced an invalid Value"
    pure (transaction, ())
  prepareCommitted snapshot { outcomeRelations := observedRoots pending }

end Eggshell.Plugin
