module

public import Eggshell.Handoff
public import Eggshell.Warm
public import Std.Sync.Mutex
public import Eggshell.WorkerLifetime

@[expose] public section

namespace Eggshell.Plugin.Worker

open Lean

abbrev Child := IO.Process.Child { stdin := .piped, stdout := .piped, stderr := .null }

structure Slot where
  gate : Std.Mutex Unit
  child : Std.Mutex (Lifetime.Cell (Option Child))

initialize slots : Std.Mutex (Lifetime.Cell (List (String × Slot))) ← Std.Mutex.new (.open [])

def slotFor (session role : String) : IO Slot := slots.atomically do
  let key := session ++ ":" ++ role
  match ← get with
  | .closed => pure {gate := ← Std.Mutex.new (), child := ← Std.Mutex.new .closed}
  | .open current =>
      if let some (_, slot) := current.find? (·.1 == key) then return slot
      let slot := { gate := ← Std.Mutex.new (), child := ← Std.Mutex.new (.open none) }
      set (Lifetime.Cell.open ((key, slot) :: current))
      pure slot

/-- Call only for a child spawned with `setsid := true`. -/
def killGroup {cfg : IO.Process.StdioConfig} (child : IO.Process.Child cfg) : IO Unit := do
  let killer ← IO.Process.spawn {
    cmd := "/bin/kill", args := #["-KILL", "--", "-" ++ toString child.pid]
    stdin := .null, stdout := .null, stderr := .null }
  let _ ← killer.wait
  try child.kill catch _ => pure ()

def cancelSlot (slot : Slot) : IO Unit := do
  let idle ← slot.gate.tryAtomically (pure ())
  if idle.isSome then return
  slot.child.atomically do
    match Lifetime.admit (← get) with
    | .reuse child => killGroup child
    | _ => pure ()

/-- Independent pipes permit overlapping reads without sharing a reply or
request cancellation. This is a per-manager concurrency bound, not a limit on
chats, users, or stored memory. Numerical model lifetime remains device-wide. -/
def readLaneCount : Nat := 4

abbrev ReadLane := Fin readLaneCount

def readLanes (count : Nat := readLaneCount) : List (Fin count) := List.finRange count

def readLaneKey (lane : Fin count) : String := "search-" ++ toString lane.val

structure ReadPool (count : Nat := readLaneCount) where
  pipes : Vector Slot count

def ReadPool.slot (pool : ReadPool count) (lane : Fin count) : Slot :=
  pool.pipes[lane]

def readPoolFor (session : String) : IO ReadPool := do
  let pipes ← (Vector.ofFn (fun lane : ReadLane => lane)).mapM fun lane =>
    slotFor session (readLaneKey lane)
  pure {pipes}

def cancel (session role : String) : IO Unit := do
  if role == "search" then
    let pool ← readPoolFor session
    for lane in readLanes readLaneCount do cancelSlot (pool.slot lane)
  else cancelSlot (← slotFor session role)

def retire (slot : Slot) (child : Child) : IO Unit := do
  let owned ← slot.child.atomically do
    let (state, owned) := Lifetime.release (fun current => current.pid == child.pid) (← get)
    set state
    pure owned
  if let some owned := owned then
    killGroup owned
    let _ ← owned.wait
    pure ()

partial def awaitUntil (task : Task (Except IO.Error α)) (deadline : Nat) : IO (Option α) := do
  if ← IO.hasFinished task then
    match ← IO.wait task with
    | .ok value => return some value
    | .error error => throw error
  if (← IO.monoMsNow) ≥ deadline then return none
  IO.sleep 5
  awaitUntil task deadline

structure Search where
  pending : PendingTurn
  state : ThreadState
  work : String
  enforce : Bool
  evidence : Option String := none
  staged : Bool := false
  deadline : Nat := 0
  route : SearchRoute := .configured
  receipt : Option String := none
  deriving ToJson, FromJson

/-- Every search frame belongs to one native invocation, including its original
deadline. Progress changes scheduling only; it has no Handoff payload. -/
structure SearchIdentity where
  turn : String
  epoch : Nat
  deadline : Nat
  receipt : Option String
  deriving BEq, Repr, ToJson, FromJson

