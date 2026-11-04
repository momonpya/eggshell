import Main

open Lean Eggshell Eggshell.DB Eggshell.Plugin Eggshell.Persistence.Store
namespace Eggshell.Research.InterestLifetimeIOChecks

def lane : PreparationPlan.Lane := ⟨0,by decide⟩

def check (condition : Bool) (message : String) : IO Unit :=
  unless condition do throw (IO.userError message)

def audit (root : System.FilePath) : IO Unit := do
  check (root.isAbsolute && !(← root.pathExists)) "fresh lifecycle fixture required"
  FileSystem.privateDirectory root
  let project ← ProjectStore.create (root/"project") 1
  let view ← ProjectStore.pin project ((← IO.monoMsNow)+10000)
  let original ← ProjectStore.withOwner project 0 fun owner => do
    let capsule : Publication.Capsule := {
      session := "interest-io",turn := "source",cwd := root.toString,work := "inspect original"
      checkpoint := false
      tools := #[{
        name := "mcp__fixture__inspect"
        useId := "source"
        input := "{}"
        response := "original lifecycle evidence"}]
      finalMessage := some "notebook",timing := #[.unavailable]}
    let request ← IO.ofExcept (capsule.prepare project.directory owner.source.identity)
    let ack ← owner.publish view #[{request with target := project.sourceDirectory 0}]
    check (ack.size == 1) "original ACK missing"
    project.current 0
  let target ← registerIndexTarget original
    [(← IO.appPath).toString,"search-provider","--mode","lexical"] true
  let pool ← PreparationService.Pool.new
  try
    let cutoff := (← IO.monoMsNow)+10000
    let some first ← pool.openWaiter cutoff | throw (IO.userError "first grant missing")
    let some second ← pool.openWaiter cutoff | throw (IO.userError "second grant missing")
    check (← pool.demand "index" target.key original.head first) "first source demand refused"
    check (← pool.demand "index" target.key original.head second) "shared source demand refused"
    let some active ← pool.take lane | throw (IO.userError "shared attempt missing")
    let some old ← pool.pipe lane | throw (IO.userError "owned pipe missing")
    -- Pause the real, still-idle product worker before assigning work. This
    -- forces cancellation to race actual blocked IPC without a fake slow path.
    let child ← IO.Process.spawn {
      cmd := (← IO.appPath).toString,args := #["codex-worker","index"],
      stdin := .piped,stdout := .piped,stderr := .null,setsid := true}
    try
      let stopped ← IO.Process.output {cmd := "/bin/kill",args := #["-STOP","--","-"++toString child.pid]}
      check (stopped.exitCode == 0) "could not pause the actual preparation worker"
      old.child.atomically (set (Worker.Lifetime.Cell.open (some child)))
    catch error =>
      Worker.killGroup child
      let _ ← child.wait
      throw error
    let running ← IO.asTask (pool.run lane active) .dedicated
    try
      pool.release first
      IO.sleep 20
      check (!(← IO.hasFinished running)) "one cancellation stopped another live waiter"
      let stats ← pool.stats
      check ((stats.getObjValAs? Nat "claimReferences").toOption == some 1)
        "shared active claim was lost"
      pool.release second
    catch error =>
      pool.close
      let _ ← IO.wait running
      throw error
    let ended ← Worker.awaitUntil running ((← IO.monoMsNow)+3000)
    unless ended.isSome do
      pool.close
      let _ ← IO.wait running
      throw (IO.userError "last release did not stop blocked preparation IO")
    check (← old.closed) "cancelled handle remained open"
    let stats ← pool.stats
    check ((stats.getObjValAs? Nat "active").toOption == some 0 &&
      (stats.getObjValAs? Nat "residentBytes").toOption == some 0 &&
      (stats.getObjValAs? Nat "retirements").toOption == some 1 &&
      (stats.getObjValAs? Nat "retries").toOption == some 0)
      "cancelled blocked attempt leaked capacity or retried"
    let some third ← pool.openWaiter ((← IO.monoMsNow)+10000) |
      throw (IO.userError "replacement grant missing")
    check (!(← pool.demand "index" target.key original.head second)) "released remote ticket revived"
    check (← pool.demand "index" target.key original.head third) "replacement demand refused"
    let some successor ← pool.take lane | throw (IO.userError "replacement attempt missing")
    let some replacement ← pool.pipe lane | throw (IO.userError "replacement pipe missing")
    Worker.closeSlot old
    check (!(← replacement.closed)) "late close of old handle closed its successor"
    pool.run lane successor
    pool.release third
    check ((← PreparedInputs.load? original MiniLM.model SearchProvider.encoderContract).isSome)
      "replacement worker did not prepare the actual source"
    check ((← project.current 0).head == original.head) "derived cancellation changed acknowledged originals"
    pool.close
    let some _ := (← pool.openWaiter ((← IO.monoMsNow)+1000)) | do
      check ((← pool.pipe lane).isNone) "closed service respawned a worker"
      IO.FS.writeFile (root/"report.json") ((Json.mkObj [
        ("sharedCancellation",toJson true),("blockedRealWorkerStopped",toJson true),
        ("staleHandleIsolated",toJson true),("successorPrepared",toJson true),
        ("originalHeadUnchanged",toJson true),("terminalClosure",toJson true),
        ("afterCancellation",stats),("final",← pool.stats)]).pretty++"\n")
      IO.println "actual blocked index worker: shared release, last-release termination, successor and closure PASS"
      return
    throw (IO.userError "closed service granted a new waiter")
  finally pool.close

end Eggshell.Research.InterestLifetimeIOChecks
