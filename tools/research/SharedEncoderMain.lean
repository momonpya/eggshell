import tools.research.SharedEncoderControls
def main (args : List String) : IO UInt32 := do
  match args with
  | [root] => Eggshell.Research.SharedEncoderControls.run (.mk root); return 0
  | _ => throw (IO.userError "OUTPUT required")
