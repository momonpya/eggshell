module

public import Eggshell.DB.CacheReclaim

public import Eggshell.Worker
public import Eggshell.MiniLM

@[expose] public section

namespace Eggshell.Plugin

open Lean

def requiredString (json : Json) (name : String) : Except String String := do
  (json.getObjVal? name).bind Json.getStr?

def optionalString (json : Json) (name : String) : Option String :=
  (json.getObjVal? name).toOption.bind (Json.getStr? · |>.toOption)

def jsonField (json : Json) (name : String) : String :=
  json.getObjValD name |>.compress

def emptyHook : String := "{}"

def systemMessage (message : String) : String :=
  Json.mkObj [("systemMessage", message)] |>.compress

def withSearchNotice (handoff : Option Handoff) (output : String) : String :=
  match handoff.bind (·.search) with
  | some trace =>
      if trace.route == .lexical && trace.semantic != .notRequested then
        let status := match trace.semantic with
          | .timedOut => "timed out"
          | .pending => "is pending"
          | .failed => "is unavailable"
          | .completed => "completed"
          | .notRequested => "was not requested"
        let delivery := if handoff.any (fun result =>
            result.reason != "search-incomplete" && !result.text.isEmpty) then
          "keyword search supplied saved-memory evidence."
          else "no new saved-memory body was delivered."
        match Json.parse output with
        | .ok json => (json.setObjVal! "systemMessage" (toJson
            s!"Eggshell semantic search {status}; {delivery}")).compress
        | .error _ => output
      else output
  | none => output

def defaultState (config : Config.Config) : ThreadState :=
  { profile := config.defaultProfile }

def withDefaultMatcher (config : Config.Config) : IO Config.Config := do
  if config.semanticMatcherWasSet then pure config
  else pure {config with semanticMatcher := ← MiniLM.command (← Paths.installRoot)}

def configFromHook (input : Json) (cwd : System.FilePath) : IO (Option Config.Config) := do
  let config? ← Config.loadWith cwd (optionalString input "_eggshell_config")
  config?.mapM withDefaultMatcher

def replaceSourceStatus (keys : List String) (key : String) : List String :=
  match SourceEvidence.deliveryScope? key with
  | none => (keys ++ [key]).eraseDups
  | some scope =>
      (keys.filter (fun old => SourceEvidence.deliveryScope? old != some scope) ++ [key]).eraseDups

theorem replace_source_status_preserves_other_keys (keys : List String) (key previous : String)
    (present : previous ∈ keys) (ordinary : SourceEvidence.deliveryScope? previous = none) :
    previous ∈ replaceSourceStatus keys key := by
  unfold replaceSourceStatus
  split
  · simp [present]
  · simp [present, ordinary]

def addDeliveredGraphs (state : ThreadState) (keys : List String) : ThreadState :=
  { state with deliveredGraphs := keys.foldl replaceSourceStatus state.deliveredGraphs }

theorem add_delivered_preserves_other_keys (state : ThreadState) (keys : List String)
    (previous : String) (present : previous ∈ state.deliveredGraphs)
    (ordinary : SourceEvidence.deliveryScope? previous = none) :
    previous ∈ (addDeliveredGraphs state keys).deliveredGraphs := by
  have preserved : ∀ incoming : List String, ∀ prior : List String,
      previous ∈ prior → previous ∈ incoming.foldl replaceSourceStatus prior := by
    intro incoming
    induction incoming with
    | nil => intro prior member; exact member
    | cons key tail ih =>
        intro prior member
        exact ih _ (replace_source_status_preserves_other_keys prior key previous member ordinary)
  exact preserved keys state.deliveredGraphs present

/-- Compaction forgets context delivery but retains evidence-specific checkpoints. -/
def compactState (state : ThreadState) : ThreadState := {
  state with
      epoch := state.epoch + 1
      offers := []
      deliveredGraphs := state.deliveredGraphs.filter (·.startsWith "d:")
      afterCompaction := true
      lastHandoff := ""
      lastReason := "compacted; graph may be resent without repeating a checkpoint" }

theorem compaction_preserves_checkpoint (state : ThreadState) (key : String)
    (present : key ∈ state.deliveredGraphs) (checkpoint : key.startsWith "d:" = true) :
    key ∈ (compactState state).deliveredGraphs := by
  simp [compactState, present, checkpoint]

def boundedHookDeadline (now budget : Nat) (upstream : Option Nat) : Nat :=
  min (now + budget) (upstream.getD (now + budget))

theorem hook_deadline_preserves_upstream (now budget deadline : Nat)
    (within : deadline ≤ now + budget) :
    boundedHookDeadline now budget (some deadline) = deadline := by
  simp [boundedHookDeadline, Nat.min_eq_right within]