inductive SearchFrame where
  | ready (identity : SearchIdentity)
  | reply (identity : SearchIdentity) (handoff : Option Handoff)
  deriving ToJson, FromJson

structure SearchPolicy where
  identity : SearchIdentity
  finishReady : Bool := false
  onReady : Nat → IO Unit := fun _ => pure ()

def Search.identity (request : Search) : SearchIdentity :=
  { turn := request.pending.turnId, epoch := request.state.epoch,
    deadline := request.deadline, receipt := request.receipt }

def readyDeadline (expected actual : SearchIdentity) (finishReady : Bool)
    (cutoff arrived : Nat) : Nat :=
  min expected.deadline (if finishReady && expected == actual && arrived < cutoff then
    expected.deadline else cutoff)

theorem ready_preserves_upstream (expected actual : SearchIdentity) (finishReady : Bool)
    (cutoff arrived : Nat) :
    readyDeadline expected actual finishReady cutoff arrived ≤ expected.deadline :=
  Nat.min_le_left _ _

theorem unready_preserves_cutoff (expected actual : SearchIdentity) (cutoff arrived : Nat) :
    readyDeadline expected actual false cutoff arrived ≤ cutoff := by
  simpa [readyDeadline] using (Nat.min_le_right expected.deadline cutoff)

theorem late_ready_preserves_cutoff (expected actual : SearchIdentity) (finishReady : Bool)
    (cutoff arrived : Nat) (late : cutoff ≤ arrived) :
    readyDeadline expected actual finishReady cutoff arrived ≤ cutoff := by
  simpa [readyDeadline, Nat.not_lt.mpr late] using (Nat.min_le_right expected.deadline cutoff)

theorem foreign_ready_preserves_cutoff (expected actual : SearchIdentity) (finishReady : Bool)
    (cutoff arrived : Nat) (foreign : (expected == actual) = false) :
    readyDeadline expected actual finishReady cutoff arrived ≤ cutoff := by
  simpa [readyDeadline, foreign] using (Nat.min_le_right expected.deadline cutoff)

/-- One optional ready frame followed by one final reply. Repeated, foreign or
late progress cannot restart or extend the upstream deadline. -/
def readSearchReply (input : IO.FS.Handle) (policy : SearchPolicy)
    (window : Std.Mutex Nat) : IO Json := do
  let readFrame : IO SearchFrame := do
    IO.ofExcept (Json.parse (← input.getLine) >>= fromJson? (α := SearchFrame))
  let frame ← readFrame
  let reply ← match frame with
    | .ready identity => do
        let arrived ← window.atomically do
          let cutoff ← get
          let arrived ← IO.monoMsNow
          unless identity == policy.identity && arrived < cutoff do
            throw (IO.userError "foreign or expired search progress")
          set (readyDeadline policy.identity identity policy.finishReady cutoff arrived)
          pure arrived
        policy.onReady arrived
        readFrame
    | other => pure other
  match reply with
  | .reply identity result =>
      unless identity == policy.identity do throw (IO.userError "foreign search reply")
      unless (← IO.monoMsNow) < (← window.atomically get) do
        throw (IO.userError "expired search reply")
      return toJson result
  | .ready _ => throw (IO.userError "repeated search progress")

partial def awaitSearch (task : Task (Except IO.Error α)) (window : Std.Mutex Nat) : IO (Option α) := do
  if ← IO.hasFinished task then
    match ← IO.wait task with
    | .ok value => return some value
    | .error error => throw error
  if (← IO.monoMsNow) ≥ (← window.atomically get) then return none
  IO.sleep 5
  awaitSearch task window

/-- Execution permission is constructed from a fresh monotonic-clock sample
inside the worker gate, after any contention wait. -/
structure OpenWindow (deadline : Nat) where
  now : Nat
  before : now < deadline

def OpenWindow.check (deadline now : Nat) : Option (OpenWindow deadline) :=
  if before : now < deadline then some ⟨now, before⟩ else none

theorem expired_window_cannot_start (deadline now : Nat) (expired : deadline ≤ now) :
    OpenWindow.check deadline now = none := by
  simp [OpenWindow.check, Nat.not_lt.mpr expired]

