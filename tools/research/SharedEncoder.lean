module
public import Lean.Data.Json.FromToJson
public import Lean.Data.Json.Parser
public import Std.Sync.Mutex
public import Eggshell.TaskDeadline

@[expose] public section
namespace Eggshell.Research.SharedEncoder
open Lean Std Async

abbrev Kernel := IO.Process.Child {stdin := .piped,stdout := .piped,stderr := .inherit}

/-- A response cannot resolve another request's promise without passing this
checked binding. IDs are allocated by Lean and are never recycled. -/
structure Reply (identity : Nat) where
  received : Nat
  same : received = identity
  body : String

def Reply.check (identity received : Nat) (body : String) : Option (Reply identity) :=
  if same : received = identity then some ⟨received,same,body⟩ else none

theorem Reply.foreign_rejected (identity received : Nat) (body : String) (different : received ≠ identity) :
    Reply.check identity received body = none := by simp [Reply.check,different]

theorem Reply.bound (reply : Reply identity) : reply.received = identity := reply.same

abbrev Pending := Sigma fun identity => IO.Promise (Except IO.Error (Reply identity))

structure State where
  next : Nat := 0
  pending : List Pending := []
  closed : Bool := false

def State.older (state : State) : Prop := ∀ entry ∈ state.pending, entry.1 < state.next

def State.reserve (state : State) (promise : IO.Promise (Except IO.Error (Reply state.next))) : State × Pending :=
  let entry : Pending := ⟨state.next,promise⟩
  ({state with next := state.next+1,pending := entry :: state.pending},entry)

theorem State.reserve_advances (state : State) (promise) :
    state.next < (state.reserve promise).1.next := Nat.lt_succ_self _

theorem State.reserve_fresh (state : State) (promise) (older : state.older) :
    ∀ entry ∈ state.pending, entry.1 ≠ (state.reserve promise).2.1 := by
  intro entry present same
  have before := older entry present
  simp only [State.reserve] at same
  omega

theorem State.reserve_older (state : State) (promise) (older : state.older) :
    (state.reserve promise).1.older := by
  intro entry present
  simp only [State.reserve,List.mem_cons] at present
  rcases present with rfl | present
  · exact Nat.lt_succ_self _
  · exact Nat.lt_trans (older entry present) (Nat.lt_succ_self _)

def State.extract (state : State) (identity : Nat) : State × Option Pending :=
  ({state with pending := state.pending.filter (fun entry => entry.1 != identity)},
    state.pending.find? (fun entry => entry.1 == identity))

theorem State.extract_preserves_generation (state : State) (identity : Nat) :
    (state.extract identity).1.next = state.next := rfl

theorem State.extract_older (state : State) (identity : Nat) (older : state.older) :
    (state.extract identity).1.older := by
  intro entry present
  exact older entry (List.mem_filter.mp present).1

def State.retire (state : State) : State × Bool × List Pending :=
  if state.closed then (state,false,[]) else ({state with pending := [],closed := true},true,state.pending)

theorem State.retire_once (state : State) (closed : state.closed = true) :
    state.retire = (state,false,[]) := by simp [State.retire,closed]

theorem State.retire_preserves_generation (state : State) : state.retire.1.next = state.next := by
  cases closed : state.closed <;> simp [State.retire,closed]

theorem State.retire_older (state : State) (older : state.older) : state.retire.1.older := by
  cases closed : state.closed
  · simp [State.retire,closed,State.older]
  · simpa [State.retire,closed] using older

structure CheckedState where
  value : State
  older : value.older

structure Core where
  private mk ::
  child : Kernel
  private state : Std.Mutex CheckedState
  private writer : Std.Mutex Unit

structure Server where
  core : Core
  reader : Task (Except IO.Error Unit)

def stop (child : Kernel) : IO Unit := do
  if (← child.tryWait).isNone then
    child.kill
    discard <| child.wait

/-- The management transaction returns the retirement owner. Stopping and
resolving promises happen after it, so EOF and shutdown cannot reap twice. -/
@[no_expose] def Core.abort (core : Core) (message : String) : IO Unit := do
  let (owner,pending) ← core.state.atomically do
    let checked ← get
    let plan := checked.value.retire
    set (⟨plan.1,checked.value.retire_older checked.older⟩ : CheckedState)
    return (plan.2.1,plan.2.2)
  for entry in pending do entry.2.resolve (.error (IO.userError message))
  if owner then stop core.child

@[no_expose] def Core.send (core : Core) (request : Json) : IO Unit := do
  -- This protects frame bytes on one physical pipe, never model execution.
  let frame := request.compress ++ "\n"
  core.writer.atomically do
    core.child.stdin.putStr frame
    core.child.stdin.flush

@[no_expose] def Core.route (core : Core) (value : Json) : IO Unit := do
  let identity ← IO.ofExcept (value.getObjValAs? Nat "id")
  if value.getObjValD "operation" == toJson "cancel" then return
  let selected ← core.state.atomically do
    let checked ← get
    let plan := checked.value.extract identity
    set (⟨plan.1,checked.value.extract_older identity checked.older⟩ : CheckedState)
    return plan.2
  let some selected := selected | throw (IO.userError "shared encoder returned an unknown or completed request")
  let some checked := Reply.check selected.1 identity value.compress | do
    selected.2.resolve (.error (IO.userError "shared encoder crossed response owners"))
    throw (IO.userError "shared encoder crossed response owners")
  if let .ok error := value.getObjValAs? String "error" then
    selected.2.resolve (.error (IO.userError error))
  else selected.2.resolve (.ok checked)