theorem hook_deadline_never_extends_upstream (now budget deadline : Nat) :
    boundedHookDeadline now budget (some deadline) ≤ deadline := by
  exact Nat.min_le_right _ _

/-- The native client reserves teardown/RPC time inside the 30-second hook.
Search consumes that shared deadline rather than imposing a second 20-second
cutoff. Direct callers retain the client's ordinary 29-second ceiling. -/
def hookDeadline (input : Json) (budget : Nat := 29000) : IO Nat := do
  let now ← IO.monoMsNow
  pure <| boundedHookDeadline now budget
    (input.getObjValAs? Nat "_eggshell_deadline").toOption

/-- Closing with no message cannot erase a final answer already received. -/
def sealPending (pending : PendingTurn) (message : Option String) : PendingTurn :=
  { pending with finalMessage := message.or pending.finalMessage, closed := true, inFlight := [] }

theorem terminal_order_preserves_answer (pending : PendingTurn) (message : String) :
    sealPending (sealPending pending none) (some message) =
      sealPending (sealPending pending (some message)) none := by
  simp [sealPending]

theorem terminal_seal_preserves_observations (pending : PendingTurn) (message : Option String) :
    observedRoots (sealPending pending message) = observedRoots pending := by rfl

theorem terminal_close_never_reopens (pending : PendingTurn) (message : Option String) :
    (sealPending pending message).closed = true ∧
      (sealPending pending message).inFlight = [] := ⟨rfl, rfl⟩

/-- Archive only metadata while holding the session lock. Receipts stay in place.
Retain the original turn capability before removing its active slot: SessionEnd
may arrive before Stop, or an already running result may finish after closure. -/
def deferPending (files : SessionFiles) (pending : PendingTurn) : IO Unit := do
  -- Keep unresolved reservations as diagnostic/recovery state. They never
  -- become observed roots; Stop separately clears them when sealing an answer.
  let pending := { pending with closed := true }
  writeJson (closedTurnPath files pending.turnId) pending
  let key := SemanticMatcher.contentKey (.text pending.turnId)
  writeJson (files.directory / "deferred" / (key ++ ".json")) pending
  removeIfExists files.pending

/-- The journal is authoritative for observed events even if the native hook
    exits between recording a receipt and registering its save. This cursor is
    only an optimization: restarting a manager safely replays all receipts. -/
def reconcileToolReceipts (session : String) (files : SessionFiles)
    (cursor : IO.Ref (String × List String)) : IO Unit := do
  let pending ← withSession session fun files => do
    let some state ← readState? files | return none
    if !state.enabled then return none
    readPendingBase? files
  let some pending := pending | return
  let (turn, seen) ← cursor.get
  let mut seen := if turn == pending.turnId then seen else []
  let directory := toolDirectory files pending.turnId
  if ← directory.pathExists then
    for entry in ← directory.readDir do
      if !entry.fileName.endsWith ".json" || seen.contains entry.fileName then continue
      try
        if let some (native, version) ← readNativeTool? entry.path then
          let tool ← attachCertificate files pending.turnId native version
          let paths := (Json.parse tool.input).toOption.map
            (SourceObservation.targets (System.FilePath.mk pending.cwd) tool.name) |>.getD []
          queueCheckpoint files {pending with tools := [tool], sources := paths.map (fun relative => ⟨relative, none⟩), inFlight := [], finalMessage := none, closed := false}
          seen := entry.fileName :: seen
          cursor.set (pending.turnId, seen)
      catch error => IO.eprintln s!"Eggshell retained an unqueued tool receipt: {error}"

/-- Saving is isolated from search and never holds the session state lock. -/
def flushDeferred (session : String) (deadline : Nat)
    (cursor : Option (IO.Ref (String × List String)) := none) : IO Unit := do
  let files ← sessionFiles session
  try Persistence.withLockWithin (files.directory / "save") 0 do
    if let some cursor := cursor then reconcileToolReceipts session files cursor
    let mut entries := []
    for name in ["deferred", "checkpoints"] do
      let directory := files.directory / name
      if ← directory.pathExists then entries := entries ++ (← directory.readDir).toList
    for entry in entries.take 8 do
      if (← IO.monoMsNow) ≥ deadline then return
      if !entry.fileName.endsWith ".json" then continue
      let state ← withSession session fun files => readState? files
      if state.any (! ·.enabled) then return
      let epoch := state.map (·.epoch)
      let payload := Json.mkObj [("session", session), ("path", entry.path.toString)]
      let some result ← Worker.exchange session "save" payload deadline | return
      let .ok keys := (fromJson? result : Except String (List String)) |
        IO.eprintln s!"Eggshell retained uncommitted work in {session} from {entry.path}: {result.compress}"
        continue
      -- A save can finish after compaction. Its graph remains valid on disk,
      -- but is not thereby evidence that the new native context contains it.
      withSession session fun files => do
        if let some state ← readState? files then
          if state.enabled && !state.afterCompaction && epoch == some state.epoch then
            writeJson files.state (addDeliveredGraphs state keys)
  catch error => IO.eprintln s!"Eggshell retained queued work: {error}"

