module
public import Eggshell.Receipt
public import Lean.Data.Json.FromToJson
@[expose] public section

namespace Eggshell.DiscoveryCounters
open Lean

structure Count where
  calls : Nat := 0
  nanos : Nat := 0
  deriving ToJson

structure Recorder where
  receipt : Option String
  counts : IO.Ref (Std.HashMap String Count)
  failed : IO.Ref Bool

def create (receipt : Option String) : IO Recorder := do
  return ⟨receipt,← IO.mkRef {},← IO.mkRef false⟩

/-- Counts contain durations and call counts only, never source/query data.
The result and exception of the observed action are returned unchanged. -/
def timed (recorder : Recorder) (name : String) (action : IO α) : IO α := do
  if recorder.receipt.isNone then return ← action
  let started ← IO.monoNanosNow
  try action
  finally
    try
      let elapsed := (← IO.monoNanosNow)-started
      recorder.counts.modify fun counts =>
        let previous := counts.getD name {}
        counts.insert name ⟨previous.calls+1,previous.nanos+elapsed⟩
    catch _ => recorder.failed.set true

def emit (recorder : Recorder) (outcomes : Nat) : IO Unit := do
  if recorder.receipt.isNone then return
  let values := (← recorder.counts.get).toList.mergeSort (fun a b => a.1 ≤ b.1)
  Receipt.observe recorder.receipt s!"discovery-counters-{← IO.monoNanosNow}" (Json.mkObj [
    ("complete",toJson (!(← recorder.failed.get))),
    ("scope",toJson "overlapping counters; do not sum admission with nested frequency IO"),
    ("graphOutcomes",toJson outcomes),
    ("counters",Json.mkObj (values.map fun (name,value) => (name,toJson value)))])

end Eggshell.DiscoveryCounters
