import tools.research.ReplayWorkChecks
import tools.research.ReadRangeChecks

open Lean

def main (args : List String) : IO Unit := do
  let [directory,"ranges"] := args | throw (IO.userError "NEW-PRIVATE-FIXTURE ranges")
  Eggshell.Research.ReplayWorkChecks.run [directory,"prefix"]
  let root := System.FilePath.mk directory
  let ranges ← Eggshell.Research.ReadRangeChecks.run root
  let report ← IO.ofExcept (Json.parse (← IO.FS.readFile (root / "result.json")))
  let report := report.setObjVal! "ranges" ranges
  IO.FS.writeFile (root / "result.json") report.pretty
  IO.println report.compress
