import Main
import tools.research.MemoryCapacity
open Eggshell.Plugin
def main (args : List String) : IO UInt32 := do
  match args with
  | ["codex-publication-daemon"] => Eggshell.Numerical.withDefaultKeeper Publication.Service.run 1000
  | ["parent-facts-capacity",input] =>
    Eggshell.Research.MemoryCapacity.run (.mk input)
    return 0
  | _ => runProcess false args
