module
public import Eggshell.ReplayWork
@[expose] public section
namespace Eggshell.Synapses.ReplayReadiness
open Lean DB

/-- A full immutable head, not a revision number or path alone. An unfinished
feed scan and a missing source never authorize the preparation fast path. -/
def settled (cursor : ReplayWork.SourceCursor) (current : Option PageMap.Head) : Bool :=
  decide (cursor.inFlight = false ∧ cursor.head = current) && cursor.head.isSome

theorem settled_exact (cursor : ReplayWork.SourceCursor) (current : Option PageMap.Head)
    (accepted : settled cursor current = true) : cursor.inFlight = false ∧ cursor.head = current := by
  have checked : decide (cursor.inFlight = false ∧ cursor.head = current) = true ∧ cursor.head.isSome = true := by
    simpa only [settled,Bool.and_eq_true] using accepted
  exact of_decide_eq_true checked.1

theorem partial_refused (cursor : ReplayWork.SourceCursor) (current : Option PageMap.Head)
    (partialScan : cursor.inFlight = true) : settled cursor current = false := by
  simp [settled,partialScan]

theorem changed_head_refused (cursor : ReplayWork.SourceCursor) (current : Option PageMap.Head)
    (changed : cursor.head ≠ current) : settled cursor current = false := by
  simp [settled,changed]

theorem missing_refused (cursor : ReplayWork.SourceCursor) : settled cursor none = false := by
  cases stored : cursor.head <;> simp [settled,stored]

/-- Read every registered DB dependency at the existing private replay scope.
This only detects an unchanged materialization cut; it grants no Work/Union or
file freshness authority. Publication and query certification are unchanged. -/
def sourcesCurrent (journal : PageMap.Snapshot) (base : String) (primary : PageMap.Snapshot) : IO Bool := do
  if ← ReplayWork.pending journal base then return false
  let key := base++":source:"
  journal.foldRange ⟨key,key++"~"⟩ (fun ready row => do
    if !ready then return false
    let some bytes := row.2 | return ready
    let cursor ← Index.decode (α := ReplayWork.SourceCursor) bytes
    unless row.1 == ReplayWork.sourceKey base cursor.path do
      throw (IO.userError "foreign source dependency cursor")
    if cursor.inFlight then return false
    let current ← if cursor.path == primary.directory.normalize.toString then pure (some primary)
      else PageMap.open? (.mk cursor.path)
    return settled cursor (current.map (·.head))) true
end Eggshell.Synapses.ReplayReadiness
