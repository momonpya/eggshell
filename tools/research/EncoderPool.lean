module
public import Std.Sync.Mutex
@[expose] public section
namespace Eggshell.Research.EncoderPool

/-- A slot keeps its credit through startup, use and retirement. An encoder
is not available to another request while its pipe is owned by this ticket. -/
inductive Slot (α : Type) where
  | empty
  | idle (resource : α)
  | running (token : Nat) (resource : Option α)
  | retiring (token : Nat) (resource : α)

structure Ticket (α : Type) where
  index : Nat
  token : Nat
  cached : Option α

structure State (α : Type) where
  slots : Array (Slot α)
  next : Nat := 0
  starts : Nat := 0
  closed : Bool := false

def State.reserveAt (state : State α) (index : Nat) : Option (State α × Ticket α) := do
  if state.closed then none else do
    let slot ← state.slots[index]?
    let resource ← match slot with
      | .empty => some none
      | .idle value => some (some value)
      | _ => none
    let ticket : Ticket α := {index,token := state.next,cached := resource}
    return ({state with slots := state.slots.set! index (.running state.next resource),next := state.next+1},ticket)

def State.reserve (state : State α) : Option (State α × Ticket α) := Id.run do
  for index in [:state.slots.size] do
    if let some (.idle _) := state.slots[index]? then
      if let some result := state.reserveAt index then return some result
  for index in [:state.slots.size] do
    if let some result := state.reserveAt index then return some result
  return none

theorem closed_reservation_refused (state : State α) (index : Nat)
    (closed : state.closed = true) : state.reserveAt index = none := by
  simp [State.reserveAt,closed]

theorem running_reservation_refused (state : State α) (index token : Nat) (resource : Option α)
    (running : state.slots[index]? = some (.running token resource)) : state.reserveAt index = none := by
  cases closed : state.closed <;> simp [State.reserveAt,closed,running]

theorem retiring_reservation_refused (state : State α) (index token : Nat) (resource : α)
    (retiring : state.slots[index]? = some (.retiring token resource)) : state.reserveAt index = none := by
  cases closed : state.closed <;> simp [State.reserveAt,closed,retiring]

def State.install (state : State α) (ticket : Ticket α) (resource : α) : State α × Bool :=
  match state.slots[ticket.index]? with
  | some (.running token none) =>
    if token == ticket.token then
      ({state with slots := state.slots.set! ticket.index (.running token (some resource)),starts := state.starts+1},true)
    else (state,false)
  | _ => (state,false)

def State.giveBack (state : State α) (ticket : Ticket α) (keep : Bool) : State α × Option α :=
  match state.slots[ticket.index]? with
  | some (.running token resource) =>
    if token == ticket.token then
      match resource with
      | none => ({state with slots := state.slots.set! ticket.index .empty},none)
      | some value =>
        if keep && !state.closed then
          ({state with slots := state.slots.set! ticket.index (.idle value)},none)
        else ({state with slots := state.slots.set! ticket.index (.retiring token value)},some value)
    else (state,none)
  | _ => (state,none)

def State.retired (state : State α) (ticket : Ticket α) : State α :=
  match state.slots[ticket.index]? with
  | some (.retiring token _) =>
    if token == ticket.token then {state with slots := state.slots.set! ticket.index .empty} else state
  | _ => state

theorem stale_return_unchanged (state : State α) (ticket : Ticket α) (token : Nat)
    (resource : Option α) (keep : Bool)
    (running : state.slots[ticket.index]? = some (.running token resource))
    (different : token ≠ ticket.token) : state.giveBack ticket keep = (state,none) := by
  simp [State.giveBack,running,different]

theorem stale_retirement_unchanged (state : State α) (ticket : Ticket α) (token : Nat)
    (resource : α) (retiring : state.slots[ticket.index]? = some (.retiring token resource))
    (different : token ≠ ticket.token) : state.retired ticket = state := by
  simp [State.retired,retiring,different]

