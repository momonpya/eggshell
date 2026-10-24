import Eggshell.Handoff
open Eggshell

namespace Eggshell.Matcher

/-- Even changing the old retrieved flag cannot turn a nominated observation
into authority. The evidence constructor itself rejects that promotion. -/
theorem nominated_evidence_stays_advisory (matched : Match)
    (nominated : matched.work = .nominated) :
    matched.judgment.delivery = .advisory := by
  simp [Match.judgment, Match.workJudgment, nominated, ApplicabilityJudgment.delivery]

theorem nominated_evidence_has_no_generator (quotient : Quotient) (inquiry : Value)
    (matched : Match) (nominated : matched.work = .nominated) :
    localUnion? quotient inquiry matched = none := by
  simp [localUnion?, nominated]

theorem nominated_original_result (demand : Value) (owner : OutcomeEdge) :
    (Match.nominated demand owner).projectionOutcome = owner.outcome := rfl

end Eggshell.Matcher

open Lean in
run_meta do
  for name in #[``Eggshell.Matcher.nominated_evidence_stays_advisory,
      ``Eggshell.Matcher.nominated_evidence_has_no_generator,
      ``Eggshell.Matcher.nominated_original_result] do
    for axiomName in ← Lean.collectAxioms name do
      unless #[``propext, ``Classical.choice, ``Quot.sound].contains axiomName do
        throwError "Nominated evidence contract has unapproved axiom {axiomName}"
  logInfo "Nominated evidence cannot acquire authority by changing a flag; original result retained"
