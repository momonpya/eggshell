import Eggshell.Daemon
import Eggshell.SynapseBuild

open Lean Eggshell

namespace Eggshell.Research.StudyRuntime

private def check (condition : Bool) (message : String) : IO Unit :=
  unless condition do throw (IO.userError message)

private def readJson (path : System.FilePath) : IO Json := do
  IO.ofExcept (Json.parse (← IO.FS.readFile path))

private def writeJson (path : System.FilePath) (value : Json) : IO Unit := do
  check (!(← path.pathExists)) "keep the existing experiment evidence"
  IO.FS.writeFile path (value.compress ++ "\n")

/-- Only root publication files are copied. Derived directories and private
query/session state cannot enter a checkpoint through this function. -/
def files (directory : System.FilePath) : IO (Array (String × String)) := do
  let mut result := #[]
  for entry in ← directory.readDir do
    let metadata ← entry.path.symlinkMetadata
    if metadata.type == .dir then continue
    check (metadata.type == .file) "a publication file must be a regular file"
    result := result.push (entry.fileName, Sha256.hex (← IO.FS.readBinFile entry.path))
  return result.qsort (fun a b => a.1 < b.1)

def inside (parent child : System.FilePath) : Bool :=
  let parent := parent.normalize.toString
  let child := child.normalize.toString
  child == parent || child.startsWith (parent ++ "/")

