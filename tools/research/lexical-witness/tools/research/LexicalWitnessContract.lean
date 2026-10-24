import Eggshell.LexicalReads
import Lean

open Eggshell Eggshell.Persistence.Store

namespace Eggshell.LexicalReads

/-- The retained original member bytes cannot certify a different ordinal. -/
theorem OwnerWitness.unique_ordinal (witness : OwnerWitness) (other : Nat)
    (same : payloadSize witness.member = .ok other) : other = witness.ordinal := by
  rw [witness.memberExact] at same
  exact (Except.ok.inj same).symm

/-- The witness can be constructed only from all three original validations. -/
theorem OwnerWitness.rejects_non_candidate (witness : OwnerWitness)
    (notLive : counterValue witness.candidate ≠ .ok 1) : False :=
  notLive witness.candidateExact

end Eggshell.LexicalReads

open Lean in
run_meta do
  for name in #[``Eggshell.LexicalReads.OwnerWitness.original_checks,
      ``Eggshell.LexicalReads.OwnerWitness.unique_ordinal,
      ``Eggshell.LexicalReads.OwnerWitness.rejects_non_candidate] do
    for axiomName in ← Lean.collectAxioms name do
      unless #[``propext, ``Classical.choice, ``Quot.sound].contains axiomName do
        throwError "Lexical witness uses an unapproved axiom: {name}, {axiomName}"
  logInfo "Original lexical witness retains all checks and one original ordinal"
