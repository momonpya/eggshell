import Eggshell.FileSystem

namespace Eggshell.Research.StudyEnvironment

/-- Resolve only the explicit setting carried by a frozen child environment.
Never change the controller's own environment or reinterpret a relative path. -/
def temporaryRoot? (environment : Array (String × Option String)) : Except String (Option System.FilePath) := do
  match (environment.filter (·.1 == "TMPDIR")).toList with
  | [] | [(_,none)] => return none
  | [(_,some raw)] =>
      let path := (System.FilePath.mk raw).normalize
      unless !raw.trimAscii.isEmpty && path.isAbsolute && path.toString != "/" do
        throw "study TMPDIR must name an absolute non-root directory"
      return some path
  | _ => throw "duplicate study TMPDIR setting"

/-- A sealed path does not prove that its directory exists or is writable.
Prepare a missing scratch root and probe actual IO before starting a child.
Existing directories keep their permissions; only our new probe is removed. -/
def prepare (environment : Array (String × Option String)) : IO Unit := do
  let some path ← IO.ofExcept (temporaryRoot? environment) | return
  try
    FileSystem.rejectSymlinkAncestors path
    match ← FileSystem.symlinkMetadata? path with
    | none => FileSystem.privateDirectory path
    | some metadata =>
        unless metadata.type == .dir do throw (IO.userError "scratch root is not a directory")
    let probe := path / s!".eggshell-probe-{← IO.Process.getPID}-{← IO.monoNanosNow}"
    IO.FS.createDir probe
    let file := probe / "io"
    try
      FileSystem.privateDirectory probe
      IO.FS.writeFile file "eggshell\n"
      unless (← IO.FS.readFile file) == "eggshell\n" do throw (IO.userError "scratch probe disagrees")
    finally
      if ← file.pathExists then IO.FS.removeFile file
      IO.FS.removeDir probe
  catch error => throw (IO.userError s!"study TMPDIR {path}: {error}")

end Eggshell.Research.StudyEnvironment