def drainIndexTarget (session : String) (deadline : Nat)
    (reference : System.FilePath) (target : IndexTarget) : IO Unit := do
  let snapshot ← DB.PageMap.open? (.mk target.owner.directory)
  let some snapshot := snapshot | do
    removeIfExists reference
    return
  if snapshot.head.identity != target.owner.database then
    removeIfExists reference
    return
  DB.Sidecar.observe snapshot
  -- A remembered writer grant cannot make a reader chat mutate shared DBs.
  -- Standalone recovery without a current turn can still finish prior work.
  if target.storage == .database then
    let files ← sessionFiles session
    if let some pending ← readPendingBase? files then
      unless pending.write.any (fun path =>
          (System.FilePath.mk path).normalize == (System.FilePath.mk target.owner.directory).normalize) do
        return
  let directory ← target.indexes snapshot
  let entries ← if ← directory.pathExists then directory.readDir else pure #[]
  let entries := (entries.toList.filter (·.fileName.endsWith ".json"))
    |>.mergeSort (fun a b => a.fileName ≤ b.fileName)
  let warm ← Warm.required target snapshot
  if entries.isEmpty && !warm then return
  let payload := Json.mkObj [("target", toJson target), ("warm", toJson warm),
    ("paths", toJson (entries.take 8 |>.map (·.path.toString)))]
  if let some result ← Worker.exchange session "index" payload deadline then
    if !(fromJson? result : Except String Nat).isOk then
      IO.eprintln s!"Eggshell retained unindexed published work: {result.compress}"

def drainRegisteredIndexes (session : String) (deadline : Nat) : IO Unit := do
  for (reference, target) in ← registeredIndexTargets do
    if (← IO.monoMsNow) ≥ deadline then return
    try drainIndexTarget session deadline reference target
    catch error => IO.eprintln s!"Eggshell retained DB index work: {error}"

def flushIndexWork (session : String) (deadline : Nat) : IO Unit := do
  -- Current configuration discovers portable work at a new DB location.
  -- This optional discovery cannot prevent draining already registered DBs.
  let files ← sessionFiles session
  try
    if let some pending ← (readJson? files.pending pendingJsonDefaults : IO (Option PendingTurn)) then
      if let some command := pending.semanticMatcher then
        for path in (pending.read ++ pending.write.toList).eraseDups do
          if let some snapshot ← DB.PageMap.open? (.mk path) then
            let _ ← registerIndexTarget snapshot command (pending.write == some path)
            pure ()
  catch error => IO.eprintln s!"Eggshell retained undiscovered DB work: {error}"
  let root ← dataRoot
  Persistence.rejectSymlinkAncestors root
  Persistence.privateDirectory root
  let guardPath := root / "index-drain.guard"
  Persistence.rejectSymlinkAncestors guardPath
  let guard ← IO.FS.Handle.mk guardPath .append
  Persistence.privateFile guardPath
  if !(← guard.tryLock) then return
  try
    try
      let _ ← DB.Sidecar.collect (min deadline ((← IO.monoMsNow) + 50))
      pure ()
    catch error => IO.eprintln s!"Eggshell retained private caches: {error}"
    drainRegisteredIndexes session deadline
  finally guard.unlock

/-- Installation-wide discovery survives chats. The single drain admission and
per-DB worker claim never acquire the graph writer or a session state lock. -/
def flushIndexes (session : String) (deadline : Nat) : IO Unit := do
  try flushIndexWork session deadline
  catch error => IO.eprintln s!"Eggshell retained index tickets: {error}"

