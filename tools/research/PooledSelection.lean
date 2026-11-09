module
public import Eggshell.Handoff
public import Eggshell.TaskDeadline
@[expose] public section
namespace Eggshell.Research.PooledSelection
open Lean Eggshell.Plugin

/-- A request owns immutable inputs. Neither scheduling nor another request
can change its source domain, costs, cues, authority or selection function. -/
structure Frozen where
  query : SharedRangeAdapter.ServiceQuery
  units : Array SharedRangeAdapter.ServiceUnit
  pieces : List SharedRangeAdapter.CuePiece
  source : Synapses.PreparedSourceView.Domain

def Frozen.value (input : Frozen) : Option SharedRangeAdapter.ServiceChoice :=
  SharedRangeAdapter.selectView input.query input.units input.pieces input.source

theorem Frozen.value_exact (input : Frozen) : input.value =
    SharedRangeAdapter.selectView input.query input.units input.pieces input.source := rfl

/-- IO ownership/cancellation stays with the requester and its existing view
lease. Only the pure CPU phase uses Lean's ordinary worker pool. There is no
application queue, shared selector state, added cache or reader mutex here. -/
def run (input : Frozen) (deadline : Nat) : IO (Option SharedRangeAdapter.ServiceChoice) := do
  TaskDeadline.ensureLive deadline
  let submitted ← IO.monoNanosNow
  let ownerThread ← IO.getTID
  let trace := (← IO.getEnv "EGGSHELL_TRACE_SERVICE_PROFILE") == some "1"
  let task ← IO.asTask (do
    TaskDeadline.ensureLive deadline
    let started ← IO.monoNanosNow
    let thread ← IO.getTID
    let result ← (← IO.mkRef input.value).get
    let finished ← IO.monoNanosNow
    if trace then
      Receipt.observe (some (← Receipt.fresh)) "pooled-selection" (Json.mkObj [
        ("pid",toJson (← IO.Process.getPID).toNat),
        ("ownerThread",toJson ownerThread.toNat),("cpuThread",toJson thread.toNat),
        ("submittedNs",toJson submitted),("startedNs",toJson started),("finishedNs",toJson finished),
        ("queueUs",toJson ((started-submitted)/1000)),("workUs",toJson ((finished-started)/1000))])
    return result) .default
  try
    TaskDeadline.wait task deadline
  finally
    unless ← IO.hasFinished task do IO.cancel task
    discard <| IO.wait task

#print axioms Frozen.value_exact
end Eggshell.Research.PooledSelection
