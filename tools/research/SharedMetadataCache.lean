module
public import Std.Data.HashMap
public import Std.Sync.Mutex
public import Init.System.Promise
@[expose] public section

namespace Eggshell.Synapses.SharedMetadataCache

structure Budget (capacity : Nat) where
  used : Nat := 0
  within : used ≤ capacity := by omega

def Budget.reserve? (budget : Budget capacity) (amount : Nat) : Option (Budget capacity) :=
  if fits : budget.used+amount ≤ capacity then some ⟨budget.used+amount,fits⟩ else none

def Budget.release (budget : Budget capacity) (amount : Nat) : Budget capacity :=
  ⟨budget.used-amount,Nat.le_trans (Nat.sub_le ..) budget.within⟩

structure Entry (α : Type) where
  promise : IO.Promise (Except String α)
  charge : Nat
  borrowers : Nat
  stamp : Nat
  serial : Nat
  loading : Bool := true

structure State (α : Type) (capacity : Nat) where
  entries : Std.HashMap String (Entry α) := {}
  budget : Budget capacity := {}
  active : Nat := 0
  clock : Nat := 0
  closed : Bool := false
  loads : Nat := 0
  hits : Nat := 0
  joins : Nat := 0
  evictions : Nat := 0

structure Cache (α : Type) (capacity : Nat) where
  state : Std.Mutex (State α capacity)
  tasks : Std.Mutex (Array (Task (Except IO.Error Unit)))
  maxEntries : Nat
  maxLoads : Nat

def Cache.new (α : Type) (capacity maxEntries maxLoads : Nat) : IO (Cache α capacity) :=
  return ⟨← Std.Mutex.new {},← Std.Mutex.new #[],maxEntries,maxLoads⟩

def evict (state : State α capacity) : Option (State α capacity) := do
  let idle := state.entries.toArray.filter fun (_,entry) => !entry.loading && entry.borrowers == 0
  let (key,entry) ← (idle.qsort fun a b => a.2.stamp < b.2.stamp)[0]?
  return {state with
    entries := state.entries.erase key
    budget := state.budget.release entry.charge
    evictions := state.evictions+1}

def reclaim (state : State α capacity) (amount maxEntries : Nat) : Nat → State α capacity
  | 0 => state
  | fuel+1 =>
    if state.budget.used+amount ≤ capacity && state.entries.size < maxEntries then state else
    match evict state with
    | none => state
    | some next => reclaim next amount maxEntries fuel

inductive Admission (α : Type) where
  | found (entry : Entry α)
  | start (entry : Entry α)
  | busy

def Cache.admit (cache : Cache α capacity) (key : String) (amount : Nat) : IO (Admission α) :=
  cache.state.atomically do
    let state ← get
    unless !state.closed do throw (IO.userError "metadata cache is closed")
    if let some prior := state.entries[key]? then
      unless prior.charge == amount do throw (IO.userError "immutable metadata changed its admission charge")
      let entry := {prior with borrowers := prior.borrowers+1,stamp := state.clock+1}
      set {state with
        entries := state.entries.insert key entry,clock := state.clock+1,
        hits := state.hits+(if entry.loading then 0 else 1),joins := state.joins+(if entry.loading then 1 else 0)}
      return .found entry
    if state.active ≥ cache.maxLoads then return .busy
    let state := reclaim state amount cache.maxEntries cache.maxEntries
    let some budget := state.budget.reserve? amount | set state; return .busy
    if state.entries.size ≥ cache.maxEntries then set state; return .busy
    let entry : Entry α := ⟨← IO.Promise.new,amount,1,state.clock+1,state.clock+1,true⟩
    set {state with
      entries := state.entries.insert key entry,budget,
      active := state.active+1,clock := state.clock+1,loads := state.loads+1}
    return .start entry

def Cache.release (cache : Cache α capacity) (key : String) (serial : Nat) : IO Unit :=
  cache.state.atomically do
    modify fun state => match state.entries[key]? with
      | none => state
      | some entry => if entry.serial != serial then state else
        {state with entries := state.entries.insert key {entry with borrowers := entry.borrowers-1}}

def Cache.finish (cache : Cache α capacity) (key : String) (entry : Entry α)
    (result : Except String α) : IO Unit := cache.state.atomically do
  let state ← get
  if !state.closed then
    if let some current := state.entries[key]? then
      if current.serial == entry.serial then
        match result with
        | .ok _ => set {state with
            active := state.active-1,
            entries := state.entries.insert key {current with loading := false}}
        | .error _ => set {state with
            active := state.active-1,
            entries := state.entries.erase key,budget := state.budget.release current.charge}
  unless ← entry.promise.isResolved do entry.promise.resolve result

def Cache.launch (cache : Cache α capacity) (key : String) (entry : Entry α) (load : IO α) : IO Unit :=
  cache.state.atomically do
    let state ← get
    if state.closed then
      unless ← entry.promise.isResolved do entry.promise.resolve (.error "metadata cache stopped")
      return
    let task ← IO.asTask (do
      let result ← try
          if ← IO.checkCanceled then throw (IO.userError "metadata load cancelled")
          let value ← load
          if ← IO.checkCanceled then throw (IO.userError "metadata load cancelled")
          pure (.ok value : Except String α)
        catch error => pure (.error error.toString)
      cache.finish key entry result) .dedicated
    cache.tasks.atomically do
      let live ← (← get).filterM fun task => return !(← IO.hasFinished task)
      set (live.push task)

/-- Publication and DB/scope identity belong in key; capabilities and query
text do not. Concurrent consumers join a single immutable load. -/
def Cache.withReady (cache : Cache α capacity) (key : String) (amount deadline : Nat)
    (load : IO α) (use : α → IO β) : IO β := do
  unless amount ≤ capacity do throw (IO.userError "metadata exceeds shared resident budget")
  let mut selected := none
  repeat
    unless (← IO.monoMsNow) < deadline do throw (IO.userError "metadata admission expired")
    match ← cache.admit key amount with
    | .busy => IO.sleep 1
    | .found entry => selected := some entry; break
    | .start entry =>
      try cache.launch key entry load
      catch error => cache.finish key entry (.error error.toString)
      selected := some entry
      break
  let some entry := selected | throw (IO.userError "metadata admission disappeared")
  try
    repeat
      unless (← IO.monoMsNow) < deadline do throw (IO.userError "metadata wait expired")
      if ← entry.promise.isResolved then
        let some result := entry.promise.result?.get | throw (IO.userError "metadata result disappeared")
        return ← use (← IO.ofExcept result)
      IO.sleep 1
    throw (IO.userError "unreachable metadata wait")
  finally cache.release key entry.serial

def Cache.close (cache : Cache α capacity) : IO Unit := do
  cache.state.atomically do
    let state : State α capacity ← get
    let stopped : State α capacity := {state with closed := true,entries := {},budget := {},active := 0}
    set stopped
    for (_,entry) in state.entries do
      unless ← entry.promise.isResolved do entry.promise.resolve (.error "metadata cache stopped")
  for task in ← cache.tasks.atomically get do IO.cancel task

end Eggshell.Synapses.SharedMetadataCache
