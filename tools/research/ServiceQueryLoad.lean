import Eggshell.PublicationClient
import Eggshell.PublicationService
import Eggshell.Daemon

open Lean Eggshell Eggshell.Plugin Std Async TCP
namespace Eggshell.Research.ServiceQueryLoad

private def check (value : Bool) (message : String) : IO Unit :=
  unless value do throw (IO.userError message)

/-- Capabilities stay in memory only. Persisted replay examples deliberately
have no Access, SourceReference or Endpoint field. -/
structure Captured where
  sources : Array Synapses.SourceViewBatch.Request
  query : Json
  choice : Json

structure Example where
  heads : Array DB.PageMap.Head
  owners : Array (Array String)
  query : Json
  choice : Json
  deriving ToJson,FromJson

def Captured.example (capture : Captured) : Example := {
  heads := capture.sources.map (·.access.source),owners := capture.sources.map (·.owners)
  query := capture.query,choice := capture.choice }

structure Proxy where
  actual : Daemon.Endpoint
  endpoint : Daemon.Endpoint
  stopping : IO.Ref Bool
  captures : Std.Mutex (Array Captured)
  task : Task (Except IO.Error Unit)

private def forward (actual : Daemon.Endpoint) (captures : Std.Mutex (Array Captured))
    (client : Socket.Client) : IO Unit := do
  let deadline := (← IO.monoMsNow)+31000
  let request ← Daemon.receiveFrameBefore client deadline
  let some requestText := String.fromUTF8? request | throw (IO.userError "invalid request UTF-8")
  let input ← IO.ofExcept (Json.parse requestText)
  let upstream ← Daemon.connect actual
  Daemon.sendFrame upstream request
  let first ← Daemon.receiveFrameBefore upstream deadline
  Daemon.sendFrame client first
  let some headerText := String.fromUTF8? first | throw (IO.userError "invalid reply UTF-8")
  let header ← IO.ofExcept (Json.parse headerText)
  let size := (header.getObjValAs? Nat "bytes").toOption
  let capture := (input.getObjValAs? String "kind").toOption == some "source-plan"
  let mut body := ByteArray.empty
  if let some size := size then
    check (size ≤ Publication.Stream.maxBytes) "proxy refuses an oversized stream"
    let mut received := 0
    while received < size do
      let part ← Daemon.receiveFrameBefore upstream deadline
      check (!part.isEmpty && received+part.size ≤ size) "proxy saw an invalid stream extent"
      received := received+part.size
      Daemon.sendFrame client part
      if capture then body := body ++ part
  if capture && size.isSome then
    let some bodyText := String.fromUTF8? body | throw (IO.userError "invalid selection reply")
    let reply ← IO.ofExcept (Json.parse bodyText)
    let payload := input.getObjValD "payload"
    let sources ← IO.ofExcept (payload.getObjValAs? (Array Synapses.SourceViewBatch.Request) "sources")
    let query ← IO.ofExcept (payload.getObjVal? "selector")
    let choice ← IO.ofExcept (reply.getObjVal? "choice")
    captures.atomically (modify (·.push ⟨sources,query,choice⟩))

def start : IO Proxy := do
  let some actual ← Publication.Client.endpoint? | throw (IO.userError "no owned publisher to observe")
  let socket ← Socket.Server.mk
  socket.bind (Daemon.loopback 0)
  socket.listen 128
  socket.noDelay
  let address ← socket.getSockName
  let endpoint := {actual with port := address.port.toNat}
  let stopping ← IO.mkRef false
  let captures ← Std.Mutex.new #[]
  let task ← IO.asTask (do
    let mut clients : List (Task (Except IO.Error Unit)) := []
    try
      while !(← stopping.get) do
        match ← socket.tryAccept with
        | none => IO.sleep 1
        | some client => clients := (← IO.asTask (forward actual captures client) .dedicated) :: clients
        clients ← Daemon.retainRunning clients
    finally
      for client in clients do
        if let .error error ← IO.wait client then IO.eprintln s!"query capture relay: {error}") .dedicated
  writeJson ((← Publication.directory) / "endpoint.json") endpoint
  return ⟨actual,endpoint,stopping,captures,task⟩

def Proxy.stop (proxy : Proxy) : IO Unit := do
  let path := (← Publication.directory) / "endpoint.json"
  if let some current ← Publication.Client.endpoint? then
    if current.port == proxy.endpoint.port && current.secret == proxy.actual.secret then writeJson path proxy.actual
  proxy.stopping.set true
  IO.ofExcept (← IO.wait proxy.task)