def checkpoint (source target : System.FilePath) : IO (Array (String × String)) := do
  check (source.isAbsolute && target.isAbsolute) "checkpoint needs absolute paths"
  Persistence.rejectSymlinkAncestors source
  Persistence.rejectSymlinkAncestors target
  check (!(inside source target)) "checkpoint must be outside its source database"
  check (!(← target.pathExists)) "keep the existing checkpoint"
  let snapshot ← DB.PageMap.pin source
  let original ← files source
  IO.FS.createDirAll target
  for (name,_) in original do
    -- APFS shares unchanged page extents. No recursive directory copy occurs.
    let copied ← IO.Process.output {cmd := "/bin/cp", args := #["-c", (source / name).toString, (target / name).toString]}
    check (copied.exitCode == 0) "publication file copy failed"
  let retained ← DB.PageMap.pin source
  let saved ← DB.PageMap.pin target
  check (snapshot.head == retained.head && snapshot.head == saved.head &&
      original == (← files source) && original == (← files target)) "publication changed during checkpoint"
  return original

def restore (source target : System.FilePath) : IO Unit := do
  check (source.isAbsolute && target.isAbsolute) "restore needs absolute paths"
  Persistence.rejectSymlinkAncestors source
  Persistence.rejectSymlinkAncestors target
  check (!(inside target source)) "restoring must not remove the protected seed"
  if ← target.pathExists then
    check ((← target.symlinkMetadata).type == .dir) "active database must be a directory"
    let _ ← DB.PageMap.pin target
    pure ()
  let pending := System.FilePath.mk (target.toString ++ ".restoring")
  let _ ← checkpoint source pending
  if ← target.pathExists then IO.FS.removeDirAll target
  IO.FS.rename pending target

private abbrev Child := IO.Process.Child {stdin := .null, stdout := .inherit, stderr := .inherit}

private def poll (child : Child) (exit : IO.Ref (Option UInt32)) : IO (Option UInt32) := do
  if let some code ← exit.get then return some code
  let code ← child.tryWait
  exit.set code
  return code

private partial def ready (child : Child) (session : String) (path : System.FilePath)
    (exit : IO.Ref (Option UInt32)) (deadline : Nat) : IO Plugin.Daemon.Endpoint := do
  check ((← poll child exit).isNone) "owned daemon exited before readiness"
  if ← path.pathExists then
    let endpoint ← IO.ofExcept (fromJson? (α := Plugin.Daemon.Endpoint) (← readJson path))
    check (endpoint.pid == child.pid.toNat && endpoint.session == session) "session belongs to another daemon"
    return endpoint
  check ((← IO.monoMsNow) < deadline) "owned daemon did not become ready"
  IO.sleep 5
  ready child session path exit deadline

private partial def stopped (child : Child) (exit : IO.Ref (Option UInt32)) (deadline : Nat) : IO UInt32 := do
  if let some code ← poll child exit then return code
  check ((← IO.monoMsNow) < deadline) "owned daemon did not exit before the cleanup deadline"
  IO.sleep 5
  stopped child exit deadline

/-- This process owns and reaps the real daemon. The controller sends one
shutdown command; acknowledgement is checked independently of actual exit.
No global shutdown, endpoint replacement, or timeout-text fallback is used. -/
def supervise (binary plugin : System.FilePath) (session : String) (report : System.FilePath) : IO UInt32 := do
  let _ ← IO.ofExcept (Plugin.safeSession session)
  check (!(← report.pathExists)) "keep the existing supervisor result"
  check (← (plugin / "bin/eggshelld").pathExists) "missing reviewed plugin launcher"
  let path ← Plugin.Daemon.endpointPath session
  check (!(← path.pathExists)) "a daemon already owns this session"
  let child ← IO.Process.spawn {
    cmd := binary.toString, args := #["codex-daemon",session]
    env := #[("PLUGIN_ROOT",some plugin.toString)]
    stdin := .null, stdout := .inherit, stderr := .inherit, setsid := true}
  let exit ← IO.mkRef none
  let started ← IO.monoMsNow
  try
    let endpoint ← ready child session path exit (started + 10000)
    let stdout ← IO.getStdout
    stdout.putStr ((Json.mkObj [("phase",toJson "ready"),("pid",toJson endpoint.pid)]).compress ++ "\n")
    stdout.flush
    let command ← IO.ofExcept (Json.parse (← (← IO.getStdin).getLine))
    check ((command.getObjValAs? String "command").toOption == some "shutdown") "expected supervisor shutdown"
    let current ← IO.ofExcept (fromJson? (α := Plugin.Daemon.Endpoint) (← readJson path))
    check (current.pid == endpoint.pid && current.secret == endpoint.secret) "owned daemon was replaced"
    let acknowledged ← Plugin.Daemon.exchange endpoint "shutdown" (budget := 500)
    check (acknowledged == "") "daemon rejected shutdown"
    let stopStarted ← IO.monoMsNow
    let code ← stopped child exit (stopStarted + 15000)
    let removed := !(← path.pathExists)
    let result := Json.mkObj [("phase",toJson "stopped"),("pid",toJson endpoint.pid),
      ("daemonExitCode",toJson code.toNat),("endpointRemoved",toJson removed),
      ("stopElapsedMs",toJson ((← IO.monoMsNow)-stopStarted)),("acknowledged",toJson true)]
    writeJson report result
    check (code == 0 && removed) "owned daemon did not stop cleanly"
    return 0
  catch error =>
    if !(← report.pathExists) then
      writeJson report (Json.mkObj [("phase",toJson "failed"),("error",toJson error.toString)])
    throw error
  finally
    if (← poll child exit).isNone then
      Plugin.Worker.killGroup child
      let _ ← child.wait
      pure ()

end Eggshell.Research.StudyRuntime

def main (args : List String) : IO UInt32 := do
  try
    match args with
    | ["checkpoint",source,target,report] =>
        if ← (System.FilePath.mk report).pathExists then throw (IO.userError "keep the existing checkpoint report")
        let files ← Eggshell.Research.StudyRuntime.checkpoint (.mk source) (.mk target)
        IO.FS.writeFile (.mk report) ((toJson files).compress ++ "\n")
        return 0
    | ["restore",source,target] =>
        Eggshell.Research.StudyRuntime.restore (.mk source) (.mk target)
        return 0
    | ["supervise",binary,plugin,session,report] =>
        Eggshell.Research.StudyRuntime.supervise (.mk binary) (.mk plugin) session (.mk report)
    | _ => throw (IO.userError "StudyRuntime checkpoint SOURCE TARGET REPORT | restore SOURCE TARGET | supervise BINARY PLUGIN SESSION REPORT")
  catch error =>
    IO.eprintln error.toString
    return 1