/-- A busy gate is a continuation, distinct from a completed empty action. -/
inductive GateDecision (α : Type) where
  | expired
  | retry
  | finished (result : Option α)

def gateDecision (deadline now : Nat) (probe : Option (Option α)) : GateDecision α :=
  if now < deadline then
    match probe with
    | none => .retry
    | some result => .finished result
  else .expired

theorem busy_open_gate_retries (deadline now : Nat) (before : now < deadline) :
    gateDecision deadline now (none : Option (Option α)) = .retry := by
  simp [gateDecision, before]

theorem completed_empty_gate_is_finished (deadline now : Nat) (before : now < deadline) :
    gateDecision deadline now (some none : Option (Option α)) = .finished none := by
  simp [gateDecision, before]

/-- Wait in the requesting task: no extra worker, abandoned queued action, or
blocking mutex acquisition. Contention consumes the same deadline as execution.
The second clock check prevents an expired waiter from starting a pipe request. -/
partial def withGateWithin (gate : Std.Mutex Unit) (deadline : Nat)
    (action : OpenWindow deadline → IO α) : IO (Option α) := do
  if ← IO.checkCanceled then return none
  let now ← IO.monoMsNow
  if now ≥ deadline then return none
  let probe ← gate.tryAtomically do
    match OpenWindow.check deadline (← IO.monoMsNow) with
    | none => pure none
    | some window => some <$> action window
  match gateDecision deadline now probe with
  | .expired => pure none
  | .finished result => pure result
  | .retry =>
      IO.sleep (min 5 (deadline - now)).toUInt32
      withGateWithin gate deadline action

/-- The admission records exactly which pipe owns execution and a fresh clock
sample after acquiring that pipe's gate. An expired waiter owns no pipe. -/
structure ReadAdmission (deadline : Nat) (count : Nat := readLaneCount) where
  lane : Fin count
  window : OpenWindow deadline

theorem read_admission_is_live (admission : ReadAdmission deadline count) :
    admission.window.now < deadline := admission.window.before

theorem read_admission_is_bounded (admission : ReadAdmission deadline count) :
    admission.lane.val < count := admission.lane.isLt

/-- Probe all pipes before sleeping. A completed `none` is still a completion;
only a busy gate retries. No action is left queued after the caller expires. -/
def probeReadPool (pool : ReadPool count) (deadline : Nat)
    (action : ReadAdmission deadline count → IO α) : IO (Option (Option α)) := do
  for lane in readLanes count do
    let probe ← (pool.slot lane).gate.tryAtomically do
      match OpenWindow.check deadline (← IO.monoMsNow) with
      | none => pure none
      | some window => some <$> action ⟨lane, window⟩
    if probe.isSome then return probe
  pure none

partial def withReadPoolWithin (pool : ReadPool count) (deadline : Nat)
    (action : ReadAdmission deadline count → IO α) : IO (Option α) := do
  if ← IO.checkCanceled then return none
  let now ← IO.monoMsNow
  if now ≥ deadline then return none
  match gateDecision deadline now (← probeReadPool pool deadline action) with
  | .expired => pure none
  | .finished result => pure result
  | .retry =>
      IO.sleep (min 5 (deadline - now)).toUInt32
      withReadPoolWithin pool deadline action

