module
@[expose] public section

namespace Eggshell.Research.ReplyHold

/-- A reply has one producer and one consumer. A disconnected consumer may
not return storage while its producer is still constructing the payload. -/
inductive Cell where
  | waiting
  | producing (bytes : Nat) (consumerClosed : Bool)
  | ready (bytes : Nat)
  | closed
  deriving Inhabited,BEq,ReflBEq,LawfulBEq

def Cell.charge : Cell → Nat
  | .waiting | .closed => 0
  | .producing bytes _ | .ready bytes => bytes

def grant (cell : Cell) (bytes : Nat) : Option Cell :=
  match cell with
  | .waiting => if 0 < bytes then some (.producing bytes false) else none
  | _ => none

def close : Cell → Cell × Nat
  | .producing bytes _ => (.producing bytes true,0)
  | .ready bytes => (.closed,bytes)
  | .waiting | .closed => (.closed,0)

def finish : Cell → Cell × Nat
  | .producing bytes false => (.ready bytes,0)
  | .producing bytes true => (.closed,bytes)
  | .ready bytes => (.ready bytes,0)
  | .waiting | .closed => (.closed,0)

theorem grant_starts_producer (before after : Cell) (bytes : Nat)
    (granted : grant before bytes = some after) :
    before = .waiting ∧ after = .producing bytes false ∧ 0 < bytes := by
  cases before <;> simp [grant] at granted
  exact ⟨rfl,granted.2.symm,granted.1⟩

theorem granted_charge (before after : Cell) (bytes : Nat)
    (granted : grant before bytes = some after) : after.charge = bytes := by
  rw [(grant_starts_producer before after bytes granted).2.1]
  rfl

theorem closed_cannot_grant (bytes : Nat) : grant .closed bytes = none := rfl

theorem close_keeps_producer_charge (bytes : Nat) (closed : Bool) :
    (close (.producing bytes closed)).1.charge = bytes ∧
      (close (.producing bytes closed)).2 = 0 := ⟨rfl,rfl⟩

theorem live_consumer_keeps_finished_charge (bytes : Nat) :
    finish (.producing bytes false) = (.ready bytes,0) := rfl

theorem close_accounting (cell : Cell) :
    (close cell).1.charge + (close cell).2 = cell.charge := by
  cases cell <;> simp [close,Cell.charge]

theorem finish_accounting (cell : Cell) :
    (finish cell).1.charge + (finish cell).2 = cell.charge := by
  cases cell with
  | producing bytes consumerClosed => cases consumerClosed <;> simp [finish,Cell.charge]
  | _ => simp [finish,Cell.charge]

theorem second_close_releases_nothing (cell : Cell) : (close (close cell).1).2 = 0 := by
  cases cell <;> rfl

theorem second_finish_releases_nothing (cell : Cell) : (finish (finish cell).1).2 = 0 := by
  cases cell with
  | producing bytes consumerClosed => cases consumerClosed <;> rfl
  | _ => rfl

theorem both_closed (cell : Cell) : (close (finish cell).1).1 = .closed ∧
    (finish (close cell).1).1 = .closed := by
  cases cell with
  | producing bytes consumerClosed => cases consumerClosed <;> exact ⟨rfl,rfl⟩
  | _ => exact ⟨rfl,rfl⟩

theorem release_exact_in_both_orders (cell : Cell) :
    (finish cell).2 + (close (finish cell).1).2 = cell.charge ∧
      (close cell).2 + (finish (close cell).1).2 = cell.charge := by
  cases cell with
  | producing bytes consumerClosed => cases consumerClosed <;> simp [finish,close,Cell.charge]
  | _ => simp [finish,close,Cell.charge]

end Eggshell.Research.ReplyHold
