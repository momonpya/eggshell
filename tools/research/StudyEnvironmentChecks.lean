import tools.research.StudyEnvironment
import Lean.Data.Json.FromToJson

open Lean Eggshell Eggshell.Research

namespace Eggshell.Research.StudyEnvironmentChecks

private def check (condition : Bool) (message : String) : IO Unit :=
  unless condition do throw (IO.userError message)

private def rejected (environment : Array (String × Option String)) : IO Bool := do
  try StudyEnvironment.prepare environment; pure false
  catch _ => pure true

private def scenario (root : System.FilePath) : IO Unit := do
  check (root.isAbsolute && !(← root.pathExists)) "new absolute scratch fixture required"
  IO.FS.createDirAll root
  let scratch := root / "scratch"
  let configured := #[("TMPDIR",some scratch.toString)]
  StudyEnvironment.prepare configured
  check (← scratch.isDir) "missing configured scratch was not prepared"
  IO.FS.writeFile (scratch / "retained") "keep"
  StudyEnvironment.prepare configured
  check ((← IO.FS.readFile (scratch / "retained")) == "keep" && (← scratch.readDir).size == 1)
    "scratch admission changed existing files or leaked its probe"
  let file := root / "file"
  IO.FS.writeFile file "keep"
  check (← rejected #[("TMPDIR",some file.toString)]) "file accepted as scratch root"
  check (← rejected #[("TMPDIR",some "relative/scratch")]) "relative scratch accepted"
  check (← rejected #[("TMPDIR",some "")]) "empty scratch accepted"
  check (← rejected #[("TMPDIR",some "/")]) "filesystem root accepted as private scratch"
  check (← rejected (configured ++ configured)) "duplicate scratch accepted"
  let link := root / "link"
  let linked ← IO.Process.output {cmd := "/bin/ln",args := #["-s",scratch.toString,link.toString]}
  check (linked.exitCode == 0 && (← rejected #[("TMPDIR",some link.toString)])) "symlink scratch accepted"
  IO.setAccessRights scratch {user := {read := true,execution := true},group := {},other := {}}
  try
    check (← rejected configured) "unwritable existing scratch was silently enabled"
  finally FileSystem.privateDirectory scratch
  check ((← IO.FS.readFile file) == "keep") "invalid scratch probe replaced an existing file"
  StudyEnvironment.prepare #[]
  StudyEnvironment.prepare #[("TMPDIR",none)]
  IO.println ((Json.mkObj [("missingPrepared",toJson true),("existingRetained",toJson true),
    ("invalidCasesRejected",toJson (7 : Nat)),("probesRemoved",toJson true),
    ("answeringModelCalls",toJson (0 : Nat))]).compress)

def cliMain (args : List String) : IO Unit := do
  match args with
  | [root] => scenario (.mk root)
  | ["prepare",path] => StudyEnvironment.prepare #[("TMPDIR",some path)]
  | _ => throw (IO.userError "StudyEnvironmentChecks NEW-DIRECTORY | prepare TMPDIR")

end Eggshell.Research.StudyEnvironmentChecks
