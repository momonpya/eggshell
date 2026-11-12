import Eggshell.CanonicalSourcePrepared
open Lean Eggshell.Synapses
#print axioms SourcePlanContract.UnitChecked.original
#print axioms SourcePlanContract.Checked.rendered_costs
#print axioms SourcePlanContract.Checked.unit_checked
#print axioms SourcePlanContract.Checked.all_rows_eligible
#print axioms PreparedOwnerArena.published_result_checked
#print axioms PreparedOwnerArena.Ready.no_foreign_origin
run_elab do
  let env ← getEnv
  let some body := (env.find? ``PreparedOwnerArena.preparePublished).bind (·.value?) |
    throwError "actual owner loader is absent"
  unless body.getUsedConstants.contains ``SourcePlanContract.check do
    throwError "actual owner loader bypasses the source contract"
  if body.getUsedConstants.contains ``PublishedPlanMetadata.check then
    throwError "actual owner loader still requires the obsolete grouping policy"
  for name in [``SourcePlanContract.Located.mk,``SourcePlanContract.UnitChecked.mk,``SourcePlanContract.Checked.mk] do
    let some declaration := env.find? name | throwError "source contract carrier absent"
    for dependency in declaration.type.getUsedConstants do
      if ["IO","Eggshell.Matcher.Match","WorkGraph","Eggshell.WorkGraph"].contains dependency.toString then
        throwError "source contract acquired execution or completion authority"
