import tools.research.OwnedSelect
import Lean.Data.Json.FromToJson
open Lean Std Async
namespace Eggshell.Research.SelectorErrorChecks
def check (ok : Bool) (message : String) : IO Unit := unless ok do throw (IO.userError message)
def trial (fixed failure : Bool) : IO Json := do
  let first ← IO.mkRef (none : Option (Waiter Unit))
  let second ← IO.mkRef (none : Option (Waiter Unit))
  let cleanups ← IO.mkRef (0 : Nat)
  let make := fun (saved : IO.Ref (Option (Waiter Unit))) => ({
    tryFn := pure none
    registerFn := fun waiter => saved.set (some waiter)
    unregisterFn := do saved.set none; cleanups.modify (·+1) } : Selector Unit)
  let payload := ByteArray.mk (Array.replicate 65536 (37 : UInt8))
  let continuation := fun (_ : Unit) => do
    let retained ← IO.mkRef payload
    return (← retained.get).size
  let selectors := #[Selectable.case (make first) continuation,Selectable.case (make second) continuation]
  let action := if fixed then OwnedSelect.one selectors else Selectable.one selectors
  let task ← action.toIO
  try
    let some waiter ← first.get | throw (IO.userError "first source not registered")
    check (← second.get).isSome "second source not registered"
    waiter.race (pure ()) fun promise =>
      promise.resolve (if failure then .error (IO.userError "owned selector failure") else .ok ())
    let deadline := (← IO.monoMsNow)+2000
    while !(← IO.hasFinished task) do
      check ((← IO.monoMsNow) < deadline) "selector completion did not arrive"
      IO.sleep 1
    let result ← IO.wait task
    let retained := (if (← first.get).isSome then 1 else 0)+(if (← second.get).isSome then 1 else 0)
    let count ← cleanups.get
    check (match result with
      | .error error => failure && error.toString.contains "owned selector failure"
      | .ok size => !failure && size == 65536) "selection changed its original result/error"
    check (if failure && !fixed then retained == 2 && count == 0 else retained == 0 && count == 2)
      "selector cleanup differs from the expected control"
    return Json.mkObj [("fixed",toJson fixed),("failure",toJson failure),
      ("registeredSources",toJson (2 : Nat)),("cleanupCalls",toJson count),("retainedWaiters",toJson retained),
      ("originalResultPreserved",toJson true)]
  finally
    -- Break the demonstrated parent cycle explicitly; do not leave test data
    -- or an unresolved losing source behind in this process.
    first.set none
    second.set none
    if !(← IO.hasFinished task) then IO.cancel task
def main (args : List String) : IO Unit := do
  let [destination] := args | throw (IO.userError "fresh selector evidence file required")
  let path : System.FilePath := .mk destination
  check (!(← path.pathExists)) "preserve selector controls"
  let mut rows := #[]
  for (fixed,failure) in [(false,false),(false,true),(true,false),(true,true)] do
    rows := rows.push (← trial fixed failure)
  let result := Json.mkObj [("rows",toJson rows),("parentErrorCleanupBugReproduced",toJson true),
    ("fixedErrorAndSuccessReleaseAllSources",toJson true),("modelCalls",toJson (0 : Nat)),("adopted",toJson false)]
  IO.FS.writeFile path result.compress
  IO.println result.compress
end Eggshell.Research.SelectorErrorChecks
def main := Eggshell.Research.SelectorErrorChecks.main
