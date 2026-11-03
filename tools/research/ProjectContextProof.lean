import Eggshell.PluginProjectContext
import Eggshell.DemandMemo
import Lean

open Lean Eggshell Eggshell.Plugin

namespace Eggshell.Research.ProjectContextProof

theorem captured_images_exact (context : ProjectContext.Context) :
    context.reads.images = context.images := context.retained

theorem project_cache_shared (left right : DB.PageMap.Snapshot) (project : String) :
    QueryMemoStore.key left (some project) = QueryMemoStore.key right (some project) := rfl

run_cmd do
  let declaration ← getConstInfo ``DemandMemo.publish
  let .defnInfo body := declaration | throwError "memo publisher is not auditable"
  let used := body.value.getUsedConstants
  if used.contains ``DB.PageMap.withWriter then
    throwError "demand memo bypasses its private writer boundary"
  unless used.contains ``QueryMemoStore.withWriter do
    throwError "demand memo lost its private writer boundary"

#print axioms captured_images_exact
#print axioms ProjectContext.Context.complete
#print axioms ProjectContext.Context.complete_sources
#print axioms project_cache_shared

end Eggshell.Research.ProjectContextProof
