module
import all Eggshell.Handoff
import all Eggshell.SubsetLexical
import Lean
open Lean
run_meta do
  let env ← getEnv
  for (caller,required) in [
      (``Eggshell.Plugin.federatedDiscovery,#[``Eggshell.SubsetLexical.read?,``Eggshell.Plugin.indexedDiscoveryUsing]),
      (``Eggshell.Plugin.indexedDiscoveryUsing,#[``Eggshell.Plugin.refocusObservedNeighborhood,``Eggshell.Synapses.Transport.build]),
      (``Eggshell.SubsetLexical.read?,#[``Eggshell.SubsetLexical.point,``Eggshell.SubsetLexical.project,``Eggshell.SubsetLexical.rank]),
      (``Eggshell.SubsetLexical.project,#[``Eggshell.SourceOwners.root,``Eggshell.Persistence.Store.findTerm?,``Eggshell.SubsetLexical.point])] do
    let actual := (Compiler.getImplementedBy? env caller).getD caller
    let some declaration := env.find? (Compiler.mkUnsafeRecName actual) <|> env.find? actual
      | throwError "missing subset ranking implementation"
    let some body := declaration.value? | throwError "missing subset ranking body"
    for dependency in required do
      unless body.getUsedConstants.contains dependency do throwError "{caller} lost {dependency}"
    if caller == ``Eggshell.SubsetLexical.project then
      for forbidden in [``Eggshell.SourceOwners.Reader.postingRoot,``Eggshell.SourceBitmap.Reader.members,``Eggshell.SourceBitmap.Reader.union] do
        if body.getUsedConstants.contains forbidden then throwError "subset query restores full postings through {forbidden}"
#print axioms Eggshell.SubsetLexical.rank_exact
#print axioms Eggshell.Plugin.refocus_prepared_lexical_exact
