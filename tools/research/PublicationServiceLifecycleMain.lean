import Eggshell.PublicationClient

open Lean Eggshell Eggshell.Plugin Eggshell.Synapses
open Eggshell.Plugin.Publication

private def check (condition : Bool) (message : String) : IO Unit :=
  unless condition do throw (IO.userError message)

private abbrev Child := IO.Process.Child {stdin := .null,stdout := .null,stderr := .inherit}

private def start (product : String) : IO (Child × Daemon.Endpoint) := do
  let child ← IO.Process.spawn {
    cmd := product,args := #["codex-publication-daemon"]
    stdin := .null,stdout := .null,stderr := .inherit}
  let deadline := (← IO.monoMsNow)+10000
  repeat
    check (← child.tryWait).isNone "lifecycle publisher exited during startup"
    if let some endpoint ← Client.endpoint? then
      check (endpoint.pid == child.pid.toNat) "lifecycle found a foreign publisher"
      let _ ← Daemon.exchange endpoint "ping" (budget := 1000)
      return (child,endpoint)
    check ((← IO.monoMsNow) < deadline) "lifecycle publisher startup expired"
    IO.sleep 5
  throw (IO.userError "unreachable")

private def stop (child : Child) (endpoint : Daemon.Endpoint) : IO Nat := do
  let started ← IO.monoMsNow
  IO.println s!"request shutdown {endpoint.pid}"
  let _ ← Daemon.exchange endpoint "shutdown" (budget := 5000)
  IO.println s!"shutdown acknowledged {endpoint.pid}"
  repeat
    if let some code ← child.tryWait then
      IO.println s!"publisher exited {endpoint.pid}: {code}"
      check (code == 0 && (← Client.endpoint?).isNone) "publisher retained its endpoint or failed on shutdown"
      return (← IO.monoMsNow)-started
    check ((← IO.monoMsNow) < started+10000) "active source commit prevented bounded shutdown"
    IO.sleep 5
  throw (IO.userError "unreachable")

private def input (index : Nat) : Capsule := {
  session := s!"lifecycle-{index}",turn := "turn",cwd := "/fixture",work := "inspect original evidence"
  checkpoint := true,finalMessage := none
  tools := #[⟨"mcp__records__lookup","lookup",(Json.mkObj [("id",toJson index)]).compress,
    (Json.mkObj [("id",toJson index),("body",toJson (String.ofList (List.replicate 50000 'x')))]).compress,none⟩]
  timing := #[Timing.interval ⟨Sha256.hex "publication-lifecycle".toUTF8,10,20,some 1000⟩] }

private def present (source : DB.PageMap.Snapshot) (capsule : Capsule) : IO Bool := do
  let some tool := capsule.tools[0]? | throw (IO.userError "missing lifecycle source")
  let owner := (compileOperationOutcomes (.text capsule.session) (.text capsule.turn) tool).2
  let some edge := OutcomeEdge.fromValue? owner | throw (IO.userError "invalid lifecycle edge")
  let some origin ← Provenance.lookup? source edge ⟨capsule.session,capsule.turn,tool.useId⟩ | return false
  let reader ← Persistence.Store.NodeReader.new source
  let document ← Provenance.checkedDocument reader origin
  check (document.source == some (canonicalJson tool.response) && document.workText == some (canonicalToolWork tool))
    "shutdown left a partial original or mismatched interval"
  return true

