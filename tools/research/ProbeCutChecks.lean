import tools.research.ProbeCut
import tools.research.RuntimeReadControls
open Lean
namespace Eggshell.Research.ProbeCutChecks
open Eggshell.Plugin.Publication.Service
#print axioms ProbeCut.accepted_endpoints
#print axioms ProbeCut.accepted_version
#print axioms ProbeCut.busy_never_executes
#print axioms ProbeCut.busy_is_unexecuted
run_cmd do
  let env ← getEnv
  let some value := (env.find? ``retentionProbe).bind (·.value?) | throwError "actual diagnostic handler missing"
  unless value.getUsedConstants.contains ``ProbeCut.run && value.getUsedConstants.contains ``ProbeCut.Result.json do
    throwError "actual handler bypasses the typed non-execution boundary"
  logInfo "Actual diagnostic handler returns typed non-execution and preserves observed overlap"
def check (ok : Bool) (message : String) : IO Unit := unless ok do throw (IO.userError message)
def run (output : System.FilePath) : IO Unit := do
  let server ← makeServer
  try
    let quiet ← stats server
    check (WorkQuiescence.idle quiet && ProbeCut.acceptable quiet quiet) "real empty service schema is not a complete idle cut"
    let busy := quiet.setObjVal! "preparation" ((quiet.getObjValD "preparation").setObjVal! "active" (toJson (1 : Nat)))
    let calls ← IO.mkRef 0
    let observe := do calls.modify (·+1); pure (Json.mkObj [("originalMeasurement",toJson true)])
    let refused ← ProbeCut.run busy observe (pure quiet)
    check (!(refused.executed) && (← calls.get) == 0 && refused.json.getObjValD "status" == toJson "busy")
      "busy probe performed an intervention"
    let admitted ← ProbeCut.run quiet observe (pure quiet)
    check (admitted.executed && (← calls.get) == 1 && admitted.json.getObjValD "status" == toJson "observed")
      "idle probe did not execute exactly once"
    let changed := quiet.setObjVal! "operations" ((quiet.getObjValD "operations").setObjVal! "completed" (toJson (1 : Nat)))
    check (WorkQuiescence.idle changed && !ProbeCut.acceptable quiet changed)
      "a job that finished between two idle samples went unnoticed"
    let overlap ← ProbeCut.run quiet observe (pure changed)
    check (overlap.executed && (← calls.get) == 2 && overlap.json.getObjValD "status" == toJson "overlapped" &&
      overlap.json.getObjValD "observation" == Json.mkObj [("originalMeasurement",toJson true)])
      "executed overlap was hidden or retried"
    let missing := quiet.setObjVal! "publishedGroups" Json.null
    check (!ProbeCut.acceptable quiet missing && !ProbeCut.acceptable missing missing)
      "missing version schema admitted an intervention"
    IO.FS.writeFile output (Json.mkObj [("realServiceSchemaAccepted",toJson true),
      ("busyExecutedCalls",toJson (0 : Nat)),("idleExecutedOnce",toJson true),
      ("sameIdleGaugesWithChangedWorkVersionRejected",toJson true),
      ("observedOverlapPreservedWithoutRetry",toJson true),("missingVersionRejected",toJson true),
      ("observedEndpointsAreNotAWholeHeapCensus",toJson true)]).compress
  finally
    server.palettes.close
    server.retained.close
    server.prepared.close
    server.operations.close
    server.preparation.close
end Eggshell.Research.ProbeCutChecks
