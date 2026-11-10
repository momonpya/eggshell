module
public import Lean.Data.Json.Parser
public import Lean.Data.Json.FromToJson
@[expose] public section
namespace Eggshell.Research.PreparedRoutingObserver
open Lean
def read (path : System.FilePath) : IO Json := IO.FS.readFile path >>= (IO.ofExcept ∘ Json.parse)
def check (condition : Bool) (message : String) : IO Unit :=
  unless condition do throw (IO.userError message)

abbrev Child := IO.Process.Child {stdin := .null,stdout := .inherit,stderr := .inherit}

def waitOwned (child : Child) (exit : IO.Ref (Option UInt32)) : IO UInt32 := do
  if let some code ← exit.get then return code
  let code ← child.wait
  exit.set (some code)
  return code

def closeOwned (child : Child) (exit : IO.Ref (Option UInt32)) : IO Unit := do
  if (← exit.get).isSome then return
  if let some code ← child.tryWait then
    exit.set (some code)
    return
  discard <| IO.Process.output {cmd := "/bin/kill",args := #["-TERM",s!"-{child.pid.toNat}"]}
  discard <| waitOwned child exit

def controls (output : String) : IO Unit := do
  let path : System.FilePath := .mk output
  check (!(← path.pathExists)) "fresh child-lifecycle controls required"
  for program in ["/usr/bin/true","/usr/bin/false"] do
    let child : Child ← IO.Process.spawn {
      cmd := program
      stdin := .null
      stdout := .inherit
      stderr := .inherit
      setsid := true }
    let exit ← IO.mkRef (none : Option UInt32)
    let first ← try waitOwned child exit finally closeOwned child exit
    let second ← waitOwned child exit
    closeOwned child exit
    check (first == second && (← exit.get) == some first) "owned exit was lost across finally"
  let child : Child ← IO.Process.spawn {
    cmd := "/bin/sleep"
    args := #["1"]
    stdin := .null
    stdout := .inherit
    stderr := .inherit
    setsid := true }
  let exit ← IO.mkRef (none : Option UInt32)
  closeOwned child exit
  closeOwned child exit
  check (← exit.get).isSome "cancelled child was not reaped"
  IO.FS.writeFile path (Json.mkObj [("successAndFailureExitPreservedAcrossFinally",toJson true),
    ("idempotentWaitAndClose",toJson true),("cancelledOwnedChildReaped",toJson true),
    ("productHookReplay",toJson false)]).compress
def runAt (inputPath : String) (delayMs : UInt32) (sampleSeconds : String)
    (afterPhase : Option (IO Unit) := none) : IO Unit := do
  let input ← read (.mk inputPath)
  check (input.getObjValD "counts" == toJson (#[(4 : Nat)]) &&
    input.getObjValD "diagnostic" == toJson true) "late sampling is a four-client diagnostic only"
  let runtime ← IO.ofExcept (input.getObjValAs? String "runtime")
  let root : System.FilePath := .mk (← IO.ofExcept (input.getObjValAs? String "output"))
  let dataRoot : System.FilePath := .mk (← IO.ofExcept (input.getObjValAs? String "data"))
  let environment : Array (String × Option String) ← IO.ofExcept (fromJson? (input.getObjValD "environment"))
  let child ← IO.Process.spawn {
    cmd := runtime
    args := #["owned-selection-capacity",inputPath]
    env := environment
    stdin := .null
    stdout := .inherit
    stderr := .inherit
    setsid := true }
  let exit ← IO.mkRef (none : Option UInt32)
  try
    let limit := (← IO.monoMsNow)+180000
    let phase := root/"phase-4/initializations.json"
    while !(← phase.pathExists) do
      let code ← child.tryWait
      if code.isSome then
        exit.set code
        throw (IO.userError "owned capacity process exited before the measured phase")
      check ((← IO.monoMsNow) < limit) "late sampler did not reach the owned phase"
      IO.sleep 5
    let phaseObserved ← IO.monoMsNow
    let endpoint ← read (dataRoot/"publisher/endpoint.json")
    let pid ← IO.ofExcept (endpoint.getObjValAs? Nat "pid")
    check (endpoint.getObjValD "session" == toJson "publisher") "sampling a foreign endpoint"
    let process ← IO.Process.output {cmd := "/bin/ps",args := #["-p",toString pid,"-o","ppid=","-o","command="]}
    let fields := process.stdout.trimAscii.toString.splitOn " " |>.filter (!·.isEmpty)
    check (process.exitCode == 0 && fields[0]? == some (toString child.pid.toNat) &&
      fields[1]? == some runtime && fields[2]? == some "codex-publication-daemon")
      "sample target is not the directly owned publisher"
    match afterPhase with
    | none => IO.sleep delayMs
    | some action => do action; IO.sleep delayMs
    let started ← IO.monoMsNow
    let sample ← IO.Process.output {
      cmd := "/usr/bin/sample"
      args := #[toString pid,sampleSeconds,"5","-file",(root/"publisher-late.sample.txt").toString] }
    let stopped ← IO.monoMsNow
    IO.FS.writeFile (root/"sampling.json") (Json.mkObj [("pid",toJson pid),
      ("ownedParentPid",toJson child.pid.toNat),("phaseObservedMs",toJson phaseObserved),
      ("sampleStartedMs",toJson started),("sampleFinishedMs",toJson stopped),
      ("phaseToSampleMs",toJson (started-phaseObserved)),("sampleExitCode",toJson sample.exitCode.toNat),
      ("stdout",toJson sample.stdout),("stderr",toJson sample.stderr),
      ("diagnosticInterferencePossible",toJson true),("wholeHookCpuPercentages",toJson false)]).compress
    check (sample.exitCode == 0) "owned late sampling failed"
    let code ← waitOwned child exit
    check (code == 0) "owned diagnostic workload failed"
  finally
    closeOwned child exit
def run (inputPath : String) : IO Unit := runAt inputPath 2000 "3"
end Eggshell.Research.PreparedRoutingObserver
