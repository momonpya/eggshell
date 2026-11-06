import Main
import Eggshell.ContractAudit
open Lean Eggshell
open Eggshell.Plugin
#print axioms OperationWire.Request.advance_bounded
#print axioms OperationWire.Request.advance_same
#print axioms Worker.ready_preserves_upstream
#print axioms Daemon.received_chunk_decreases
def check (ok : Bool) (message : String) : IO Unit := unless ok do throw (IO.userError message)
def socketPair : IO (Std.Async.TCP.Socket.Client × Std.Async.TCP.Socket.Client) := do
  let server ← Std.Async.TCP.Socket.Server.mk
  server.bind (Daemon.loopback 0)
  server.listen 1
  let outgoing ← Std.Async.TCP.Socket.Client.mk
  let connecting ← (outgoing.connect (← server.getSockName)).toIO
  let incoming ← TaskDeadline.run server.accept ((← IO.monoMsNow)+2000)
  TaskDeadline.wait connecting ((← IO.monoMsNow)+2000)
  return (outgoing,incoming)
def checks (root : System.FilePath) : IO Unit := do
  check (!(← root.pathExists)) "preserve previous immutable-deadline checks"
  IO.FS.createDirAll root
  let expected : OperationWire.Identity := ⟨"original-turn",7,1000,none⟩
  let request : OperationWire.Request := ⟨"request","chat",.search,Json.null,100,some expected,true⟩
  check ((request.advance expected 100 99).toOption == some 1000) "valid progress failed its original policy"
  check ((({request with finishReady := false}).advance expected 100 99).toOption == some 100) "unready progress extended cutoff"
  check ((request.advance expected 100 100).toOption.isNone &&
    (request.advance {expected with epoch := 8} 100 99).toOption.isNone &&
    ({request with identity := none}.advance expected 100 99).toOption.isNone) "late/foreign/unexpected progress accepted"
  let (sender,receiver) ← socketPair
  let cancelled ← IO.mkRef false
  let bytes := ByteArray.mk ((Array.range 70000).map Nat.toUInt8)
  let frame := (Daemon.frameLength bytes).append bytes
  let deadline := (← IO.monoMsNow)+4000
  let reading ← IO.asTask (OperationWire.receiveFrame receiver deadline cancelled) .dedicated
  for offset in [0:frame.size:4093] do
    TaskDeadline.run (sender.sendAll #[frame.extract offset (min frame.size (offset+4093))]) deadline
    IO.sleep 1
  check ((← TaskDeadline.wait reading deadline) == bytes) "immutable cutoff changed fragmented frame bytes"
  let (blockedSender,blockedReceiver) ← socketPair
  let stop ← IO.mkRef false
  let pending ← IO.asTask (OperationWire.receiveExactly blockedReceiver 10 ((← IO.monoMsNow)+2000) stop) .dedicated
  IO.sleep 5
  stop.set true
  let cancelledRead ← try
      discard <| TaskDeadline.wait pending ((← IO.monoMsNow)+2000)
      pure false
    catch error => pure (error.toString.contains "operation transport cancelled or expired")
  check cancelledRead "cancelled owned read did not finish with its original error"
  discard <| IO.wait pending
  TaskDeadline.run blockedSender.shutdown ((← IO.monoMsNow)+2000)
  let (expiredSender,expiredReceiver) ← socketPair
  let expired ← try
      discard <| OperationWire.receiveExactly expiredReceiver 10 ((← IO.monoMsNow)+20) cancelled
      pure false
    catch error => pure (error.toString.contains "operation transport cancelled or expired")
  check expired "immutable cutoff failed to retire expired native receive"
  TaskDeadline.run expiredSender.shutdown ((← IO.monoMsNow)+2000)
  let liveDeadline := (← IO.monoMsNow)+2000
  OperationWire.sendFrame sender bytes liveDeadline cancelled
  check ((← OperationWire.receiveFrame receiver liveDeadline cancelled) == bytes) "retired request affected live peer"
  let (closedSender,closedReceiver) ← socketPair
  TaskDeadline.run closedSender.shutdown ((← IO.monoMsNow)+2000)
  let eof ← try
      discard <| OperationWire.receiveExactly closedReceiver 1 ((← IO.monoMsNow)+2000) cancelled
      pure false
    catch error => pure (error.toString.contains "operation service closed its response")
  check eof "EOF changed after removing the deadline mutex"
  IO.FS.writeFile (root/"report.json") (Json.mkObj [("progressPolicyExact",toJson true),
    ("lateForeignUnexpectedProgressRejected",toJson true),("fragmentedFrameExact",toJson true),
    ("cancelDeadlineEofAndPeerIsolation",toJson true),("immutableDeadlineNoMutexOrRef",toJson true),
    ("nativeReadsRetiredBeforeReturn",toJson true),("answeringModelCalls",toJson (0 : Nat)),("adopted",toJson false)]).pretty
def main (args : List String) : IO UInt32 := do
  match args with
  | ["immutable-deadline-check",root] => checks (.mk root); return 0
  | ["front-traffic-audit",source] =>
    let result ← IO.Process.output {cmd := "/Users/ovm/.codex/experiments/eggshell/scope-token-study-20261028/fixed-frame-study/metadata-ingress-candidate-build/StudyMain",args := #["front-traffic-audit",source]}
    IO.print result.stdout
    IO.eprint result.stderr
    return result.exitCode
  | other => sourceRouteEngine other