/-- Search contention waits within the hook's own deadline rather than dropping
the request. Saving and indexing remain separate, independently scheduled lanes.
Pipe writes and reads use the remaining deadline after admission. -/
def exchange (session role : String) (payload : Json) (deadline : Nat)
    (searchPolicy : Option SearchPolicy := none) : IO (Option Json) := do
  let searchPolicy ← if role == "search" then
      match searchPolicy with
      | some policy => pure (some policy)
      | none => do
          let request ← IO.ofExcept (fromJson? payload : Except String Search)
          pure (some {identity := request.identity})
    else pure none
  let deadline := searchPolicy.map (fun policy => min deadline policy.identity.deadline) |>.getD deadline
  let execute := fun (slot : Slot) (_window : OpenWindow deadline) => do
    let child ← slot.child.atomically do
      match Lifetime.admit (← get) with
      | .refused => pure none
      | .reuse child => pure (some child)
      | .spawn =>
          let child ← IO.Process.spawn {
            cmd := (← IO.appPath).toString, args := #["codex-worker", role]
            stdin := .piped, stdout := .piped, stderr := .null, setsid := true }
          set (Lifetime.Cell.open (some child))
          pure (some child)
    let some child := child | return none
    try
      let window ← Std.Mutex.new deadline
      let task ← IO.asTask (do
        child.stdin.putStr (payload.compress ++ "\n")
        child.stdin.flush
        match searchPolicy with
        | some policy => readSearchReply child.stdout policy window
        | none => IO.ofExcept (Json.parse (← child.stdout.getLine))) .dedicated
      let result ← if role == "save" then do
        match ← IO.wait task with
        | .ok json => pure (some json)
        | .error error => throw error
        else if searchPolicy.isSome then awaitSearch task window
        else awaitUntil task deadline
      match result with
      | some json => return some json
      | none =>
          retire slot child
          let _ ← IO.wait task
          return none
    catch error =>
      retire slot child
      IO.eprintln s!"Eggshell {role} worker stopped: {error}"
      return none
  let result ← if role == "search" then do
      let pool ← readPoolFor session
      withReadPoolWithin pool deadline fun admission =>
        execute (pool.slot admission.lane) admission.window
    else do
      let slot ← slotFor session role
      slot.gate.tryAtomically do
      match OpenWindow.check deadline (← IO.monoMsNow) with
      | none => pure none
      | some window => execute slot window
  pure (result.bind id)

/-- A finished search is publishable only in its requesting context and before
    its deadline. An incomplete search can carry only a current-context notice,
    never an arbitrary Handoff or a completion checkpoint. -/
inductive SearchDelivery (stamp : RequestStamp) (turn : String) (epoch now budget : Nat) where
  | obsolete
  | incomplete (currentTurn : stamp.turn = turn) (currentEpoch : stamp.epoch = epoch)
  | empty (accepted : stamp.accepts turn epoch now = true)
  | found (accepted : stamp.accepts turn epoch now = true)
      (handoff : Handoff) (fits : handoff.text.length ≤ budget)
      (bytesFit : handoff.text.utf8ByteSize ≤ Config.nativeHandoffBytes)

def SearchDelivery.ofReply (stamp : RequestStamp) (turn : String) (epoch now budget : Nat)
    (reply : Option Json) : SearchDelivery stamp turn epoch now budget :=
  if currentTurn : stamp.turn = turn then
    if currentEpoch : stamp.epoch = epoch then
      if accepted : stamp.accepts turn epoch now = true then
        match reply with
        | none => .incomplete currentTurn currentEpoch
        | some json =>
            match (fromJson? json : Except String (Option Handoff)) with
            | .error _ => .incomplete currentTurn currentEpoch
            | .ok none => .empty accepted
            | .ok (some handoff) =>
                if fits : handoff.text.length ≤ budget ∧
                    handoff.text.utf8ByteSize ≤ Config.nativeHandoffBytes then
                  .found accepted handoff fits.1 fits.2
                else .incomplete currentTurn currentEpoch
      else .incomplete currentTurn currentEpoch
    else .obsolete
  else .obsolete

def SearchDelivery.handoff {stamp : RequestStamp} {turn : String} {epoch now budget : Nat} :
    SearchDelivery stamp turn epoch now budget → Option Handoff
  | .obsolete | .empty _ => none
  | .incomplete _ _ => some pendingSearch
  | .found _ handoff _ _ => some handoff

/-- Oversized UTF-8 data cannot become delivered evidence even if the profile's
character allowance is large enough. The receipt remains authority-free. -/
theorem oversized_utf8_reply_is_incomplete (stamp : RequestStamp) (turn : String)
    (epoch now budget : Nat) (json : Json) (handoff : Handoff)
    (currentTurn : stamp.turn = turn) (currentEpoch : stamp.epoch = epoch)
    (parsed : (fromJson? json : Except String (Option Handoff)) = .ok (some handoff))
    (tooLarge : Config.nativeHandoffBytes < handoff.text.utf8ByteSize) :
    (SearchDelivery.ofReply stamp turn epoch now budget (some json)).handoff = some pendingSearch := by
  by_cases accepted : stamp.accepts turn epoch now = true <;>
    simp [SearchDelivery.ofReply, SearchDelivery.handoff, currentTurn, currentEpoch,
      accepted, parsed, Nat.not_le_of_gt tooLarge]

