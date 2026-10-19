module

public import tests.EqualityDependencyTests

@[expose] public section

def main : IO UInt32 := do
  Eggshell.EqualityDependencyTests.run
  pure 0
