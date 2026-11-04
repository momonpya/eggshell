module
import all tools.RetrievalGrams
import all Eggshell.Handoff
import Lean
open Lean
run_meta do
  for (caller,required) in [
      (``Eggshell.RetrievalResearch.terms,#[``Eggshell.RetrievalResearch.StableTerms.addWord]),
      (``Eggshell.RetrievalResearch.StableTerms.addWord,#[``Eggshell.RetrievalResearch.wordForms]),
      (``Eggshell.RetrievalResearch.wordForms,#[``Eggshell.RetrievalResearch.boundaryWord]),
      (``Eggshell.Plugin.lexicalNominations,#[``Eggshell.SearchRank.literalTerm,``Eggshell.SearchRank.preferLiteralMatches])] do
    let env ← getEnv
    let actual := (Compiler.getImplementedBy? env caller).getD caller
    let some declaration := env.find? (Compiler.mkUnsafeRecName actual) <|> env.find? actual
      | throwError "missing boundary implementation: {caller}"
    let some body := declaration.value? | throwError "missing boundary body: {caller}"
    for dependency in required do
      unless body.getUsedConstants.contains dependency do throwError "{caller} lost {dependency}"
#print axioms Eggshell.RetrievalResearch.boundaryWord_idempotent
#print axioms Eggshell.RetrievalResearch.boundaryWord_period
#print axioms Eggshell.RetrievalResearch.boundaryWord_colon
#print axioms Eggshell.RetrievalResearch.wordForms_literal
#print axioms Eggshell.RetrievalResearch.wordForms_bounded
#print axioms Eggshell.SearchRank.literalUnits_period
#print axioms Eggshell.SearchRank.literalUnits_colon
#print axioms Eggshell.SearchRank.preferLiteralMatches_members
#print axioms Eggshell.SearchRank.preferLiteralMatches_order
