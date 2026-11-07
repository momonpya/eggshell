module
public import Lean.Data.Json.FromToJson
@[expose] public section
namespace Eggshell.Research.AllocationMeasure
open Lean

/-- The runtime counts small allocations on this thread, not bytes, live
objects, RSS or work delegated to another thread. Bookkeeping is included. -/
@[noinline,nospecialize] def run (input : α) (produce : α → β) (inspect : β → Json) : IO Json := do
  let argument ← IO.mkRef input
  let sink ← IO.mkRef (none : Option β)
  let began ← IO.monoNanosNow
  let before ← IO.getNumHeartbeats
  let value ← argument.get
  sink.set (some (produce value))
  let result ← sink.get
  let after ← IO.getNumHeartbeats
  let ended ← IO.monoNanosNow
  let some result := result | throw (IO.userError "allocation measurement produced no value")
  return Json.mkObj [("elapsedUs",toJson ((ended-began)/1000)),
    ("before",toJson before),("after",toJson after),("monotonic",toJson (decide (before ≤ after))),
    ("smallAllocations",toJson (after-before)),("summary",inspect result)]

def difference (before after : Nat) : Json := Json.mkObj [
  ("before",toJson before),("after",toJson after),("monotonic",toJson (decide (before ≤ after))),
  ("smallAllocations",toJson (after-before))]
end Eggshell.Research.AllocationMeasure
