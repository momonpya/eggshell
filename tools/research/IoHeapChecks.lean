import Main
import Eggshell.ContractAudit
import tools.research.HeapObservation
import Std.Internal.UV.TCP
open Lean Eggshell Eggshell.Plugin Eggshell.Research
namespace IoHeapChecks
def check (ok : Bool) (message : String) : IO Unit := unless ok do throw (IO.userError message)
@[noinline] def produce (keep : IO.Ref (Array ByteArray)) : IO Unit := do
  let mut blocks := #[]
  for index in [:256] do blocks := blocks.push (ByteArray.mk (Array.replicate 65536 index.toUInt8))
  keep.set blocks
@[noinline] def clear (keep : IO.Ref (Array ByteArray)) : IO Unit := do
  let blocks ← keep.get
  check (blocks.size == 256 && blocks.all (·.size == 65536)) "I/O fixture payload changed"
  keep.set #[]

/-- Model an ordinary temporary allocation on the owner. This is a diagnostic
counterfactual, not a collection policy or a proposed production workaround. -/
@[noinline] def scratch (count : Nat) : IO Unit := do
  let temporary ← IO.mkRef (ByteArray.mk (Array.replicate count (count%251).toUInt8))
  let bytes ← temporary.get
  check (bytes.size == count) "temporary allocation size changed"

def tcpOwner : IO Nat := do
  let listener ← Std.Internal.UV.TCP.Socket.new
  listener.bind (Daemon.loopback 0)
  listener.listen 1
  let accepting ← listener.accept
  let peer ← Std.Internal.UV.TCP.Socket.new
  let connecting ← peer.connect (← listener.getSockName)
  let socket ← IO.ofExcept (← IO.wait accepting.result!)
  IO.ofExcept (← IO.wait connecting.result!)
  let incoming ← socket.recv? 1
  check (!(← incoming.isResolved)) "TCP control completed before registration"
  let observed ← IO.mapTask (t := incoming.result!) (sync := true) fun result => do
    let bytes ← IO.ofExcept result
    check (bytes == some "x".toUTF8) "TCP control changed its byte"
    HeapObservation.threadId
  let sent ← peer.send #["x".toUTF8]
  IO.ofExcept (← IO.wait sent.result!)
  let identity ← TaskDeadline.wait observed ((← IO.monoMsNow)+2000)
  listener.cancelAccept
  return identity

def mailboxOwner : IO Json := do
  let probe ← HeapObservation.Probe.new
  let entered : IO.Promise Nat ← IO.Promise.new
  let task ← IO.asTask (do
    entered.resolve (← HeapObservation.threadId)
    repeat
      if ← IO.checkCanceled then return
      probe.respond
      IO.sleep 1) .dedicated
  try
    let expected ← TaskDeadline.wait (Std.Async.AsyncTask.ofPurePromise entered) ((← IO.monoMsNow)+2000)
    let value ← probe.request
    check (value.getObjValD "thread" == toJson expected) "mailbox measured a foreign heap owner"
    return value
  finally
    IO.cancel task
    discard <| IO.wait task
    probe.stop

