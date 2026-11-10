import tools.research.ParallelProjection
import Lean.Data.Json.FromToJson
open Lean Eggshell Eggshell.Research.ParallelProjection

def check (condition : Bool) (message : String) : IO Unit :=
  unless condition do throw (IO.userError message)

@[noinline] def checksum (input : Array UInt64) : UInt64 :=
  input.foldl (fun prior next => (prior ^^^ next)*1099511628211) 14695981039346656037

@[noinline] def repeatedChecksum (input : Array UInt64) : UInt64 :=
  (List.range 256).foldl (fun prior _ =>
    input.foldl (fun acc next => (acc ^^^ next)*1099511628211) prior) 14695981039346656037

def run (output : System.FilePath) : IO Unit := do
  check (!(← output.pathExists)) "preserve completed lifecycle controls"
  let input ← (← IO.mkRef ((Array.range 100000).map UInt64.ofNat)).get
  let deadline := (← IO.monoMsNow)+30000
  let owner ← IO.getTID
  let borrowed ← IO.mkRef true
  let saved ← IO.mkRef (none : Option (Task (Except IO.Error UInt64)))
  let (value,projected) ← withJob (fun _ => checksum input) deadline fun task => do
    saved.set (some task)
    check ((← IO.getTID) == owner) "IO callback moved onto the CPU pool"
    let fromWorker ← TaskDeadline.wait task deadline
    check (← borrowed.get) "view released before child joined"
    return fromWorker
  check (value == projected && projected == checksum input) "pure projection changed"
  check (← IO.hasFinished (← saved.get).get!) "successful scope left a child"
  borrowed.set false
  let failed ← IO.mkRef false
  try
    discard <| withJob (β := Unit) (fun _ => repeatedChecksum input) deadline fun task => do
      saved.set (some task)
      throw (IO.userError "expected callback failure")
  catch error =>
    failed.set (error.toString.contains "expected callback failure")
  check (← failed.get) "callback error was lost"
  check (← IO.hasFinished (← saved.get).get!) "failed scope left a child"
  let expired ← IO.mkRef false
  let entered ← IO.mkRef false
  try
    discard <| withJob (fun _ => checksum input) 0 fun _ => do
      entered.set true
      return ()
  catch _ => expired.set true
  check ((← expired.get) && !(← entered.get)) "expired job entered its callback"
  entered.set false
  let cancellable ← IO.asTask (withJob (fun _ => repeatedChecksum input) deadline fun task => do
    saved.set (some task)
    entered.set true
    repeat
      if ← IO.checkCanceled then throw (IO.userError "expected owner cancellation")
      IO.sleep 1
    return ()) .dedicated
  -- Wait for ownership to enter the callback before cancelling the parent.
  while !(← entered.get) do
    check ((← IO.monoMsNow) < deadline) "cancellation control did not enter"
    IO.sleep 1
  IO.cancel cancellable
  let cancelled ← IO.wait cancellable
  check (match cancelled with | .error _ => true | .ok _ => false) "owner cancellation did not propagate"
  check (← IO.hasFinished (← saved.get).get!) "cancelled scope left a child"
  IO.FS.writeFile output (Json.mkObj [
    ("pureValueEqual",toJson true),("ioStayedOnOwner",toJson true),
    ("borrowHeldUntilJoin",toJson true),("callbackFailurePreserved",toJson true),
    ("successFailureCancellationChildrenJoined",toJson true),("expiredCallbackRejected",toJson true),
    ("notAHardRealtimeProof",toJson true)]).compress

def main (args : List String) : IO Unit := do
  match args with
  | [output] => run (.mk output)
  | _ => throw (IO.userError "parallel-projection-checks OUTPUT")
