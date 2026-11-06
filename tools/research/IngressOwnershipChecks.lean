import Main
import Eggshell.ContractAudit
import tools.research.OwnedIngress
open Lean Eggshell Eggshell.Plugin Std Async
namespace Eggshell.Research.IngressOwnershipChecks
open Eggshell.Plugin.Publication.Service
def check (ok : Bool) (message : String) : IO Unit := unless ok do throw (IO.userError message)
def create : IO Server := do
  let originals ← Synapses.CanonicalSource.Shared.Pool.new
  return ⟨← Std.Mutex.new ({} : State),← Std.Mutex.new 0,← IO.mkRef false,
    ← Std.Mutex.new #[],originals,← Synapses.CanonicalSource.Leases.Pool.new originals,
    ← Synapses.ObservedRecordView.Cache.new,← Std.Mutex.new 0,← Std.Mutex.new #[],
    ← Synapses.SharedReadViews.Pool.new,← Publication.Owned.Pool.new,
    ← PreparationService.Pool.new,← OperationPool.Pool.new⟩
def pair : IO (TCP.Socket.Client × TCP.Socket.Client) := do
  let server ← TCP.Socket.Server.mk
  server.bind (Daemon.loopback 0)
  server.listen 1
  let outgoing ← TCP.Socket.Client.mk
  let connecting ← (outgoing.connect (← server.getSockName)).toIO
  let incoming ← TaskDeadline.run server.accept ((← IO.monoMsNow)+2000)
  TaskDeadline.wait connecting ((← IO.monoMsNow)+2000)
  return (outgoing,incoming)
def read (fixed : Bool) (server : Server) (client : TCP.Socket.Client) (amount deadline : Nat) : IO ByteArray :=
  if fixed then OwnedIngress.receive server.stopping client amount deadline
  else receiveLive server client amount deadline
def controls (fixed : Bool) : IO Json := do
  let server ← create
  let (sender,receiver) ← pair
  let bytes := ByteArray.mk ((Array.range 70000).map Nat.toUInt8)
  let deadline := (← IO.monoMsNow)+5000
  let reading ← IO.asTask (read fixed server receiver bytes.size deadline) .dedicated
  for offset in [0:bytes.size:4093] do
    TaskDeadline.run (sender.sendAll #[bytes.extract offset (min bytes.size (offset+4093))]) deadline
    IO.sleep 2
  check ((← TaskDeadline.wait reading deadline) == bytes) "fragmented publisher body changed"
  let (blockedSender,blockedReceiver) ← pair
  let waiting ← IO.asTask (read fixed server blockedReceiver 1 ((← IO.monoMsNow)+2000)) .dedicated
  IO.sleep 20
  server.stopping.set true
  let stopped ← try
      discard <| TaskDeadline.wait waiting ((← IO.monoMsNow)+2000)
      pure false
    catch _ => pure true
  check stopped "publisher shutdown failed to retire receive"
  discard <| IO.wait waiting
  server.stopping.set false
  let expired ← try
      discard <| read fixed server blockedReceiver 1 ((← IO.monoMsNow)+20)
      pure false
    catch _ => pure true
  check expired "publisher receive ignored its deadline"
  TaskDeadline.run blockedSender.shutdown ((← IO.monoMsNow)+2000)
  let eof ← try
      discard <| read fixed server blockedReceiver 1 ((← IO.monoMsNow)+2000)
      pure false
    catch _ => pure true
  check eof "publisher receive accepted incomplete EOF"
  -- A cancelled/expired read must not leave a native receive behind. Use the
  -- same connection for a fresh request, and keep the unrelated peer live.
  let nextDeadline := (← IO.monoMsNow)+2000
  TaskDeadline.run (sender.sendAll #[bytes]) nextDeadline
  check ((← read fixed server receiver bytes.size nextDeadline) == bytes) "one retired receive affected another peer"
  server.operations.close
  return Json.mkObj [("fixed",toJson fixed),("fragmentedBytesExact",toJson true),
    ("stopDeadlineEofPeerIsolation",toJson true)]
def rss : IO Nat := do
  let result ← IO.Process.output {cmd := "/bin/ps",args := #["-o","rss=","-p",toString (← IO.Process.getPID)]}
  let some value := result.stdout.trimAscii.toString.toNat? | throw (IO.userError "RSS unavailable")
  return value
def wave (fixed : Bool) (server : Server) (payload : ByteArray) : IO Nat := do
  let started ← IO.monoMsNow
  let actors ← (Array.range 16).mapM fun _ => IO.asTask (do
    let (sender,receiver) ← pair
    let deadline := (← IO.monoMsNow)+10000
    let task ← IO.asTask (read fixed server receiver payload.size deadline) .dedicated
    try
      for offset in [0:payload.size:8191] do
        TaskDeadline.run (sender.sendAll #[payload.extract offset (min payload.size (offset+8191))]) deadline
        IO.sleep 1
      check ((← TaskDeadline.wait task deadline) == payload) "publisher workload changed original bytes"
    finally
      if !(← IO.hasFinished task) then IO.cancel task
      discard <| IO.wait task) .dedicated
  for actor in actors do TaskDeadline.wait actor ((← IO.monoMsNow)+12000)
  return (← IO.monoMsNow)-started
def workload (fixed : Bool) : IO Json := do
  let server ← create
  let bytes := ByteArray.mk ((Array.range (512*1024)).map Nat.toUInt8)
  let before ← rss
  let mut waves := #[]
  for _ in [0:3] do
    let elapsed ← wave fixed server bytes
    IO.sleep 100
    waves := waves.push (Json.mkObj [("elapsedMs",toJson elapsed),("rssKiB",toJson (← rss))])
  server.operations.close
  return Json.mkObj [("fixed",toJson fixed),("beforeRssKiB",toJson before),("waves",toJson waves),
    ("connections",toJson (48 : Nat)),("bytesPerConnection",toJson bytes.size),
    ("allOriginalBytesEqual",toJson true),("fullServiceCapacityClaim",toJson false)]
def main (args : List String) : IO UInt32 := do
  match args with
  | ["ingress-controls",destination] =>
    let path : System.FilePath := .mk destination
    check (!(← path.pathExists)) "preserve ingress controls"
    IO.FS.writeFile path (toJson (← #[false,true].mapM controls)).compress
    return 0
  | ["ingress-workload",mode,destination] =>
    check (mode == "parent" || mode == "fixed") "explicit ingress mode required"
    let path : System.FilePath := .mk destination
    check (!(← path.pathExists)) "preserve ingress workload"
    IO.FS.writeFile path (← workload (mode == "fixed")).compress
    return 0
  | other => sourceRouteEngine other
end Eggshell.Research.IngressOwnershipChecks
def main := Eggshell.Research.IngressOwnershipChecks.main
