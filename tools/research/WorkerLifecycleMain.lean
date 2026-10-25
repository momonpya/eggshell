import Eggshell.Worker

open Lean Eggshell.Plugin

private def check (condition : Bool) (message : String) : IO Unit := do
  unless condition do throw (IO.userError message)

private partial def waitForChild (slot : Worker.Slot) (deadline : Nat) : IO UInt32 := do
  match Worker.Lifetime.admit (← slot.child.atomically get) with
  | .reuse child => return child.pid
  | .refused => throw (IO.userError "slot closed before fixture admission")
  | .spawn =>
      if (← IO.monoMsNow) ≥ deadline then throw (IO.userError "worker fixture did not start")
      IO.sleep 1
      waitForChild slot deadline

private def refused (slot : Worker.Slot) : IO Bool := do
  match Worker.Lifetime.admit (← slot.child.atomically get) with
  | .refused => pure true
  | _ => pure false

/-- Only the fixture branch uses sleep; production cancellation is exercised
through real child pipes, process groups and the actual Worker.exchange. -/
private def fixture : IO UInt32 := do
  let input ← IO.getStdin
  let _ ← input.getLine
  IO.sleep 60000
  return 0

private def scenario (count : Nat) : IO UInt32 := do
  let session := s!"lifecycle-{count}"
  let deadline := (← IO.monoMsNow)+10000
  let save ← Worker.slotFor session "save"
  let index ← Worker.slotFor session "index"
  let pool ← Worker.readPoolFor session
  let identity : Worker.SearchIdentity := ⟨"turn",0,deadline,none⟩
  let policy : Worker.SearchPolicy := {identity}
  let activeSave ← IO.asTask (Worker.exchange session "save" Json.null deadline) .dedicated
  let activeIndex ← IO.asTask (Worker.exchange session "index" Json.null deadline) .dedicated
  let mut activeSearch := #[]
  for _ in [:Worker.readLaneCount] do
    activeSearch := activeSearch.push (← IO.asTask
      (Worker.exchange session "search" Json.null deadline (some policy)) .dedicated)
  let mut pids := #[← waitForChild save deadline,← waitForChild index deadline]
  for lane in Worker.readLanes Worker.readLaneCount do
    pids := pids.push (← waitForChild (pool.slot lane) deadline)
  let waiting ← (List.range count).mapM fun _ => IO.asTask
    (Worker.exchange session "search" Json.null deadline (some policy)) .dedicated
  IO.sleep 10
  let started ← IO.monoMsNow
  for task in waiting do IO.cancel task
  Worker.shutdown
  let shutdownMs := (← IO.monoMsNow)-started
  for task in [activeSave,activeIndex] ++ activeSearch.toList ++ waiting do
    let result ← Worker.awaitUntil task ((← IO.monoMsNow)+2000)
    check (result == some none) "cancelled request did not settle without a reply"
  check (← refused save) "captured save slot reopened"
  check (← refused index) "captured index slot reopened"
  for lane in Worker.readLanes Worker.readLaneCount do
    check (← refused (pool.slot lane)) "captured search slot reopened"
  let late ← (List.range count).mapM fun index => IO.asTask (do
    let result ← Worker.exchange s!"late-{index}" "save" Json.null ((← IO.monoMsNow)+1000)
    check result.isNone "late request spawned a worker or received a result"
    check (← refused (← Worker.slotFor s!"late-{index}" "save")) "late slot was not sealed") .dedicated
  for task in late do
    let result ← Worker.awaitUntil task ((← IO.monoMsNow)+2000)
    check result.isSome "late client did not settle"
  Worker.shutdown
  for pid in pids do
    let alive ← IO.Process.output {cmd := "/bin/kill",args := #["-0",toString pid]}
    check (alive.exitCode != 0) "owned worker survived shutdown"
  check (shutdownMs < 15000) "shutdown exceeded original acquisition budget"
  IO.println (Json.mkObj [("clients",toJson count),("activeChildren",toJson pids.size),
    ("shutdownMs",toJson shutdownMs),("lateAdmissionResults",toJson late.length),
    ("lateWorkerSpawns",toJson (0 : Nat)),("survivingChildren",toJson (0 : Nat)),
    ("databaseOrAnsweringModelUsed",toJson false)]).compress
  return 0

def main (args : List String) : IO UInt32 := do
  try
    match args with
    | ["codex-worker",_] => fixture
    | ["scenario",count] =>
        let some count := count.toNat? | throw (IO.userError "invalid client count")
        scenario count
    | [] =>
        let executable ← IO.appPath
        for count in [10,40,80] do
          let result ← IO.Process.output {cmd := executable.toString,args := #["scenario",toString count]}
          IO.print result.stdout
          IO.eprint result.stderr
          check (result.exitCode == 0) s!"lifecycle scenario {count} failed"
        return 0
    | _ => throw (IO.userError "WorkerLifecycleMain [scenario COUNT]")
  catch error => IO.eprintln error.toString; return 1