def State.close (state : State α) : State α × Array α := Id.run do
  let mut slots := state.slots
  let mut idle := #[]
  for index in [:slots.size] do
    if let some (.idle resource) := slots[index]? then
      idle := idle.push resource
      slots := slots.set! index .empty
  return ({state with slots,closed := true},idle)

/-- CPU and model-resident credits set a ceiling, not a fixed search-worker
count. Slots are created lazily only when an independent request needs one.
The external numerical runtime's RSS still requires measurement. -/
def residentBudget : Nat := 1024*1024*1024
def residentPerSlot : Nat := 512*1024*1024
def capacity (hardwareThreads : Nat) : Nat :=
  max 1 (min (max 1 (hardwareThreads/4)) (residentBudget/residentPerSlot))

theorem capacity_positive (hardwareThreads : Nat) : 0 < capacity hardwareThreads := by
  simp only [capacity]
  omega

theorem capacity_bounded (hardwareThreads : Nat) : capacity hardwareThreads ≤ 2 := by
  simp only [capacity,residentBudget,residentPerSlot]
  omega

structure Pool (α : Type) where
  state : Std.Mutex (State α)

def Pool.make (count : Nat) : IO (Pool α) := do
  return ⟨← Std.Mutex.new {slots := Array.replicate count .empty}⟩

def Pool.take? (pool : Pool α) : IO (Option (Ticket α)) := pool.state.atomically do
  let state ← get
  if state.closed then throw (IO.userError "encoder pool is closed")
  match state.reserve with
  | none => return none
  | some (state,ticket) => set state; return some ticket

def Pool.install (pool : Pool α) (ticket : Ticket α) (resource : α) : IO Bool := pool.state.atomically do
  let (state,accepted) := (← get).install ticket resource
  set state
  return accepted

def Pool.giveBack (pool : Pool α) (ticket : Ticket α) (keep : Bool) (dispose : α → IO Unit) : IO Unit := do
  let retired ← pool.state.atomically do
    let (state,retired) := (← get).giveBack ticket keep
    set state
    return retired
  if let some resource := retired then
    -- A failed stop does not free a slot for another live model.
    dispose resource
    pool.state.atomically (modify (·.retired ticket))

def Pool.close (pool : Pool α) (dispose : α → IO Unit) : IO Unit := do
  let idle ← pool.state.atomically do
    let (state,idle) := (← get).close
    set state
    return idle
  for resource in idle do dispose resource

def Pool.borrow (pool : Pool α) (live : IO Bool) : IO (Ticket α) := do
  repeat
    unless ← live do throw (IO.userError "encoder request is no longer live")
    if let some ticket ← pool.take? then return ticket
    IO.sleep 1
  throw (IO.userError "unreachable encoder admission")

/-- No pool lock spans creation, pipe IO, inference, cancellation, stopping
or joining. The callback has an exclusive pipe and a once-only retirement
operation. Shutdown closes admission but leaves active owners in charge. -/
def Pool.withResource (pool : Pool α) (live : IO Bool) (create : Ticket α → IO α)
    (dispose : α → IO Unit) (use : Ticket α → α → IO Unit → IO β) : IO β := do
  let ticket ← pool.borrow live
  let resource ← try
    match ticket.cached with
    | some value => pure value
    | none => do
      let value ← create ticket
      unless ← pool.install ticket value do
        dispose value
        throw (IO.userError "encoder slot changed before installation")
      pure value
  catch error =>
    pool.giveBack ticket false dispose
    throw error
  let succeeded ← IO.mkRef false
  let retire := pool.giveBack ticket false dispose
  try
    unless ← live do throw (IO.userError "encoder request expired before execution")
    let result ← use ticket resource retire
    succeeded.set true
    return result
  finally pool.giveBack ticket (← succeeded.get) dispose

end Eggshell.Research.EncoderPool