def sessionStart (input : Json) : IO String := do
  let session ← IO.ofExcept (requiredString input "session_id")
  if optionalString input "source" = some "compact" then
    Worker.cancel session "search"
    withSession session fun files => do
      if let some state ← readState? files then
        if state.enabled then writeJson files.state (compactState state)
    return emptyHook
  else
    let cwd := System.FilePath.mk ((optionalString input "cwd").getD ".")
    let config ← configFromHook input cwd
    let state ← withSession session fun files => do
      let state ← readState? files
      if state.isNone then
        if let some config := config then
          let state := defaultState config
          writeJson files.state state
          return some state
      pure state
    let some config := config |
      return systemMessage "Eggshell memory is not configured for this project. Ask Codex: Set up Eggshell for this project."
    let some state := state | return emptyHook
    if !state.enabled then
      return systemMessage "Eggshell memory is off for this chat. Use !egg on only if you want to enable it."
    let selection ← IO.ofExcept (Config.resolve config state.profile)
    let mode := if selection.read.isEmpty && selection.write.isNone then "off"
      else if selection.write.isNone then "read-only" else "read/write"
    return systemMessage (s!"Eggshell session hook connected: memory {mode}, profile {state.profile}. " ++
      "Use !egg doctor to check setup; !egg graph shows context actually delivered.")

def acceptOffer (state : ThreadState) (turn : String) (now : Nat)
    (offer : DeliveryOffer) : ThreadState :=
  if state.enabled && offer.stamp.accepts turn state.epoch now then
    { (addDeliveredGraphs state offer.graphs) with
      lastHandoff := offer.text, lastReason := offer.reason, lastSearch := offer.search }
  else state

theorem rejected_offer_changes_nothing (state : ThreadState) (turn : String)
    (now : Nat) (offer : DeliveryOffer)
    (rejected : offer.stamp.accepts turn state.epoch now = false) :
    acceptOffer state turn now offer = state := by
  simp [acceptOffer, rejected]

theorem disabled_memory_rejects_delivery (state : ThreadState) (turn : String)
    (now : Nat) (offer : DeliveryOffer) (disabled : state.enabled = false) :
    acceptOffer state turn now offer = state := by
  simp [acceptOffer, disabled]

def acknowledge (session id : String) : IO Bool := withSession session fun files => do
  let some state ← readState? files | return false
  let some pending ← readPendingBase? files | return false
  let now ← IO.monoMsNow
  let some offer := state.offers.find? (·.id == id) | return false
  let state := { state with offers := state.offers.filter (·.id != id) }
  writeJson files.state (acceptOffer state pending.turnId now offer)
  pure (state.enabled && offer.stamp.accepts pending.turnId state.epoch now)

/-- Semantic discovery gets the first window; DB delivery retains the rest. -/
def semanticSearchBudgetMs : Nat := 4500

def semanticSearchDeadline (now deadline : Nat) : Nat :=
  min deadline (now + min semanticSearchBudgetMs ((deadline - now) / 2))

def searchIncomplete (reply : Option Json) : Bool :=
  match reply with
  | none => true
  | some json => match (fromJson? json : Except String (Option Handoff)) with
    | .error _ => true
    | .ok none => false
    | .ok (some handoff) => handoff.reason == "search-incomplete"

def incompleteSemanticStatus (reply : Option Json) (now deadline : Nat) : SemanticSearchStatus :=
  if now ≥ deadline then .timedOut else
    match reply with
    | none => .failed
    | some json => match (fromJson? json : Except String (Option Handoff)) with
      | .ok (some handoff) => if handoff.reason == "search-incomplete" then .pending else .failed
      | _ => .failed

/-- Constant metadata per DB, never a scan or embedding job in the hook.
The installation registry and invalidated DB checkpoint persist the warm debt. -/
def requestBackgroundWarm (pending : PendingTurn) (deadline : Nat) : IO Nat := do
  let some command := pending.semanticMatcher | return 0
  let _ :: "search-provider" :: _ := command | return 0
  let mut count := 0
  for path in pending.read.eraseDups do
    if (← IO.monoMsNow) ≥ deadline then break
    try
      if let some snapshot ← DB.PageMap.open? (.mk path) then
        let target ← registerIndexTarget snapshot command (pending.write == some path)
        Warm.invalidate target snapshot
        count := count + 1
    catch error => IO.eprintln s!"Eggshell retained an unavailable warm target: {error}"
  pure count

