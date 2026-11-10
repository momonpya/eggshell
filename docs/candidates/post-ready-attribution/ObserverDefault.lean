module
public import tools.research.PreparedRoutingObserver
@[expose] public section
namespace Eggshell.Research.PreparedRoutingObserver
open Lean
noncomputable def previousRun (inputPath : String) : IO Unit := do
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
    IO.sleep 2000
    let started ← IO.monoMsNow
    let sample ← IO.Process.output {
      cmd := "/usr/bin/sample"
      args := #[toString pid,"3","5","-file",(root/"publisher-late.sample.txt").toString] }
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

theorem run_default_exact : @run = @previousRun := by rfl
#print axioms run_default_exact
end Eggshell.Research.PreparedRoutingObserver