theorem incomplete_delivery_has_no_authority (stamp : RequestStamp) (turn : String)
    (epoch now budget : Nat) (currentTurn : stamp.turn = turn) (currentEpoch : stamp.epoch = epoch) :
    let delivery : SearchDelivery stamp turn epoch now budget := .incomplete currentTurn currentEpoch
    delivery.handoff = some pendingSearch ∧ pendingSearch.completed = 0 ∧
      pendingSearch.deliveredGraphs = [] ∧ pendingSearch.coveredFragments = [] ∧
      pendingSearch.blocksCurrent = false := by
  exact ⟨rfl, pending_search_has_no_authority⟩

theorem stale_search_reply_is_discarded (stamp : RequestStamp) (turn : String)
    (epoch now budget : Nat) (reply : Option Json) (stale : stamp.turn ≠ turn) :
    (SearchDelivery.ofReply stamp turn epoch now budget reply).handoff = none := by
  simp [SearchDelivery.ofReply, SearchDelivery.handoff, stale]

theorem old_context_reply_is_discarded (stamp : RequestStamp) (turn : String)
    (epoch now budget : Nat) (reply : Option Json) (stale : stamp.epoch ≠ epoch) :
    (SearchDelivery.ofReply stamp turn epoch now budget reply).handoff = none := by
  simp [SearchDelivery.ofReply, SearchDelivery.handoff, stale]

theorem expired_search_reply_is_incomplete (stamp : RequestStamp) (turn : String)
    (epoch now budget : Nat) (reply : Option Json)
    (currentTurn : stamp.turn = turn) (currentEpoch : stamp.epoch = epoch)
    (expired : stamp.deadline ≤ now) :
    (SearchDelivery.ofReply stamp turn epoch now budget reply).handoff = some pendingSearch := by
  simp [SearchDelivery.ofReply, SearchDelivery.handoff, currentTurn, currentEpoch,
    expired_request_cannot_publish stamp turn epoch now expired]

theorem missing_search_reply_is_incomplete (stamp : RequestStamp) (turn : String)
    (epoch now budget : Nat)
    (currentTurn : stamp.turn = turn) (currentEpoch : stamp.epoch = epoch) :
    (SearchDelivery.ofReply stamp turn epoch now budget none).handoff = some pendingSearch := by
  by_cases accepted : stamp.accepts turn epoch now = true <;>
    simp [SearchDelivery.ofReply, SearchDelivery.handoff, currentTurn, currentEpoch, accepted]

/-- Seal admission before waiting for any process. Old slots and late callers
can no longer create a child; each existing child has one retiring owner. -/
def shutdown : IO Unit := do
  let owned ← slots.atomically do
    let (state, owned) := Lifetime.close (← get)
    set state
    pure (owned.getD [])
  for (_, slot) in owned do
    let child ← slot.child.atomically do
      let (state, owned) := Lifetime.close (← get)
      set state
      pure (owned.bind id)
    if let some child := child then
      killGroup child
      let _ ← child.wait
      pure ()

/-- A waiting search must refresh acknowledged deliveries in its own live
context before rendering. The captured pre-wait state cannot admit execution. -/
structure CurrentSearch (request : Search) where
  state : ThreadState
  pending : PendingTurn
  valid : pending.turnId = request.pending.turnId ∧ state.epoch = request.state.epoch ∧
    state.enabled = true ∧ pending.closed = false ∧ pending.finalMessage.isNone = true

def currentSearch? (request : Search) (state : ThreadState) (pending : PendingTurn) :
    Option (CurrentSearch request) :=
  if valid : pending.turnId = request.pending.turnId ∧ state.epoch = request.state.epoch ∧
      state.enabled = true ∧ pending.closed = false ∧ pending.finalMessage.isNone = true then
    some ⟨state, pending, valid⟩
  else none

