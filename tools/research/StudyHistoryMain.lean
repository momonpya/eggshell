import tools.research.StudyHistoryChecks

def main (args : List String) : IO Unit := do
  match args with
  | "test" :: rest => Eggshell.Research.StudyHistoryChecks.cliMain rest
  | _ => Eggshell.Research.StudyHistory.cliMain args
