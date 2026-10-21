module

public import tests.MemoReplayTests
public meta import tests.MemoReplayTests

@[expose] public section

def main (args : List String) : IO UInt32 := do
  let [root] := args | throw (IO.userError "one fresh fixture DB path is required")
  Eggshell.MemoReplayTests.run (.mk root)
  pure 0
