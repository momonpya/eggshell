import Main

open Lean Eggshell
namespace Eggshell.Research.TaskDeadlineChecks

def check (value : Bool) (message : String) : IO Unit :=
  unless value do throw (IO.userError message)

def numericOwners : IO Nat := do
  let some config ← Numerical.defaultConfig? | throw (IO.userError "installed numerical boundary required")
  let backend : Numerical.Backend := {
    modelGate := ← Std.Mutex.new ()
    scoreGate := ← Std.Mutex.new ()
    child := ← IO.mkRef none
    rawChild := ← IO.mkRef none
    rawStarts := ← IO.mkRef 0
    projections := ← ProjectionCache.Cache.make
    pages := ← IO.mkRef {}
    starts := ← IO.mkRef 0
    stopping := ← IO.mkRef false }
  let entered : IO.Promise Unit ← IO.Promise.new
  let release : IO.Promise Unit ← IO.Promise.new
  let held ← IO.asTask (backend.modelGate.atomically do
    entered.resolve ()
    let _ ← IO.wait release.result?
    pure ()) .dedicated
  let _ ← IO.wait entered.result?
  let started ← IO.monoMsNow
  try
    let vector := "000000000000f03f"++String.join (List.replicate 383 "0000000000000000")
    let body := (Json.mkObj [("queries",toJson #[vector]),
      ("blockRows",toJson #[BlockScore.Input.projected vector])]).compress
    let client ← Std.Async.TCP.Socket.Client.mk
    let reply ← backend.scoreBlocks config client body (started+5000)
    let value ← IO.ofExcept (Json.parse reply)
    let scores ← IO.ofExcept (value.getObjValAs? (Array Json) "scores")
    check (scores.size == 1) "independent score kernel lost its row"
    let score ← IO.ofExcept (SearchProvider.number scores[0]!)
    check (score == 1.0) "independent kernel changed the original dot product"
    check ((← backend.starts.get) == 0 && (← backend.rawStarts.get) == 1)
      "cache-only scoring started an embedding model"
    return (← IO.monoMsNow)-started
  finally
    backend.stopping.set true
    release.resolve ()
    let _ ← IO.wait held
    backend.scoreGate.atomically do
      if let some child ← backend.rawChild.get then Numerical.stopRaw child

def run (root : System.FilePath) : IO Unit := do
  check (!(← root.pathExists)) "preserve earlier task-deadline evidence"
  IO.FS.createDir root
  let started ← IO.monoMsNow
  let mut values := #[]
  for i in [:128] do
    let result ← TaskDeadline.wait (Task.pure (.ok i)) ((← IO.monoMsNow)+1000)
    check (result == i) "completion before registration lost its result"
    values := values.push result
  IO.FS.writeFile (root/"early.json") ((Json.mkObj [("elapsedMs",toJson ((← IO.monoMsNow)-started))]).compress)
  let fastPid ← IO.mkRef 0
  SemanticMatcher.withProvider ["/bin/cat"] fun running => do
    fastPid.set running.child.pid.toNat
    for i in [:64] do
      let result ← SemanticMatcher.withResponseDeadline running (pure i)
      check (result == i) "owned provider wait changed a completed result"
  check (!(← Numerical.alive (← fastPid.get))) "successful provider left a live child"
  IO.FS.writeFile (root/"fast-provider.json") ((Json.mkObj [("elapsedMs",toJson ((← IO.monoMsNow)-started))]).compress)
  let timeoutStarted ← IO.monoMsNow
  let timeoutPid ← IO.mkRef 0
  let timedOut ← try
    SemanticMatcher.withProvider ["/bin/cat"] fun running => do
      timeoutPid.set running.child.pid.toNat
      let _ ← SemanticMatcher.withResponseDeadline running running.child.stdout.getLine 50
      pure ()
    pure false
  catch error => pure (error.toString.contains "deadline")
  let timeoutMs := (← IO.monoMsNow)-timeoutStarted
  IO.FS.writeFile (root/"timeout.json") ((Json.mkObj [("timedOut",toJson timedOut),("elapsedMs",toJson timeoutMs)]).compress)
  check (timedOut && timeoutMs < 1000) "pipe deadline did not retire actual provider IO"
  check (!(← Numerical.alive (← timeoutPid.get))) "timed-out provider survived"
  let cancelStarted ← IO.monoMsNow
  let cancelPid ← IO.mkRef 0
  let cancelled ← SemanticMatcher.withProvider ["/bin/cat"] fun running => do
    cancelPid.set running.child.pid.toNat
    let task ← IO.asTask (SemanticMatcher.withResponseDeadline running running.child.stdout.getLine) .dedicated
    IO.sleep 5
    IO.cancel task
    let answer ← TaskDeadline.wait task ((← IO.monoMsNow)+1000)
      |>.toBaseIO
    return match answer with | .error error => error.toString.contains "cancelled" | _ => false
  check (cancelled && (← IO.monoMsNow)-cancelStarted < 1000) "cooperative cancellation retained provider IO"
  check (!(← Numerical.alive (← cancelPid.get))) "cancelled provider survived"
  let cancellationMs := (← IO.monoMsNow)-cancelStarted
  let scoreMs ← numericOwners
  let result := Json.mkObj [("allPassed",toJson true),("earlyCompletions",toJson values.size),
    ("providerReplies",toJson (64 : Nat)),("pipeTimeoutMs",toJson timeoutMs),
    ("cancelledPipe",toJson cancelled),("cancellationMs",toJson cancellationMs),
    ("elapsedMs",toJson ((← IO.monoMsNow)-started)),
    ("scoredWhileModelOwnerHeld",toJson true),("independentScoreMs",toJson scoreMs),
    ("answeringModelCalls",toJson (0 : Nat)),("adopted",toJson false)]
  IO.FS.writeFile (root/"report.json") (result.pretty++"\n")
  IO.println result.compress

end Eggshell.Research.TaskDeadlineChecks
