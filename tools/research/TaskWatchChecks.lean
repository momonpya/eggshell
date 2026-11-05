import Main
open Lean Eggshell Eggshell.Plugin
namespace Eggshell.Research.TaskWatchChecks
def check (ok : Bool) (message : String) : IO Unit := unless ok do throw (IO.userError message)
def awaitDone (watched : TaskDeadline.Watched α) (deadline : Nat) : IO Unit := do
  while !(← watched.finished) do
    check ((← IO.monoMsNow) < deadline) "registered completion not observed"
    IO.sleep 1
def run (root : System.FilePath) : IO Unit := do
  check (!(← root.pathExists)) "preserve previous registered completion check"
  IO.FS.createDirAll root
  let started ← IO.monoMsNow
  let gate : IO.Promise Bool ← IO.Promise.new
  let pending ← (List.range 80).toArray.mapM fun index => do
    TaskDeadline.watch (← IO.asTask (do
      let _ ← IO.wait gate.result!
      return index) .dedicated)
  try
    for watched in pending do check (!(← watched.finished)) "unfinished task was marked complete"
  finally gate.resolve true
  for (watched,index) in pending.zipIdx do
    awaitDone watched (started+5000)
    check ((← IO.ofExcept (← watched.wait)) == index) "registered observer changed another task's payload"
    for _ in [:128] do check (← watched.finished) "finished observation regressed or consumed the result"
  let raw ← IO.asTask (pure (none : Option Nat)) .dedicated
  check ((← IO.ofExcept (← IO.wait raw)).isNone) "valid empty result changed before registration"
  let empty ← TaskDeadline.watch raw
  awaitDone empty ((← IO.monoMsNow)+1000)
  check ((← IO.ofExcept (← empty.wait)).isNone) "already-complete empty result became pending"
  let promise : IO.Promise (Option Nat) ← IO.Promise.new
  let response ← TaskDeadline.watch promise.result?
  check (!(← response.finished)) "unresolved reply was marked complete"
  promise.resolve none
  awaitDone response ((← IO.monoMsNow)+1000)
  check ((← response.wait) == some none) "valid empty reply became a dropped owner"
  let dropped ← do
    let owner : IO.Promise (Option Nat) ← IO.Promise.new
    TaskDeadline.watch owner.result?
  awaitDone dropped ((← IO.monoMsNow)+1000)
  check ((← dropped.wait).isNone) "dropped owner became a valid empty reply"
  let failed ← TaskDeadline.watch (← IO.asTask (throw (IO.userError "watched sentinel") : IO Unit) .dedicated)
  awaitDone failed ((← IO.monoMsNow)+1000)
  match ← failed.wait with
  | .ok _ => throw (IO.userError "failed task became successful completion")
  | .error error => check (error.toString.contains "watched sentinel") "completion observer lost original error"
  let retired ← IO.mkRef false
  let peer ← TaskDeadline.watch (← IO.asTask (IO.sleep 40 *> pure (7 : Nat)) .dedicated)
  let cancelled ← TaskDeadline.watch (← IO.asTask (do
    try
      repeat
        TaskDeadline.ensureLive ((← IO.monoMsNow)+1000)
        IO.sleep 2
      pure ()
    finally retired.set true) .dedicated)
  IO.sleep 10
  cancelled.cancel
  awaitDone cancelled ((← IO.monoMsNow)+1000)
  check ((← cancelled.wait).toOption.isNone && (← retired.get)) "cancelled task was not joined with its finalizer"
  awaitDone peer ((← IO.monoMsNow)+1000)
  check ((← IO.ofExcept (← peer.wait)) == 7) "cancelling a task affected its peer"
  IO.FS.writeFile (root/"report.json") (Json.mkObj [("parallelTasks",toJson (80 : Nat)),
    ("monotoneChecksPerTask",toJson (128 : Nat)),("completedBeforeRegistration",toJson true),
    ("validEmptyPreserved",toJson true),("originalErrorPreserved",toJson true),
    ("unresolvedReplyNotComplete",toJson true),("emptyReplyAndDroppedOwnerDistinct",toJson true),
    ("cancelledTaskFinalizerJoined",toJson true),("peerUnaffected",toJson true),
    ("elapsedMs",toJson ((← IO.monoMsNow)-started)),("actualHookCapacityTested",toJson false),("adopted",toJson false)]).pretty
end Eggshell.Research.TaskWatchChecks
