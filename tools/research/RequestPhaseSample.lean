import tools.research.PreparedRoutingObserver

def main (args : List String) : IO Unit := do
  let [input] := args | throw (IO.userError "request-phase-sample INPUT")
  Eggshell.Research.PreparedRoutingObserver.run input