/-- Search results become offers only after checking the current turn and epoch. -/
def deliverForWork (input : Json) (pending : PendingTurn) (work : String)
    (enforce : Bool) (evidenceText : Option String := none) (staged : Bool := false) :
    IO (Option Handoff) := do
  let session := pending.sessionId
  let deadline ← hookDeadline input
  let snapshot ← withSession session fun files => do
    let some state ← readState? files | return none
    let some current ← readPendingBase? files | return none
    if !state.enabled || current.turnId != pending.turnId || (current.closed || current.finalMessage.isSome) then
      return none
    pure (some state)
  let some initial := snapshot | return none
  if pending.projection == .none || pending.read.isEmpty then return none
  let stamp : RequestStamp := { turn := pending.turnId, epoch := initial.epoch, deadline }
  let query : Worker.Search := {
    pending, state := initial, work, enforce, evidence := evidenceText, staged, deadline
    receipt := optionalString input "_eggshell_receipt" }
  let semantic := pending.projection == .automatic && pending.semanticMatcher.isSome && evidenceText.isNone
  let started ← IO.monoMsNow
  let firstDeadline := if semantic then semanticSearchDeadline started deadline else deadline
  let first ← Worker.exchange session "search" (toJson {query with deadline := firstDeadline}) firstDeadline
  let observed ← IO.monoMsNow
  let (result, trace) ← if semantic && searchIncomplete first then do
      let warmRequests ← requestBackgroundWarm pending
        (min deadline (observed + (deadline - observed) / 4))
      let lexical := {query with route := .lexical}
      let lexicalStarted ← IO.monoMsNow
      let result ← Worker.exchange session "search" (toJson lexical) deadline
      let trace : SearchTrace := {
        semantic := incompleteSemanticStatus first observed firstDeadline, route := .lexical
        semanticMs := observed - started, lexicalMs := (← IO.monoMsNow) - lexicalStarted
        warmMs := lexicalStarted - observed, warmRequests }
      pure (result, trace)
    else do
      let trace : SearchTrace := {
        semantic := if semantic then .completed else .notRequested, route := .configured
        semanticMs := if semantic then observed - started else 0
        lexicalMs := if semantic then 0 else observed - started }
      pure (first, trace)
  let (handoff, disposition) ← withSession session fun files => do
    let some state ← readState? files | return (none, "missing-state")
    let some current ← readPendingBase? files | return (none, "missing-turn")
    let now ← IO.monoMsNow
    if !state.enabled then return (none, "disabled")
    if current.closed || current.finalMessage.isSome then return (none, "closed-turn")
    match Worker.SearchDelivery.ofReply stamp current.turnId state.epoch now
        pending.handoffChars result with
    | .obsolete => return (none, "obsolete")
    | .empty _ =>
        if trace.route == .lexical then return (some {pendingSearch with search := some trace}, "empty")
        return (none, "empty")
    | .incomplete _ _ => return (some {pendingSearch with search := some trace}, "incomplete")
    | .found _ handoff _ _ => do
        -- Linearize only publication, never the search or semantic matcher.
        -- Concurrent offers subtract the same original ranges under this short lock.
        let some reconciled := handoff.reconcileDelivery
            (state.deliveryClaims current.turnId now) pending.handoffChars Config.nativeHandoffBytes |
          return (none, "reconciled-empty")
        let handoff := {reconciled.handoff with search := some trace}
        let checkpoints := handoff.sourceCheckpoints.map (·.key)
        let id := (optionalString input "_eggshell_receipt").getD "direct"
        let offer : DeliveryOffer := {
          id, stamp, graphs := handoff.deliveredGraphs, text := handoff.text
          reason := handoff.reason, search := handoff.search }
        writeJson files.state {
          (addDeliveredGraphs state checkpoints) with
          offers := offer :: (state.offers.filter fun (offer : DeliveryOffer) =>
            offer.id != id && offer.stamp.accepts current.turnId state.epoch now).take 15 }
        pure (some handoff, "offered")
  Receipt.observe (optionalString input "_eggshell_receipt") "search" (Json.mkObj [
    ("turn", toJson pending.turnId), ("epoch", toJson initial.epoch),
    ("deadlineMs", toJson deadline), ("trace", toJson trace), ("disposition", toJson disposition),
    ("reason", toJson (handoff.map (·.reason))),
    ("completed", toJson (handoff.map (·.completed))),
    ("localUnions", toJson (handoff.map (·.localUnions))),
    ("equalityOrigin", if handoff.any (fun h => h.completed > 0 || h.blocksCurrent) then
      Json.mkObj [("status", toJson (if handoff.any (·.equalitySelection.isSome) then "partial" else "untracked")),
        ("selection", toJson (handoff.bind (·.equalitySelection))),
        ("deliveryAncestry", toJson "untracked")]
      else Json.null)])
  pure handoff

