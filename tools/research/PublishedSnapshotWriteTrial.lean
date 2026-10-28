import Eggshell.PublicationClient
import Std.Sync.Mutex
import tools.research.PublicationServiceContract

open Lean Eggshell Eggshell.Plugin Eggshell.Synapses
open Eggshell.Plugin.Publication

private def check (condition : Bool) (message : String) : IO Unit :=
  unless condition do throw (IO.userError message)

private def transaction (path : System.FilePath) (client bytes : Nat) : PendingTurn := {
  sessionId := s!"client-{client}",turnId := "turn",cwd := path.parent.get!.toString
  prompt := "inspect persisted evidence",profile := "PRIVATE_PROFILE_CANARY",semanticMatcher := none
  read := ["PRIVATE_READ_PATH_CANARY"],write := some path.toString,handoffChars := 120000,projection := .none
  tools := [{
    name := "mcp__records__lookup"
    useId := "lookup"
    input := (Json.mkObj [("record",toJson s!"RECORD_{client}")]).compress
    response := (Json.mkObj [("id",toJson s!"RECORD_{client}"),
      ("body",toJson (String.ofList (List.replicate bytes 'x')))]).compress}] }

private def capsule (pending : PendingTurn) (path : System.FilePath) : IO Capsule := do
  let prepared ← NativePublication.prepare pending path true
  let input := Capsule.ofPrepared prepared
  let serialized := (toJson input).compress
  check ((serialized.splitOn "PRIVATE_PROFILE_CANARY").length == 1 &&
    (serialized.splitOn "PRIVATE_READ_PATH_CANARY").length == 1)
    "publication wire leaked private scheduling state"
  let interval : NativePublication.Interval := ⟨Sha256.hex "publication-service-trial".toUTF8,10,20,some 1010⟩
  return {input with timing := input.tools.map (fun _ => Timing.interval interval)}

private def originals (snapshot : DB.PageMap.Snapshot) (pending : PendingTurn) : IO Unit := do
  let reader ← Persistence.Store.NodeReader.new snapshot
  for tool in pending.tools do
    let occurrence : Occurrence := ⟨pending.sessionId,pending.turnId,tool.useId⟩
    let owner := (compileOperationOutcomes (.text pending.sessionId) (.text pending.turnId) tool).2
    let some edge := OutcomeEdge.fromValue? owner | throw (IO.userError "invalid native source")
    let some origin ← Provenance.lookup? snapshot edge occurrence |
      throw (IO.userError "source ACK lost its original interval")
    let doc ← Provenance.checkedDocument reader origin
    check (doc.source == some (canonicalJson tool.response) && doc.workText == some (canonicalToolWork tool))
      "source ACK differs from its original complete bytes"

private def rejection (action : IO α) : IO Unit := do
  let rejected ← try let _ ← action; pure false catch _ => pure true
  check rejected "unauthorized or malformed publication was accepted"

