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
  let client ← Plugin.Daemon.connect endpoint
  -- Leave a real frame header unfinished, keeping this socket open through
  -- release. Shutdown must not await its ordinary 24-second request budget.
  (client.send (ByteArray.mk #[0])).block
  IO.sleep 50
  let started ← IO.monoMsNow
  let mut releaseError : Option String := none
  try Numerical.release keeper 100
  catch error => releaseError := some error.toString
  let elapsed := (← IO.monoMsNow)-started
  IO.FS.writeFile (root / "release.json") ((Json.mkObj [
    ("releaseError",toJson releaseError),("shutdownMs",toJson elapsed)]).compress ++ "\n")
  let serviceAliveBeforePeerClose ← Numerical.alive endpoint.pid
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

def main (args : List String) : IO UInt32 := do
  match args with
  | ["codex-numerical-daemon",model,models,python] => Numerical.serve ⟨model,.mk models,.mk python⟩
  | ["idle",directory] => idle directory
  | [output] => defunct output
  | _ => throw (IO.userError "NumericalLifecycleChecks NEW-REPORT | idle NEW-DIRECTORY")
