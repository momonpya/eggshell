module
public import Eggshell.SynapseJournal
public import Std.Sync.Mutex
@[expose] public section

namespace Eggshell.Synapses.ReplayPreparation
open Lean DB

structure Slot where
  view : String
  cursor : Journal.ReplayCursor

structure State where
  slots : Array Slot := #[]
  created : Nat := 0
  resumed : Nat := 0
  evicted : Nat := 0

/-- One user-owned index worker retains at most four private continuations.
The namespace is fixed by its private data root. No private event payload is
written into the shared project DB or sent to its publication service. -/
structure Pool where
  privateRoot : System.FilePath
  gate : Std.Mutex Unit
  state : IO.Ref State
  capacity : Nat := 4

def new : IO Pool := return {
  privateRoot := ← Paths.dataRoot,gate := ← Std.Mutex.new (),state := ← IO.mkRef {slots := #[]}}

def Pool.run (pool : Pool) : Journal.ReplayRunner := fun source entries index cache deadline =>
  pool.gate.atomically do
    unless (← Paths.dataRoot).normalize == pool.privateRoot.normalize do
      throw (IO.userError "private replay cursor crossed its data root")
    unless index.manifest.scope == .shared && index.manifest.source.identity == source.head.identity &&
        index.manifest.source.authority == source.head.authority do
      throw (IO.userError "private replay locator crossed its source scope")
    let view ← UsageCache.readViewIdentity index
    let state ← pool.state.get
    let existing := state.slots.findIdx? fun slot =>
      slot.cursor.source.directory == source.directory && slot.cursor.source.head == source.head &&
        slot.view == view && slot.cursor.values == entries
    let cursor ← match existing with
      | some ordinal => do
        let some slot := state.slots[ordinal]? | throw (IO.userError "private cursor slot disappeared")
        pool.state.set {state with
          resumed := state.resumed+1
          slots := (state.slots.extract 0 ordinal ++ state.slots.extract (ordinal+1) state.slots.size).push slot}
        pure slot.cursor
      | none => do
        let cursor ← Journal.beginReplay source entries (some index) (some cache)
        if pool.capacity > 0 then
          let slots := if state.slots.size < pool.capacity then state.slots else
            state.slots.extract 1 state.slots.size
          pool.state.set {state with
            slots := slots.push ⟨view,cursor⟩,created := state.created+1
            evicted := state.evicted+(if state.slots.size ≥ pool.capacity then 1 else 0)}
        pure cursor
    Journal.resumeReplay cursor deadline

def Pool.stats (pool : Pool) : IO Json := pool.gate.atomically do
  let state ← pool.state.get
  return Json.mkObj [("slots",toJson state.slots.size),("capacity",toJson pool.capacity),
    ("created",toJson state.created),("resumed",toJson state.resumed),("evicted",toJson state.evicted)]

end Eggshell.Synapses.ReplayPreparation
