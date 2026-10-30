module
public import Eggshell.CanonicalSourceRecipe
public import Std.Sync.Mutex
public import Init.System.Promise
@[expose] public section

namespace Eggshell.Synapses.PreparedOwnerArena
open Lean DB

/-- Query-independent, checked original data. A resident value never contains
query cues, usage feedback, selection weights, a budget or authority. -/
structure Ready where
  database : String
  owner : String
  stored : CanonicalSource.Recipe.Stored
  layout : CanonicalSource.Recipe.Checked stored.rows
  checked : CanonicalSource.Recipe.check stored.rows stored.records = .ok layout
  original : ∃ registry, CanonicalSource.load database stored.rows = .ok registry
  scope : stored.rows.all (fun row => row.origins.all (fun origin =>
    origin.binding.database == database && origin.binding.owner == owner)) = true

def prepare (database owner : String) (stored : CanonicalSource.Recipe.Stored) : Except String Ready := do
  if inScope : stored.rows.all (fun row => row.origins.all (fun origin =>
      origin.binding.database == database && origin.binding.owner == owner)) = true then
    match loaded : CanonicalSource.load database stored.rows with
    | .error message => throw message
    | .ok registry =>
      match checked : CanonicalSource.Recipe.check stored.rows stored.records with
      | .error message => throw message
      | .ok layout => return ⟨database,owner,stored,layout,checked,⟨registry,loaded⟩,inScope⟩
  else throw "prepared owner crosses its source scope"

theorem Ready.no_foreign_origin (ready : Ready) (row : CanonicalSource.StoredRow)
    (member : row ∈ ready.stored.rows) (origin : CanonicalSource.Origin)
    (present : origin ∈ row.origins) :
    (origin.binding.database == ready.database && origin.binding.owner == ready.owner) = true := by
  exact (Array.all_eq_true'.mp ((Array.all_eq_true'.mp ready.scope) row member)) origin present

theorem Ready.complete_catalogue (ready : Ready) (index : Fin ready.stored.rows.size) :
    index ∈ ready.layout.catalogue.flatten := ready.layout.catalogue_complete index

/-- One shared service budget. Snapshot headers keep 64 MiB, geometry 16 MiB,
and PageMap pages 128 MiB; these resident owners use the remaining 304 MiB. -/
def capacity : Nat := 304*1024*1024
def maxEntries : Nat := 4096
def maxLoads : Nat := 2

/-- Conservative admission charge, independent of caller count. The RSS guard
is still authoritative: this is an accounting bound, not a Lean-heap theorem. -/
def charge (payloadBytes : Nat) : Nat := 65536+16*payloadBytes

structure Budget where
  used : Nat := 0
  within : used ≤ capacity := by decide

def Budget.reserve? (budget : Budget) (amount : Nat) : Option Budget :=
  if fits : budget.used+amount ≤ capacity then some ⟨budget.used+amount,fits⟩ else none

def Budget.release (budget : Budget) (amount : Nat) : Budget :=
  ⟨budget.used-amount,Nat.le_trans (Nat.sub_le ..) budget.within⟩

structure Entry where
  promise : IO.Promise (Except String Ready)
  charge : Nat
  borrowers : Nat
  stamp : Nat
  serial : Nat
  loading : Bool := true

structure State where
  entries : Std.HashMap (String × String × String) Entry := {}
  budget : Budget := {}
  active : Nat := 0
  clock : Nat := 0
  closed : Bool := false
  loads : Nat := 0
  hits : Nat := 0
  joins : Nat := 0
  evictions : Nat := 0

structure Cache where
  state : Std.Mutex State
  tasks : Std.Mutex (Array (Task (Except IO.Error Unit)))

def Cache.new : IO Cache := return ⟨← Std.Mutex.new {},← Std.Mutex.new #[]⟩

def evict (state : State) : Option State := do
  let idle := state.entries.toArray.filter fun (_,entry) => !entry.loading && entry.borrowers == 0
  let (key,entry) ← (idle.qsort fun a b => a.2.stamp < b.2.stamp)[0]?
  return {state with
    entries := state.entries.erase key
    budget := state.budget.release entry.charge
    evictions := state.evictions+1}

def reclaim (state : State) (amount : Nat) : Nat → State
  | 0 => state
  | fuel+1 =>
    if state.budget.used+amount ≤ capacity && state.entries.size < maxEntries then state else
    match evict state with
    | none => state
    | some next => reclaim next amount fuel

inductive Admission where
  | found (entry : Entry)
  | start (entry : Entry)
  | busy

