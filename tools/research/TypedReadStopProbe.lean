import Eggshell.Daemon
open Lean Eggshell Eggshell.Plugin
def check (ok : Bool) (message : String) : IO Unit := unless ok do throw (IO.userError message)
def ownedRows (engine : String) : IO (Array String) := do
  let rows ← IO.Process.output {cmd := "/bin/ps",args := #["-axo","pid=,ppid=,stat=,args="]}
  check (rows.exitCode == 0) "cannot inspect stop probe processes"
  let own := toString (← IO.Process.getPID)
  return ((rows.stdout.splitOn "\n").filter (fun row => (row.contains engine || row.contains "worker-cpu-target/bin/eggshelld") &&
    ((row.trimAscii.toString.splitOn " ").headD "") != own)).toArray
def probe (root : System.FilePath) (engine : String) (parallel : Bool := false) (dropReply : Bool := false) : IO Unit := do
  check (!(← root.pathExists)) "fresh stop probe result required"
  IO.FS.createDirAll root
  let endpoint ← Daemon.ensure "cpu-wave-a-0"
  let register := fun index => do
    let name := if index < 16 then "cpu-wave-a-"++toString index else if index < 32 then
      "cpu-wave-b-"++toString index else "stop-probe-"++toString index
    discard <| Daemon.exchange endpoint "register" (Json.mkObj [("session_id",toJson name)]) (budget := 5000)
  if parallel then
    let tasks ← (Array.range 80).mapM fun index => IO.asTask (register index) .dedicated
    for task in tasks do IO.ofExcept (← IO.wait task)
  else for index in [:32] do register index
  let status ← Daemon.exchange endpoint "stats"
  let before ← ownedRows engine
  if dropReply then
    let dropped ← IO.Process.output {cmd := (← IO.appPath).toString,args := #["send-stop"]}
    check (dropped.exitCode == 0) "shutdown sender failed before closing its socket"
  let started ← IO.monoMsNow
  let stopping ← IO.asTask (do
    let output ← IO.Process.output {cmd := engine,args := #["codex-daemon","shutdown"]}
    return (output,(← IO.monoMsNow)-started)) .dedicated
  IO.sleep 1000
  let sample ← if !(← IO.hasFinished stopping) && (← Daemon.running endpoint) then do
    let sampled ← IO.Process.output {cmd := "/usr/bin/sample",args := #[toString endpoint.pid,"1","-file",(root/"frontend.sample.txt").toString]}
    pure (Json.mkObj [("pid",toJson endpoint.pid),("exitCode",toJson sampled.exitCode.toNat),
      ("stderr",toJson (sampled.stderr.take 2048).copy)])
    else pure Json.null
  let (frontend,frontMs) ← IO.ofExcept (← IO.wait stopping)
  let endpointPresent ← (← Daemon.endpointPath).pathExists
  let afterFrontend ← ownedRows engine
  let publisher ← IO.Process.output {cmd := engine,args := #["publication-control","shutdown"]}
  let afterPublisher ← ownedRows engine
  -- The probe is the frontend child owner, so it alone reaps that exact handle.
  let ownerStop ← try Daemon.shutdown; pure "ok" catch error => pure error.toString
  let result := Json.mkObj [("registrationCount",toJson (if parallel then 80 else 32 : Nat)),
    ("parallelRegistration",toJson parallel),("pendingSessionsInjected",toJson false),
    ("searchOrModelRequests",toJson (0 : Nat)),("sample",sample),("endpointPresentAfterStop",toJson endpointPresent),
    ("shutdownSenderDropsReply",toJson dropReply),
    ("beforeStatus",toJson status),
    ("frontendExit",toJson frontend.exitCode.toNat),("frontendStdout",toJson frontend.stdout),("frontendStderr",toJson frontend.stderr),
    ("frontendStopMs",toJson frontMs),("publisherExit",toJson publisher.exitCode.toNat),
    ("publisherStdout",toJson publisher.stdout),("publisherStderr",toJson publisher.stderr),
    ("before",toJson before),("afterFrontend",toJson afterFrontend),("afterPublisher",toJson afterPublisher),
    ("ownerStop",toJson ownerStop),("final",toJson (← ownedRows engine)),("adopted",toJson false)]
  IO.FS.writeFile (root/"report.json") result.compress
def main (args : List String) : IO UInt32 := do
  match args with
  | [root,engine] => probe (.mk root) engine; return 0
  | [root,engine,"parallel"] => probe (.mk root) engine true; return 0
  | [root,engine,"drop"] => probe (.mk root) engine false true; return 0
  | ["send-stop"] =>
    let endpoint ← Daemon.loadEndpoint "stop-probe"
    let socket ← Daemon.connect endpoint
    Daemon.sendFrame socket (Daemon.request endpoint.secret "shutdown" Json.null).compress.toUTF8
    return 0
  | _ => throw (IO.userError "stop probe RESULT ENGINE")
