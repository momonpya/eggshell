module
public import Eggshell.CanonicalSourcePrepared
public import Std.Sync.Mutex
@[expose] public section

namespace Eggshell.Synapses.SharedReadViews
open Lean DB

def capacity : Nat := 128*1024*1024
def maxActive : Nat := 8
def maxQueued : Nat := 128
def charge (wireBytes : Nat) : Nat := 65536+32*wireBytes

structure Source where
  scope : String
  source : PageMap.Head
  loaded : CanonicalSource.Shared.Loaded
  owners : Std.HashSet String

/-- One reservation owns the complete set of pinned project views. It never
holds a first project's admission slot while waiting for a second one. -/
structure View where
  scope : String
  sources : Array Source
  deadline : Nat
  charge : Nat
  borrowers : Nat := 0
  released : Bool := false

structure State where
  active : Std.HashMap String View := {}
  waiting : List Nat := []
  next : Nat := 0
  closed : Bool := false
  admitted : Nat := 0
  released : Nat := 0
  expired : Nat := 0
  peak : Nat := 0

def State.used (state : State) : Nat := state.active.fold (fun bytes _ view => bytes+view.charge) 0

/-- Expiration forbids new work, but cannot pretend that a still-running
borrower has released its memory. Its reservation ends in the finalizer. -/
def State.reap (state : State) (now : Nat) : State :=
  let expired := state.active.fold (fun total _ view => total+
    if !view.released && view.deadline ≤ now && view.borrowers == 0 then 1 else 0) 0
  let active := state.active.filter fun _ view =>
    0 < view.borrowers || (!view.released && now < view.deadline)
  {state with active,expired := state.expired+expired}

structure Pool where
  state : Std.Mutex State

def Pool.new : IO Pool := return ⟨← Std.Mutex.new {}⟩

def Pool.reserve (pool : Pool) (scope : String) (wireBytes deadline : Nat) : IO String := do
  let amount := charge wireBytes
  unless amount ≤ capacity do throw (IO.userError "original view exceeds its query budget")
  let ticket ← pool.state.atomically do
    let state ← get
    unless !state.closed && state.waiting.length < maxQueued do
      throw (IO.userError "original view admission is stopped or full")
    set {state with waiting := state.waiting ++ [state.next],next := state.next+1}
    return state.next
  try
    repeat
      let now ← IO.monoMsNow
      unless now < deadline do throw (IO.userError "original view admission expired")
      let token ← pool.state.atomically do
        let state := (← get).reap now
        unless !state.closed do throw (IO.userError "original view admission stopped")
        if state.waiting.head? == some ticket && state.active.size < maxActive && state.used+amount ≤ capacity then
          let token := Blake3.hex (← IO.getRandomBytes 32)
          unless !state.active.contains token do throw (IO.userError "original view token collision")
          let view : View := {scope,sources := #[],deadline,charge := amount}
          set {state with
            active := state.active.insert token view,waiting := state.waiting.drop 1,
            admitted := state.admitted+1,peak := max state.peak (state.used+amount)}
          return some token
        set state
        return none
      if let some token := token then return token
      IO.sleep 2
    throw (IO.userError "unreachable original view admission")
  finally pool.state.atomically (modify fun state => {state with waiting := state.waiting.filter (· != ticket)})

def Pool.attach (pool : Pool) (token scope : String) (sources : Array Source) : IO Unit := do
  let now ← IO.monoMsNow
  pool.state.atomically do
    let state := (← get).reap now
    let some view := state.active[token]? | throw (IO.userError "original view expired before binding")
    unless !state.closed && !view.released && now < view.deadline && view.scope == scope &&
        view.sources.isEmpty && !sources.isEmpty do throw (IO.userError "original view binding changed its scope")
    set {state with active := state.active.insert token {view with sources}}

def Pool.acquireMany (pool : Pool) (scope : String) (sources : Array Source)
    (wireBytes deadline : Nat) : IO String := do
  let token ← pool.reserve scope wireBytes deadline
  try
    pool.attach token scope sources
    return token
  catch error =>
    pool.state.atomically (modify fun state => {state with active := state.active.erase token})
    throw error

def Pool.acquire (pool : Pool) (scope : String) (source : PageMap.Head)
    (loaded : CanonicalSource.Shared.Loaded) (owners : Array String) (wireBytes deadline : Nat) : IO String :=
  pool.acquireMany scope #[⟨scope,source,loaded,Std.HashSet.ofArray owners⟩] wireBytes deadline

def Pool.validateView (pool : Pool) (token scope : String) : IO View := do
  let now ← IO.monoMsNow
  pool.state.atomically do
    let state := (← get).reap now
    set state
    let some view := state.active[token]? | throw (IO.userError "original view expired or released")
    unless !state.closed && !view.released && now < view.deadline && view.scope == scope && !view.sources.isEmpty do
      throw (IO.userError "original view changed its read domain")
    return view

def Pool.validate (pool : Pool) (token scope : String) (source : PageMap.Head)
    (owners : Array String) : IO (CanonicalSource.Shared.Loaded × Nat) := do
  let view ← pool.validateView token scope
  let some entry := view.sources.find? (fun entry => entry.scope == scope && entry.source == source) |
    throw (IO.userError "original view has no requested source")
  unless owners.all entry.owners.contains do throw (IO.userError "original view has no requested owner")
  return (entry.loaded,view.deadline)

def Pool.withView (pool : Pool) (token scope : String) (use : View → IO α) : IO α := do
  let now ← IO.monoMsNow
  let view ← pool.state.atomically do
    let state := (← get).reap now
    let some view := state.active[token]? | throw (IO.userError "original view expired or released")
    unless !state.closed && !view.released && now < view.deadline && view.scope == scope && !view.sources.isEmpty do
      throw (IO.userError "original view changed its read domain")
    set {state with active := state.active.insert token {view with borrowers := view.borrowers+1}}
    return view
  try use view
  finally
    let now ← IO.monoMsNow
    pool.state.atomically do
      let state ← get
      let some view := state.active[token]? | return
      set ({state with active := state.active.insert token {view with borrowers := view.borrowers-1}}.reap now)

def Pool.release (pool : Pool) (token scope : String) : IO Unit := pool.state.atomically do
  let state ← get
  let some view := state.active[token]? | return
  unless view.scope == scope do throw (IO.userError "original view release crossed read scope")
  if view.released then return
  let active := if view.borrowers == 0 then state.active.erase token else
    state.active.insert token {view with released := true}
  set {state with active,released := state.released+1}

def Pool.close (pool : Pool) : IO Unit := pool.state.atomically do
  let state ← get
  let active := state.active.filterMap fun _ view =>
    if view.borrowers == 0 then none else some {view with released := true}
  set {state with closed := true,active,waiting := []}

def Pool.stats (pool : Pool) : IO Json := pool.state.atomically do
  let state ← get
  return Json.mkObj [("active",toJson state.active.size),("queued",toJson state.waiting.length),
    ("chargedBytes",toJson state.used),("capacity",toJson capacity),("peakChargedBytes",toJson state.peak),
    ("admitted",toJson state.admitted),("released",toJson state.released),("expired",toJson state.expired),
    ("closed",toJson state.closed)]

end Eggshell.Synapses.SharedReadViews
