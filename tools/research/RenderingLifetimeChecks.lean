module
public import Eggshell.Handoff
import all Eggshell.Handoff
public import Lean
@[expose] public section
namespace Eggshell.Plugin

#print axioms audit_preparation_exact
#print axioms SelectionAudit.prepared_snapshot_exact

run_elab do
  let env ← Lean.getEnv
  for target in [``PreparedSelectionAudit,``SelectionAudit.Prepared] do
    let some (.inductInfo info) := env.find? target | throwError "prepared audit type is missing"
    for ctor in info.ctors do
      let some value := env.find? ctor | throwError "prepared audit constructor is missing"
      let types := value.type.getUsedConstants
      for forbidden in [``Matcher.Discovery,``RunView,``WorkGraph,``Quotient,``Equality,``Extraction] do
        if types.contains forbidden then throwError "prepared audit retains a discovery domain"

end Eggshell.Plugin