def controls (root : System.FilePath) : IO Unit := do
  check (!(← root.pathExists)) "fresh I/O heap control root required"
  IO.FS.createDirAll root
  HeapObservation.initializeObserver
  let caller ← HeapObservation.threadId
  let before ← HeapObservation.ioSnapshot
  let ioThread ← IO.ofExcept (before.getObjValAs? Nat "thread")
  let keep ← IO.mkRef (#[] : Array ByteArray)
  let (producer,_) ← HeapObservation.onNativeTimer (produce keep)
  let held ← HeapObservation.ioSnapshot
  clear keep
  let released ← HeapObservation.ioSnapshot
  check ((← keep.get).isEmpty) "remote release did not clear the application root"
  let (maintenance,_) ← HeapObservation.onNativeTimer (scratch (1024*1024))
  let afterAllocation ← HeapObservation.ioSnapshot
  let (localProducer,_) ← HeapObservation.onNativeTimer (do produce keep; clear keep)
  let localReleased ← HeapObservation.ioSnapshot
  let worker ← HeapObservation.workerSnapshot
  let mailbox ← mailboxOwner
  let socketThread ← tcpOwner
  let arenas ← HeapObservation.arenasRaw
  let number := fun value key => (value.getObjValAs? Nat key).toOption.getD 0
  let complete := [before,held,released,afterAllocation,localReleased].all (fun value => number (value.getObjValD "heap") "complete" == 1)
  let sameOwner := caller != ioThread && producer == ioThread && socketThread == ioThread &&
    maintenance == ioThread && localProducer == ioThread &&
    [held,released,afterAllocation,localReleased].all (fun value => number value "thread" == ioThread)
  IO.FS.writeFile (root/"report.json") (Json.mkObj [("before",before),("held",held),("released",released),
    ("afterOrdinaryAllocation",afterAllocation),("localReleased",localReleased),("defaultWorker",worker),("mailboxOwner",mailbox),
    ("applicationRootEmptyAfterRemoteRelease",toJson true),
    ("censusIsAllocatorAccountingNotReachability",toJson true),
    ("caller",toJson caller),("producer",toJson producer),("socketThread",toJson socketThread),
    ("sameNativeTimerAndTcpOwner",toJson sameOwner),("arenas",toJson arenas),("complete",toJson complete),
    ("ownerStillAlive",toJson (← HeapObservation.threadAlive ioThread)),("miCollectCalled",toJson false)]).compress
  check (complete && sameOwner) "I/O owner observation was incomplete or ran on the wrong thread"
  check (number (held.getObjValD "heap") "allocatedBytes" ≥ number (before.getObjValD "heap") "allocatedBytes"+16*1024*1024)
    "I/O observer failed its retained sixteen MiB positive control"
  check (number (localReleased.getObjValD "heap") "allocatedBytes"+16*1024*1024 ≤ number (held.getObjValD "heap") "allocatedBytes")
    "I/O observer failed its owner-local released payload negative control"
  check (number worker "thread" != caller && number (worker.getObjValD "heap") "complete" == 1)
    "default worker observation ran on the caller or was incomplete"

@[noinline] def produceShape (keep : IO.Ref ByteArray) (size : Nat) : IO Unit := do
  let payload := ByteArray.mk (Array.replicate size (37 : UInt8))
  check (payload.size == size) "heap-shape fixture changed its original bytes"
  keep.set payload

/-- A small-block positive control cannot establish that a heap visitor sees
large native buffers. Validate the actual Lean allocation path at both sizes. -/
def shapes (root : System.FilePath) : IO Unit := do
  check (!(← root.pathExists)) "fresh heap shape control required"
  IO.FS.createDirAll root
  HeapObservation.initializeObserver
  let mut rows := #[]
  let mut valid := true
  let number := fun value key => (value.getObjValAs? Nat key).toOption.getD 0
  for size in [65536,2*1024*1024,32*1024*1024] do
    let keep ← IO.mkRef ByteArray.empty
    let before ← HeapObservation.ioSnapshot
    let (producer,_) ← HeapObservation.onNativeTimer (produceShape keep size)
    let held ← HeapObservation.ioSnapshot
    let (releaseOwner,_) ← HeapObservation.onNativeTimer (keep.set ByteArray.empty)
    let released ← HeapObservation.ioSnapshot
    let same := before.getObjValD "thread" == toJson producer && producer == releaseOwner &&
      held.getObjValD "thread" == toJson producer && released.getObjValD "thread" == toJson producer
    let complete := [before,held,released].all (fun value =>
      number (value.getObjValD "heap") "complete" == 1)
    let heldBytes := number (held.getObjValD "heap") "allocatedBytes"
    let seen := decide (number (before.getObjValD "heap") "allocatedBytes"+size ≤ heldBytes)
    let freed := decide (number (released.getObjValD "heap") "allocatedBytes"+size ≤ heldBytes)
    rows := rows.push (Json.mkObj [("payloadBytes",toJson size),("before",before),("held",held),
      ("released",released),("sameOwner",toJson same),("complete",toJson complete),
      ("heldPayloadCounted",toJson seen),("ownerLocalReleaseCounted",toJson freed)])
    valid := valid && same && complete && seen && freed
  IO.FS.writeFile (root/"report.json") (Json.mkObj [("rows",toJson rows),
    ("allPayloadShapesCounted",toJson valid),("noCollectionOrOptionChange",toJson true)]).compress
  check valid "heap census does not cover every tested native buffer shape"
end IoHeapChecks
def main (args : List String) : IO UInt32 := do
  match args with
  | ["io-heap-check",root] => IoHeapChecks.controls (.mk root); return 0
  | ["io-heap-shapes",root] => IoHeapChecks.shapes (.mk root); return 0
  | ["front-traffic-audit",source] =>
    let result ← IO.Process.output {
      cmd := "/Users/ovm/.codex/experiments/eggshell/scope-token-study-20261028/fixed-frame-study/metadata-ingress-candidate-build/StudyMain"
      args := #["front-traffic-audit",source] }
    IO.print result.stdout
    IO.eprint result.stderr
    return result.exitCode
  | _ =>
    if args == ["codex-publication-daemon"] &&
        (← IO.getEnv "EGGSHELL_RESEARCH_IO_HEAP") == some "1" then HeapObservation.initializeObserver
    sourceRouteEngine args
