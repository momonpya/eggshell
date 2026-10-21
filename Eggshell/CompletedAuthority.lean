module

public import Eggshell.Matcher
public import Eggshell.SelectionDependency

@[expose] public section

namespace Eggshell.Matcher

theorem completed_not_retrieved {matched : Match}
    (completed : matched.judgment.delivery = .completed) : matched.retrieved = false := by
  cases retrieved : matched.retrieved with
  | false => rfl
  | true => simp [Match.judgment, retrieved, ApplicabilityJudgment.delivery] at completed

/-- Every selected equality premise follows from this run's current generators,
including decomposition and child deduplication, and preserves Exact authority. -/
theorem extraction_comparisons_generated (discovery : Discovery)
    (comparison : SelectionDependency.Comparison)
    (used : comparison ∈ SelectionDependency.comparisons discovery.view.quotient.toEquality
      discovery.current (extraction discovery).selection) :
    Equivalent (discovery.persistentUnions ++ discovery.view.localUnions)
      comparison.left comparison.right ∧
    Value.SameExactFootprint comparison.left comparison.right := by
  have positive := SelectionDependency.comparisons_positive _ _ _ _ _
    (extraction_sound discovery) comparison used
  have generated := discovery.generated comparison.left comparison.right positive
  exact ⟨generated, generated.exactAuthority⟩

/-- Completed authorization is generated equality plus an intrinsic automatic
Match and original-owner provenance. This is not semantic correctness of an
Outcome. Source binding/freshness and transport are explicit IO boundaries. -/
theorem completed_authority {discovery : Discovery} {demand : Value} {edge : OutcomeEdge}
    (used : (demand, edge) ∈ (extraction discovery).selection.completedUses) :
    ∃ matched ∈ discovery.hits,
      matched.retrieved = false ∧ matched.automatic = true ∧
      matched.projectionWork = demand ∧ matched.projectedEdge.relation = edge.relation ∧
      matched.judgment.direction = .pastWorkInsideCurrentDemand ∧
      matched.judgment.reusableOutcome = true ∧
      matched.work.fragmentIdentity = true ∧ matched.work.subwork = true ∧
      (matched.projectedEdge = matched.edge ∨
        matched.edge.relation ∈ matched.projectedEdge.observations) ∧
      edge.outcome ∈ (extraction discovery).priorOutcomes ∧
      Equivalent (discovery.persistentUnions ++ discovery.view.localUnions) edge.work demand ∧
      Value.SameExactFootprint edge.work demand := by
  obtain ⟨matched, member, automatic, projection, relation, forward, reusable,
    identity, subwork, coverage, origin, prior⟩ := extraction_completed_has_match used
  have completed : matched.judgment.delivery = .completed := by
    simp [ApplicabilityJudgment.delivery, forward, reusable]
  have sound := Selection.completedUse_sound (extraction_sound discovery) used
  have generated := discovery.generated edge.work demand sound.2.1
  exact ⟨matched, member, completed_not_retrieved completed, automatic, projection, relation,
    forward, reusable, identity, subwork, origin, prior, generated, generated.exactAuthority⟩

/-- The source boundary supplies ownership in the pinned original publication.
The predicate supports sparse IO; it does not materialize the whole DB. -/
theorem completed_original_authority {discovery : Discovery} {demand : Value} {edge : OutcomeEdge}
    (original : OutcomeEdge → Prop)
    (owned : ∀ matched ∈ discovery.hits, original matched.edge)
    (used : (demand, edge) ∈ (extraction discovery).selection.completedUses) :
    ∃ matched ∈ discovery.hits,
      original matched.edge ∧
      matched.retrieved = false ∧ matched.automatic = true ∧
      matched.projectionWork = demand ∧ matched.projectedEdge.relation = edge.relation ∧
      matched.judgment.direction = .pastWorkInsideCurrentDemand ∧
      matched.judgment.reusableOutcome = true ∧
      matched.work.fragmentIdentity = true ∧ matched.work.subwork = true ∧
      (matched.projectedEdge = matched.edge ∨
        matched.edge.relation ∈ matched.projectedEdge.observations) ∧
      edge.outcome ∈ (extraction discovery).priorOutcomes ∧
      Equivalent (discovery.persistentUnions ++ discovery.view.localUnions) edge.work demand ∧
      Value.SameExactFootprint edge.work demand := by
  obtain ⟨matched, member, supported⟩ := completed_authority used
  exact ⟨matched, member, owned matched member, supported⟩

end Eggshell.Matcher
