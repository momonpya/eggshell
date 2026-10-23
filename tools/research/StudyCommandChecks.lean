import tools.research.StudyCommand

open Lean Eggshell Eggshell.Research

namespace Eggshell.Research.StudyCommandChecks

private def check (condition : Bool) (message : String) : IO Unit :=
  unless condition do throw (IO.userError message)

def cliMain (args : List String) : IO Unit := do
  let [fixture,directory] := args | throw (IO.userError "StudyCommandChecks FIXTURE NEW-DIRECTORY")
  let root := System.FilePath.mk directory
  check (root.isAbsolute && !(← root.pathExists)) "new absolute command fixture required"
  IO.FS.createDirAll root
  let scratch := root / "scratch"
  let result ← StudyCommand.run fixture #["scratch-check"] #[("TMPDIR",some scratch.toString)]
    root.toString "" (root / "accepted") 10000
  let json ← IO.ofExcept (Json.parse result.stdout)
  check (result.exitCode == 0 && (json.getObjValAs? Bool "temporaryDirectoryCreated").toOption == some true &&
    (← scratch.readDir).isEmpty) "native command failed with prepared scratch"
  let invalid := root / "file"
  IO.FS.writeFile invalid "keep"
  let rejected ← try
    let _ ← StudyCommand.run fixture #["scratch-check"] #[("TMPDIR",some invalid.toString)]
      root.toString "" (root / "rejected") 10000
    pure false
    catch _ => pure true
  check (rejected && !(← (root / "rejected").pathExists) && (← IO.FS.readFile invalid) == "keep")
    "invalid command scratch reached process launch or damaged evidence"
  IO.println ((Json.mkObj [("scratchPreparedBeforeSpawn",toJson true),
    ("invalidScratchRejectedBeforeSpawn",toJson rejected),("nativeTemporaryDirectoryCreated",toJson true),
    ("answeringModelCalls",toJson (0 : Nat))]).compress)

end Eggshell.Research.StudyCommandChecks