@[no_expose] def Core.read (core : Core) : IO Unit := do
  try
    repeat
      let line ← core.child.stdout.getLine
      unless !line.isEmpty do throw (IO.userError "shared encoder reached EOF")
      core.route (← IO.ofExcept (Json.parse line))
  catch error => core.abort error.toString

def waitStartup (task : Task (Except IO.Error String)) (live : IO Bool) : IO String := do
  let ready ← TaskDeadline.event task
  let deadline := (← IO.monoMsNow)+15000
  repeat
    let now ← IO.monoMsNow
    unless (← live) && !(← IO.checkCanceled) && now < deadline do
      throw (IO.userError "shared encoder startup expired or service stopped")
    let value ← TaskDeadline.awaitEvent (do
      let timer ← Selector.sleep (.ofNat (min 5 (deadline-now)))
      OwnedSelect.one #[.case ready (fun value => pure (some value)),.case timer (fun _ => pure none)])
    if let some value := value then return value
  throw (IO.userError "unreachable shared encoder startup")

@[no_expose] def Server.start (create : IO Kernel) (live : IO Bool := pure true) : IO Server := do
  let child ← create
  try
    child.stdin.putStrLn (Json.mkObj [("operation",toJson "ready")]).compress
    child.stdin.flush
    let task ← IO.asTask child.stdout.getLine .dedicated
    let line ← try waitStartup task live
      catch error =>
        try child.kill catch _ => pure ()
        discard <| IO.wait task
        throw error
    let ready ← IO.ofExcept (Json.parse line)
    unless ready.getObjValD "ready" == toJson true && ready.getObjValD "pid" == toJson child.pid.toNat do
      throw (IO.userError "shared encoder failed its owned-process readiness check")
    let empty : CheckedState := ⟨{},by simp [State.older]⟩
    let core : Core := ⟨child,← Std.Mutex.new empty,← Std.Mutex.new ()⟩
    return ⟨core,← IO.asTask core.read .dedicated⟩
  catch error => stop child; throw error

def Server.close (server : Server) : IO Unit := do
  try server.core.abort "shared encoder service stopped"
  finally discard <| IO.wait server.reader

@[no_expose] def Core.register (core : Core) : IO Pending := core.state.atomically do
  let checked ← get
  let state := checked.value
  if state.closed then throw (IO.userError "shared encoder is closed")
  -- The caller owns an encoder-compute slot until the terminal response.
  if state.pending.length ≥ 2 then throw (IO.userError "shared encoder compute capacity exceeded")
  let promise ← IO.Promise.new
  let plan := state.reserve promise
  set (⟨plan.1,state.reserve_older promise checked.older⟩ : CheckedState)
  return plan.2

@[no_expose] def Server.pending (server : Server) : IO Nat := server.core.state.atomically do
  return (← get).value.pending.length

@[no_expose] def Server.closed (server : Server) : IO Bool := server.core.state.atomically do
  return (← get).value.closed

def waitReply (entry : Pending) (deadline : Nat) (live : IO Bool) : IO (Reply entry.1) := do
  let ready ← TaskDeadline.event entry.2.result!
  repeat
    let now ← IO.monoMsNow
    unless (← live) && now < deadline do throw (IO.userError "shared encoder request expired or disconnected")
    let value ← TaskDeadline.awaitEvent (do
      let timer ← Selector.sleep (.ofNat (min 5 (deadline-now)))
      OwnedSelect.one #[.case ready (fun value => pure (some value)),.case timer (fun _ => pure none)])
    if let some value := value then return value
  throw (IO.userError "unreachable shared encoder wait")

/-- Every operation after registration is outside the state mutex. A cancelled
request retains its compute slot until ORT has returned its terminal response.
Only an unresponsive/broken service is retired as a whole. -/
def Server.request (server : Server) (body : String) (deadline : Nat) (live : IO Bool) : IO String := do
  let value ← IO.ofExcept (Json.parse body)
  let texts ← IO.ofExcept (value.getObjValAs? (Array String) "texts")
  let entry ← server.core.register
  try
    server.core.send (Json.mkObj [("operation",toJson "start"),("id",toJson entry.1),("texts",toJson texts)])
    let reply ← waitReply entry deadline live
    return reply.body
  catch error =>
    if !(← entry.2.isResolved) then
      try
        server.core.send (Json.mkObj [("operation",toJson "cancel"),("id",toJson entry.1)])
        try discard <| waitReply entry ((← IO.monoMsNow)+1000) (pure true) catch _ => pure ()
        unless ← entry.2.isResolved do server.core.abort "shared encoder did not acknowledge native cancellation"
      catch failure => server.core.abort failure.toString
    throw error

end Eggshell.Research.SharedEncoder
