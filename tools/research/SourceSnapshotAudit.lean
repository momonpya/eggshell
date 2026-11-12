import Eggshell.ProjectPublication
open Eggshell Eggshell.DB Eggshell.ProjectStore

namespace SourceSnapshotAudit
/-- A captured source cannot inhabit the publisher's owner type. This uses
the actual Owner field checked by acquireOwner, rather than a parallel model. -/
theorem owner_is_managed (owner : Owner) : owner.project.manifest.kind ≠ .snapshot := by
  intro snapshot
  have writable := owner.managed
  unfold Manifest.writable at writable
  rw [snapshot] at writable
  change false = true at writable
  cases writable

theorem captured_head_is_original (manifest : Manifest) (slot : Nat) (head : PageMap.Head)
    (accepted : {manifest with kind := .snapshot}.accepts slot head = true) :
    manifest.owners[slot]? = some head := snapshot_membership_exact manifest slot head accepted

#print axioms snapshot_not_writable
#print axioms snapshot_membership_exact
#print axioms capture_step_bounded
#print axioms owner_is_managed
#print axioms captured_head_is_original
end SourceSnapshotAudit
