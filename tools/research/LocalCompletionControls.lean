module
public import tools.research.LocalCompletion
public import Eggshell.TaskDeadline
public import Lean
@[expose] public section
namespace Eggshell.Research.LocalCompletionControls
open Lean
def check (ok : Bool) (message : String) : IO Unit := unless ok do throw (IO.userError message)
run_elab do
  let environment ← Lean.getEnv
  for name in [``LocalCompletion.awaitTask,``LocalCompletion.Mailbox.read] do
    let some body := (environment.find? name).bind (·.value?) | throwError "Missing local completion owner"
    for forbidden in [``IO.wait,``IO.waitAny,``IO.hasFinished,``IO.sleep] do
      if body.getUsedConstants.contains forbidden then throwError "Local completion re-enters global task waiting"
#check LocalCompletion.State.first_reply
#check LocalCompletion.State.ready_unchanged
#check LocalCompletion.State.closed_unchanged

def waitUntil (condition : IO Bool) : IO Unit := do
  let deadline := (← IO.monoMsNow)+3000
  repeat
    if ← condition then return
    check ((← IO.monoMsNow) < deadline) "private completion barrier expired"
    IO.sleep 1

def run : IO Json := do
  let replies ← (Array.range 80).mapM fun _ => IO.Promise.new (α := Except IO.Error Nat)
  let parked ← (Array.range 80).mapM fun _ => IO.mkRef false
  let wakes ← (Array.range 80).mapM fun _ => IO.mkRef (0 : Nat)
  let tasks ← (replies.zip (parked.zip wakes)).mapM fun (reply,(parked,wakes)) => IO.asTask
    (LocalCompletion.awaitTask reply.result! (parked.set true) (wakes.modify (·+1))) .dedicated
  try
    waitUntil (parked.allM fun value => do return ← value.get)
    -- Each resolution invokes the runtime's global task-completion notify.
    -- None of these promises belongs to one of the eighty parked owners.
    for index in [:1000] do
      let unrelated ← IO.Promise.new (α := Nat)
      unrelated.resolve index
    IO.sleep 30
    let unrelatedWakes ← wakes.mapM (·.get)
    check (unrelatedWakes.all (· == 0)) "unrelated task completion woke private owners"
    let some selected := replies[17]? | throw (IO.userError "missing selected private owner")
    selected.resolve (.ok 17)
    waitUntil (do return ← IO.hasFinished tasks[17]!)
    let first ← wakes.mapM (·.get)
    check ((first.zipIdx.all fun (count,index) => if index == 17 then count == 1 else count == 0))
      "one completion woke a different owner or its notification was lost"
    for (reply,index) in replies.zipIdx do reply.resolve (.ok index)
    let results ← tasks.mapM fun task => do IO.ofExcept (← IO.wait task)
    check (results == Array.range 80) "private completion changed reply identity"
    let ready ← IO.Promise.new (α := Except IO.Error Nat)
    ready.resolve (.ok 91)
    check ((← LocalCompletion.awaitTask ready.result!) == 91) "completion before registration was lost"
    let failed ← IO.Promise.new (α := Except IO.Error Nat)
    failed.resolve (.error (IO.userError "original local error"))
    let preserved ← try
      discard <| LocalCompletion.awaitTask failed.result!
      pure false
    catch error => pure (error.toString.contains "original local error")
    check preserved "original source failure was changed"
    let box ← LocalCompletion.Mailbox.make (α := Nat)
    box.close
    box.publish (.ok 99)
    check (!(← box.read).isOk) "late callback reopened a closed owner"
    let pending ← IO.Promise.new (α := Except IO.Error Unit)
    let started ← IO.monoMsNow
    let expired ← try
      discard <| Eggshell.TaskDeadline.wait pending.result! (started+40)
      pure false
    catch error => pure (error.toString.contains "deadline")
    pending.resolve (.ok ())
    check (expired && (← IO.monoMsNow)-started < 1000) "async bridge lost its absolute deadline"
    let pending ← IO.Promise.new (α := Except IO.Error Unit)
    let task ← IO.asTask (Eggshell.TaskDeadline.wait pending.result! ((← IO.monoMsNow)+1000)) .dedicated
    IO.sleep 5
    let cancelledAt ← IO.monoMsNow
    IO.cancel task
    let cancelled ← IO.wait task
    pending.resolve (.ok ())
    check (!cancelled.isOk && (← IO.monoMsNow)-cancelledAt < 1000) "async bridge lost cooperative cancellation"
    return Json.mkObj [("privateOwners",toJson (80 : Nat)),("unrelatedCompletions",toJson (1000 : Nat)),
      ("wakesFromUnrelatedCompletions",toJson unrelatedWakes),("firstNotificationWokeOnlyItsOwner",toJson true),
      ("allRepliesPreserved",toJson true),("preCompletedReplyPreserved",toJson true),
      ("originalErrorPreserved",toJson true),("closedOwnerRejectsLateReply",toJson true)]
  finally
    for (reply,index) in replies.zipIdx do reply.resolve (.ok index)
    for task in tasks do discard <| IO.wait task
end Eggshell.Research.LocalCompletionControls
