import Main
import Eggshell.ContractAudit
open Lean Eggshell Eggshell.Plugin

#print axioms HookFrontend.OwnedTasks.reader_registered
#print axioms HookFrontend.OwnedTasks.client_registered
#print axioms HookFrontend.OwnedTasks.maintenance_registered
#print axioms HookFrontend.OwnedTasks.reader_preserves_others
#print axioms HookFrontend.OwnedTasks.client_preserves_others
#print axioms HookFrontend.OwnedTasks.maintenance_preserves_others
run_cmd do
  let environment ← getEnv
  for (caller,required) in [(``HookFrontend.run,``HookFrontend.OwnedTasks.finish),
      (``HookFrontend.run,``HookFrontend.OwnedTasks.addReader),
      (``HookFrontend.run,``HookFrontend.OwnedTasks.addClient),
      (``HookFrontend.run,``HookFrontend.OwnedTasks.addMaintenance),
      (``HookFrontend.OwnedTasks.finish,``IO.wait),
      (``HookFrontend.OwnedTasks.finish,``Worker.shutdown)] do
    let some declaration := environment.find? caller | throwError "missing task owner {caller}"
    let some value := declaration.value? | throwError "opaque task owner {caller}"
    unless value.getUsedConstants.contains required do throwError "disconnected task owner {caller} -> {required}"
  logInfo "Actual frontend registration and finalization use the live single-owner registry"

def check (ok : Bool) (message : String) : IO Unit := unless ok do throw (IO.userError message)

/-- Keep an actual frontend client active when shutdown arrives. The external
release is cleanup only; a successful finalizer must cancel/join it first. -/
def ownerCheck (root : System.FilePath) : IO Unit := do
  check (!(← root.pathExists)) "fresh frontend owner control required"
  IO.FS.createDirAll root
  let server ← Std.Async.TCP.Socket.Server.mk
  server.bind (Daemon.loopback 0)
  server.listen 128
  server.noDelay
  let address ← server.getSockName
  let endpoint : Daemon.Endpoint := {
    session := "owner-control",pid := (← IO.Process.getPID).toNat,port := address.port.toNat
    secret := "native-owner-control",generation := ← Daemon.desiredGeneration}
  let entered ← IO.mkRef false
  let retired ← IO.mkRef false
  let released ← IO.mkRef false
  let handle := fun (_ : String) (request : Json) => do
    if Plugin.optionalString request "kind" == some "hook" then
      try
        entered.set true
        while !(← IO.checkCanceled) && !(← released.get) do IO.sleep 5
        pure (Daemon.response (.ok ""),false)
      finally retired.set true
    else pure (Daemon.response (.ok ""),Plugin.optionalString request "kind" == some "shutdown")
  let running ← IO.asTask (HookFrontend.run server endpoint.secret "owner-control" handle) .dedicated
  let caller ← IO.asTask (Daemon.exchange endpoint "hook"
    (Json.mkObj [("session_id",toJson "owner-control")]) (budget := 5000)) .dedicated
  try
    let deadline := (← IO.monoMsNow)+3000
    while !(← entered.get) do
      check ((← IO.monoMsNow) < deadline) "control client did not enter actual frontend handler"
      IO.sleep 5
    let began ← IO.monoMsNow
    discard <| Daemon.exchange endpoint "shutdown" (budget := 1000)
    TaskDeadline.wait running ((← IO.monoMsNow)+3000)
    let stoppedMs := (← IO.monoMsNow)-began
    check (← retired.get) "frontend returned with an unjoined active client"
    check (!(← released.get)) "external cleanup hid the missing task owner"
    discard <| IO.wait caller
    IO.FS.writeFile (root/"report.json") (Json.mkObj [("actualFrontendActiveClientJoined",toJson true),
      ("externalReleaseNeeded",toJson false),("stopMs",toJson stoppedMs),
      ("searchOrModelRequests",toJson (0 : Nat)),("adopted",toJson false)]).compress
  finally
    released.set true
    IO.cancel running
    IO.cancel caller
    discard <| IO.wait caller
    discard <| IO.wait running

def main (args : List String) : IO UInt32 := do
  match args with
  | ["frontend-owner-check",root] => ownerCheck (.mk root); return 0
  | ["front-traffic-audit",source] =>
    let output ← IO.Process.output {
      cmd := "/Users/ovm/.codex/experiments/eggshell/scope-token-study-20261028/fixed-frame-study/metadata-ingress-candidate-build/StudyMain",
      args := #["front-traffic-audit",source]}
    IO.print output.stdout
    IO.eprint output.stderr
    return output.exitCode
  | other => sourceRouteEngine other
