import Main
open Lean Eggshell Eggshell.Plugin
namespace Eggshell.Research.StartupChecks
def check (value : Bool) (message : String) : IO Unit := unless value do throw (IO.userError message)
def save (path : System.FilePath) (value : Json) : IO Unit := IO.FS.writeFile path (value.compress++"\n")
def client (session : String) (deadline : Nat) : IO Json := do
  let began ← IO.monoMsNow
  let endpoint ← Daemon.ensureBefore session deadline
  let reply ← Daemon.exchangeBefore endpoint "ping" Json.null deadline
  check reply.toNat?.isSome "ready frontend did not authenticate its ping"
  return Json.mkObj [("session",toJson session),("pid",toJson endpoint.pid),
    ("generation",toJson endpoint.generation),("elapsedMs",toJson ((← IO.monoMsNow)-began))]
def hold (held released : IO.Ref Bool) : IO (Task (Except IO.Error Unit)) :=
  IO.asTask (do Persistence.withLockUntil (← Daemon.startupLock) ((← IO.monoMsNow)+10000) do
    held.set true
    let endAt := (← IO.monoMsNow)+10000
    while !(← released.get) do
      check ((← IO.monoMsNow)<endAt) "test starter guard was never released"
      IO.sleep 5) .dedicated
def awaitHeld (held : IO.Ref Bool) : IO Unit := do
  let deadline := (← IO.monoMsNow)+3000
  while !(← held.get) do
    check ((← IO.monoMsNow)<deadline) "test did not acquire the real startup guard"
    IO.sleep 1
def denied (action : IO α) : IO Bool := do
  try let _ ← action; return false catch _ => return true
def run (root : System.FilePath) : IO Unit := do
  check (!(← root.pathExists)) "preserve earlier startup trial"
  IO.FS.createDirAll root
  let identity ← IO.Process.output {cmd := "/usr/bin/shasum",args := #["-a","256",(← IO.appPath).toString]}
  check (identity.exitCode == 0) "missing runtime identity"
  IO.FS.writeFile (root/"runtime.sha256") identity.stdout
  let held ← IO.mkRef false
  let released ← IO.mkRef false
  let holder ← hold held released
  let mut rows := #[]
  try
    awaitHeld held
    let began ← IO.monoMsNow
    check (← denied (Daemon.ensureBefore "expired" (began+70))) "expired waiter started a frontend"
    let elapsed := (← IO.monoMsNow)-began
    check (elapsed ≥ 70 && elapsed<1000) "expiry ignored its own absolute deadline"
    let cancelled ← IO.asTask (Daemon.ensureBefore "cancelled" ((← IO.monoMsNow)+10000)) .dedicated
    IO.sleep 30
    IO.cancel cancelled
    check (!(← IO.wait cancelled).isOk) "cancelled startup waiter survived"
    check (!(← (← Daemon.endpointPath).pathExists)) "expired or cancelled waiter published an endpoint"
    save (root/"negative.json") (Json.mkObj [("expiredWaitMs",toJson elapsed),
      ("cancelledWaitRejected",toJson true),("noFrontendSpawned",toJson true)])
    let deadline := (← IO.monoMsNow)+10000
    let tasks ← (List.range 80).toArray.mapM fun i => IO.asTask (client s!"startup-{i}" deadline) .dedicated
    IO.sleep 350
    check (!(← (← Daemon.endpointPath).pathExists)) "a contender bypassed the real starter owner"
    released.set true
    IO.ofExcept (← IO.wait holder)
    let mut failures := #[]
    for i in [:tasks.size] do
      match ← IO.wait tasks[i]! with
      | .ok row => rows := rows.push row
      | .error error => failures := failures.push (i,error.toString)
    save (root/"cold.json") (Json.mkObj [("rows",toJson rows),("errors",toJson failures)])
    check (failures.isEmpty && rows.size == 80) "cold frontend startup lost a native client"
    let endpoint ← Daemon.readyEndpoint "startup-0"
    check (rows.all (fun row => row.getObjValD "pid" == toJson endpoint.pid)) "cold callers started different frontends"
    let runningTasks ← (List.range 80).toArray.mapM fun i => do
      IO.asTask (client s!"running-{i}" ((← IO.monoMsNow)+10000)) .dedicated
    let running ← runningTasks.mapM fun task => do IO.ofExcept (← IO.wait task)
    check (running.all (fun row => row.getObjValD "pid" == toJson endpoint.pid)) "live frontend was replaced"
    save (root/"running.json") (toJson running)
    let path ← Daemon.endpointPath
    writeJson path {endpoint with session := "not-a-shared-frontend"}
    try
      check (← denied (Daemon.ensureBefore "invalid-live" ((← IO.monoMsNow)+1000))) "invalid live endpoint was accepted"
      let retained ← Daemon.loadEndpoint "invalid-live"
      check (retained.pid == endpoint.pid && retained.session == "not-a-shared-frontend") "live endpoint error replaced its owner"
    finally writeJson path endpoint
    check (← denied (Daemon.ensureBefore "already-expired" 0)) "expired request reused a live frontend"
  finally
    released.set true
    discard <| IO.wait holder
    Daemon.shutdown
  let held ← IO.mkRef false
  let released ← IO.mkRef false
  let holder ← hold held released
  try
    awaitHeld held
    let deadline := (← IO.monoMsNow)+10000
    let children : Array (IO.Process.Child {stdin := .null,stdout := .piped,stderr := .piped}) ←
      (List.range 8).toArray.mapM fun i => do IO.Process.spawn {
      cmd := (← IO.appPath).toString,args := #["shared-startup-client",s!"process-{i}",toString deadline]
      stdin := .null,stdout := .piped,stderr := .piped }
    IO.sleep 350
    released.set true
    IO.ofExcept (← IO.wait holder)
    let mut external := #[]
    for child in children do
      let text ← child.stdout.readToEnd
      let errors ← child.stderr.readToEnd
      let code ← child.wait
      external := external.push (Json.mkObj [("exitCode",toJson code.toNat),
        ("stdout",toJson text),("stderr",toJson errors)])
    save (root/"processes.json") (toJson external)
    check (external.all (fun row => row.getObjValD "exitCode" == toJson (0 : Nat))) "cross-process startup lost a caller"
    let endpoint ← Daemon.readyEndpoint "process-0"
    for row in external do
      let value ← IO.ofExcept (Json.parse ((row.getObjValAs? String "stdout").toOption.getD ""))
      check (value.getObjValD "pid" == toJson endpoint.pid) "cross-process callers observed different frontends"
    save (root/"report.json") (Json.mkObj [("allPassed",toJson true),("coldClients",toJson (80 : Nat)),
      ("runningClients",toJson (80 : Nat)),("externalProcesses",toJson (8 : Nat)),
      ("heldGuardMs",toJson (350 : Nat)),("liveInvalidEndpointRejected",toJson true),
      ("answeringModelCalls",toJson (0 : Nat)),("adopted",toJson false)])
  finally
    released.set true
    discard <| IO.wait holder
    Daemon.shutdown
    let _ ← Publication.Client.control "shutdown"
    pure ()
end Eggshell.Research.StartupChecks
