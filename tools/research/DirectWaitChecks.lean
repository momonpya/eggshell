import Eggshell.TaskDeadline
import Lean.Data.Json.FromToJson
open Lean Std Async
namespace Eggshell.Research.DirectWaitChecks
def check (ok : Bool) (message : String) : IO Unit :=
  unless ok do throw (IO.userError message)
def run (root : System.FilePath) : IO Unit := do
  check (!(← root.pathExists)) "preserve earlier direct-wait checks"
  IO.FS.createDirAll root
  let started ← IO.monoMsNow
  for index in [:128] do
    let direct ← TaskDeadline.awaitEvent (pure index)
    let timed ← TaskDeadline.wait (Task.pure (.ok index)) ((← IO.monoMsNow)+1000)
    check (direct == index && timed == index) "early completion changed its value"
  let failed ← try
    let _ ← TaskDeadline.awaitEvent (throw (IO.userError "event-error") : Async Nat)
    pure false
    catch error => pure (error.toString == "event-error")
  check failed "direct event discarded an exception"
  let someValue ← TaskDeadline.awaitEvent (pure (some (0 : Nat)))
  let emptyValue ← TaskDeadline.awaitEvent (pure (none : Option Nat))
  check (someValue == some 0 && emptyValue.isNone) "valid empty event lost its distinction"
  let tasks ← (List.range 80).toArray.mapM fun index => IO.asTask (do
    let deadline := (← IO.monoMsNow)+2000
    let answer ← TaskDeadline.run (do
      let timer ← Selector.sleep (.ofNat (5+index%13))
      Selectable.one #[.case timer (fun _ => pure (index+17))]) deadline
    check (answer == index+17) "native timer returned another request's payload"
    return answer) .dedicated
  let answers ← tasks.mapM fun task => do IO.ofExcept (← IO.wait task)
  check (answers == (List.range 80).toArray.map (·+17)) "parallel event order changed"
  let now ← IO.monoMsNow
  let expired ← try
    let _ ← TaskDeadline.wait (Task.pure (.ok (1 : Nat))) now
    pure false
    catch _ => pure true
  check expired "already complete result bypassed the absolute deadline"
  IO.FS.writeFile (root/"direct-events.json") (Json.mkObj [
    ("earlyCompletions",toJson (128 : Nat)),("parallelNativeTimers",toJson answers.size),
    ("exactPayloadsAndOrder",toJson true),("exceptionsPreserved",toJson true),
    ("validEmptyPreserved",toJson true),("expiredCompletionRefused",toJson true),
    ("elapsedMs",toJson ((← IO.monoMsNow)-started)),("actualHookCapacityTested",toJson false),
    ("answeringModelCalls",toJson (0 : Nat)),("adopted",toJson false)]).pretty
end Eggshell.Research.DirectWaitChecks
