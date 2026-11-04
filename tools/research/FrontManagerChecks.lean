import Main

open Lean Eggshell Eggshell.Plugin
namespace Eggshell.Research.FrontManagerChecks

def check (condition : Bool) (message : String) : IO Unit :=
  unless condition do throw (IO.userError message)

def input (root : System.FilePath) : IO PendingTurn := do
  IO.ofExcept (Json.parse (← IO.FS.readFile (root/"captured-turn.json")) >>= fromJson? (α := PendingTurn))

def setup (root : System.FilePath) : IO Unit := do
  let pending ← input root
  let some context ← ProjectContext.open? pending ((← IO.monoMsNow)+30000) |
    throw (IO.userError "manager fixture lost its complete project")
  let some write := context.selection.write | throw (IO.userError "manager fixture has no write project")
  check (write.project.manifest.owners.size == 16) "manager fixture requires sixteen original owners"
  let view ← ProjectStore.pin write.project ((← IO.monoMsNow)+30000)
  let some command := pending.semanticMatcher | throw (IO.userError "actual MiniLM is required")
  for source in view.sources do
    let _ ← Warm.run source command
    pure ()
  let mut rows := #[]
  for index in [:80] do
    let started ← IO.monoMsNow
    let next ← ProjectContext.capture {pending with
      sessionId := s!"front-client-{index}",turnId := "front-turn",
      projectInputs := none,inputBoundary := none,preparedInputs := none,
      tools := [],inFlight := [],finalMessage := none,closed := false} (started+30000)
    check next.preparedInputs.isSome "new chat did not capture a prepared current frame"
    let files ← sessionFiles next.sessionId
    writeJson files.state ({profile := next.profile} : ThreadState)
    writeJson files.pending next
    rows := rows.push (Json.mkObj [("client",toJson index),("captureMs",toJson ((← IO.monoMsNow)-started))])
  IO.FS.writeFile (root/"front-setup.json") ((toJson rows).pretty++"\n")

def managerRss (pids : Array Nat) : IO Nat := do
  let result ← IO.Process.output {cmd := "/bin/ps",args := #["-o","rss=","-p",
    String.intercalate "," (pids.toList.map toString)]}
  check (result.exitCode == 0) "could not observe native manager RSS"
  let rows := result.stdout.splitOn "\n" |>.filterMap (fun row => row.trimAscii.toString.toNat?)
  check (rows.length == pids.size) "a manager disappeared during RSS observation"
  return rows.foldl (·+·) 0

