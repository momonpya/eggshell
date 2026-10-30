module
public import Eggshell.SynapticBindings
public import tools.ByteBudgetCache
public import Std.Sync.Mutex
public import Init.System.Promise
@[expose] public section

namespace Eggshell.Synapses.IndexedBindings.Prepared
open Lean DB

/-- The namespace contains the complete read scope and immutable index file
incarnation. The per-range publication marker changes with its postings. -/
abbrev Key := String × Range
def capacity : Nat := 128*1024*1024
def maxLoads : Nat := 2
def readLimit : Nat := 32*1024*1024

structure Ready where
  scan : Scan
  complete : scan.complete = true

def Ready.charge (key : Key) (value : Ready) : Nat :=
  512 + key.1.utf8ByteSize + (toJson key.2).compress.utf8ByteSize +
    8*value.scan.bytes + 512*value.scan.rows.size

structure Flight where
  serial : Nat
  promise : IO.Promise (Except String Scan)

structure State where
  cache : ByteBudgetCache.Cache Key Ready (capacity/2) := {}
  flights : Std.HashMap Key Flight := {}
  serial : Nat := 0
  hits : Nat := 0
  loads : Nat := 0
  joins : Nat := 0
  skipped : Nat := 0
  closed : Bool := false

structure Pool where
  state : Std.Mutex State
  tasks : Std.Mutex (Array (Task (Except IO.Error Unit)))

def Pool.new : IO Pool := return ⟨← Std.Mutex.new {},← Std.Mutex.new #[]⟩

inductive Admission where
  | ready (value : Ready)
  | start (flight : Flight)
  | join (flight : Flight)
  | busy

def Pool.admit (pool : Pool) (key : Key) : IO Admission := pool.state.atomically do
  let state ← get
  unless !state.closed do throw (IO.userError "prepared binding cache is closed")
  if let some value := state.cache.find? key then
    let cache := if (state.cache.recent.find? key).isSome then state.cache else
      state.cache.touch ⟨key,value,value.charge key⟩
    set {state with cache,hits := state.hits+1}
    return .ready value
  if let some flight := state.flights[key]? then
    set {state with joins := state.joins+1}
    return .join flight
  if state.flights.size ≥ maxLoads then return .busy
  let flight := Flight.mk (state.serial+1) (← IO.Promise.new)
  set {state with
    serial := flight.serial,loads := state.loads+1,
    flights := state.flights.insert key flight}
  return .start flight

def Pool.finish (pool : Pool) (key : Key) (flight : Flight) (result : Except String Scan) : IO Unit :=
  pool.state.atomically do
    let state ← get
    if !state.closed && (state.flights[key]?).any (·.serial == flight.serial) then
      let mut cache := state.cache
      let mut skipped := state.skipped
      if let .ok scan := result then
        if complete : scan.complete = true then
          let value : Ready := ⟨scan,complete⟩
          if value.charge key ≤ capacity/2 then
            cache := cache.touch ⟨key,value,value.charge key⟩
          else skipped := skipped+1
      set {state with cache,skipped,flights := state.flights.erase key}
    unless ← flight.promise.isResolved do flight.promise.resolve result

/-- Closing and task launch share the ownership lock. A request's deadline
does not cancel a load which another reader is already waiting for. -/
def Pool.launch (pool : Pool) (key : Key) (flight : Flight) (load : IO Scan) : IO Unit :=
  pool.state.atomically do
    unless !(← get).closed do
      unless ← flight.promise.isResolved do flight.promise.resolve (.error "prepared binding cache stopped")
      return
    let task ← IO.asTask (do
      let result ← try pure (.ok (← load)) catch error => pure (.error error.toString)
      pool.finish key flight result) .dedicated
    pool.tasks.atomically do
      let live ← (← get).filterM fun task => return !(← IO.hasFinished task)
      set (live.push task)

def Flight.wait (flight : Flight) (deadline : Nat) : IO Scan := do
  repeat
    if (← IO.monoMsNow) ≥ deadline then return {complete := false}
    if ← flight.promise.isResolved then
      let some result := flight.promise.result?.get |
        throw (IO.userError "prepared binding result disappeared")
      return ← IO.ofExcept result
    IO.sleep 1
  throw (IO.userError "unreachable prepared binding wait")

def keyFor (namespaceKey : String) (reader : Index.Reader) (source : Range) : IO Key := do
  let change ← Index.bindingChange? reader.index source
  let identity := (toJson (namespaceKey,reader.manifest.source.identity,
    reader.index.directory.toString,reader.index.head.identity,reader.index.head.authority,
    change.map (·.publication))).compress
  return (identity,source)

def Pool.raw (pool : Pool) (namespaceKey : String) (reader : Index.Reader) (source : Range)
    (deadline byteLimit : Nat) : IO Scan := do
  let key ← keyFor namespaceKey reader source
  repeat
    if (← IO.monoMsNow) ≥ deadline then return {complete := false}
    let admitted ← pool.admit key
    let scan ← match admitted with
      | .busy => IO.sleep 1; continue
      | .ready value => pure value.scan
      | .start flight | .join flight => do
        if let .start _ := admitted then
          pool.launch key flight (rawLookup reader source ((← IO.monoMsNow)+28000) readLimit)
        flight.wait deadline
    -- A smaller caller budget retains the old partial-prefix semantics.
    if scan.bytes > byteLimit then return ← rawLookup reader source deadline byteLimit
    return scan
  throw (IO.userError "unreachable prepared binding read")

def Pool.resolve (pool : Pool) (namespaceKey : String) (reader : Index.Reader)
    (wanted : Array Range) (allowed : Std.HashSet String) (deadline : Nat) : IO Resolved :=
  resolveUsing reader wanted allowed deadline (fun source byteLimit =>
    pool.raw namespaceKey reader source deadline byteLimit)

theorem ready_complete (value : Ready) : value.scan.complete = true := value.complete

theorem namespace_isolated (a b : String) (source : Range) (different : a ≠ b) :
    (a,source) ≠ (b,source) := by
  intro same
  exact different (congrArg Prod.fst same)

theorem retained_budget (state : State) :
    ByteBudgetCache.allocated state.cache.recent.slots +
      ByteBudgetCache.allocated state.cache.previous.slots ≤ capacity := by
  simpa [capacity] using state.cache.allocated_bounded

def Pool.close (pool : Pool) : IO Unit := do
  pool.state.atomically do
    let state ← get
    set {state with closed := true,cache := {},flights := {}}
    for (_,flight) in state.flights do
      unless ← flight.promise.isResolved do flight.promise.resolve (.error "prepared binding cache stopped")
  for task in ← pool.tasks.atomically get do IO.cancel task

def Pool.stats (pool : Pool) : IO Json := pool.state.atomically do
  let state ← get
  return Json.mkObj [("hits",toJson state.hits),("loads",toJson state.loads),("joins",toJson state.joins),
    ("active",toJson state.flights.size),("maxLoads",toJson maxLoads),("skippedOversize",toJson state.skipped),
    ("chargedBytes",toJson (state.cache.recent.bytes+state.cache.previous.bytes)),
    ("capacityBytes",toJson capacity),("closed",toJson state.closed)]

end Eggshell.Synapses.IndexedBindings.Prepared
