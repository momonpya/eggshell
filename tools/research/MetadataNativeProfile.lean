import Lean
open Lean
namespace Eggshell.Research.MetadataNativeProfile

def worker? (parent : Nat) (binary row : String) : Option Nat := do
  let fields := (row.splitOn " ").filter (!·.isEmpty)
  let pid ← fields[0]?.bind String.toNat?
  let ppid ← fields[1]?.bind String.toNat?
  let role := fields[4]?.getD ""
  unless ppid == parent && fields[2]? == some binary && fields[3]? == some "codex-worker" &&
    (role == "search" || role.startsWith "search-") do none
  return pid

private def sample (pid : Nat) (output : System.FilePath) : IO Unit := do
  unless !(← output.pathExists) do throw (IO.userError "preserve native sample")
  let began ← IO.monoMsNow
  let result ← IO.Process.output {
    cmd := "/usr/bin/sample"
    args := #[toString pid,"18","2","-mayDie","-file",output.toString]}
  IO.FS.writeFile (output.withExtension "json") (Json.mkObj [("pid",toJson pid),
    ("startedMs",toJson began),("stoppedMs",toJson (← IO.monoMsNow)),
    ("exitCode",toJson result.exitCode.toNat),("stdout",toJson result.stdout),("stderr",toJson result.stderr)]).pretty

partial def findWorker (parent : Nat) (binary : String) (deadline : Nat) : IO Nat := do
  let processes ← IO.Process.output {cmd := "/bin/ps",args := #["-axo","pid=,ppid=,command="]}
  unless processes.exitCode == 0 do throw (IO.userError "cannot inspect owned worker")
  if let some pid := processes.stdout.splitOn "\n" |>.findSome? (worker? parent binary) then return pid
  unless (← IO.monoMsNow) < deadline do throw (IO.userError "no owned search worker appeared")
  IO.sleep 50
  findWorker parent binary deadline

def start (publisher daemon : Nat) (binary : String) (directory : System.FilePath) :
    IO (Array (Task (Except IO.Error Unit))) := do
  IO.FS.createDirAll directory
  let deadline := (← IO.monoMsNow)+35000
  let first ← IO.asTask (sample publisher (directory / "publisher.sample.txt")) .dedicated
  let second ← IO.asTask (do
    let pid ← findWorker daemon binary deadline
    IO.FS.writeFile (directory / "worker-owner.json") (Json.mkObj [
      ("parent",toJson daemon),("pid",toJson pid),("binary",toJson binary)]).pretty
    sample pid (directory / "worker.sample.txt")) .dedicated
  return #[first,second]

def finish (tasks : Array (Task (Except IO.Error Unit))) : IO Bool := do
  let mut complete := true
  for task in tasks do
    match ← IO.wait task with
    | .ok _ => pure ()
    | .error error =>
        complete := false
        try IO.eprintln ("native diagnostic incomplete: " ++ error.toString) catch _ => pure ()
  return complete

def parserChecks : IO Unit := do
  let binary := "/owned/bin/eggshell"
  unless worker? 11 binary " 42 11 /owned/bin/eggshell codex-worker search" == some 42 &&
      worker? 11 binary " 42 11 /owned/bin/eggshell codex-worker search-0" == some 42 &&
      worker? 12 binary "42 11 /owned/bin/eggshell codex-worker search-0" == none &&
      worker? 11 binary "42 11 /other/bin/eggshell codex-worker search-0" == none &&
      worker? 11 binary "42 11 /owned/bin/eggshell codex-worker save" == none do
    throw (IO.userError "native sampling could select an unowned process")

end Eggshell.Research.MetadataNativeProfile
