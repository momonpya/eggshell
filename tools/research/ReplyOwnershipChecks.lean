module
public import Main
public import tools.research.ReplyHold
@[expose] public section
namespace Eggshell.Research.ReplyOwnershipChecks
open Lean Plugin OperationPool

def check (ok : Bool) (message : String) : IO Unit := unless ok do throw (IO.userError message)
def rejects (action : IO α) : IO Bool := try discard action; return false catch _ => return true
def charged (pool : Pool) : IO Nat := pool.searchReplies.atomically do return (← get).used
def freshJob (name : String) (deadline : Nat) : IO Job := return {
  request := {
    id := name,session := "native-credit",role := .search,payload := Json.null,
    cutoff := deadline,identity := none,finishReady := false}
  admitted := 0,cancelled := ← IO.mkRef false,ready := ← IO.mkRef none,expires := ← IO.mkRef deadline,
  reply := ← IO.Promise.new,reservation := ← Std.Mutex.new .waiting }

#print axioms ReplyHold.grant_starts_producer
#print axioms ReplyHold.close_keeps_producer_charge
#print axioms ReplyHold.close_accounting
#print axioms ReplyHold.finish_accounting
#print axioms ReplyHold.second_close_releases_nothing
#print axioms ReplyHold.second_finish_releases_nothing
#print axioms ReplyHold.both_closed
#print axioms ReplyHold.release_exact_in_both_orders

private def occurrences (target : Name) : Expr → Nat
  | .const name _ => if name == target then 1 else 0
  | .app f x => occurrences target f+occurrences target x
  | .lam _ ty body _ | .forallE _ ty body _ => occurrences target ty+occurrences target body
  | .letE _ ty value body _ => occurrences target ty+occurrences target value+occurrences target body
  | .mdata _ value | .proj _ _ value => occurrences target value
  | _ => 0

run_cmd do
  let env ← getEnv
  let body (name : Name) := do
    let some value := (env.find? name).bind (·.value?) | throwError "missing actual reply ownership implementation {name}"
    pure value
  for (name,required) in [(``Pool.runSearch,``Pool.finishReplyProducer),(``Pool.run,``Pool.finishReplyProducer),
      (``Pool.runSearchBody,``Pool.withReplyEncoding),(``Pool.withReplyEncoding,``Pool.reserveReply),
      (``Pool.finishReplyProducer,``ReplyHold.finish),(``Pool.releaseReply,``ReplyHold.close)] do
    unless occurrences required (← body name) == 1 do throwError "reply ownership is disconnected {name} -> {required}"
  unless occurrences ``Pool.reserveReply (← body ``Pool.runSearchBody) == 0 do
    throwError "search still reserves its reply only after constructing the wire JSON"
  let mut pending := [``ReplyHold.grant,``ReplyHold.finish,``ReplyHold.close]
  let mut seen : Std.HashSet Name := {}
  while let some name := pending.head? do
    pending := pending.tail!
    if seen.contains name then continue
    seen := seen.insert name
    if ["Std.Mutex.","IO.","BaseIO.","EIO."].any (fun stem => name.toString.startsWith stem) then
      throwError "pure reply ownership reaches synchronization {name}"
    if let some value := (env.find? name).bind (·.value?) then pending := value.getUsedConstants.toList++pending
  logInfo m!"Actual search/save retirement and pre-JSON admission connected; {seen.size} ownership dependencies without IO"

def waitEntered (entered : IO.Promise Unit) (deadline : Nat) : IO Unit :=
  TaskDeadline.wait (Std.Async.AsyncTask.ofPurePromise entered) deadline

def blocked (pool : Pool) (job : Job) (entered release : IO.Promise Unit) : IO (Task (Except IO.Error Unit)) :=
  IO.asTask (do
    try
      discard <| pool.withReplyEncoding job () fun _ => do
        entered.resolve ()
        discard <| IO.wait release.result!
        return Json.null
    finally pool.finishReplyProducer job) .dedicated

structure Counter where
  active : Nat := 0
  peak : Nat := 0
  entered : Nat := 0

