import Main
import Eggshell.ContractAudit
open Lean Eggshell
#print axioms Numerical.ready_foreign_scope_rejected
#print axioms Numerical.ready_foreign_generation_rejected
#print axioms Numerical.disconnected_admission_refused
#print axioms Numerical.stopped_admission_refused
#print axioms Numerical.expired_admission_refused
#print axioms Plugin.Daemon.received_chunk_decreases
def check (ok : Bool) (message : String) : IO Unit := unless ok do throw (IO.userError message)
def verifyReady (root : System.FilePath) : IO Unit := do
  check (!(← root.pathExists)) "preserve preceding readiness check"
  IO.FS.createDirAll root
  let endpoint : Plugin.Daemon.Endpoint := ⟨"fixture-generation",0,1,"fixture-secret","fixture-generation"⟩
  let generation := "fixture-generation"
  let file := root/"endpoint.json"
  let original ← Numerical.readyEndpoints.get
  try
    Numerical.readyEndpoints.set #[]
    Numerical.rememberReady root.toString generation endpoint
    check ((← Numerical.readyEndpoint? root.toString generation).isSome) "authenticated metadata not retained"
    check ((← Numerical.readyEndpoint? (root/"foreign").toString generation).isNone) "foreign scope accepted"
    check ((← Numerical.readyEndpoint? root.toString "foreign-generation").isNone) "foreign generation accepted"
    IO.FS.writeFile file (toJson endpoint).compress
    check ((← Numerical.publishedReady? root generation).isSome) "exact publication rejected"
    let replacement := {endpoint with secret := "replacement-secret",port := 2}
    IO.FS.writeFile file (toJson replacement).compress
    check ((← Numerical.publishedReady? root generation).isNone && (← Numerical.readyEndpoint? root.toString generation).isNone)
      "replaced publication retained stale hint"
    Numerical.rememberReady root.toString generation replacement
    Numerical.forgetReadyEndpoint endpoint
    check ((← Numerical.publishedReady? root generation).isSome) "old failure invalidated new endpoint"
    IO.FS.removeFile file
    check ((← Numerical.publishedReady? root generation).isNone && (← Numerical.readyEndpoint? root.toString generation).isNone)
      "retired publication retained stale hint"
    for index in [:40] do Numerical.rememberReady s!"scope-{index}" generation endpoint
    check ((← Numerical.readyEndpoints.get).size == 32) "metadata bound exceeded"
    Numerical.forgetReadyScope "scope-39" generation
    check ((← Numerical.readyEndpoint? "scope-39" generation).isNone && (← Numerical.readyEndpoint? "scope-38" generation).isSome)
      "scope retirement affected peer"
    IO.FS.writeFile (root/"report.json") (Json.mkObj [("foreignScopeRejected",toJson true),
      ("foreignGenerationRejected",toJson true),("exactPublishedIdentityRequired",toJson true),
      ("remoteRetirementInvalidatesHint",toJson true),("oldFailurePreservesReplacement",toJson true),
      ("metadataBound",toJson (32 : Nat)),("scopeRetirementPreservesPeer",toJson true),
      ("syntheticMetadataNotAuthenticationTest",toJson true),("answeringModelCalls",toJson (0 : Nat)),
      ("adopted",toJson false)]).pretty
  finally Numerical.readyEndpoints.set original
def verifyPeer : IO Unit := do
  let server ← Std.Async.TCP.Socket.Server.mk
  server.bind (Plugin.Daemon.loopback 0)
  server.listen 1
  let outgoing ← Std.Async.TCP.Socket.Client.mk
  let connecting ← (outgoing.connect (← server.getSockName)).toIO
  let deadline := (← IO.monoMsNow)+2000
  let incoming ← TaskDeadline.run server.accept deadline
  TaskDeadline.wait connecting deadline
  check (← Numerical.withPeerWaiting incoming fun waiting => waiting) "live peer rejected"
  let raised ← try
      let _ : Unit ← Numerical.withPeerWaiting incoming fun waiting => do
        check (← waiting) "peer monitor was not released"
        throw (IO.userError "intentional-peer-callback")
      pure false
    catch error => pure (error.toString.contains "intentional-peer-callback")
  check raised "callback failure changed or monitor was retained"
  let began ← IO.mkRef false
  let observing ← IO.asTask (Numerical.withPeerWaiting incoming fun waiting => do
    check (← waiting) "peer monitor could not be registered again"
    began.set true
    repeat
      if !(← waiting) then return
      unless (← IO.monoMsNow) < deadline do throw (IO.userError "peer EOF was not observed")
      IO.sleep 1) .dedicated
  try
    while !(← began.get) && (← IO.monoMsNow) < deadline do IO.sleep 1
    TaskDeadline.run outgoing.shutdown deadline
    TaskDeadline.wait observing deadline
  finally
    discard <| IO.wait observing