private def trial (product : String) (root : System.FilePath) : IO Unit := do
  check (!(← root.pathExists)) "keep existing lifecycle evidence"
  IO.FS.createDir root
  let path := root / "source.egg"
  let source ← Persistence.ensureSnapshot path
  let (child,endpoint) ← start product
  let stillRunning ← IO.mkRef true
  try
    let project ← Client.register endpoint path source.head.identity
    let initialAck ← Client.submit endpoint project (input 0)
    check initialAck.complete "initial lifecycle source ACK is incomplete"
    let admitted ← IO.mkRef false
    let inputs := (Array.range 80).map input
    let tasks ← inputs.mapM fun capsule => IO.asTask (do
      while !(← admitted.get) do IO.sleep 1
      try pure (some (← Client.submit endpoint project capsule)) catch _ => pure none) .dedicated
    admitted.set true
    let deadline := (← IO.monoMsNow)+5000
    let mut active := Json.null
    repeat
      let statistics ← Daemon.exchange endpoint "stats" >>= fun text => IO.ofExcept (Json.parse text)
      let work ← IO.ofExcept (statistics.getObjValAs? Nat "active")
      let queued ← IO.ofExcept (statistics.getObjValAs? Nat "queued")
      if work > 0 && queued > 0 then
        active := statistics
        break
      check ((← IO.monoMsNow) < deadline) "lifecycle never exercised active and queued source requests"
      IO.sleep 1
    IO.FS.writeFile (root / "before-shutdown.json") active.pretty
    let shutdownMs ← stop child endpoint
    stillRunning.set false
    IO.println "collecting interrupted replies"
    let replies ← tasks.mapM fun task => IO.ofExcept (task.get.mapError IO.Error.toString)
    let after ← DB.PageMap.pin path
    let mut acknowledged := 0
    let mut durable := 0
    for (capsule,reply) in inputs.zip replies do
      let stored ← present after capsule
      if stored then durable := durable+1
      let acknowledgedHere := capsule.session == "lifecycle-0" || reply.isSome
      if acknowledgedHere then
        acknowledged := acknowledged+1
        check (stored && reply.all (·.complete)) "shutdown lost an acknowledged original"
    check (acknowledged > 0) "shutdown acknowledgement check is vacuous"
    check ((← Provenance.records after).size == durable && durable ≤ inputs.size)
      "shutdown changed native occurrence accounting"
    let (restarted,fresh) ← start product
    IO.println s!"publisher restarted {fresh.pid}"
    try
      let registered ← Client.register fresh path source.head.identity
      let rejected ← try let _ ← Client.submit fresh project (input 0); pure false catch _ => pure true
      check rejected "a previous process capability survived service restart"
      let retry ← inputs.mapM fun capsule => IO.asTask (Client.submit fresh registered capsule) .dedicated
      for task in retry do
        let receipt ← IO.ofExcept (task.get.mapError IO.Error.toString)
        check receipt.complete "source retry did not complete after restart"
      let recovered ← DB.PageMap.pin path
      check ((← Provenance.records recovered).size == 80) "restart/retry lost or duplicated original observations"
      for capsule in inputs do check (← present recovered capsule) "restart lost complete original bytes"
      IO.FS.writeFile (root / "result.json") (Json.mkObj [
        ("clients",toJson inputs.size),("shutdownMs",toJson shutdownMs),
        ("acknowledgedBeforeShutdown",toJson acknowledged),("durableBeforeRetry",toJson durable),
        ("acknowledgedOriginalLoss",toJson (0 : Nat)),("retryDurable",toJson (80 : Nat)),
        ("retryDuplicates",toJson (0 : Nat)),("oldCapabilityRejected",toJson true),
        ("actualNetworkOrNas",toJson false),("answeringModelCalls",toJson (0 : Nat))]).pretty
    finally let _ ← stop restarted fresh; pure ()
  finally
    if ← stillRunning.get then
      try let _ ← stop child endpoint; pure ()
      catch error =>
        IO.eprintln s!"lifecycle cleanup: {error}"
        try child.kill catch _ => pure ()
        try let _ ← child.wait; pure () catch _ => pure ()

def main (args : List String) : IO UInt32 := do
  try
    let [candidate,label] := args | throw (IO.userError "PublicationServiceLifecycleMain CANDIDATE LABEL")
    trial (candidate ++ "/product") (System.FilePath.mk candidate / (label ++ "-fixtures"))
    return 0
  catch error => IO.eprintln error.toString; return 1
