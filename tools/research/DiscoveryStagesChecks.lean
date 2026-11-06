import Eggshell.PublicationService
import Main
import Eggshell.ContractAudit
open Lean Eggshell Eggshell.Plugin
run_cmd do
  let environment ← getEnv
  for (name,required) in [(``indexedDiscoveryUsing,``IndexedContext.onStage),
      (``focusIndexedEvidence,``BuiltinSearch.nominateIndexed),
      (``federatedDiscovery,``indexedDiscoveryUsing)] do
    let some declaration := environment.find? name | throwError "missing discovery stage declaration {name}"
    let some body := declaration.value? | throwError "opaque discovery stage declaration {name}"
    unless body.getUsedConstants.contains required do throwError "disconnected discovery stage {name} -> {required}"
  logInfo "Actual discovery/focus stage declarations connected;ordinary ContractAudit compiled"
def main (args : List String) : IO UInt32 := do
  match args with
  | ["front-traffic-audit",source] =>
    let result ← IO.Process.output {
      cmd := "/Users/ovm/.codex/experiments/eggshell/scope-token-study-20261028/fixed-frame-study/metadata-ingress-candidate-build/StudyMain"
      args := #["front-traffic-audit",source] }
    IO.print result.stdout
    IO.eprint result.stderr
    return result.exitCode
  | other => sourceRouteEngine other
