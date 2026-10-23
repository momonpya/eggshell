import tools.research.StudyTransport

open Lean Eggshell.Research.StudyTransport

/-- Read-only App Server metadata probe. Its client has no generation capability. -/
def main (args : List String) : IO UInt32 := do
  try
    let [path] := args | throw (IO.userError "StudyProbe SETTINGS.json")
    let settings ← IO.ofExcept (fromJson? (α := Settings)
      (← IO.ofExcept (Json.parse (← IO.FS.readFile (.mk path)))))
    withClient .inspect settings fun client => do
      let hello ← handshake client "0.145.0"
      let models ← request client (.read .models) (Json.mkObj [("includeHidden",toJson true)])
      let hooks ← request client (.read .hooks) (Json.mkObj [("cwds",toJson #[settings.cwd])])
      for (name,value) in #[("initialize",hello),("models",models),("hooks",hooks)] do
        IO.FS.writeFile (.mk settings.output / (name ++ ".json")) (value.compress ++ "\n")
    return 0
  catch error =>
    IO.eprintln error.toString
    return 1
