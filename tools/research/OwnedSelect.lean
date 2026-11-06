module
public import Std.Async.Select
import all Std.Async.Select
@[expose] public section
namespace Eggshell.Research.OwnedSelect
open Std Async

/-- A source failure is an ordinary winning value until the multiplexer has
unregistered every event source. Only then is the original error rethrown. -/
def encode (result : Except IO.Error α) : Except IO.Error (Except IO.Error α) := .ok result
def decode (result : Except IO.Error (Except IO.Error α)) : Except IO.Error α := result >>= id
theorem error_is_value (result : Except IO.Error α) : (encode result).isOk = true := rfl
theorem result_preserved (result : Except IO.Error α) : decode (encode result) = result := rfl

/-- Research attribution only; it is not read by scheduling or admission. -/
initialize forwardedErrors : IO.Ref Nat ← IO.mkRef 0

def attempt (selector : Selector α) : Selector (Except IO.Error α) := {
  tryFn := do
    try
      return (← selector.tryFn).map Except.ok
    catch error => return some (.error error)
  registerFn := fun waiter => do
    let reply ← IO.Promise.new
    discard <| IO.mapTask (t := reply.result?) (sync := true) fun result => do
      if let some result := result then
        if !result.isOk then forwardedErrors.modify (·+1)
        waiter.promise.resolve (encode result)
    selector.registerFn (waiter.withPromise reply)
  unregisterFn := selector.unregisterFn }

/-- The bridge shares the source's existing race arbitration. It introduces
no independent winner, mutex or dedicated worker. -/
private theorem same_race_impl (waiter : Waiter α) (reply : IO.Promise (Except IO.Error β)) :
    (waiter.withPromise reply).checkFinished (m := BaseIO) = waiter.checkFinished (m := BaseIO) := rfl

theorem same_race (waiter : Waiter α) (reply : IO.Promise (Except IO.Error β)) :
    (waiter.withPromise reply).checkFinished (m := BaseIO) = waiter.checkFinished (m := BaseIO) :=
  same_race_impl waiter reply

def normalized (selectable : Selectable α) : Selectable α :=
  match selectable with
  | .case selector continuation => .case (attempt selector) fun result => do
      continuation (← IO.ofExcept result)

def one (selectables : Array (Selectable α)) : Async α :=
  Selectable.one (selectables.map normalized)
end Eggshell.Research.OwnedSelect