theorem stale_waiter_cannot_start (request : Search) (state : ThreadState)
    (pending : PendingTurn) (stale : pending.turnId ≠ request.pending.turnId) :
    currentSearch? request state pending = none := by
  simp [currentSearch?, stale]

theorem changed_waiter_context_cannot_start (request : Search) (state : ThreadState)
    (pending : PendingTurn) (changed : state.epoch ≠ request.state.epoch) :
    currentSearch? request state pending = none := by
  simp [currentSearch?, changed]

def search (request : Search) (onSemanticReady : IO Unit := pure ()) : IO (Option Handoff) := do
  let files ← sessionFiles request.pending.sessionId
  -- Metadata is atomically published by the manager. A search may read it but
  -- must not quarantine or rewrite control state outside the manager's lock.
  let some state ← (readJson? files.state stateJsonDefaults : IO (Option ThreadState)) |
    throw (IO.userError "search context state disappeared")
  let some pending ← (readJson? files.pending pendingJsonDefaults : IO (Option PendingTurn)) |
    throw (IO.userError "search turn disappeared")
  let some current := currentSearch? request state pending | return none
  let configured := pendingSelection request.pending
  let selection := {configured with
    handoffBytes := some Config.nativeHandoffBytes
    semanticMatcher := if request.route == .lexical then none else configured.semanticMatcher}
  match request.pending.projection with
  | .none => pure none
  | .roots keys => manualHandoff selection request.work keys
  | .automatic =>
      let mut staged := []
      -- Unsaved observations remain reusable even while a writer is busy or
      -- the authority is temporarily unavailable. Read them before the .egg
      -- snapshot, so a concurrent completed commit cannot create a gap.
      for name in ["deferred", "checkpoints"] do
        let directory := files.directory / name
        if ← directory.pathExists then
          for entry in ← directory.readDir do
            if entry.fileName.endsWith ".json" then
              try
                if let some base ← (readJson? entry.path pendingJsonDefaults : IO (Option PendingTurn)) then
                  if base.write.any request.pending.read.contains then
                    let pending ← loadToolReceipts files base
                    let values ← IO.ofExcept (stagedGraphValues pending)
                    staged := staged ++ values
              catch _ => pure ()
      if request.staged then
        let pending ← readPending? files
        let snapshot := pending.filter (·.turnId == request.pending.turnId)
        staged := staged ++ (← IO.ofExcept (stagedGraphValues (snapshot.getD request.pending)))
      staged := staged.eraseDups
      automaticHandoff selection request.work
        (current.state.deliveryClaims pending.turnId (← IO.monoMsNow))
        request.enforce request.evidence staged (!current.state.afterCompaction)
        request.pending.localUnion
        (some {
          workspace := System.FilePath.mk request.pending.cwd
          deadline := request.deadline
          question := request.pending.prompt
          targets := SourceEvidence.workTargets? (System.FilePath.mk request.pending.cwd) request.work
          native := request.enforce || request.evidence.isSome
          receipt := request.receipt
          onSemanticReady
          onDependencies := fun sources =>
            queueCheckpoint files {request.pending with tools := [], sources := sources, inFlight := [], finalMessage := none, closed := false} })
        (request.route != .lexical)

/-- Batch compatible metadata tickets on one read snapshot. Index failure
    retains every ticket; indexing never republishes or locks the graph writer. -/
def indexQueued (target : IndexTarget) (paths : List System.FilePath) : IO Nat := do
  let pinned ← target.owner.pin
  let (pinned,_) ← Warm.refreshSource pinned target.storage ((← IO.monoMsNow)+60000)
  let _ ← Synapses.CanonicalSource.Cache.refresh pinned target.storage
  let _ ← RetrievalResearch.Index.warm pinned target.storage
  let directory ← target.indexes pinned
  DB.Sidecar.withIndexClaim target.owner (fun _ => indexOwned pinned directory) target.storage