private def scenario (endpoint : Daemon.Endpoint) (root : System.FilePath)
    (databases clients bytes : Nat) : IO Json := do
  let directory := root / s!"db-{databases}-clients-{clients}-bytes-{bytes}"
  IO.FS.createDir directory
  let paths := (Array.range databases).map fun index => directory / s!"project-{index}.egg"
  let projects ← paths.mapM fun path => do
    let source ← Persistence.ensureSnapshot path
    Client.register endpoint path source.head.identity
  let turns := (Array.range clients).map fun client => transaction paths[client%databases]! client bytes
  let inputs ← (turns.zipIdx).mapM fun (pending,index) => capsule pending paths[index%databases]!
  let started ← IO.monoMsNow
  let tasks ← (inputs.zipIdx).mapM fun (input,index) => IO.asTask (do
    let before ← IO.monoMsNow
    let some project := projects[index%databases]? | throw (IO.userError "missing test project")
    let receipt ← Client.submit endpoint project input
    check receipt.complete "publication did not account for its original timing"
    return (receipt,(← IO.monoMsNow)-before)) .dedicated
  let mut maxActive := 0
  while (← tasks.anyM fun task => return !(← IO.hasFinished task)) do
    let state ← IO.ofExcept (Json.parse (← Daemon.exchange endpoint "stats" (budget := 1000)))
    maxActive := max maxActive ((state.getObjValAs? Nat "active").toOption.getD 0)
    IO.sleep 2
  let replies ← tasks.mapM fun task => IO.ofExcept (task.get.mapError IO.Error.toString)
  let elapsed := (← IO.monoMsNow)-started
  let mut count := 0
  for (path,index) in paths.zipIdx do
    let source ← DB.PageMap.pin path
    count := count+(← Provenance.records source).size
    for (pending,client) in turns.zipIdx do
      if client%databases == index then originals source pending
  check (replies.size == clients && count == clients) "service lost an acknowledged original"
  let heads ← paths.mapM (fun path => return (← DB.PageMap.pin path).head)
  for (input,index) in inputs.zipIdx do
    let some project := projects[index%databases]? | throw (IO.userError "missing retry project")
    let reply ← Client.submit endpoint project input
    check (some reply.head == heads[index%databases]?) "ACK-loss retry duplicated its source publication"
  let statistics ← Daemon.exchange endpoint "stats" >>= fun text => IO.ofExcept (Json.parse text)
  check ((← IO.ofExcept (statistics.getObjValAs? Nat "queued")) == 0 &&
    (← IO.ofExcept (statistics.getObjValAs? Nat "admittedBytes")) == 0) "service retained completed jobs"
  check ((← IO.ofExcept (statistics.getObjValAs? Nat "publishedReplies")) ≥ clients*2)
    "service did not account for committed source replies"
  if databases > 1 then check (maxActive > 1) "independent project commits were globally serialized"
  let sorted := replies.map Prod.snd |>.qsort (· < ·)
  return Json.mkObj [("databases",toJson databases),("clients",toJson clients),
    ("payloadBytes",toJson bytes),("submitElapsedMs",toJson elapsed),
    ("maxReplyMs",toJson (replies.foldl (fun maximum row => max maximum row.2) 0)),
    ("p95ReplyMs",toJson sorted[((clients*95+99)/100)-1]!),
    ("maxActivePublications",toJson maxActive),("warmInAckPath",toJson false),
    ("accepted",toJson replies.size),("acknowledgedOriginalLoss",toJson (0 : Nat)),
    ("retryDuplicates",toJson (0 : Nat)),("servicePid",toJson endpoint.pid),
    ("transport",toJson "loopback TCP"),("actualNetworkOrNas",toJson false),
    ("answeringModelCalls",toJson (0 : Nat))]

