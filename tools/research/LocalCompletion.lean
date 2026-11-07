module
public import Std.Sync.Mutex
@[expose] public section
namespace Eggshell.Research.LocalCompletion

/-- One owner consumes the first reply. Closing releases its payload and
prevents a late completion callback from reopening or retaining it. -/
inductive State (α : Type) where
  | pending
  | ready (reply : Except IO.Error α)
  | closed

def State.offer (state : State α) (reply : Except IO.Error α) : State α × Bool :=
  match state with
  | .pending => (.ready reply,true)
  | other => (other,false)

theorem State.first_reply (reply : Except IO.Error α) :
    (State.pending : State α).offer reply = (.ready reply,true) := rfl
theorem State.ready_unchanged (first later : Except IO.Error α) :
    (State.ready first).offer later = (.ready first,false) := rfl
theorem State.closed_unchanged (reply : Except IO.Error α) :
    (State.closed : State α).offer reply = (.closed,false) := rfl

/-- The mutex and condition variable belong to one invocation. They guard
only its reply transfer; no inference, IO or other request owns this lock. -/
structure Mailbox (α : Type) where
  state : Std.Mutex (State α)
  changed : Std.Condvar

def Mailbox.make : BaseIO (Mailbox α) := do
  return ⟨← Std.Mutex.new .pending,← Std.Condvar.new⟩

def Mailbox.publish (box : Mailbox α) (reply : Except IO.Error α) : BaseIO Unit := do
  let notify ← box.state.atomically do
    let (state,notify) := (← get).offer reply
    set state
    return notify
  if notify then box.changed.notifyOne

def Mailbox.close (box : Mailbox α) : BaseIO Unit := do
  box.state.atomically (set (State.closed : State α))
  box.changed.notifyOne

/-- Diagnostics observe parking/waking only. Production uses the default
empty observers; the reply and arbitration never depend on their output. -/
def Mailbox.read (box : Mailbox α) (beforePark afterWake : BaseIO Unit := pure ()) : BaseIO (Except IO.Error α) :=
  box.state.atomically do
    repeat
      match ← get with
      | .ready reply => return reply
      | .closed => return .error (IO.userError "local completion owner closed")
      | .pending =>
          beforePark
          box.changed.wait box.state.mutex
          afterWake
    return .error (IO.userError "unreachable local completion")

/-- Observe once, without IO.wait/IO.waitAny or an async worker blocked on
another task. The original producer owns cancellation/join and must finish
its task even when the surrounding operation is cancelled. -/
def awaitTask (ready : Task (Except IO.Error α)) (beforePark afterWake : BaseIO Unit := pure ()) : IO α := do
  let box ← Mailbox.make
  discard <| IO.mapTask (t := ready) (sync := true) (fun reply => do box.publish reply)
  try IO.ofExcept (← box.read beforePark afterWake)
  finally box.close

end Eggshell.Research.LocalCompletion
