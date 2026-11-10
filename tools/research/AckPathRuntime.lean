import tools.research.ReplayReadinessChecks
import tools.research.MemoryCapacity
import tools.research.NativeTrialAudit
import tools.research.MemoryCapacityTrace

/-- Diagnostic native clients; the configured publisher/frontend stay frozen. -/
def main (args : List String) : IO Unit := do
  let [input] := args | throw (IO.userError "ACK path input required")
  Eggshell.Research.MemoryCapacityTrace.run (.mk input)
