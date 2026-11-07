module
public import Eggshell.TaskDeadline
public import Std.Sync.CancellationToken
public import tools.research.LocalCompletion
@[expose] public section
namespace Eggshell.Research.EventScope

/-- Cancellation is an owned completion signal, not an opaque condition that
must be polled. An owner signals cancellation before joining its operation.
Cancellation subscriptions are removed when readiness, cancellation or the
absolute deadline wins, including when a different source fails. -/
structure Scope where
  signals : Array Std.CancellationToken := #[]
  deadline : Option Nat := none

def permitted (cancelled : Bool) (now : Nat) (deadline : Option Nat) : Bool :=
  !cancelled && deadline.all (fun limit => now < limit)

theorem cancelled_refused (now : Nat) (deadline : Option Nat) :
    permitted true now deadline = false := by simp [permitted]

theorem expired_refused (now deadline : Nat) (expired : deadline ≤ now) :
    permitted false now (some deadline) = false := by
  simp [permitted,Nat.not_lt_of_ge expired]

def Scope.live (scope : Scope) : IO Bool := do
  let cancelled ← scope.signals.anyM (fun signal => do return ← signal.isCancelled)
  return permitted cancelled (← IO.monoMsNow) scope.deadline

def Scope.ensure (scope : Scope) : IO Unit := do
  unless (← scope.live) && !(← IO.checkCanceled) do
    throw (IO.userError "owned event scope expired or cancelled")

/-- Register a single event race, then park on this owner's private mailbox.
Event continuations unregister every losing source before publishing the
reply. No periodic timer, global task wait or polling is introduced. -/
def Scope.wait (scope : Scope) (ready : Task (Except IO.Error α)) : IO α := do
  scope.ensure
  let event ← Eggshell.TaskDeadline.event ready
  let action : Std.Async.Async α := do
    let cancelling : Array (Std.Async.Selectable α) := scope.signals.map fun signal =>
      .case signal.selector (fun _ => throw (IO.userError "owned event scope cancelled"))
    let sources := #[Std.Async.Selectable.case event pure] ++ cancelling
    match scope.deadline with
    | none => Eggshell.Research.OwnedSelect.one sources
    | some deadline => do
      let now ← IO.monoMsNow
      unless now < deadline do throw (IO.userError "owned event scope expired")
      let timer ← Std.Async.Selector.sleep (.ofNat (deadline-now))
      Eggshell.Research.OwnedSelect.one (sources.push (.case timer (fun _ => throw (IO.userError "owned event scope expired"))))
  let reply ← LocalCompletion.awaitTask (← action.toIO)
  scope.ensure
  return reply

end Eggshell.Research.EventScope
