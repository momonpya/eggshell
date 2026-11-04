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
        check (!pids.contains endpoint.pid) "two chat managers unexpectedly shared an endpoint"
        pids := pids.push endpoint.pid
      for tick in [:3] do
        if tick > 0 then IO.sleep 5000
        for index in [:count] do
          let endpoint ← Daemon.readyEndpoint s!"front-client-{index}"
          check (pids[index]? == some endpoint.pid) "manager ownership changed during the idle observation"
        let state ← IO.ofExcept (Json.parse (← Publication.Client.control "stats"))
        samples := samples.push (Json.mkObj [("managers",toJson count),("tick",toJson tick),
          ("elapsedMs",toJson ((← IO.monoMsNow)-started)),("managerRssKiB",toJson (← managerRss pids)),
          ("preparation",state.getObjValD "preparation"),("operations",state.getObjValD "operations")])
        IO.FS.writeFile (root/"manager-samples.json") ((toJson samples).pretty++"\n")
    for original in originals do
      check ((← DB.PageMap.pin original.directory).head == original.head) "idle managers changed original publications"
  finally
    Daemon.shutdown
    Worker.shutdown
    try let _ ← Publication.Client.control "shutdown" catch _ => pure ()
  for pid in pids do check (!(← Numerical.alive pid)) "manager shutdown left a live process"
  let result := Json.mkObj [("allPassed",toJson true),("nativeManagers",toJson pids.size),
    ("sourceHeadsUnchanged",toJson true),("allManagersExited",toJson true),
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
