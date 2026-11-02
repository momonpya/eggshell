import tools.research.StudySeedChecks

def main (args : List String) : IO Unit := do
  let [input,root] := args | throw (IO.userError "PreparedQueryGate INPUT NEW-ROOT")
  Eggshell.Research.StudySeedChecks.run input root (remote := true) (literal := true) (generic := true)