def userPromptSubmit (input : Json) : IO String := do
  let session ← IO.ofExcept (requiredString input "session_id")
  let turn ← IO.ofExcept (requiredString input "turn_id")
  let cwd := System.FilePath.mk (← IO.ofExcept (requiredString input "cwd"))
  let prompt ← IO.ofExcept (requiredString input "prompt")
  let some config ← configFromHook input cwd | return emptyHook
  let prepared ← withSession session fun files => do
    let mut state := (← readState? files).getD (defaultState config)
    if !state.enabled then return none
    if let some pending ← readPendingBase? files then
      if pending.turnId == turn then return none
      deferPending files pending
    let selection ← IO.ofExcept (Config.resolve config (state.nextProfile.getD state.profile))
    let pending : PendingTurn := {
      sessionId := session, turnId := turn, cwd := cwd.toString, prompt,
      profile := selection.label, semanticMatcher := selection.semanticMatcher,
      read := selection.read.map (·.path.toString), write := selection.write.map (·.path.toString),
      handoffChars := selection.handoffChars, localUnion := selection.localUnion,
      projection := state.nextProjection.getD .automatic }
    state := { state with
      epoch := state.epoch + 1
      offers := []
      deliveredGraphs := state.deliveredGraphs.filter (fun key => !key.startsWith "d:"),
      nextProfile := none, nextProjection := none }
    writeJson files.state state
    writeJson files.pending pending
    pure (some pending)
  let some pending := prepared | return emptyHook
  Worker.cancel session "search"
  let handoff ← deliverForWork input pending prompt false
  let context := handoff.map (·.text) |>.getD ""
  pure <| withSearchNotice handoff (if context == "" then emptyHook else hookContext "UserPromptSubmit" context)

def toolFromHook (input : Json) (withResponse : Bool) : Except String ToolEvent := do
  pure {
    name := ← requiredString input "tool_name"
    useId := ← requiredString input "tool_use_id"
    input := jsonField input "tool_input"
    response := if withResponse then jsonField input "tool_response" else ""
  }

inductive PreToolState where
  | ignore
  | reserved (pending : PendingTurn)

inductive PostToolState where
  | ignore
  | completed (pending : PendingTurn)

def localSourceTool (name : String) : Bool :=
  ["Bash", "bash", "shell", "exec_command", "functions.exec_command"].contains name

/-- A path argument of an arbitrary MCP/provider does not establish that the
provider read a local file. Only literal local read/search commands supply
this adapter's dependency capture. Preserve directory fields for validation,
but obtain every file from the actual command, never unrelated extra fields. -/
def nativeSourceInput? (tool : ToolEvent) : Option Json := do
  if !localSourceTool tool.name then return ← none
  let input ← (Json.parse tool.input).toOption
  let command ← ((input.getObjValAs? String "cmd").toOption).orElse
    (fun _ => (input.getObjValAs? String "command").toOption)
  if (SourceEvidence.observedCommandFiles command).isEmpty then return ← none
  let directories := ["workdir", "cwd"].filterMap fun key =>
    (input.getObjVal? key).toOption.map (fun value => (key, value))
  pure (Json.mkObj (("command", toJson command) :: directories))

theorem unknown_native_source_input_rejected (tool : ToolEvent)
    (unknown : localSourceTool tool.name = false) : nativeSourceInput? tool = none := by
  simp [nativeSourceInput?, unknown]

