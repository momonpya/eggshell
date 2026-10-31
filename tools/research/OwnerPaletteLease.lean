module
public import Eggshell.CanonicalSourcePrepared
public import Std.Sync.Mutex
@[expose] public section

namespace Eggshell.Synapses.OwnerPaletteLease
open Lean DB

/-- These reservations cover in-flight query metadata, not another copy of
the owner cache. Pending clients retain only their compact request. -/
def capacity : Nat := 128*1024*1024
def maxActive : Nat := 8
def maxQueued : Nat := 128
def charge (wireBytes : Nat) : Nat := 65536+32*wireBytes

structure View where
  scope : String
  source : PageMap.Head
  loaded : CanonicalSource.Shared.Loaded
  owners : Std.HashSet String
  deadline : Nat
  charge : Nat

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

def State.reap (state : State) (now : Nat) : State :=
  let active := state.active.filter fun _ view => now < view.deadline
  {state with active,expired := state.expired+(state.active.size-active.size)}

structure Pool where
  state : Std.Mutex State

def Pool.new : IO Pool := return ⟨← Std.Mutex.new {}⟩

def Pool.acquire (pool : Pool) (scope : String) (source : PageMap.Head)
    (loaded : CanonicalSource.Shared.Loaded) (owners : Array String)
    (wireBytes deadline : Nat) : IO String := do
  let amount := charge wireBytes
  unless amount ≤ capacity do throw (IO.userError "original palette exceeds query metadata budget")
  let ticket ← pool.state.atomically do
    let state ← get
    unless !state.closed && state.waiting.length < maxQueued do
      throw (IO.userError "original palette admission is stopped or full")
    set {state with waiting := state.waiting ++ [state.next],next := state.next+1}
    return state.next
  try
    repeat
      let now ← IO.monoMsNow
      unless now < deadline do throw (IO.userError "original palette admission expired")
      let token ← pool.state.atomically do
        let state := (← get).reap now
        unless !state.closed do throw (IO.userError "original palette admission stopped")
        if state.waiting.head? == some ticket && state.active.size < maxActive && state.used+amount ≤ capacity then
          let token := Blake3.hex (← IO.getRandomBytes 32)
          unless !state.active.contains token do throw (IO.userError "original palette token collision")
          let view : View := {scope,source,loaded,owners := Std.HashSet.ofArray owners,deadline,charge := amount}
          let next := {state with
            active := state.active.insert token view,waiting := state.waiting.drop 1,
            admitted := state.admitted+1,peak := max state.peak (state.used+amount)}
          set next
          return some token
        set state
        return none
      if let some token := token then return token
      IO.sleep 2
    throw (IO.userError "unreachable original palette admission")
  finally pool.state.atomically (modify fun state => {state with waiting := state.waiting.filter (· != ticket)})

def Pool.validate (pool : Pool) (token scope : String) (source : PageMap.Head)
    (owners : Array String) : IO (CanonicalSource.Shared.Loaded × Nat) := do
  let now ← IO.monoMsNow
  pool.state.atomically do
    let state := (← get).reap now
    set state
    let some view := state.active[token]? | throw (IO.userError "original palette lease expired or released")
    unless !state.closed && view.scope == scope && view.source == source && owners.all view.owners.contains do
      throw (IO.userError "original palette lease changed its read domain")
    return (view.loaded,view.deadline)

def Pool.release (pool : Pool) (token scope : String) : IO Unit := pool.state.atomically do
  let state ← get
  let some view := state.active[token]? | return
  unless view.scope == scope do throw (IO.userError "original palette release crossed read scope")
  set {state with active := state.active.erase token,released := state.released+1}

def Pool.close (pool : Pool) : IO Unit := pool.state.atomically do
  modify fun state => {state with closed := true,active := {},waiting := []}

def Pool.stats (pool : Pool) : IO Json := pool.state.atomically do
  let state ← get
  return Json.mkObj [("active",toJson state.active.size),("queued",toJson state.waiting.length),
    ("chargedBytes",toJson state.used),("capacity",toJson capacity),("peakChargedBytes",toJson state.peak),
    ("admitted",toJson state.admitted),("released",toJson state.released),("expired",toJson state.expired),
    ("closed",toJson state.closed)]

end Eggshell.Synapses.OwnerPaletteLease