def rawFrame : BlockScore.Frame := {
  raw := .mk (Array.replicate 16 (0 : UInt8)), queries := 1, rows := 1, width := 1
  exact := by decide, bounded := by decide, coverage := #[none]
  sourceReadMs := 0, projectionHits := 0, projectionMisses := 0, retainedBytes := 0 }

def verifyPipe : IO Unit := do
  for (mode,cancelled) in [("--echo-raw",false),("--hold-raw",true),("--hold-raw",false)] do
    let child : Numerical.Kernel ← IO.Process.spawn {
      cmd := (← IO.appPath).toString,args := #[mode],stdin := .piped,stdout := .piped,stderr := .inherit}
    let retired ← IO.mkRef false
    let retire := do
      unless ← retired.get do
        Numerical.stopRaw child
        retired.set true
    try
      if mode == "--echo-raw" then
        let reply ← Numerical.exchangeRaw child rawFrame ((← IO.monoMsNow)+2000) (pure false) retire
        check ((← IO.ofExcept (Json.parse reply)).getObjValD "fixture" == toJson true) "raw pipe response changed"
      else
        let expired ← try
            let _ ← Numerical.exchangeRaw child rawFrame ((← IO.monoMsNow)+(if cancelled then 500 else 20)) (pure cancelled) retire
            pure false
          catch error => pure (error.toString.contains "raw numerical frame expired or was cancelled")
        let process ← IO.Process.output {cmd := "/bin/ps",args := #["-p",toString child.pid,"-o","pid="]}
        check (expired && (← retired.get) && process.stdout.trimAscii.isEmpty) "cancelled raw pipe lost its error or left a live child"
    finally retire

def fixtureKernel (hold : Bool) : IO Unit := do
  if hold then
    repeat IO.sleep 10
  else
    let input ← IO.getStdin
    discard <| input.getLine
    let mut remaining : Nat := 16
    while 0 < remaining do
      let bytes ← input.read remaining.toUSize
      check (!bytes.isEmpty) "raw fixture ended early"
      remaining := remaining-bytes.size
    let output ← IO.getStdout
    output.putStrLn (Json.mkObj [("fixture",toJson true)]).compress
    output.flush

def verifyBackendRetirement : IO Unit := do
  let server ← Std.Async.TCP.Socket.Server.mk
  server.bind (Plugin.Daemon.loopback 0)
  server.listen 1
  let outgoing ← Std.Async.TCP.Socket.Client.mk
  let connecting ← (outgoing.connect (← server.getSockName)).toIO
  let incoming ← TaskDeadline.run server.accept ((← IO.monoMsNow)+2000)
  TaskDeadline.wait connecting ((← IO.monoMsNow)+2000)
  let held : Numerical.Kernel ← IO.Process.spawn {
    cmd := (← IO.appPath).toString,args := #["--hold-raw"],stdin := .piped,stdout := .piped,stderr := .inherit}
  let backend : Numerical.Backend := ⟨← Std.Mutex.new (),← Std.Mutex.new (),← IO.mkRef none,
    ← IO.mkRef (some held),← IO.mkRef 0,← ProjectionCache.Cache.make,← IO.mkRef {},← IO.mkRef 0,← IO.mkRef false⟩
  let vector := "0000000000000000"
  let body := Json.mkObj [("queries",toJson #[vector]),
    ("blockRows",toJson #[BlockScore.Input.projected vector])]
  let expected ← try
      let _ ← backend.scoreBlocks ⟨"fixture",".","."⟩ incoming body.compress ((← IO.monoMsNow)+150)
      pure false
    catch error => pure (error.toString.contains "raw numerical frame expired or was cancelled")
  let process ← IO.Process.output {cmd := "/bin/ps",args := #["-p",toString held.pid,"-o","pid="]}
  check (expected && (← backend.rawChild.get).isNone && process.stdout.trimAscii.isEmpty)
    "backend failure replaced its error or retained a reaped kernel"

def socketPair : IO (Std.Async.TCP.Socket.Client × Std.Async.TCP.Socket.Client) := do
  let server ← Std.Async.TCP.Socket.Server.mk
  server.bind (Plugin.Daemon.loopback 0)
  server.listen 1
  let outgoing ← Std.Async.TCP.Socket.Client.mk
  let connecting ← (outgoing.connect (← server.getSockName)).toIO
  let incoming ← TaskDeadline.run server.accept ((← IO.monoMsNow)+2000)
  TaskDeadline.wait connecting ((← IO.monoMsNow)+2000)
  return (outgoing,incoming)

def verifyOwnedReceive : IO Unit := do
  let (sender,receiver) ← socketPair
  let bytes := ByteArray.mk ((Array.range 70000).map Nat.toUInt8)
  let deadline := (← IO.monoMsNow)+3000
  let receiving ← IO.asTask (Plugin.Daemon.receiveExactly receiver bytes.size deadline) .dedicated
  for offset in [0:bytes.size:4093] do
    TaskDeadline.run (sender.sendAll #[bytes.extract offset (min bytes.size (offset+4093))]) deadline
    IO.sleep 1
  let actual ← TaskDeadline.wait receiving deadline
  check (actual == bytes) "fragmented frame changed original bytes"
  let raised ← try
      let _ : Unit ← Plugin.Daemon.withOwnedReceive receiver 10 fun _ =>
        throw (IO.userError "intentional-read-owner-failure")
      pure false
    catch error => pure (error.toString.contains "intentional-read-owner-failure")
  check raised "read-owner error changed"
  TaskDeadline.run (sender.sendAll #[bytes]) deadline
  check ((← Plugin.Daemon.receiveExactly receiver bytes.size deadline) == bytes) "callback failure retained a read or stole later bytes"
  let (stalledSender,stalledReceiver) ← socketPair
  let stop ← Std.CancellationToken.new
  let stalled ← IO.asTask (Plugin.Daemon.receiveExactly stalledReceiver 100 ((← IO.monoMsNow)+2000) (stop := some stop)) .dedicated
  IO.sleep 5
  stop.cancel
  let cancelled ← try
      let _ ← TaskDeadline.wait stalled ((← IO.monoMsNow)+2000)
      pure false
    catch error => pure (error.toString.contains "daemon receive cancelled")
  check cancelled "receive stop lost its cancellation error"
  discard <| IO.wait stalled
  TaskDeadline.run stalledSender.shutdown ((← IO.monoMsNow)+2000)
  let (deadlineSender,deadlineReceiver) ← socketPair
  let expired ← try
      let _ ← Plugin.Daemon.receiveExactly deadlineReceiver 10 ((← IO.monoMsNow)+20)
      pure false
    catch error => pure (error.toString.contains "deadline expired")
  check expired "owned receive deadline did not retire its read"
  TaskDeadline.run deadlineSender.shutdown ((← IO.monoMsNow)+2000)
  -- Cancellation above belongs to its connection; the live peer still works.
  TaskDeadline.run (sender.sendAll #[bytes]) ((← IO.monoMsNow)+2000)
  check ((← Plugin.Daemon.receiveExactly receiver bytes.size ((← IO.monoMsNow)+2000)) == bytes) "cancelled request affected another peer"
  let (eofSender,eofReceiver) ← socketPair
  TaskDeadline.run eofSender.shutdown ((← IO.monoMsNow)+2000)
  let eof ← try
      let _ ← Plugin.Daemon.receiveExactly eofReceiver 1 ((← IO.monoMsNow)+2000)
      pure false
    catch error => pure (error.toString.contains "closed an incomplete frame")
  check eof "owned receive did not preserve EOF"

def main (args : List String) : IO UInt32 := do
  match args with
  | ["--echo-raw"] => fixtureKernel false; return 0
  | ["--hold-raw"] => fixtureKernel true; return 0
  | [root] =>
    verifyReady (.mk root)
    verifyPeer
    verifyPipe
    verifyBackendRetirement
    verifyOwnedReceive
    IO.FS.writeFile (System.FilePath.mk root/"waits.json") (Json.mkObj [
      ("livePeerAccepted",toJson true),("callbackFailureReleasesRead",toJson true),
      ("peerEofObserved",toJson true),("rawCompletionExact",toJson true),
      ("rawCancellationKillsReapsJoins",toJson true),("fixtureKernelImplementedInLean",toJson true),
      ("rawDeadlineKillsReapsJoins",toJson true),
      ("backendFailurePreservesErrorAndRetiresOnce",toJson true),
      ("ownedReceiveFragmentExact",toJson true),("ownedReceiveCallbackReleases",toJson true),
      ("ownedReceiveCancellationDeadlineEof",toJson true),("ownedReceivePeerUnaffected",toJson true),
      ("answeringModelCalls",toJson (0 : Nat)),("adopted",toJson false)]).pretty
    return 0
  | _ => throw (IO.userError "readiness check root required")
