module
public import Eggshell.FileSystem
public import Eggshell.DaemonWire
public import Std.Async.TCP
public import Lean.Data.Json.FromToJson
@[expose] public section

namespace Eggshell.Research.RpcTrace
open Lean Std Async TCP

/-- Diagnostic metadata is opt-in, contains no request/response bytes, and is
written only to a precreated private experiment directory. -/
initialize configured : Option System.FilePath ← do
  let some value ← IO.getEnv "EGGSHELL_RESEARCH_RPC_TRACE" | return none
  let path := System.FilePath.mk value
  unless path.isAbsolute do throw (IO.userError "RPC diagnostic root must be absolute")
  FileSystem.rejectSymlinkAncestors path
  for child in [path,path/"client",path/"server"] do
    unless ← child.isDir do throw (IO.userError "RPC diagnostic directories must be prepared before startup")
    FileSystem.privateDirectory child
  return some path

def maxEvents : Nat := 64

structure Probe where
  path : System.FilePath
  role : String
  pid : Nat
  kind : IO.Ref String
  events : IO.Ref (Array (String × Nat))
  connection : IO.Ref (Option (String × String))
  dropped : IO.Ref Nat

def start? (role kind : String) (events : Option (IO.Ref (Array (String × Nat))) := none) : IO (Option Probe) := do
  let some root := configured | return none
  unless role == "client" || role == "server" do throw (IO.userError "invalid RPC diagnostic role")
  let pid := (← IO.Process.getPID).toNat
  let stamp ← IO.monoNanosNow
  let path := root/(System.FilePath.mk role)/s!"{pid}-{stamp}.json"
  let events ← match events with | some events => pure events | none => IO.mkRef #[]
  return some ⟨path,role,pid,← IO.mkRef kind,events,← IO.mkRef none,← IO.mkRef 0⟩

def kind (probe : Option Probe) (value : String) : IO Unit := do
  if let some probe := probe then
    probe.kind.set (if ["blocks","encode","ping","stats","shutdown"].contains value then value else "other")

def connected (probe : Option Probe) (client : Socket.Client) : IO Unit := do
  if let some probe := probe then
    try probe.connection.set (some (toString (← client.getSockName),toString (← client.getPeerName)))
    catch _ => pure ()

def mark (probe : Option Probe) (label : String) : IO Unit := do
  if let some probe := probe then
    let events ← probe.events.get
    if events.size < maxEvents then probe.events.set (events.push (label,← IO.monoMsNow))
    else probe.dropped.modify (·+1)

def observe (probe : Option Probe) (label : String) (client : Option Socket.Client) : IO Unit := do
  if let some client := client then connected probe client
  mark probe label

/-- Each request has one metadata writer, even after failure/cancellation.
An observer failure is visible and rejected by the experiment collector; it
must not replace the original transport exception. -/
def close (probe : Option Probe) : IO Unit := do
  if let some probe := probe then
    try
      let events ← probe.events.get
      let value := Json.mkObj [("role",toJson probe.role),("pid",toJson probe.pid),
        ("kind",toJson (← probe.kind.get)),("connection",toJson (← probe.connection.get)),
        ("events",toJson (events.extract 0 maxEvents)),("dropped",toJson ((← probe.dropped.get)+(events.size-maxEvents))),
        ("closedAt",toJson (← IO.monoMsNow)),("containsRequestOrResponseContent",toJson false)]
      let handle ← IO.FS.Handle.mk probe.path .writeNew
      FileSystem.privateFile probe.path
      handle.putStr value.compress
      handle.flush
    catch _ => IO.eprintln "RPC diagnostic record failed"

def exchange (endpoint : Plugin.Daemon.Endpoint) (kind : String) (payload : Json) (deadline : Nat) : IO String := do
  let probe ← start? "client" kind
  try
    let result ← Plugin.Daemon.exchangeBefore endpoint kind payload deadline (observe probe)
    mark probe "request:complete"
    return result
  catch error =>
    mark probe "request:failed"
    throw error
  finally close probe

theorem disabled_mark (label : String) : mark none label = pure () := rfl
theorem disabled_connection (client : Socket.Client) : connected none client = pure () := rfl
theorem disabled_close : close none = pure () := rfl
end Eggshell.Research.RpcTrace