def preToolUse (input : Json) : IO String := do
  let session ← IO.ofExcept (requiredString input "session_id")
  let turn ← IO.ofExcept (requiredString input "turn_id")
  let initial ← IO.ofExcept (toolFromHook input false)
  let files ← sessionFiles session
  -- Probe outside the session lock. This optional observation spends at most
  -- a small part of the native hook window; incomplete provenance has no
  -- authority and never prevents the requested operation from proceeding.
  let captured ← try
      let base ← (readJson? files.pending pendingJsonDefaults : IO (Option PendingTurn))
      match base with
      | some pending =>
          if pending.turnId != turn then pure none else do
            let some sourceInput := nativeSourceInput? initial | pure none
            let deadline ← hookDeadline input
            let capture ← SourceEvidence.capture (System.FilePath.mk pending.cwd)
              sourceInput (min deadline ((← IO.monoMsNow) + 250))
            pure (some (pending.cwd, capture))
      | none => pure none
    catch _ => pure none
  let tool := {initial with source := captured.map (·.2)}
  let preflight ← withSession session fun files => do
    let some state ← readState? files |
      pure PreToolState.ignore
    if !state.enabled then
      do
        removeIfExists files.pending
        pure PreToolState.ignore
    else
      let some pending ← readPendingBase? files |
        pure PreToolState.ignore
      if pending.turnId != turn || (pending.closed || pending.finalMessage.isSome) then
        pure PreToolState.ignore
      else
        let tool := if captured.any (fun previous => previous.1 != pending.cwd) then
          {tool with source := none} else tool
        let reserved := reserveTool pending tool
        writeJson files.pending reserved
        pure (.reserved reserved)
  match preflight with
  | .ignore => pure emptyHook
  | .reserved pending =>
      try
        let handoff ← deliverForWork input pending
          (canonicalToolWork tool) true none true
        if handoff.any (·.blocksCurrent) then
          withSession session fun files => do
            if let some current ← readPendingBase? files then
              if current.turnId = turn then
                writeJson files.pending (cancelTool current tool.useId)
          let text := handoff.map (·.text) |>.getD ""
          let fragments := handoff.map (fun candidate =>
            candidate.coveredFragments)
            |>.getD [] |>.map fun fragment =>
            "- " ++ treeWork (.text fragment)
          let matched := if fragments.isEmpty then "" else
            "\n\nREMOVE ONLY THESE COMPLETED FRAGMENTS:\n" ++
              "\n".intercalate fragments ++
              "\nEVERY OTHER SUBCOMMAND, PATH, SYMBOL, RANGE, AND REQUESTED FACT REMAINS OPEN."
          let instruction :=
            "Eggshell found completed prior native Work before this operation ran. Replan " ++
            "the call to omit only the covered Work and issue any genuinely uncovered " ++
            "remainder. Do not repeat covered Work merely to verify, cite, narrow, " ++
            "reformat, or reconstruct it.\n\n" ++ evidenceGapGuidance
          pure <| withSearchNotice handoff (hookDeny (instruction ++ matched ++ "\n\n" ++
            (if text = "" then
              "The Outcome is already present in this native context; Eggshell did not resend it."
            else "Newly connected prior graph:\n\n" ++ text)))
        else
          let text := handoff.map (·.text) |>.getD ""
          pure <| withSearchNotice handoff (if text = "" then emptyHook else hookContext "PreToolUse" text)
      catch error =>
        withSession session fun files => do
          if let some current ← readPendingBase? files then
            if current.turnId = turn then
              writeJson files.pending (cancelTool current tool.useId)
        throw error

/-- Retain the original read's certificate in both active and archived turns.
An existing companion is immutable; a new companion is sealed against the
pre-tool capture, never inferred from the command's output or a later hash. -/
def sealRecordedRead (pending : PendingTurn) (tool : ToolEvent) : IO ToolEvent := do
  if tool.source.isSome then return tool
  let previous := pending.inFlight.find? fun previous =>
    previous.useId == tool.useId && previous.name == tool.name &&
      canonicalJson previous.input == canonicalJson tool.input
  let source ← (previous.bind (·.source)).mapM fun capture => do
    let record ← SourceEvidence.sealCapture (System.FilePath.mk pending.cwd) capture ((← IO.monoMsNow) + 250)
    pure {capture with record}
  pure {tool with source}

theorem existing_read_certificate_retained (pending : PendingTurn) (tool : ToolEvent)
    (capture : SourceEvidence.Capture) (hasCertificate : tool.source = some capture) :
    sealRecordedRead pending tool = pure tool := by
  simp [sealRecordedRead, hasCertificate]

/-- Journal native results before contacting the manager or doing any search. -/
def captureTerminal (input : Json) : IO Unit := do
  if optionalString input "hook_event_name" != some "PostToolUse" then return
  let session ← IO.ofExcept (requiredString input "session_id")
  let turn ← IO.ofExcept (requiredString input "turn_id")
  let tool ← IO.ofExcept (toolFromHook input true)
  let files ← sessionFiles session
  -- Explicitly disabled memory retains no new observation. Invalid control
  -- metadata must preserve the native result before reporting unconfirmed work.
  let state ← try
    (readJson? files.state stateJsonDefaults : IO (Option ThreadState))
    catch error =>
      recordTool files turn tool
      throw error
  if let some state := state then
    if !state.enabled then return
  let tool := (← recordedTool? files turn tool).getD tool
  recordTool files turn tool
  if let some pending ← (readJson? files.pending pendingJsonDefaults : IO (Option PendingTurn)) then
    if pending.turnId == turn && !pending.closed && pending.finalMessage.isNone then
      let tool ← sealRecordedRead pending tool
      -- The native result was already durable before provenance validation.
      -- A crash here can lose only the optional source certificate, not work.
      recordTool files turn tool
      let paths := (Json.parse tool.input).toOption.map
        (SourceObservation.targets (System.FilePath.mk pending.cwd) tool.name) |>.getD []
      queueCheckpoint files {pending with tools := [tool], inFlight := [], sources := paths.map (fun relative => ⟨relative, none⟩)}
      return
  if let some pending ← readClosedTurn? files turn then
    unless pending.sessionId == session do throw (IO.userError "closed receipt belongs to another chat")
    let tool ← sealRecordedRead pending tool
    recordTool files turn tool
    let paths := (Json.parse tool.input).toOption.map
      (SourceObservation.targets (System.FilePath.mk pending.cwd) tool.name) |>.getD []
    queueCheckpoint files {pending with tools := [tool], inFlight := [], sources := paths.map (fun relative => ⟨relative, none⟩), finalMessage := none, closed := false}

