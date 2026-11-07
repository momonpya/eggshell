module
public import Std.Internal.UV.Timer
@[expose] public section
namespace Eggshell.Research.EventScope

/-- Cancellation is an owned completion signal, not an opaque condition that
must be polled. An owner signals cancellation before joining its operation.
Signals may be shared by arbitrarily many waiters; waiting adds no listener
continuations to those long-lived signals. -/
structure Scope where
  signals : Array (Task Unit) := #[]
  deadline : Option Nat := none

def permitted (cancelled : Bool) (now : Nat) (deadline : Option Nat) : Bool :=
  !cancelled && deadline.all (fun limit => now < limit)

theorem cancelled_refused (now : Nat) (deadline : Option Nat) :
    permitted true now deadline = false := by simp [permitted]

theorem expired_refused (now deadline : Nat) (expired : deadline ≤ now) :
    permitted false now (some deadline) = false := by
  simp [permitted,Nat.not_lt_of_ge expired]

def Scope.live (scope : Scope) : IO Bool := do
  let cancelled ← scope.signals.anyM (fun signal => do return ← IO.hasFinished signal)
  return permitted cancelled (← IO.monoMsNow) scope.deadline

def Scope.ensure (scope : Scope) : IO Unit := do
  unless (← scope.live) && !(← IO.checkCanceled) do
    throw (IO.userError "owned event scope expired or cancelled")

/-- The dedicated IO owner parks on native task readiness once. There is no
async selector loop, periodic timer or pool worker continuation. Only the
short-lived result task is mapped; shared cancellation signals are borrowed
directly. A single optional deadline timer is cancelled on every exit. -/
def Scope.wait (scope : Scope) (ready : Task (Except IO.Error α)) : IO α := do
  scope.ensure
  let finish : IO α := do
    scope.ensure
    unless ← IO.hasFinished ready do
      throw (IO.userError "owned event wait interrupted before completion")
    IO.ofExcept (← IO.wait ready)
  if ← IO.hasFinished ready then return ← finish
  let completed := ready.map (sync := true) (fun _ => ())
  let waiters := completed :: scope.signals.toList
  match scope.deadline with
  | none =>
      discard <| IO.waitAny waiters
      finish
  | some deadline =>
      let now ← IO.monoMsNow
      unless now < deadline do throw (IO.userError "owned event scope expired")
      let timer ← Std.Internal.UV.Timer.mk (deadline-now).toUInt64 false
      try
        let elapsed ← timer.next
        discard <| IO.waitAny (elapsed.resultD () :: waiters)
        finish
      finally timer.cancel

end Eggshell.Research.EventScope
