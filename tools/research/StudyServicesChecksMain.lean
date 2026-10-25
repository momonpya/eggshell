import tools.research.StudyRuntime
import tools.research.ResourceGuard

open Lean Eggshell Eggshell.Research

private def check (condition : Bool) (message : String) : IO Unit :=
  unless condition do throw (IO.userError message)

private def reject (action : IO α) : IO Unit := do
  let rejected ← try let _ ← action; pure false catch _ => pure true
  check rejected "study service ownership was not rejected"

private def live (pid : Nat) : IO Bool := do
  let rows ← ResourceGuard.processes
  return (rows[pid]?).any (fun row => !row.state.startsWith "Z")

def main (args : List String) : IO UInt32 := do
  try
    let [runtime,directory] := args | throw (IO.userError "StudyServicesChecksMain RUNTIME NEW-DIRECTORY")
    let root := System.FilePath.mk directory
    check (root.isAbsolute && !(← root.pathExists)) "new absolute service fixture required"
    IO.FS.createDir root
    let data := root / "data"
    let environment := #[("EGGSHELL_DATA_ROOT",some data.toString),("LEAN_NUM_THREADS",some "1")]
    reject (StudyRuntime.startPublisher (.mk runtime) data #[])
    check (!(← data.pathExists)) "invalid publisher environment reached process creation"
    let publisher ← StudyRuntime.startPublisher (.mk runtime) data environment
    let owner := StudyRuntime.pid publisher
    try
      reject (StudyRuntime.startPublisher (.mk runtime) data environment)
      check (← live owner) "rejected duplicate startup disturbed the existing publisher"
      check (!(← (root / "work.egg").pathExists)) "publisher startup created source context"
    finally StudyRuntime.stopManaged publisher (root / "publication-stop.json")
    check (!(← live owner)) "owned publisher survived shutdown"
    let owned ← StudyRuntime.startPublisher (.mk runtime) data environment
    let owner := StudyRuntime.pid owned
    let caught ← try
      try throw (IO.userError "synthetic generation failure")
      finally StudyRuntime.stopManaged owned (root / "failure-stop.json")
      pure false
      catch error => pure ((error.toString.splitOn "synthetic generation failure").length > 1)
    check (caught && !(← live owner)) "generation failure lost its original error or publisher cleanup"
    let result := Json.mkObj [("invalidEnvironmentBeforeSpawn",toJson true),
      ("existingPublisherPreserved",toJson true),("sourceContextNotCreated",toJson true),
      ("ownedPublisherExited",toJson true),("generationFailurePreserved",toJson true),
      ("generationFailurePublisherExited",toJson true),("answeringModelCalls",toJson (0 : Nat))]
    IO.FS.writeFile (root / "result.json") result.pretty
    IO.println result.compress
    return 0
  catch error => IO.eprintln error.toString; return 1
