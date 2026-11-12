import tools.research.AutomaticPublicationChecks
def main (args : List String) : IO UInt32 := do
  match args with
  | ["check",input,directory] => AutomaticPublicationChecks.run input directory; return 0
  | _ => sourceRouteEngine args
