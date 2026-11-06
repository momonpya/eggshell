module
public import tools.research.WorkQuiescence
@[expose] public section
namespace Eggshell.Research.ProbeCut
open Lean WorkQuiescence

/-- Cumulative work counts supplement the zero gauges. A job that both starts
and finishes between samples must not be mistaken for an unchanged endpoint.
This concerns application work, not a census of every runtime/FFI allocation. -/
def versions : List (List String) := [
  ["publishedGroups"],["publishedReplies"],
  ["operations","admitted"],["operations","started"],["operations","completed"],
  ["preparation","accepted"],["preparation","coalesced"],["preparation","finishedAttempts"],
  ["preparation","retries"],["preparation","progressedAttempts"],
  ["ownedProjects","groups"],["ownedProjects","replies"]]
def sameVersion (before after : Json) (path : List String) : Bool :=
  (count? before path).isSome && decide (count? before path = count? after path)
def unchanged (before after : Json) : Bool := versions.all (sameVersion before after)
def acceptable (before after : Json) : Bool := idle before && idle after && unchanged before after

theorem accepted_endpoints (before after : Json) (h : acceptable before after = true) :
    idle before = true ∧ idle after = true ∧ unchanged before after = true := by
  simpa only [acceptable,Bool.and_eq_true,and_assoc] using h

theorem accepted_version (before after : Json) (h : acceptable before after = true)
    (path : List String) (member : path ∈ versions) : count? before path = count? after path := by
  have checked := List.all_eq_true.mp (accepted_endpoints before after h).2.2 path member
  have equal : (count? before path).isSome = true ∧ decide (count? before path = count? after path) = true := by
    simpa only [sameVersion,Bool.and_eq_true] using checked
  exact of_decide_eq_true equal.2

inductive Result where
  | busy (before : Json)
  | observed (before observation after : Json)
def Result.executed : Result → Bool | .busy _ => false | .observed .. => true
def Result.json : Result → Json
  | .busy before => Json.mkObj [("status",toJson "busy"),("executed",toJson false),("beforeStats",before)]
  | .observed before observation after => Json.mkObj [
    ("status",toJson (if acceptable before after then "observed" else "overlapped")),
    ("executed",toJson true),("beforeStats",before),("observation",observation),("afterStats",after),
    ("quiescentBeforeAndAfter",toJson (idle before && idle after)),
    ("workVersionsUnchanged",toJson (unchanged before after))]

/-- Busy is a typed non-execution result. Once observed, even an overlapped
measurement is returned intact and must never be retried as a non-execution. -/
def run (before : Json) (observe after : IO Json) : IO Result := do
  if idle before then
    let value ← observe
    return .observed before value (← after)
  else return .busy before

theorem busy_never_executes (before : Json) (observe after : IO Json) (busy : idle before = false) :
    run before observe after = pure (.busy before) := by simp [run,busy]
theorem busy_is_unexecuted (before : Json) : (Result.busy before).executed = false := rfl
end Eggshell.Research.ProbeCut
