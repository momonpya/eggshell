module
public import Eggshell.Receipt
@[expose] public section
namespace Eggshell.Research.SelectionPreparationProbe
open Lean

/- Diagnostic implementation only. The logical functions are identity/zero;
the native boundary observes strict arguments without retaining their roots.
No application decision may depend on the returned diagnostic identifier. -/
@[noinline] unsafe def freshImpl {α : Type} (_input : α) : Nat :=
  unsafeBaseIO IO.monoNanosNow

@[implemented_by freshImpl, noinline] def fresh {α : Type} (_input : α) : Nat := 0

@[noinline] unsafe def markImpl {α : Type} (tag : Nat) (stage : String) (value : α) : α :=
  match unsafeIO (do
    let time ← IO.monoNanosNow
    let allocations ← IO.getNumHeartbeats
    let pid ← IO.Process.getPID
    Receipt.observe (some (← Receipt.fresh)) "selection-preparation" (Json.mkObj [
      ("tag",toJson tag),("stage",toJson stage),("pid",toJson pid.toNat),
      ("nanos",toJson time),("smallAllocations",toJson allocations),
      ("allocationCountIsNotBytes",toJson true)])
    return value) with
  | .ok result => result
  | .error _ => value

@[implemented_by markImpl, noinline] def mark {α : Type}
    (_tag : Nat) (_stage : String) (value : α) : α := value

theorem mark_exact (tag : Nat) (stage : String) (value : α) :
    mark tag stage value = value := rfl
end Eggshell.Research.SelectionPreparationProbe