def runUsing (pool : Pool) (root : System.FilePath) : IO Unit := do
  check (!(← root.pathExists)) "fresh reply ownership controls required"
  IO.FS.createDirAll root
  let deadline := (← IO.monoMsNow)+28000
  let maximum := replyBytes .search
  let mut jobs := #[]
  let mut entered := #[]
  let mut release := #[]
  let mut tasks := #[]
  for i in [:3] do
    let job ← freshJob s!"held-{i}" deadline
    let e ← IO.Promise.new
    let r ← IO.Promise.new
    jobs := jobs.push job; entered := entered.push e; release := release.push r
    tasks := tasks.push (← blocked pool job e r)
  let some firstJob := jobs[0]? | throw (IO.userError "first held job missing")
  let some firstRelease := release[0]? | throw (IO.userError "first held release missing")
  let some firstTask := tasks[0]? | throw (IO.userError "first held producer missing")
  try
    for e in entered do waitEntered e deadline
    check ((← charged pool) == 3*maximum) "active producers were not charged before encoding"
    let next ← freshJob "next" deadline
    let e ← IO.Promise.new
    let r ← IO.Promise.new
    let fourth ← blocked pool next e r
    try
      IO.sleep 30
      check (!(← e.isResolved)) "fourth encoder ran without its memory reservation"
      -- Consumer closure must not return the first producer's live storage.
      firstJob.cancelled.set true
      pool.releaseReply firstJob
      pool.releaseReply firstJob
      check ((← charged pool) == 3*maximum) "consumer returned storage still owned by an encoder"
      IO.sleep 30
      check (!(← e.isResolved)) "cancellation admitted a replacement before its producer finished"
      firstRelease.resolve ()
      TaskDeadline.wait firstTask deadline
      waitEntered e deadline
      check ((← charged pool) == 3*maximum) "producer retirement lost the replacement's charge"
      r.resolve ()
      TaskDeadline.wait fourth deadline
      check ((← charged pool) == 3*maximum) "finished producer returned storage still owned by its receiver"
      pool.releaseReply next
      pool.releaseReply next
      check ((← charged pool) == 2*maximum) "double close returned another producer's storage"
      check ((← pool.withReplyEncoding next () (fun _ => throw (IO.userError "closed encoder executed"))).isNone)
        "closed reply admitted another encoder"
    finally
      r.resolve ()
      discard <| IO.wait fourth
      pool.releaseReply next
  finally
    for r in release do r.resolve ()
    for task in tasks do discard <| IO.wait task
    for job in jobs do pool.releaseReply job
  check ((← charged pool) == 0) "mixed retirement order leaked reply storage"
  let failure ← freshJob "encoder-failure" deadline
  check (← rejects (try
    discard <| pool.withReplyEncoding failure () (fun _ => throw (IO.userError "original encoder error"))
    finally pool.finishReplyProducer failure)) "encoder error disappeared"
  check ((← charged pool) == maximum) "failure returned storage before receiver cleanup"
  pool.releaseReply failure
  check ((← charged pool) == 0) "failed producer leaked its receiver's charge"
  let expired ← freshJob "expired" 0
  check ((← pool.withReplyEncoding expired () (fun _ => throw (IO.userError "expired encoder executed"))).isNone)
    "expired request admitted an encoder"
  pool.finishReplyProducer expired
  pool.releaseReply expired
  -- All 80 independent clients may reach this stage; the existing bytes cap
  -- bounds simultaneous encoders rather than reducing the search actor count.
  let input := String.ofList (List.replicate (4*1024*1024) 'x')
  let counter ← Std.Mutex.new ({} : Counter)
  let began ← IO.monoMsNow
  let actors ← (Array.range 80).mapM fun i => IO.asTask (do
    let job ← freshJob s!"parallel-{i}" deadline
    let invoked ← IO.mkRef false
    try
      let result ← pool.withReplyEncoding job input fun text => do
        check ((← charged pool) ≥ maximum) "encoder started before its storage existed"
        counter.atomically do
          let c ← get
          set ({active := c.active+1,peak := max c.peak (c.active+1),entered := c.entered+1} : Counter)
        invoked.set true
        IO.sleep 2
        return Json.mkObj [("payload",toJson text)]
      check result.isSome "live independent client lost its bounded reply"
    finally
      if ← invoked.get then counter.atomically (modify fun (c : Counter) => {c with active := c.active-1})
      pool.finishReplyProducer job
      pool.releaseReply job) .dedicated
  for actor in actors do TaskDeadline.wait actor deadline
  let elapsed := (← IO.monoMsNow)-began
  let c ← counter.atomically get
  check (c.entered == 80 && c.active == 0 && 0 < c.peak && c.peak ≤ 3 && (← charged pool) == 0)
    "reply admission lost a client or exceeded its existing storage capacity"
  IO.FS.writeFile (root/"report.json") (Json.mkObj [
    ("independentClients",toJson (80 : Nat)),("encodedPayloadCharacters",toJson input.length),
    ("allClientsEntered",toJson c.entered),("peakEncoders",toJson c.peak),("componentElapsedMs",toJson elapsed),
    ("replyCapacityBytes",toJson searchReplyCapacity),("finalReservedBytes",toJson (← charged pool)),
    ("consumerCancellationKeepsProducerStorage",toJson true),("producerCompletionKeepsReceiverStorage",toJson true),
    ("doubleCloseAndOriginalFailureHandled",toJson true),("expiredAndClosedEncodersNotInvoked",toJson true),
    ("fullHooksOrGrowingProjectLoad",toJson false),("answeringModelCalls",toJson (0 : Nat)),("adopted",toJson false)]).compress

def run (root : System.FilePath) : IO Unit := do
  let pool ← Pool.new
  try runUsing pool root
  finally pool.readers.close

end Eggshell.Research.ReplyOwnershipChecks
