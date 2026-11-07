module
public import Eggshell.Handoff
import all Eggshell.Handoff
public import Lean
@[expose] public section
namespace Eggshell.Plugin

#print axioms audit_deferred_exact
#print axioms SelectionAudit.snapshot_ofReport_deferred

theorem deferred_audit_advisory_noop (receipt : Option String) (handoff : Handoff)
    (observed : List SelectionAudit.Admission) (trail : DiscoveryAudit.Trail)
    (noCompletion : handoff.completed = 0) (noControl : handoff.blocksCurrent = false) :
    auditDeferredSelection receipt none (some handoff) observed trail = pure (some handoff) := by
  cases receipt <;> simp [auditDeferredSelection,noCompletion,noControl]

run_elab do
  let env ← Lean.getEnv
  let some trace := env.find? ``traceDiscovery | throwError "missing detached trace callback"
  if trace.type.getUsedConstants.contains ``IndexedContext then
    throwError "trace callback still owns the indexed source"
  let some controller := (env.find? ``indexedDiscoveryUsing).bind (·.value?) |
    throwError "missing actual discovery controller"
  for required in [``traceDiscovery,``prepareDeferredSelectionAudit,``auditDeferredSelection] do
    unless controller.getUsedConstants.contains required do
      throwError "actual discovery bypasses its detached input or audit"
  let some body := (env.find? ``prepareDeferredSelectionAudit).bind (·.value?) |
    throwError "missing deferred audit input"
  for forbidden in [``SelectionDependency.Report.ofValid,``SelectionDependency.comparisons,
      ``SelectionAudit.Snapshot.ofSelection,``SelectionAudit.Snapshot.ofReport] do
    if body.getUsedConstants.contains forbidden then
      throwError "audit preparation still computes a comparison report or snapshot"
  for field in [``DeferredSelectionAudit.current,``DeferredSelectionAudit.selection,
      ``DeferredSelectionAudit.equality,``DeferredSelectionAudit.persistent,
      ``DeferredSelectionAudit.runLocal,``DeferredSelectionAudit.runAll,
      ``DeferredSelectionAudit.passes,``DeferredSelectionAudit.completed] do
    let some declaration := env.find? field | throwError "missing audit field"
    for forbidden in [``Matcher.Discovery,``RunView,``WorkGraph,``Extraction] do
      if declaration.type.getUsedConstants.contains forbidden then
        throwError "deferred runtime field retains a discovery domain"

end Eggshell.Plugin