where
 indexOwned (pinned : DB.PageMap.Snapshot) (directory : System.FilePath) : IO Nat := do
  let mut tickets : List System.FilePath := []
  let mut items : List SemanticMatcher.Item := []
  for path in paths.eraseDups do
    let path ← DB.PageMap.absolute path
    if path.parent != some directory then
      IO.eprintln "Eggshell refused an index ticket outside its DB lane"
      continue
    try
      if !(← path.pathExists) then continue
      let ticket ← (readBoundedJson path 1048576 : IO IndexTicket)
      unless ticket.database == pinned.head.identity &&
          ticket.provider == indexProviderKey target.command && ticket.authority == pinned.head.authority do
        throw (IO.userError "index ticket belongs to another DB or provider")
      let snapshot ← Persistence.Store.owners pinned ticket.roots
      let committed ← resolveIndexTicket snapshot ticket
      items := items ++ SemanticMatcher.outcomeWorkItems committed.outcomeRelations
      tickets := tickets ++ [path]
    catch error =>
      -- Retain the bytes outside the active suffix so a damaged first batch
      -- cannot permanently starve later valid publications.
      quarantine path
      IO.eprintln s!"Eggshell quarantined an invalid index ticket: {error}"
  if tickets.isEmpty then return 0
  let _receipt ← SemanticMatcher.indexWorks target.command
    items.eraseDups
    (some target.owner) target.storage
  for path in tickets do removeIfExists path
  pure tickets.length

def run (role : String) : IO UInt32 := do
  let input ← IO.getStdin
  let output ← IO.getStdout
  repeat
    let line ← input.getLine
    if line.isEmpty then break
    let result ← try
      let json ← IO.ofExcept (Json.parse line)
      if role == "search" then
        let request ← IO.ofExcept (fromJson? json : Except String Search)
        let announced ← IO.mkRef false
        let ready := do
          unless ← announced.get do
            announced.set true
            output.putStrLn (toJson (SearchFrame.ready request.identity)).compress
            output.flush
        pure (toJson (SearchFrame.reply request.identity (← search request ready)))
      else if role == "save" then
        let session ← IO.ofExcept (json.getObjValAs? String "session")
        let path := System.FilePath.mk (← IO.ofExcept (json.getObjValAs? String "path"))
        let files ← sessionFiles session
        let some base ← (readJson? path pendingJsonDefaults : IO (Option PendingTurn)) |
          throw (IO.userError "queued turn disappeared")
        let checkpoint := path.parent.bind (·.fileName) == some "checkpoints"
        let pending ← if checkpoint && base.finalMessage.isNone then pure base
          else loadToolReceipts files base
        let keys ← if let some target := pending.write then do
          if pending.finalMessage.isNone && pending.tools.isEmpty then pure []
          else
            let promotion ← if checkpoint && pending.finalMessage.isNone then
                promoteObservations pending (.mk target)
              else promote pending (.mk target)
            let command := pending.semanticMatcher.getD
              [(← IO.appPath).toString, "search-provider", "--mode", "lexical"]
            -- Lexical maintenance also survives a saving chat without an encoder.
            queueIndex target command promotion
            pure (promotion.outcomeRelations.map nativeHistoryKey)
          else pure []
        let finished ← observeRelatedFiles files pending ((← IO.monoMsNow) + 5000)
        if finished then removeIfExists path
        pure (toJson keys)
      else if role == "index" then
        if (json.getObjValAs? String "kind").toOption == some "synapses" then
          let target ← IO.ofExcept (json.getObjVal? "target" >>= fromJson? (α := Synapses.Journal.Target))
          let pinned ← target.owner.pin
          let (pinned,indexed) ← Warm.refreshSource pinned target.storage ((← IO.monoMsNow)+60000)
          let _ ← Synapses.CanonicalSource.Cache.refresh pinned target.storage
          pure (toJson indexed)
        else
          let target ← IO.ofExcept (json.getObjVal? "target" >>= fromJson? (α := IndexTarget))
          let paths ← IO.ofExcept (json.getObjValAs? (List String) "paths")
          let count ← indexQueued target (paths.map System.FilePath.mk)
          if (json.getObjValAs? Bool "warm").toOption.getD false then
            let _ ← Warm.runTarget (← target.owner.pin) target
            pure ()
          pure (toJson count)
      else throw (IO.userError "unknown worker role")
      catch error => pure (Json.mkObj [("error", error.toString)])
    output.putStr (result.compress ++ "\n")
    output.flush
  pure 0

end Eggshell.Plugin.Worker
