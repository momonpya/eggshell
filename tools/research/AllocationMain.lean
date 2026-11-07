import tools.research.ReplayReadinessChecks
import tools.research.RealDeliveryProbe

def main (args : List String) : IO UInt32 := do
  match args with
  | ["allocation-cells",path] => allocationStudyMain ["cells",path]; return 0
  | ["allocation-install",path] => allocationStudyMain ["install-prefix",path]; return 0
  | other => Eggshell.Research.ReplayReadinessChecks.main other
