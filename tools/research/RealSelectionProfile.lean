import Main
import tools.research.RealSelectionObserver
import tools.research.MemoryCapacity

def main (arguments : List String) : IO UInt32 := do
  match arguments with
  | ["codex-publication-daemon"] =>
      Eggshell.Numerical.withDefaultKeeper Eggshell.Plugin.Publication.Service.RealSelectionLoop.observed 1000
  | ["real-selection-profile",input] => Eggshell.Research.MemoryCapacity.run (.mk input); return 0
  | other => runProcess false other
