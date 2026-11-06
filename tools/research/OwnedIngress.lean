module
public import Eggshell.DaemonWire
public import Init.Data.ByteArray.Lemmas
@[expose] public section
namespace Eggshell.Research.OwnedIngress
open Std Async Eggshell.Plugin

def live (stopping : IO.Ref Bool) (deadline : Nat) : IO Unit := do
  Eggshell.TaskDeadline.ensureLive deadline
  if ← stopping.get then throw (IO.userError "publisher frame expired")

/-- A handler already owns this connection and its dedicated task. Start one
native receive per fragment; retain it until completion or cancel/join. No
readiness callback performs a blocking receive on a second worker. -/
def receive (stopping : IO.Ref Bool) (client : TCP.Socket.Client) (remaining deadline : Nat)
    (received : ByteArray := ByteArray.empty) : IO ByteArray := do
  if remaining == 0 then return received
  live stopping deadline
  let chunk ← Daemon.withOwnedReceive client remaining fun reading => do
    repeat
      live stopping deadline
      if ← IO.hasFinished reading then return ← IO.ofExcept (← IO.wait reading)
      IO.sleep (min 5 (deadline-(← IO.monoMsNow))).toUInt32
    throw (IO.userError "unreachable publisher receive")
  let some bytes := chunk | throw (IO.userError "publisher peer closed an incomplete frame")
  if _valid : 0 < bytes.size ∧ bytes.size ≤ remaining then
    receive stopping client (remaining-bytes.size) deadline (received.append bytes)
  else throw (IO.userError "publisher received an empty or oversized frame")
termination_by remaining
decreasing_by exact Daemon.received_chunk_decreases remaining bytes.size _valid

theorem progress (remaining : Nat) (bytes : ByteArray)
    (valid : 0 < bytes.size ∧ bytes.size ≤ remaining) : remaining-bytes.size < remaining :=
  Daemon.received_chunk_decreases remaining bytes.size valid

theorem extent_preserved (received bytes : ByteArray) (remaining total : Nat)
    (before : received.size+remaining = total) (bounded : bytes.size ≤ remaining) :
    (received.append bytes).size+(remaining-bytes.size) = total := by
  rw [ByteArray.append_eq,ByteArray.size_append]
  omega
end Eggshell.Research.OwnedIngress
