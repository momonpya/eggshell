import tools.research.ReplayReadinessChecks
import tools.research.MemoryCapacity
import tools.research.NativeTrialAudit

def main (args : List String) : IO UInt32 := do
  match args with
  | ["reference-capacity",input] =>
    Eggshell.Research.MemoryCapacity.run (.mk input)
    return 0
  | other => Eggshell.Research.ReplayReadinessChecks.main other
