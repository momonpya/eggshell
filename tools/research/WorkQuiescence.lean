module
public import Lean.Data.Json.FromToJson
@[expose] public section
namespace Eggshell.Research.WorkQuiescence
open Lean

/-- These are queued/executing work counters, not resident immutable caches.
Both endpoints must be inspected; absent or malformed counts reject the cut. -/
def counters : List (List String) := [
  ["queued"],["active"],
  ["operations","pending"],["operations","active"],["operations","activeSearchActors"],
  ["operations","requestBytes"],
  ["preparation","pending"],["preparation","active"],["preparation","residentBytes"],
  ["preparation","waiters"],
  ["ownedProjects","queued"],["ownedProjects","active"],["ownedProjects","admittedBytes"]]
def atPath (value : Json) : List String → Json
  | [] => value
  | key::rest => atPath (value.getObjValD key) rest
def count? (value : Json) (path : List String) : Option Nat := (atPath value path).getNat?.toOption
def zero (value : Json) (path : List String) : Bool := decide (count? value path = some 0)
def idle (value : Json) : Bool := counters.all (zero value)

theorem admitted_count_zero (value : Json) (accepted : idle value = true)
    (path : List String) (watched : path ∈ counters) : count? value path = some 0 := by
  have checked := List.all_eq_true.mp accepted path watched
  exact of_decide_eq_true checked

theorem active_preparation_refused (value : Json)
    (active : count? value ["preparation","active"] ≠ some 0) : idle value = false := by
  cases accepted : idle value with
  | false => rfl
  | true => exact False.elim (active (admitted_count_zero value accepted _ (by simp [counters])))
end Eggshell.Research.WorkQuiescence
