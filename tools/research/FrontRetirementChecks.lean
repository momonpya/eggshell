import Eggshell.Daemon
import Lean

open Lean Eggshell Eggshell.Plugin

def main (args : List String) : IO Unit := do
  let [root] := args | throw (IO.userError "fixture root required")
  let root := System.FilePath.mk root
  let executable : System.FilePath := "/Users/ovm/.codex/experiments/eggshell/scope-token-study-20261028/fixed-frame-study/front-manager-build/StudyMain"
  let child ← IO.Process.spawn {
    cmd := executable.toString
    args := #["codex-daemon","front-client-0"]
    stdin := .null,stdout := .null,stderr := .null,setsid := true}
  let reaped ← IO.mkRef false
  let mut ready : Option Daemon.Endpoint := none
  for _ in [:800] do
    if let some code ← child.tryWait then throw (IO.userError s!"frontend exited at startup: {code}")
    try
      let observed ← Daemon.loadEndpoint "front-client-0"
      if observed.pid == child.pid.toNat then
        let _ ← Daemon.exchange observed "ping" (budget := 250)
        ready := some observed
        break
    catch _ => pure ()
    IO.sleep 10
  let some endpoint := ready | child.kill; throw (IO.userError "frontend did not start")
  try
    let stalled ← Daemon.connect endpoint
    (stalled.send (ByteArray.mk #[0])).block
    IO.sleep 20
    let stats ← Daemon.exchange endpoint "stats"
    let started ← IO.monoMsNow
    let outcome ← try Daemon.shutdown; pure "returned" catch error => pure error.toString
    let elapsed := (← IO.monoMsNow)-started
    let state ← IO.Process.output {cmd := "/bin/ps",args := #["-o","pid=,ppid=,stat=,rss=,command=","-p",toString child.pid]}
    let waited ← child.tryWait
    reaped.set waited.isSome
    let sample ← if waited.isNone then IO.Process.output {
        cmd := "/usr/bin/sample"
        args := #[toString child.pid,"1","1","-file",(root/"retirement.sample").toString]}
      else pure {exitCode := 0,stdout := "",stderr := ""}
    let result := Json.mkObj [("shutdown",toJson outcome),("elapsedMs",toJson elapsed),
      ("pidStateBeforeWait",toJson state.stdout),("psExitCode",toJson state.exitCode.toNat),
      ("actualChildExitCode",toJson (waited.map UInt32.toNat)),("sampleExitCode",toJson sample.exitCode.toNat),
      ("sampleStderr",toJson sample.stderr),("statsBeforeShutdown",toJson stats),
      ("endpointRemoved",toJson (!(← (← Daemon.endpointPath).pathExists)))]
    IO.FS.writeFile (root/"retirement-diagnosis.json") (result.pretty++"\n")
    IO.println result.compress
    discard <| stalled.getSockName
    unless waited.isSome do throw (IO.userError "actual frontend process is still live")
  finally
    unless ← reaped.get do
      if (← child.tryWait).isNone then
        child.kill
        discard <| child.wait
    try
      let _ ← Publication.Client.control "shutdown"
    catch _ => pure ()
