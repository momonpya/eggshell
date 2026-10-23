import Eggshell.Numerical

open Lean Eggshell

private def processState (pid : Nat) : IO String := do
  let result ← IO.Process.output {cmd := "/bin/ps",args := #["-o","stat=","-p",toString pid]}
  return result.stdout.trimAscii.copy

/-- Keep the child handle unreaped deliberately. An exited service may be a
different process's child, so a kill-0 probe alone is not an exit test. -/
private def defunct (output : String) : IO UInt32 := do
  let path := System.FilePath.mk output
  unless path.isAbsolute && !(← path.pathExists) do throw (IO.userError "new absolute lifecycle report required")
  let child ← IO.Process.spawn {cmd := "/usr/bin/true",stdin := .null,stdout := .null,stderr := .null}
  let deadline := (← IO.monoMsNow)+3000
  let mut state := ""
  repeat
    state ← processState child.pid.toNat
    if state.startsWith "Z" then break
    unless (← IO.monoMsNow) < deadline do
      let _ ← child.wait
      throw (IO.userError "fixture did not observe an unreaped exited child")
    IO.sleep 5
  let observedAlive ← Numerical.alive child.pid.toNat
  let code ← child.wait
  let afterReap ← Numerical.alive child.pid.toNat
  IO.FS.writeFile path ((Json.mkObj [("observedState",toJson state),
    ("exitedChildReportedAlive",toJson observedAlive),("afterReapAlive",toJson afterReap),
    ("childExitCode",toJson code.toNat),("answeringModelCalls",toJson (0 : Nat)),
    ("numericalModelCalls",toJson (0 : Nat))]).compress ++ "\n")
  return if !observedAlive && !afterReap && code == 0 then 0 else 1

private def idle (directory : String) : IO UInt32 := do
  let root := System.FilePath.mk directory
  unless root.isAbsolute && !(← root.pathExists) do throw (IO.userError "new idle-client fixture required")
  FileSystem.privateDirectory root
  let config : Numerical.Config := ⟨"idle-client-fixture",root,.mk "/usr/bin/false"⟩
  let keeper ← Numerical.keep config
  let endpoint ← Numerical.resolve config
  IO.FS.writeFile (root / "service.json") ((Json.mkObj [("pid",toJson endpoint.pid)]).compress ++ "\n")
  let client ← Plugin.Daemon.connect endpoint
  -- Leave a real frame header unfinished, keeping this socket open through
  -- release. Shutdown must not await its ordinary 24-second request budget.
  (client.send (ByteArray.mk #[0])).block
  let _ ← Plugin.Daemon.exchange endpoint "stats"
  IO.sleep 50
  let started ← IO.monoMsNow
  let mut releaseError : Option String := none
  try Numerical.release keeper 100
  catch error => releaseError := some error.toString
  let elapsed := (← IO.monoMsNow)-started
  IO.FS.writeFile (root / "release.json") ((Json.mkObj [
    ("releaseError",toJson releaseError),("shutdownMs",toJson elapsed)]).compress ++ "\n")
  let serviceAliveBeforePeerClose ← Numerical.alive endpoint.pid
  if serviceAliveBeforePeerClose then
    let state ← IO.Process.output {cmd := "/bin/ps",args := #["-o","pid=,ppid=,stat=,wchan=,args=","-p",toString endpoint.pid]}
    IO.FS.writeFile (root / "service-state.txt") state.stdout
    let sampled ← IO.Process.output {cmd := "/usr/bin/sample",args := #[toString endpoint.pid,"1","1","-file",(root / "service-stack.txt").toString]}
    IO.FS.writeFile (root / "sample-process.json") ((Json.mkObj [
      ("exitCode",toJson sampled.exitCode.toNat),("stdout",toJson sampled.stdout),("stderr",toJson sampled.stderr)]).compress ++ "\n")
  (client.shutdown).block
  let cleanupDeadline := (← IO.monoMsNow)+15000
  while ← Numerical.alive endpoint.pid do
    unless (← IO.monoMsNow) < cleanupDeadline do throw (IO.userError "fixture numerical service remained after peer EOF")
    IO.sleep 5
  IO.FS.writeFile (root / "result.json") ((Json.mkObj [
    ("releaseError",toJson releaseError),("shutdownMs",toJson elapsed),
    ("serviceAliveBeforePeerClose",toJson serviceAliveBeforePeerClose),
    ("endpointRemoved",toJson (!(← (Numerical.endpoint? config)).isSome)),
    ("answeringModelCalls",toJson (0 : Nat)),("numericalModelCalls",toJson (0 : Nat))]).compress ++ "\n")
  return if releaseError.isNone && !serviceAliveBeforePeerClose && elapsed < 1000 then 0 else 1

private def gone (pid deadline : Nat) : IO Bool := do
  repeat
    if !(← Numerical.alive pid) then return true
    if (← IO.monoMsNow) ≥ deadline then return false
    IO.sleep 5
  return false

private def fragmented (directory : String) : IO UInt32 := do
  let root := System.FilePath.mk directory
  unless root.isAbsolute && !(← root.pathExists) do throw (IO.userError "new fragmented-frame fixture required")
  FileSystem.privateDirectory root
  let config : Numerical.Config := ⟨"idle-client-fixture",root,.mk "/usr/bin/false"⟩
  let endpoint ← Numerical.withKeeper config do
    let endpoint ← Numerical.resolve config
    let client ← Plugin.Daemon.connect endpoint
    let payload := (Plugin.Daemon.request endpoint.secret "ping").compress.toUTF8
    let frame := (Plugin.Daemon.frameLength payload).append payload
    for index in [:frame.size] do
      (client.send (frame.extract index (index+1))).block
      IO.sleep 8
    let bytes ← Plugin.Daemon.receiveFrame client 1000
    let some text := String.fromUTF8? bytes | throw (IO.userError "fragmented response is not UTF-8")
    let reply ← IO.ofExcept (Json.parse text)
    unless (reply.getObjValAs? Bool "ok").toOption == some true &&
      (reply.getObjValAs? String "output").toOption == some "" do
      throw (IO.userError "fragmented request changed its response")
    return endpoint
  let stopped ← gone endpoint.pid ((← IO.monoMsNow)+1000)
  IO.FS.writeFile (root / "result.json") ((Json.mkObj [
    ("oneByteFragmentsAccepted",toJson true),("serviceStopped",toJson stopped),
    ("answeringModelCalls",toJson (0 : Nat)),("numericalModelCalls",toJson (0 : Nat))]).compress ++ "\n")
  return if stopped then 0 else 1

private def holder (directory : String) : IO UInt32 := do
  let root := System.FilePath.mk directory
  let config : Numerical.Config := ⟨"idle-client-fixture",root,.mk "/usr/bin/false"⟩
  Numerical.withKeeper config do
    let _ ← Numerical.resolve config
    IO.FS.writeFile (root / "holder-ready") "ready\n"
    IO.sleep 30000
    return 0

private def vanishedOwner (directory : String) : IO UInt32 := do
  let root := System.FilePath.mk directory
  unless root.isAbsolute && !(← root.pathExists) do throw (IO.userError "new vanished-owner fixture required")
  FileSystem.privateDirectory root
  let config : Numerical.Config := ⟨"idle-client-fixture",root,.mk "/usr/bin/false"⟩
  let owner ← IO.Process.spawn {
    cmd := (← IO.appPath).toString
    args := #["holder",directory]
    stdin := .null, stdout := .null, stderr := .inherit }
  let closed ← IO.mkRef false
  try
    let deadline := (← IO.monoMsNow)+5000
    while !(← (root / "holder-ready").pathExists) do
      unless (← IO.monoMsNow) < deadline do throw (IO.userError "owner fixture did not become ready")
      IO.sleep 5
    let some endpoint ← Numerical.endpoint? config | throw (IO.userError "owner fixture has no service")
    let client ← Plugin.Daemon.connect endpoint
    (client.send (ByteArray.mk #[0])).block
    let _ ← Plugin.Daemon.exchange endpoint "stats"
    owner.kill
    let _ ← owner.wait
    closed.set true
    let started ← IO.monoMsNow
    let stopped ← gone endpoint.pid (started+1000)
    let elapsed := (← IO.monoMsNow)-started
    (client.shutdown).block
    IO.FS.writeFile (root / "result.json") ((Json.mkObj [
      ("vanishedOwnerStoppedService",toJson stopped),("shutdownMs",toJson elapsed),
      ("answeringModelCalls",toJson (0 : Nat)),("numericalModelCalls",toJson (0 : Nat))]).compress ++ "\n")
    return if stopped then 0 else 1
  finally
    if !(← closed.get) then
      try owner.kill catch _ => pure ()
      let _ ← owner.wait
      pure ()

def main (args : List String) : IO UInt32 := do
  match args with
  | ["codex-numerical-daemon",model,models,python] =>
      let code ← Numerical.serve ⟨model,.mk models,.mk python⟩
      IO.FS.writeFile (.mk models / "service-returned.json") ((Json.mkObj [("exitCode",toJson code.toNat)]).compress ++ "\n")
      return code
  | ["idle",directory] => idle directory
  | ["fragmented",directory] => fragmented directory
  | ["holder",directory] => holder directory
  | ["vanished-owner",directory] => vanishedOwner directory
  | [output] => defunct output
  | _ => throw (IO.userError "NumericalLifecycleChecks NEW-REPORT | idle|fragmented|vanished-owner NEW-DIRECTORY")