private def negatives (endpoint : Daemon.Endpoint) (root : System.FilePath) : IO Json := do
  let path := root / "negative.egg"
  let initial ← Persistence.ensureSnapshot path
  let project ← Client.register endpoint path initial.head.identity
  let pending := transaction path 0 128
  let input ← capsule pending path
  rejection (Client.submit endpoint {project with capability := Sha256.hex "wrong".toUTF8} input)
  rejection (Client.submit endpoint {project with database := Sha256.hex "foreign".toUTF8} input)
  let projectPeer := {endpoint with secret := project.capability}
  rejection (Daemon.exchange projectPeer "shutdown" (budget := 1000))
  rejection (Daemon.exchange projectPeer "register" (Json.mkObj [
    ("directory",toJson path.toString),("database",toJson initial.head.identity)]) (budget := 1000))
  rejection (Client.submit endpoint project {input with tools := input.tools++input.tools,timing := input.timing++input.timing})
  rejection (Client.submit endpoint project {input with timing := #[.interval ⟨"bad",20,10,none⟩]})
  let oversized ← Daemon.connect endpoint
  let declared : ByteArray := .mk #[0,128,0,1]
  (oversized.sendAll #[declared]).block
  let response ← Daemon.receiveFrame oversized 1000
  let response ← IO.ofExcept (Json.parse (String.fromUTF8! response))
  check (response.getObjValD "ok" == false) "oversized transport frame was admitted"
  let incomplete ← Daemon.connect endpoint
  (incomplete.sendAll #[ByteArray.mk #[0,0,4,0],"partial".toUTF8]).block
  incomplete.shutdown.block
  let response ← Daemon.receiveFrame incomplete 1000
  let response ← IO.ofExcept (Json.parse (String.fromUTF8! response))
  check (response.getObjValD "ok" == false) "incomplete frame was admitted"
  check ((← DB.PageMap.pin path).head == initial.head) "rejected request changed source publication"
  let first ← Client.submit endpoint project input
  let again ← Client.submit endpoint project input
  check (first.head == again.head) "lost ACK retry changed its source head"
  originals (← DB.PageMap.pin path) pending
  let different : NativePublication.Interval := ⟨Sha256.hex "publication-service-trial".toUTF8,11,21,some 1011⟩
  let conflicting := {input with timing := #[.interval different]}
  let neighbours ← (Array.range 12).mapM fun index => capsule (transaction path (index+1) 5000) path
  let start ← IO.mkRef false
  let bad ← IO.asTask (do
    while !(← start.get) do IO.sleep 1
    rejection (Client.submit endpoint project conflicting)) .dedicated
  let good ← neighbours.mapM fun input => IO.asTask (do
    while !(← start.get) do IO.sleep 1
    let receipt ← Client.submit endpoint project input
    check receipt.complete "valid neighbour was discarded with an invalid group") .dedicated
  start.set true
  let _ ← IO.ofExcept (bad.get.mapError IO.Error.toString)
  for task in good do let _ ← IO.ofExcept (task.get.mapError IO.Error.toString); pure ()
  let after ← DB.PageMap.pin path
  check ((← Provenance.records after).size == 13) "fault isolation omitted or partially published an observation"
  for index in [:12] do originals after (transaction path (index+1) 5000)
  -- A project capability cannot continue writing after the directory has
  -- been replaced by a different DB identity.
  IO.FS.rename path (root / "negative-retired.egg")
  let replacement ← Persistence.ensureSnapshot path
  rejection (Client.submit endpoint project input)
  check ((← DB.PageMap.pin path).head == replacement.head) "old capability wrote into a replacement DB"
  return Json.mkObj [("wrongCapability",toJson true),("foreignDatabase",toJson true),
    ("projectCannotAdminister",toJson true),("duplicateOccurrenceRejected",toJson true),
    ("invalidTimingRejected",toJson true),("noRejectedPublication",toJson true),
    ("lostAckRetryIdempotent",toJson true),("conflictingNeighbourIsolation",toJson true),
    ("replacementDatabaseUnchanged",toJson true),("oversizedFrameRejected",toJson true),
    ("incompleteFrameRejected",toJson true)]

private def endpoint (child : IO.Process.Child {stdin := .null,stdout := .null,stderr := .inherit}) : IO Daemon.Endpoint := do
  let deadline := (← IO.monoMsNow)+10000
  repeat
    check (← child.tryWait).isNone "publication daemon exited during startup"
    if let some current ← Client.endpoint? then
      check (current.pid == child.pid.toNat) "trial found another publisher"
      let _ ← Daemon.exchange current "ping" (budget := 1000)
      return current
    check ((← IO.monoMsNow) < deadline) "publisher startup expired"
    IO.sleep 5
  throw (IO.userError "unreachable")

def main (args : List String) : IO UInt32 := do
  try
    let (binary,output,profile) ← match args with
      | [binary,output] => pure (binary,output,false)
      | [binary,output,"profile"] => pure (binary,output,true)
      | _ => throw (IO.userError "PublishedSnapshotWriteTrial PRODUCT NEW-OUTPUT [profile]")
    let root := System.FilePath.mk output
    check (root.isAbsolute && !(← root.pathExists)) "new trial directory required"
    IO.FS.createDir root
    let child ← IO.Process.spawn {
      cmd := binary,args := #["codex-publication-daemon"]
      stdin := .null,stdout := .null,stderr := .inherit}
    let service ← endpoint child
    try
      let errors ← if profile then pure Json.null else negatives service root
      IO.FS.writeFile (root / "negatives.json") errors.pretty
      let mut reports := #[]
      for bytes in (if profile then #[50000] else #[5000,50000]) do
        for databases in (if profile then #[1] else #[1,16]) do
          for clients in #[80] do
            let result ← scenario service root databases clients bytes
            reports := reports.push result
            IO.FS.writeFile (root / "results.json") (toJson reports).pretty
            IO.println result.compress
            (← IO.getStdout).flush
      IO.FS.writeFile (root / "service-stats.json") (← Daemon.exchange service "stats")
    finally
      let start ← IO.monoMsNow
      let _ ← Daemon.exchange service "shutdown" (budget := 5000)
      let deadline := (← IO.monoMsNow)+5000
      let mut exit := none
      repeat
        if let some code ← child.tryWait then
          exit := some code.toNat
          break
        check ((← IO.monoMsNow) < deadline) "publisher shutdown exceeded five seconds"
        IO.sleep 5
      IO.FS.writeFile (root / "shutdown.json") (Json.mkObj [
        ("elapsedMs",toJson ((← IO.monoMsNow)-start)),("pid",toJson service.pid),
        ("exitCode",toJson exit),("endpointRemoved",toJson (← Client.endpoint?).isNone)]).pretty
    return 0
  catch error => IO.eprintln error.toString; return 1
