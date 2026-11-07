module
public import Std.Sync.Mutex
public import Init.Data.Array.MapIdx
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
  waiting : Nat := 0

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

def Slot.isIdle : Slot α → Bool | .idle _ => true | _ => false

def Slot.trim (anchor token index : Nat) (slot : Slot α) : Slot α :=
  if index == anchor then slot else match slot with
    | .idle resource => .retiring (token+index) resource
    | other => other

theorem Slot.trim_idle_anchor (anchor token index : Nat) (slot : Slot α) (resource : α)
    (found : slot.trim anchor token index = .idle resource) : index = anchor := by
  by_cases same : index = anchor
  · exact same
  · cases slot <;> simp [Slot.trim,same] at found

theorem Slot.trim_running (anchor token index owner : Nat) (resource : Option α) :
    (Slot.running owner resource).trim anchor token index = .running owner resource := by
  by_cases same : index = anchor <;> simp [Slot.trim,same]

theorem Slot.trim_retiring (anchor token index owner : Nat) (resource : α) :
    (Slot.retiring owner resource).trim anchor token index = .retiring owner resource := by
  by_cases same : index = anchor <;> simp [Slot.trim,same]

/-- Queued demand keeps both warm pipes available. At quiescence keep one
hot standby; surplus resources retain their slots until stopping succeeds. -/
def State.trimIdle (state : State α) : State α × Array (Ticket α × α) :=
  if state.waiting ≠ 0 then (state,#[]) else
    let anchor := (state.slots.findIdx? Slot.isIdle).getD 0
    let spare := state.slots.zipIdx.filterMap fun (slot,index) => match slot with
      | .idle resource => if index == anchor then none else
          some (({index,token := state.next+index,cached := none} : Ticket α),resource)
      | _ => none
    let slots := state.slots.mapIdx (fun index slot => slot.trim anchor state.next index)
    let nextToken := if spare.isEmpty then state.next else state.next+state.slots.size
    ({state with slots,next := nextToken},spare)

def State.standbyBound (state : State α) : Prop :=
  ∃ anchor : Nat, ∀ (index : Nat) (resource : α), state.slots[index]? = some (Slot.idle resource) → index = anchor

theorem State.trimIdle_demand (state : State α) (demand : state.waiting ≠ 0) :
    state.trimIdle = (state,#[]) := by simp [State.trimIdle,demand]

theorem State.trimIdle_standby (state : State α) (quiet : state.waiting = 0) :
    state.trimIdle.1.standbyBound := by
  refine ⟨(state.slots.findIdx? Slot.isIdle).getD 0,?_⟩
  intro index resource found
  simp only [State.trimIdle,quiet,ne_eq,not_true_eq_false,if_false,Array.getElem?_mapIdx] at found
  cases original : state.slots[index]? with
  | none => simp [original] at found
  | some slot =>
      exact Slot.trim_idle_anchor _ _ _ slot resource (by simpa [original] using found)

theorem State.trimIdle_running (state : State α) (index token : Nat) (resource : Option α)
    (found : state.slots[index]? = some (.running token resource)) :
    state.trimIdle.1.slots[index]? = some (.running token resource) := by
  by_cases demand : state.waiting ≠ 0
  · simp [State.trimIdle,demand,found]
  · simp [State.trimIdle,demand,Array.getElem?_mapIdx,found,Slot.trim_running]

theorem State.trimIdle_retiring (state : State α) (index token : Nat) (resource : α)
    (found : state.slots[index]? = some (.retiring token resource)) :
    state.trimIdle.1.slots[index]? = some (.retiring token resource) := by
  by_cases demand : state.waiting ≠ 0
  · simp [State.trimIdle,demand,found]
  · simp [State.trimIdle,demand,Array.getElem?_mapIdx,found,Slot.trim_retiring]

theorem State.trimIdle_unique (state : State α) (quiet : state.waiting = 0)
    (left right : Nat) (a b : α) (ha : state.trimIdle.1.slots[left]? = some (.idle a))
    (hb : state.trimIdle.1.slots[right]? = some (.idle b)) : left = right := by
  obtain ⟨anchor,unique⟩ := state.trimIdle_standby quiet
  exact (unique left a ha).trans (unique right b hb).symm

theorem State.trimIdle_size (state : State α) : state.trimIdle.1.slots.size = state.slots.size := by
  by_cases demand : state.waiting ≠ 0 <;> simp [State.trimIdle,demand]

/-- CPU and a two-replica deployment ceiling bound model processes, not search
actors. This is not a byte bound; actual runtime RSS remains guarded. -/
def maxReplicas : Nat := 2
def capacity (hardwareThreads : Nat) : Nat :=
  max 1 (min (max 1 (hardwareThreads/4)) maxReplicas)

theorem capacity_positive (hardwareThreads : Nat) : 0 < capacity hardwareThreads := by
  simp only [capacity]
  omega

theorem capacity_bounded (hardwareThreads : Nat) : capacity hardwareThreads ≤ 2 := by
  simp only [capacity,maxReplicas]
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

def Pool.disposeRetired (pool : Pool α) (retired : Array (Ticket α × α)) (dispose : α → IO Unit) : IO Unit := do
  let mut failure := none
  for (ticket,resource) in retired do
    try
      dispose resource
      pool.state.atomically (modify (·.retired ticket))
    catch error => if failure.isNone then failure := some error
  if let some error := failure then throw error

def Pool.returnPlan (pool : Pool α) (ticket : Ticket α) (keep : Bool) : IO (Array (Ticket α × α)) :=
  pool.state.atomically do
    let (state,retired) := (← get).giveBack ticket keep
    let (state,spare) := state.trimIdle
    set state
    return (retired.map (fun resource => (ticket,resource))).toArray ++ spare

def Pool.giveBack (pool : Pool α) (ticket : Ticket α) (keep : Bool) (dispose : α → IO Unit) : IO Unit := do
  let retired ← pool.returnPlan ticket keep
  pool.disposeRetired retired dispose

theorem Pool.return_stops_after_plan (pool : Pool α) (ticket : Ticket α) (keep : Bool) (dispose : α → IO Unit) :
    pool.giveBack ticket keep dispose = (do
      let retired ← pool.returnPlan ticket keep
      pool.disposeRetired retired dispose) := rfl

def Pool.close (pool : Pool α) (dispose : α → IO Unit) : IO Unit := do
  let idle ← pool.state.atomically do
    let (state,idle) := (← get).close
    set state
    return idle
  for resource in idle do dispose resource

def Pool.waitTicket (pool : Pool α) (live : IO Bool) : IO (Ticket α) := do
  repeat
    unless ← live do throw (IO.userError "encoder request is no longer live")
    if let some ticket ← pool.take? then return ticket
    IO.sleep 1
  throw (IO.userError "unreachable encoder admission")

def Pool.queueLeavePlan (pool : Pool α) : IO (Array (Ticket α × α)) :=
  pool.state.atomically do
    let state ← get
    let (state,spare) := {state with waiting := state.waiting-1}.trimIdle
    set state
    return spare

def Pool.finishWaiting (pool : Pool α) (dispose : α → IO Unit) : IO Unit := do
  let spare ← pool.queueLeavePlan
  pool.disposeRetired spare dispose

theorem Pool.queue_stops_after_plan (pool : Pool α) (dispose : α → IO Unit) :
    pool.finishWaiting dispose = (do
      let spare ← pool.queueLeavePlan
      pool.disposeRetired spare dispose) := rfl

def Pool.borrow (pool : Pool α) (live : IO Bool) (dispose : α → IO Unit) : IO (Ticket α) := do
  let assigned ← IO.mkRef none
  pool.state.atomically do
    let state ← get
    if state.closed then throw (IO.userError "encoder pool is closed")
    set {state with waiting := state.waiting+1}
  try
    let ticket ← pool.waitTicket live
    assigned.set (some ticket)
    return ticket
  finally
    try pool.finishWaiting dispose
    catch error =>
      if let some ticket ← assigned.get then pool.giveBack ticket false dispose
      throw error

/-- No pool lock spans creation, pipe IO, inference, cancellation, stopping
or joining. The callback has an exclusive pipe and a once-only retirement
operation. Shutdown closes admission but leaves active owners in charge. -/
def Pool.withResource (pool : Pool α) (live : IO Bool) (create : Ticket α → IO α)
    (dispose : α → IO Unit) (use : Ticket α → α → IO Unit → IO β) : IO β := do
  let ticket ← pool.borrow live dispose
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