def audit (root : System.FilePath) : IO Unit := do
  let pending ← input root
  let some context ← ProjectContext.open? pending ((← IO.monoMsNow)+30000) |
    throw (IO.userError "manager audit lost its authorized original scope")
  let originals ← context.reads.sources.mapM fun source => DB.PageMap.pin source.directory
  let mut pids : Array Nat := #[]
  let mut samples := #[]
  let started ← IO.monoMsNow
  let _ ← Publication.Client.resolve
  try
    for count in [10,40,80] do
      while pids.size < count do
        let session := s!"front-client-{pids.size}"
        let endpoint ← Daemon.ensure session
        check (pids.isEmpty || pids[0]? == some endpoint.pid) "chat created a second shared frontend"
        pids := pids.push endpoint.pid
      for tick in [:3] do
        if tick > 0 then IO.sleep 5000
        for index in [:count] do
          let endpoint ← Daemon.readyEndpoint s!"front-client-{index}"
          check (pids[index]? == some endpoint.pid) "manager ownership changed during the idle observation"
        let state ← IO.ofExcept (Json.parse (← Publication.Client.control "stats"))
        let endpoint ← Daemon.readyEndpoint "front-client-0"
        let frontend ← IO.ofExcept (Json.parse (← Daemon.exchange endpoint "stats"))
        check (frontend.getObjValD "registeredSessions" == toJson count) "frontend lost a registered chat"
        let active ← IO.ofExcept (frontend.getObjValAs? Nat "activeMaintenance")
        check (active ≤ HookBudget.maintenance) "frontend exceeded its maintenance bound"
        let bytes ← IO.ofExcept (frontend.getObjValAs? Nat "requestBytes")
        check (bytes ≤ HookBudget.bytes) "frontend exceeded its admitted byte bound"
        samples := samples.push (Json.mkObj [("managers",toJson count),("tick",toJson tick),
          ("elapsedMs",toJson ((← IO.monoMsNow)-started)),("managerRssKiB",toJson (← managerRss pids.toList.eraseDups.toArray)),
          ("nativeManagers",toJson pids.toList.eraseDups.length),("frontend",frontend),
          ("preparation",state.getObjValD "preparation"),("operations",state.getObjValD "operations")])
        IO.FS.writeFile (root/"manager-samples.json") ((toJson samples).pretty++"\n")
    for original in originals do
      check ((← DB.PageMap.pin original.directory).head == original.head) "idle managers changed original publications"
    let endpoint ← Daemon.readyEndpoint "front-client-0"
    let clocks := (List.range 80).map fun i => Daemon.chatClock endpoint.secret s!"front-client-{i}"
    check (clocks.eraseDups.length == 80) "shared frontend merged independent chat clock domains"
    for kind in ["hook","ack"] do
      let (reply,stop) ← Daemon.serveRequest "front-client-0" endpoint.secret
        (Daemon.request endpoint.secret kind (Json.mkObj [("session_id",toJson "front-client-1")]))
      check (reply.getObjValD "ok" == toJson false && !stop) "wrong-chat input was admitted"
    let rejected ← try
      let _ ← Daemon.exchange {endpoint with secret := "invalid"} "register"
        (Json.mkObj [("session_id",toJson "unauthorized-chat")])
      pure false
    catch _ => pure true
    check rejected "frontend admitted an unauthenticated chat"
    -- A peer that sends only part of its header must not keep shutdown alive.
    let stalled ← Daemon.connect endpoint
    (stalled.send (ByteArray.mk #[0])).block
    IO.sleep 20
    let shutdownStarted ← IO.monoMsNow
    try Daemon.shutdown
    catch error =>
      let _ ← IO.Process.output {cmd := "/usr/bin/sample",args := #[toString endpoint.pid,"1","1",
        "-file",(root/"shutdown.sample").toString]}
      throw error
    let shutdownMs := (← IO.monoMsNow)-shutdownStarted
    discard <| stalled.getSockName
    IO.FS.writeFile (root/"shutdown-check.json") ((Json.mkObj [
      ("partialHeaderPeer",toJson true),("shutdownMs",toJson shutdownMs),
      ("clockDomains",toJson clocks.eraseDups.length),("wrongChatRejected",toJson true),
      ("unauthorizedRejected",toJson rejected)]).pretty++"\n")
  finally
    Daemon.shutdown
    Worker.shutdown
    try let _ ← Publication.Client.control "shutdown" catch _ => pure ()
  for pid in pids.toList.eraseDups do check (!(← Numerical.alive pid)) "manager shutdown left a live process"
  let result := Json.mkObj [("allPassed",toJson true),("logicalClients",toJson pids.size),
    ("nativeManagers",toJson pids.toList.eraseDups.length),
    ("sourceHeadsUnchanged",toJson true),("allManagersExited",toJson true),
    ("partialHeaderShutdown",toJson true),("clockDomains",toJson (80 : Nat)),
    ("wrongChatRejected",toJson true),("unauthorizedRejected",toJson true),
    ("idleOnly",toJson true),("fullHookOrSustainedCapacity",toJson false),
    ("answeringModelCalls",toJson (0 : Nat)),("adopted",toJson false)]
  IO.FS.writeFile (root/"manager-report.json") (result.pretty++"\n")
  IO.println result.compress

end Eggshell.Research.FrontManagerChecks

def main (args : List String) : IO UInt32 := do
  match args with
  | ["front-setup",root] => Numerical.withDefaultKeeper (do
      Eggshell.Research.FrontManagerChecks.setup (.mk root); return 0) (drainMs := 1000)
  | ["front-managers",root] => Numerical.withDefaultKeeper (do
      Eggshell.Research.FrontManagerChecks.audit (.mk root); return 0) (drainMs := 1000)
  | other => sourceRouteEngine other