def postToolUse (input : Json) : IO String := do
  let session ← IO.ofExcept (requiredString input "session_id")
  let turn ← IO.ofExcept (requiredString input "turn_id")
  let initial ← IO.ofExcept (toolFromHook input true)
  let files ← sessionFiles session
  let tool := (← recordedTool? files turn initial).getD initial
  let postflight ← withSession session fun files => do
    let some state ← readState? files |
      pure PostToolState.ignore
    if !state.enabled then
      do
        removeIfExists files.pending
        pure PostToolState.ignore
    else
      let some pending ← readPendingBase? files |
        pure PostToolState.ignore
      if pending.turnId != turn || (pending.closed || pending.finalMessage.isSome) then
        pure PostToolState.ignore
      else
        recordTool files turn tool
        queueCheckpoint files { pending with tools := [tool], inFlight := [] }
        let pending := cancelTool pending tool.useId
        writeJson files.pending pending
        let roots := observedRoots { pending with tools := [tool] }
        writeJson files.state (addDeliveredGraphs state (roots.map nativeHistoryKey))
        pure (.completed pending)
  match postflight with
  | .ignore => pure emptyHook
  | .completed pending =>
      try
        let handoff ← deliverForWork input pending
          (canonicalToolWork tool) false
          (if tool.response.trimAscii.isEmpty then none else some (canonicalJson tool.response))
        let text := handoff.map (·.text) |>.getD ""
        pure <| withSearchNotice handoff (if text = "" then emptyHook else hookContext "PostToolUse" text)
      catch error =>
        IO.eprintln s!"Eggshell recorded the native result but omitted its handoff: {error}"
        pure (hookContext "PostToolUse" pendingSearch.text)

def postCompact (input : Json) : IO String := do
  let session ← IO.ofExcept (requiredString input "session_id")
  withSession session fun files => do
    if let some state ← readState? files then
      if state.enabled then writeJson files.state (compactState state)
  Worker.cancel session "search"
  pure emptyHook

def stop (input : Json) : IO String := do
  let session ← IO.ofExcept (requiredString input "session_id")
  let turn := optionalString input "turn_id"
  let finalMessage := optionalString input "last_assistant_message"
  let current ← withSession session fun files => do
    let some state ← readState? files | return false
    if !state.enabled then return false
    let active ← readPendingBase? files
    let current := active.any (matchesHookTurn · turn)
    let pending ← if current then pure active else do
      pure ((← turn.mapM (readClosedTurn? files)).join)
    let some pending := pending | return false
    unless pending.sessionId == session do throw (IO.userError "terminal receipt belongs to another chat")
    let sealed := sealPending pending finalMessage
    -- Queue first. A crash while updating lifecycle metadata cannot discard
    -- the already durable final answer, and replay is idempotent in the DB.
    queueCheckpoint files sealed
    if current then
      writeJson files.pending sealed
      writeJson files.state { state with epoch := state.epoch + 1, offers := [] }
    else writeJson (closedTurnPath files pending.turnId) sealed
    pure current
  if current then Worker.cancel session "search"
  pure emptyHook

def interrupt (input : Json) : IO String := do
  let session ← IO.ofExcept (requiredString input "session_id")
  withSession session fun files => do
    if let some state ← readState? files then
      writeJson files.state { state with epoch := state.epoch + 1, offers := [] }
  Worker.cancel session "search"
  pure emptyHook

def sessionEnd (input : Json) : IO String := do
  let session ← IO.ofExcept (requiredString input "session_id")
  withSession session fun files => do
    if let some pending ← readPendingBase? files then deferPending files pending
    if let some state ← readState? files then
      writeJson files.state { state with epoch := state.epoch + 1, offers := [] }
  Worker.cancel session "search"
  pure emptyHook

def dispatchHook (input : Json) : IO String := do
  let event ← IO.ofExcept (requiredString input "hook_event_name")
  match event with
  | "SessionStart" => sessionStart input
  | "UserPromptSubmit" => userPromptSubmit input
  | "PreToolUse" => preToolUse input
  | "PostToolUse" => postToolUse input
  | "PostCompact" => postCompact input
  | "Stop" => stop input
  | "Interrupt" => interrupt input
  | "SessionEnd" => sessionEnd input
  | other => throw (IO.userError s!"unsupported Codex hook {other}")

end Eggshell.Plugin
