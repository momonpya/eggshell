import Eggshell.OwnedSocket
import Eggshell.DaemonWire
import Lean.Data.Json.FromToJson
open Lean Eggshell Std Async TCP
namespace OwnedSocketChecks
def check (valid : Bool) (message : String) : IO Unit := unless valid do throw (IO.userError message)
def finish (task : Task (Except IO.Error α)) : IO α := do
  IO.ofExcept ((← IO.wait task).mapError IO.Error.toString)
def accept (server : Socket.Server) (deadline : Nat) : IO Socket.Client := do
  repeat
    match ← server.tryAccept with
    | some client => return client
    | none =>
      unless (← IO.monoMsNow) < deadline do throw (IO.userError "fixture accept expired")
      IO.sleep 1
  throw (IO.userError "unreachable fixture accept")
def listener : IO (Socket.Server × Nat) := do
  let server ← Socket.Server.mk
  server.bind (Plugin.Daemon.loopback 0)
  server.listen 32
  server.noDelay
  return (server,(← server.getSockName).port.toNat)
def waitPromise (promise : IO.Promise Unit) (deadline : Nat) : IO Unit := do
  while !(← promise.isResolved) do
    unless (← IO.monoMsNow) < deadline do throw (IO.userError "fixture did not reach its declared phase")
    IO.sleep 1