def Cache.admit (cache : Cache) (key : String × String × String) (amount : Nat) : IO Admission :=
  cache.state.atomically do
    let state ← get
    unless !state.closed do throw (IO.userError "prepared owner arena is closed")
    if let some prior := state.entries[key]? then
      unless prior.charge == amount do throw (IO.userError "prepared owner descriptor changed inside its publication")
      let entry := {prior with borrowers := prior.borrowers+1,stamp := state.clock+1}
      set {state with
        entries := state.entries.insert key entry,clock := state.clock+1,
        hits := state.hits+(if entry.loading then 0 else 1),
        joins := state.joins+(if entry.loading then 1 else 0)}
      return .found entry
    if state.active ≥ maxLoads then return .busy
    let state := reclaim state amount maxEntries
    let some budget := state.budget.reserve? amount | set state; return .busy
    if state.entries.size ≥ maxEntries then set state; return .busy
    let entry : Entry := ⟨← IO.Promise.new,amount,1,state.clock+1,state.clock+1,true⟩
    set {state with
      entries := state.entries.insert key entry,budget,
      active := state.active+1,clock := state.clock+1,loads := state.loads+1}
    return .start entry

def Cache.release (cache : Cache) (key : String × String × String) (serial : Nat) : IO Unit :=
  cache.state.atomically do
    modify fun state => match state.entries[key]? with
      | none => state
      | some entry => if entry.serial != serial then state else
        {state with entries := state.entries.insert key {entry with borrowers := entry.borrowers-1}}

def Cache.finish (cache : Cache) (key : String × String × String) (entry : Entry)
    (result : Except String Ready) : IO Unit := cache.state.atomically do
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

def Cache.launch (cache : Cache) (key : String × String × String) (entry : Entry) (load : IO Ready) : IO Unit :=
  cache.state.atomically do
    let state ← get
    if state.closed then
      unless ← entry.promise.isResolved do entry.promise.resolve (.error "prepared owner arena stopped")
      return
    let task ← IO.asTask (do
      let result ← try
          if ← IO.checkCanceled then throw (IO.userError "prepared owner load cancelled")
          let ready ← load
          if ← IO.checkCanceled then throw (IO.userError "prepared owner load cancelled")
          unless ready.database == key.2.1 && ready.owner == key.2.2 do
            throw (IO.userError "prepared owner load changed its database or owner")
          pure (.ok ready : Except String Ready)
        catch error => pure (.error error.toString)
      cache.finish key entry result) .dedicated
    cache.tasks.atomically do
      let live ← (← get).filterM fun task => return !(← IO.hasFinished task)
      set (live.push task)

/-- The key is the authenticated immutable preparation identity plus owner.
Loans remain charged until their continuation returns. Expiry never restarts
an in-flight load; other borrowers join its existing promise. -/
def Cache.withReady (cache : Cache) (publication database owner : String) (payloadBytes deadline : Nat)
    (load : IO Ready) (use : Ready → IO α) : IO α := do
  let amount := charge payloadBytes
  unless amount ≤ capacity do throw (IO.userError "prepared owner exceeds shared resident budget")
  let key := (publication,database,owner)
  let mut selected := none
  repeat
    unless (← IO.monoMsNow) < deadline do throw (IO.userError "prepared owner admission expired")
    match ← cache.admit key amount with
    | .busy => IO.sleep 1
    | .found entry => selected := some entry; break
    | .start entry =>
      try cache.launch key entry load
      catch error => cache.finish key entry (.error error.toString)
      selected := some entry
      break
  let some entry := selected | throw (IO.userError "prepared owner admission disappeared")
  try
    repeat
      unless (← IO.monoMsNow) < deadline do throw (IO.userError "prepared owner wait expired")
      if ← entry.promise.isResolved then
        let some result := entry.promise.result?.get | throw (IO.userError "prepared owner reply disappeared")
        return ← use (← IO.ofExcept result)
      IO.sleep 1
    throw (IO.userError "unreachable prepared owner wait")
  finally cache.release key entry.serial

def Cache.close (cache : Cache) : IO Unit := do
  cache.state.atomically do
    let state ← get
    set {state with closed := true,entries := {},budget := {},active := 0}
    for (_,entry) in state.entries do
      unless ← entry.promise.isResolved do entry.promise.resolve (.error "prepared owner arena stopped")
  for task in ← cache.tasks.atomically get do IO.cancel task

def Cache.stats (cache : Cache) : IO Json := cache.state.atomically do
  let state ← get
  return Json.mkObj [("entries",toJson state.entries.size),("chargedBytes",toJson state.budget.used),
    ("capacity",toJson capacity),("loads",toJson state.loads),("hits",toJson state.hits),
    ("joins",toJson state.joins),("evictions",toJson state.evictions),("active",toJson state.active),
    ("borrowers",toJson (state.entries.fold (fun n _ entry => n+entry.borrowers) 0)),
    ("accountedExact",toJson (state.budget.used == state.entries.fold (fun n _ entry => n+entry.charge) 0)),
    ("closed",toJson state.closed)]

end Eggshell.Synapses.PreparedOwnerArena
