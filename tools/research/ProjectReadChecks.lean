import tools.research.ProjectReadFixture
open Eggshell.Plugin

def main : List String → IO UInt32
  | ["checks",installation,root] => do ProjectReadChecks.run installation root; return 0
  | ["fresh",installation,root] => do ProjectReadChecks.fresh installation root; return 0
  | args => sourceRouteEngine args
