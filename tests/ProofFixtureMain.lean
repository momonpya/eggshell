module

import tests.KernelFixtures
import tests.MatcherFixtures
public import tests.Blake3Fixtures

@[expose] public section

def main : IO UInt32 := do
  Eggshell.Blake3Fixtures.run
  IO.println "PASS kernel and matcher computational fixtures compiled in test modules"
  pure 0
