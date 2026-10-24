import Eggshell.WorkClassLookup
import Lean
open Lean

run_meta do
  let claims := [
    ``Eggshell.WorkClassLookup.Prepared.member_iff,
    ``Eggshell.WorkClassLookup.Prepared.full_iff,
    ``Eggshell.WorkClassLookup.Prepared.select_full,
    ``Eggshell.WorkClassLookup.Owner.generated,
    ``Eggshell.WorkClassLookup.Owner.preservesExact]
  for claim in claims do
    for axiomName in ← collectAxioms claim do
      unless [``propext,``Classical.choice,``Quot.sound].contains axiomName do
        throwError "unexpected axiom {axiomName} in {claim}"

#print axioms Eggshell.WorkClassLookup.Prepared.member_iff
#print axioms Eggshell.WorkClassLookup.Prepared.full_iff
#print axioms Eggshell.WorkClassLookup.Prepared.select_full
#print axioms Eggshell.WorkClassLookup.Owner.generated
#print axioms Eggshell.WorkClassLookup.Owner.preservesExact
