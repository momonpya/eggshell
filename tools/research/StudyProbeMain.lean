import tools.research.StudyTransport

open Lean Eggshell.Research.StudyTransport

/-- Read-only App Server metadata probe. Its client has no generation capability. -/
def main (args : List String) : IO UInt32 := do
  try
    let [path] := args | throw (IO.userError "StudyProbe SETTINGS.json")
    let settings ← IO.ofExcept (fromJson? (α := Settings)
      (← IO.ofExcept (Json.parse (← IO.FS.readFile (.mk path)))))
    probe settings
    return 0
  catch error =>
    IO.eprintln error.toString
    return 1
