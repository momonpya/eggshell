import Eggshell.PreparedRoot

namespace Eggshell.Research.PreparedCutLaws
open Eggshell Eggshell.DB

/-- The parent chain carries the actual source authority. Matching counters
alone cannot justify using a completed component from a different source. -/
theorem lineage_authority (chain : SourceDelta.Lineage before after) :
    before.authority = after.authority := by
  induction chain with
  | same => rfl
  | step _ linked ih =>
    simp only [SourceDelta.linked, Bool.and_eq_true, beq_iff_eq, decide_eq_true_eq] at linked
    exact ih.trans linked.1.1.2

theorem checked_ancestor_same_source (found : SourceDelta.Ancestor target α) :
    found.source.identity = target.identity ∧ found.source.authority = target.authority ∧
      found.source.revision ≤ target.revision :=
  ⟨found.same_identity,lineage_authority found.lineage,found.not_newer⟩

theorem ready_promotion_same_source (promotion : PreparedRoot.Promotion before after) :
    before.identity = after.identity ∧ before.authority = after.authority ∧
      before.revision ≤ after.revision :=
  ⟨promotion.same_database,lineage_authority promotion.lineage,promotion.never_backward⟩

#check PreparedRoot.workspace
#check PreparedRoot.Workspace.write
#print axioms lineage_authority
#print axioms checked_ancestor_same_source
#print axioms ready_promotion_same_source

end Eggshell.Research.PreparedCutLaws