private def runClient (actual : Daemon.Endpoint) (capture : Captured) (index : Nat) : IO Json := do
  let started ← IO.monoMsNow
  let deadline := started+29000
  let mut phase := "palette"
  let mut paletteMs := 0
  let mut selectionMs := 0
  let mut exact := false
  let outcome : Except String Unit ← try
    let references := capture.sources.map fun source =>
      (({endpoint := {actual with secret := source.access.capability},access := source.access}
        : Publication.Client.SourceReference),source.owners)
    let batch ← Publication.Client.sourcePalettes references deadline
    paletteMs := (← IO.monoMsNow)-started
    try
      phase := "selection"
      let before ← IO.monoMsNow
      let choice ← batch.select capture.query deadline
      selectionMs := (← IO.monoMsNow)-before
      check (choice == capture.choice) "concurrent service changed the actual hook's exact selection"
      exact := true
      phase := "release"
      pure (.ok ())
    finally batch.release deadline
  catch error => pure (.error error.toString)
  return Json.mkObj [("client",toJson index),("elapsedMs",toJson ((← IO.monoMsNow)-started)),
    ("paletteMs",toJson paletteMs),("selectionMs",toJson selectionMs),("lastPhase",toJson phase),
    ("exactChoice",toJson exact),("completed",toJson outcome.isOk),
    ("error",match outcome with | .ok _ => Json.null | .error e => toJson e)]

def phase (actual : Daemon.Endpoint) (captures : Array Captured) (count : Nat) : IO Json := do
  let ready ← Std.Mutex.new (0 : Nat)
  let release ← IO.mkRef false
  let mut clients := #[]
  for index in [:count] do
    let some capture := captures[index%captures.size]? | throw (IO.userError "no captured actual query")
    clients := clients.push (← IO.asTask (do
      ready.atomically (modify (·+1))
      while !(← release.get) do IO.sleep 1
      runClient actual capture index) .dedicated)
  let barrier := (← IO.monoMsNow)+5000
  while (← ready.atomically get) < count do
    check ((← IO.monoMsNow) < barrier) "native client launch barrier expired"
    IO.sleep 1
  release.set true
  let results ← clients.mapM fun task => do IO.ofExcept (← IO.wait task)
  let times := (results.map fun value => (value.getObjValAs? Nat "elapsedMs").toOption.getD 0).qsort (· < ·)
  let statistics ← try
      IO.ofExcept (Json.parse (← Daemon.exchange actual "stats" (budget := 1000)))
    catch error => pure (Json.mkObj [("error",toJson error.toString)])
  return Json.mkObj [("clients",toJson count),("requests",toJson results),
    ("successes",toJson (results.filter (fun value => value.getObjValD "completed" == toJson true)).size),
    ("p50Ms",toJson (times[count/2]?.getD 0)),("sampleMaximumMs",toJson (times.back?.getD 0)),
    ("serviceStats",statistics)]

def Proxy.load (proxy : Proxy) (root : System.FilePath) (expected : Nat)
    (counts : Array Nat := #[1,4,16,40,80]) (saveFixture : Bool := false) : IO Unit := do
  let observed ← proxy.captures.atomically get
  check (observed.size == expected && expected == 6) "must capture both ordinary chats for every topic"
  let mut captures : Array Captured := #[]
  let mut seen : Std.HashMap String Json := {}
  for capture in observed do
    let key := (toJson (Synapses.SourceViewBatch.key capture.sources,capture.query)).compress
    if let some previous := seen[key]? then
      check (previous == capture.choice) "repeated actual hook changed its selection for an identical query"
    else
      captures := captures.push capture
      seen := seen.insert key capture.choice
  check (captures.size == 3) "three repeated topic queries must give exactly three immutable selector inputs"
  if saveFixture then
    writeJson (root / "selector-fixture.json") (captures.map Captured.example)
  let identities := captures.map fun capture => Json.mkObj [
    ("sourceIdentities",toJson (capture.sources.map (·.access.identity))),
    ("owners",toJson (capture.sources.map (·.owners))),
    ("querySha256",toJson (Sha256.hex capture.query.compress.toUTF8)),
    ("choiceSha256",toJson (Sha256.hex capture.choice.compress.toUTF8)),
    ("queryBytes",toJson capture.query.compress.utf8ByteSize),
    ("choiceBytes",toJson capture.choice.compress.utf8ByteSize)]
  writeJson (root / "captured-queries.json") identities
  let mut results := #[]
  for count in counts do
    check (0 < count && count ≤ 80) "invalid service load client count"
    results := results.push (← phase proxy.actual captures count)
    writeJson (root / "service-load.json") (Json.mkObj [("phases",toJson results),
      ("source",toJson "actual LLVM topic 1/2/3 hook selection requests"),
      ("answeringModelCalls",toJson (0 : Nat)),("embeddingCallsDuringReplay",toJson (0 : Nat)),
      ("fullHookConcurrency",toJson false),("eightHourLoad",toJson false)])

end Eggshell.Research.ServiceQueryLoad