def tcpDescriptors : IO Nat := do
  let pid := toString (← IO.Process.getPID).toNat
  let result ← IO.Process.output {cmd := "/usr/sbin/lsof",args := #["-a","-p",pid,"-iTCP","-Ff"]}
  check (result.exitCode ≤ 1 && result.stderr.isEmpty) "cannot inspect fixture TCP descriptors"
  return (result.stdout.splitOn "\n" |>.filter (·.startsWith "f")).length
def noBytesUntilClose (client : Socket.Client) (deadline : Nat) : IO Unit :=
  Plugin.Daemon.withOwnedReceive client 1 fun reading => do
    let bytes ← TaskDeadline.wait reading deadline
    check bytes.isNone "silent request unexpectedly sent data"
def payload (index : Nat) : ByteArray :=
  (String.intercalate "\n" ((List.range 40).map fun row =>
    s!"request {index} / row {row}: 原文を完全なバイト列のまま渡す αβγδε / path:start-end")).toUTF8
def echo (client : Socket.Client) (deadline : Nat) : IO Unit := do
  let bytes ← Plugin.Daemon.receiveFrameBefore client deadline
  let header := Plugin.Daemon.frameLength bytes
  TaskDeadline.run (client.sendAll #[header.extract 0 2]) deadline
  IO.sleep 1
  TaskDeadline.run (client.sendAll #[header.extract 2 4,bytes.extract 0 37,bytes.extract 37 bytes.size]) deadline
def parallelEcho : IO Json := do
  let (server,port) ← listener
  let deadline := (← IO.monoMsNow)+10000
  let serving ← IO.asTask (do
    let mut tasks := #[]
    for _ in [:16] do
      let client ← accept server deadline
      tasks := tasks.push (← IO.asTask (echo client deadline) .dedicated)
    for task in tasks do finish task) .dedicated
  let started ← IO.monoMsNow
  let tasks ← (List.range 16).toArray.mapM fun index => IO.asTask (do
    let bytes := payload index
    let returned ← OwnedSocket.withConnection port deadline fun connection => do
      connection.writeFrame bytes deadline
      connection.readFrame deadline
    check (returned == bytes) "native socket changed a complete UTF-8 payload"
    return Json.mkObj [("client",toJson index),("bytes",toJson bytes.size),("exact",toJson true)]) .dedicated
  let rows ← tasks.mapM finish
  finish serving
  let elapsed := (← IO.monoMsNow)-started
  check (elapsed < 10000) "sixteen-client transport gate exceeded ten seconds"
  return Json.mkObj [("clients",toJson (16 : Nat)),("elapsedMs",toJson elapsed),("rows",toJson rows)]
def malformed (oversized : Bool) : IO Json := do
  let (server,port) ← listener
  let deadline := (← IO.monoMsNow)+2000
  let serving ← IO.asTask (do
    let client ← accept server deadline
    TaskDeadline.run (client.sendAll #[if oversized then .mk #[255,255,255,255] else .mk #[0,0]]) deadline
    TaskDeadline.run client.shutdown deadline) .dedicated
  let began ← IO.monoMsNow
  let failure ← try
    discard <| OwnedSocket.withConnection port deadline fun connection => connection.readFrame deadline
    pure none
    catch error => pure (some error.toString)
  finish serving
  check failure.isSome "malformed native frame was accepted"
  if oversized then check (failure.any (·.contains "exceeds its bound")) "oversized header was not rejected before its payload"
  return Json.mkObj [("oversized",toJson oversized),("elapsedMs",toJson ((← IO.monoMsNow)-began)),("failure",toJson failure)]
def interruption (cancel : Bool) : IO Json := do
  let (server,port) ← listener
  let deadline := (← IO.monoMsNow)+2000
  let entered ← IO.Promise.new
  let serving ← IO.asTask (do
    let client ← accept server deadline
    noBytesUntilClose client deadline) .dedicated
  let client ← IO.asTask (OwnedSocket.withConnection port deadline fun connection => do
    entered.resolve ()
    let now ← IO.monoMsNow
    let readDeadline := if cancel then deadline else now+100
    discard <| connection.readFrame readDeadline) .dedicated
  waitPromise entered deadline
  IO.sleep 20
  check (!(← IO.hasFinished client)) "request was not blocked before interruption"
  let began ← IO.monoMsNow
  if cancel then IO.cancel client
  let outcome ← IO.wait client
  check (!outcome.isOk) "interrupted request unexpectedly succeeded"
  finish serving
  let elapsed := (← IO.monoMsNow)-began
  check (elapsed < 1000) "cancel/deadline failed to close and join its descriptor"
  return Json.mkObj [("cancel",toJson cancel),("elapsedMs",toJson elapsed),("peerObservedClose",toJson true)]
def blockedSend : IO Json := do
  let (server,port) ← listener
  let deadline := (← IO.monoMsNow)+4000
  let entered ← IO.Promise.new
  let release ← IO.Promise.new
  let serving ← IO.asTask (do
    let client ← accept server deadline
    waitPromise release deadline
    -- Drain only after cancellation; a reset or EOF must terminate the peer.
    let mut received := 0
    let mut closed := false
    while !closed do
      try
        let part ← Plugin.Daemon.withOwnedReceive client 65536 fun reading => TaskDeadline.wait reading deadline
        match part with
        | none => closed := true
        | some part => received := received+part.size
      catch _ => closed := true
    return received) .dedicated
  let client ← IO.asTask (OwnedSocket.withConnection port deadline fun connection => do
    let bytes := ByteArray.mk (Array.replicate OwnedSocket.maxFrameBytes 0x5a)
    entered.resolve ()
    for _ in [:8] do connection.writeFrame bytes deadline) .dedicated
  waitPromise entered deadline
  IO.sleep 100
  check (!(← IO.hasFinished client)) "fixture did not retain an in-progress send"
  let began ← IO.monoMsNow
  IO.cancel client
  let result ← IO.wait client
  let elapsed := (← IO.monoMsNow)-began
  check (!result.isOk && elapsed < 1000) "blocked send did not cancel and join"
  release.resolve ()
  let received ← finish serving
  check (received < 8*(OwnedSocket.maxFrameBytes+4)) "fixture completed all sends before interruption"
  return Json.mkObj [("cancelJoinMs",toJson elapsed),("peerReceivedBytes",toJson received),
    ("allFramesSent",toJson false),("peerTerminated",toJson true)]
def escapedScope : IO Json := do
  let (server,port) ← listener
  let deadline := (← IO.monoMsNow)+2000
  let serving ← IO.asTask (do
    noBytesUntilClose (← accept server deadline) deadline
    echo (← accept server deadline) deadline) .dedicated
  let escaped ← OwnedSocket.withConnection port deadline pure
  let rejected ← OwnedSocket.withConnection port deadline fun current => do
    let rejected ← try
      escaped.writeFrame (payload 0) deadline
      pure false
      catch _ => pure true
    let bytes := payload 1
    current.writeFrame bytes deadline
    check ((← current.readFrame deadline) == bytes) "closed handle affected another connection"
    return rejected
  finish serving
  check rejected "a connection escaped its closed scope"
  return Json.mkObj [("closedScopeRejected",toJson true),("otherConnectionUnchanged",toJson true)]
def lateResult : IO Json := do
  let (server,port) ← listener
  let deadline := (← IO.monoMsNow)+1000
  let serving ← IO.asTask (do
    let client ← accept server deadline
    noBytesUntilClose client deadline) .dedicated
  let refused ← try
    discard <| OwnedSocket.withConnection port ((← IO.monoMsNow)+80) fun _ => do
      IO.sleep 120
      pure (42 : Nat)
    pure false
    catch _ => pure true
  finish serving
  check refused "callback returned success after its absolute deadline"
  return Json.mkObj [("lateSuccessRefused",toJson true),("peerObservedClose",toJson true)]
def run (output : System.FilePath) : IO Unit := do
  check (!(← output.pathExists)) "fresh socket evidence required"
  let before ← tcpDescriptors
  let echo ← parallelEcho
  let malformed ← #[false,true].mapM malformed
  let interrupted ← #[true,false].mapM interruption
  let blocked ← blockedSend
  let escaped ← escapedScope
  let late ← lateResult
  let invalidPort ← try
    discard <| OwnedSocket.withConnection 65536 ((← IO.monoMsNow)+100) fun _ => pure ()
    pure false
    catch _ => pure true
  check invalidPort "oversized port was truncated into another destination"
  IO.sleep 100
  let after ← tcpDescriptors
  check (before == after) "fixture TCP descriptors survived joined operations"
  IO.FS.writeFile output (Json.mkObj [("echo",echo),("malformed",toJson malformed),
    ("interrupted",toJson interrupted),("blockedSend",blocked),("invalidPortRejected",toJson true),
    ("escapedScope",escaped),("tcpDescriptorsBefore",toJson before),("tcpDescriptorsAfter",toJson after),
    ("lateResult",late),
    ("actualProjectQueries",toJson (0 : Nat)),("answeringModelCalls",toJson (0 : Nat)),("adopted",toJson false)]).compress
end OwnedSocketChecks
def main : List String → IO Unit
  | [output] => OwnedSocketChecks.run (.mk output)
  | _ => throw (IO.userError "OwnedSocketChecks OUTPUT")
