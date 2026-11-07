import tools.research.EncoderPool
import Lean.Data.Json.FromToJson
import Init.System.Promise
import Lean
open Lean Eggshell.Research.EncoderPool
namespace Eggshell.Research.EncoderPoolControls
run_elab do
  let environment ← Lean.getEnv
  let some body := (environment.find? ``awaitWake).bind (·.value?) | throwError "Missing encoder event wait"
  for forbidden in [``Std.Mutex.atomically,``Std.Mutex.tryAtomically,``Pool.take?,``Pool.takeOrWatch,``IO.sleep] do
    if body.getUsedConstants.contains forbidden then throwError "Encoder event wait polls the pool or sleeps a thread"

#check WakeQueue.register_fresh
#check WakeQueue.remove_preserves_generation
#check WakeQueue.removed_absent
#check State.notification_preserves_credits
#check State.notification_preserves_generation
def check (ok : Bool) (message : String) : IO Unit := unless ok do throw (IO.userError message)
def rejects (action : IO α) : IO Bool := try discard action; pure false catch _ => pure true
def waitUntil (condition : IO Bool) : IO Unit := do
  let deadline := (← IO.monoMsNow)+3000
  repeat
    if ← condition then return
    check ((← IO.monoMsNow) < deadline) "pool concurrency barrier expired"
    IO.sleep 1

def overlap : IO Json := do
  let pool ← Pool.make (α := Nat) 2
  let entered ← Std.Mutex.new (#[] : Array Nat)
  let finished ← Std.Mutex.new (0 : Nat)
  let release ← IO.Promise.new
  let disposed ← Std.Mutex.new (0 : Nat)
  let dispose := fun (_ : Nat) => disposed.atomically (modify (·+1))
  let tasks ← (Array.range 2).mapM fun _ => IO.asTask (pool.withResource (pure true)
    (fun ticket => pure ticket.index) dispose fun _ value _ => do
      entered.atomically (modify (·.push value))
      discard <| IO.wait release.result!
      finished.atomically (modify (·+1))
      return value) .dedicated
  try
    waitUntil (do return (← entered.atomically get).size == 2)
    check ((← pool.take?).isNone) "third request acquired an already owned slot"
    let values ← entered.atomically get
    check (values.toList.eraseDups.length == 2) "two concurrent owners received the same pipe slot"
    -- Both callbacks must finish their work while management is held. Their
    -- short give-back is intentionally allowed only after this lock releases.
    pool.state.atomically do
      release.resolve ()
      waitUntil (do return (← finished.atomically get) == 2)
    for task in tasks do discard <| IO.ofExcept (← IO.wait task)
    let snapshot ← pool.state.atomically get
    check (snapshot.starts == 2 && snapshot.slots.size == 2) "pool grew past its resident credits"
    check (snapshot.waiting == 0 && (snapshot.slots.filter Slot.isIdle).size == 1 &&
      (← disposed.atomically get) == 1) "spare idle model was retained after all work returned"
    let reused ← pool.withResource (pure true) (fun _ => throw (IO.userError "warm reuse spawned a third encoder"))
      dispose (fun _ resource _ => pure resource)
    check (values.contains reused) "warm reuse returned an unregistered encoder"
    pool.close dispose
    check ((← disposed.atomically get) == 2) "close lost or repeated an encoder retirement"
    check (← rejects (pool.withResource (pure true) (fun _ => pure 9) dispose (fun _ value _ => pure value)))
      "closed pool accepted a new encoder"
    return Json.mkObj [("simultaneousOwners",toJson (2 : Nat)),("differentPipeSlots",toJson true),
      ("workFinishedWhileManagementLockHeld",toJson true),("warmReuseDidNotSpawn",toJson true),
      ("boundedAndExactlyOnceClose",toJson true),("oneIdleAfterWork",toJson true)]
  finally
    release.resolve ()
    for task in tasks do IO.cancel task
    for task in tasks do discard <| IO.wait task

def retiring : IO Json := do
  let pool ← Pool.make (α := Nat) 1
  let entered ← IO.Promise.new
  let release ← IO.Promise.new
  let disposed ← IO.mkRef (0 : Nat)
  let dispose := fun (_ : Nat) => do
    disposed.modify (·+1)
    entered.resolve ()
    discard <| IO.wait release.result!
  let work ← IO.asTask (show IO Unit from pool.withResource (pure true) (fun _ => pure 7) dispose fun _ _ retire => do
    retire
    throw (IO.userError "fixture inference failed")) .dedicated
  try
    waitUntil (do return (← disposed.get) == 1)
    check ((← pool.take?).isNone) "retiring process released its resident credit too early"
    let state ← pool.state.atomically get
    check (match state.slots[0]? with | some (Slot.retiring _ _) => true | _ => false)
      "unjoined child is not retained as retiring"
    release.resolve ()
    let result ← IO.wait work
    let failed := match result with | .error _ => true | .ok _ => false
    check (failed && (← disposed.get) == 1) "transport failure lost or repeated retirement"
    let some next ← pool.take? | throw (IO.userError "confirmed stop did not restore its credit")
    let old : Ticket Nat := {index := 0,token := next.token-1,cached := none}
    pool.giveBack old false dispose
    let state ← pool.state.atomically get
    check (match state.slots[0]? with | some (Slot.running token _) => token == next.token | _ => false)
      "late completion changed a new request's slot"
    pool.giveBack next false dispose
    pool.close dispose
    check ((← disposed.get) == 1) "empty startup reservation disposed a resource twice"
    return Json.mkObj [("creditHeldUntilStopFinished",toJson true),
      ("failureRetiredOnce",toJson true),("lateCompletionRejected",toJson true)]
  finally
    release.resolve ()
    IO.cancel work
    discard <| IO.wait work

def failureAndClose : IO Json := do
  let pool ← Pool.make (α := Nat) 1
  let disposed ← IO.mkRef (0 : Nat)
  let dispose := fun (_ : Nat) => disposed.modify (·+1)
  check (← rejects (pool.withResource (pure true) (fun _ => throw (IO.userError "fixture spawn failed"))
    dispose (fun _ resource _ => pure resource))) "startup failure was accepted"
  check ((← disposed.get) == 0) "failed startup retired an unrelated resource"
  let entered ← IO.Promise.new
  let release ← IO.Promise.new
  let work ← IO.asTask (pool.withResource (pure true) (fun _ => pure 11) dispose fun _ resource _ => do
    entered.resolve ()
    discard <| IO.wait release.result!
    return resource) .dedicated
  try
    discard <| IO.wait entered.result!
    pool.close dispose
    check ((← disposed.get) == 0) "shutdown stopped a pipe still owned by its request"
    release.resolve ()
    check ((← IO.ofExcept (← IO.wait work)) == 11 && (← disposed.get) == 1)
      "active owner did not retire on return to the closed pool"
    return Json.mkObj [("failedStartupReleasedCredit",toJson true),
      ("shutdownPreservedActiveOwner",toJson true),("activeReturnRetiredExactlyOnce",toJson true)]
  finally
    release.resolve ()
    IO.cancel work
    discard <| IO.wait work

def idlePreferred : IO Json := do
  let pool ← Pool.make (α := Nat) 2
  let some first ← pool.take? | throw (IO.userError "first slot missing")
  let some second ← pool.take? | throw (IO.userError "second slot missing")
  check (← pool.install first 1) "first resource rejected"
  check (← pool.install second 2) "second resource rejected"
  let disposed ← IO.mkRef ([] : List Nat)
  let dispose := fun value => disposed.modify (value :: ·)
  pool.giveBack first false dispose
  pool.giveBack second true dispose
  let reused ← pool.withResource (pure true) (fun _ => throw (IO.userError "spawned despite an idle model"))
    dispose (fun _ value _ => pure value)
  check (reused == 2) "empty slot was preferred to a warm encoder"
  pool.close dispose
  check ((← disposed.get).length == 2) "idle preference lost a model"
  return Json.mkObj [("warmModelPreferredOverEmptySlot",toJson true)]

def demandAndStandby : IO Json := do
  let pool ← Pool.make (α := Nat) 2
  let some first ← pool.take? | throw (IO.userError "first slot missing")
  let some second ← pool.take? | throw (IO.userError "second slot missing")
  check (← pool.install first 1) "first resource rejected"
  check (← pool.install second 2) "second resource rejected"
  let entered ← IO.Promise.new
  let release ← IO.Promise.new
  let stopped ← IO.Promise.new
  let disposed ← IO.mkRef ([] : List Nat)
  let dispose := fun value => do
    disposed.modify (value :: ·)
    if value == 2 then
      entered.resolve ()
      discard <| IO.wait release.result!
      stopped.resolve ()
  pool.state.atomically (modify fun state => {state with waiting := 1})
  pool.giveBack first true dispose
  pool.giveBack second true dispose
  let demanded ← pool.state.atomically get
  check ((demanded.slots.filter Slot.isIdle).size == 2 && (← disposed.get).isEmpty)
    "queued demand prematurely retired a useful model"
  let retiring ← IO.asTask (pool.finishWaiting dispose) .dedicated
  try
    discard <| IO.wait entered.result!
    let some kept ← pool.take? | throw (IO.userError "standby was lost while another model stops")
    check (kept.cached == some 1 && (← pool.take?).isNone) "retiring spare released its credit before stopping"
    pool.giveBack kept true dispose
    pool.state.atomically do
      release.resolve ()
      waitUntil stopped.isResolved
    discard <| IO.ofExcept (← IO.wait retiring)
    let quiet ← pool.state.atomically get
    check (quiet.waiting == 0 && (quiet.slots.filter Slot.isIdle).size == 1)
      "draining the last waiter did not trim the spare"
    pool.close dispose
    check ((← disposed.get).mergeSort (· ≤ ·) == [1,2]) "standby retirement lost or repeated a resource"
    return Json.mkObj [("queuedDemandKeptBothModels",toJson true),("oneStandbyAfterQueueDrained",toJson true),
      ("spareCreditHeldUntilStop",toJson true),("stoppingOutsideManagementLock",toJson true)]
  finally
    release.resolve ()
    IO.cancel retiring
    discard <| IO.wait retiring

def cancelledWaiter : IO Json := do
  let pool ← Pool.make (α := Nat) 1
  let some active ← pool.take? | throw (IO.userError "active slot missing")
  check (← pool.install active 7) "active resource rejected"
  let live ← IO.mkRef true
  let disposed ← IO.mkRef (0 : Nat)
  let dispose := fun (_ : Nat) => disposed.modify (·+1)
  let waiter ← IO.asTask (pool.withResource live.get (fun _ => pure 9) dispose (fun _ value _ => pure value)) .dedicated
  try
    waitUntil (do return (← pool.state.atomically get).waiting == 1)
    live.set false
    let result ← IO.wait waiter
    check (match result with | .error _ => true | _ => false) "expired waiter obtained a pipe"
    check ((← pool.state.atomically get).waiting == 0 && (← disposed.get) == 0)
      "expired waiter leaked demand or stopped another owner"
    pool.giveBack active true dispose
    pool.close dispose
    check ((← disposed.get) == 1) "waiter cleanup lost the active model"
    return Json.mkObj [("expiredWaiterRemovedDemand",toJson true),("activeOwnerPreserved",toJson true)]
  finally
    live.set false
    IO.cancel waiter
    discard <| IO.wait waiter

def notificationBeforeWait : IO Json := do
  let pool ← Pool.make (α := Nat) 1
  let some active ← pool.take? | throw (IO.userError "notification fixture lacks its active owner")
  let .inr watch ← pool.takeOrWatch | throw (IO.userError "full pool did not register a notification")
  pool.giveBack active false (fun _ => pure ())
  check (← watch.ready.isResolved) "return lost its notification before the observer registered"
  awaitWake watch (pure true)
  let some acquired ← pool.take? | throw (IO.userError "notification consumed a resource credit")
  pool.giveBack acquired false (fun _ => pure ())
  pool.close (fun _ => pure ())
  return Json.mkObj [("notificationBeforeObserverPreserved",toJson true),
    ("notificationDidNotConsumeOrCreateCredit",toJson true)]

def eightyWaiters (closing : Bool) : IO Json := do
  let pool ← Pool.make (α := Nat) 2
  let some first ← pool.take? | throw (IO.userError "first admission owner missing")
  let some second ← pool.take? | throw (IO.userError "second admission owner missing")
  check (← pool.install first 1) "first admission resource rejected"
  check (← pool.install second 2) "second admission resource rejected"
  let lives ← (Array.range 80).mapM fun _ => IO.mkRef true
  let calls ← (Array.range 80).mapM fun _ => IO.mkRef (0 : Nat)
  let active ← Std.Mutex.new (#[] : Array Nat)
  let maximum ← Std.Mutex.new (0 : Nat)
  let disposed ← Std.Mutex.new (0 : Nat)
  let dispose := fun (_ : Nat) => disposed.atomically (modify (·+1))
  let tasks ← (lives.zip calls).mapIdxM fun index (live,call) => IO.asTask (pool.withResource
    (do call.modify (·+1); live.get)
    (fun ticket => pure ticket.index) dispose fun ticket _ _ => do
      active.atomically do
        let slots ← get
        check (!slots.contains ticket.index) "two request owners acquired one inference credit"
        set (slots.push ticket.index)
        maximum.atomically (modify (max (slots.size+1)))
      -- A fixture operation yields while its credit remains exclusively owned.
      IO.sleep 2
      active.atomically (modify (·.filter (· != ticket.index)))
      return index) .dedicated
  try
    waitUntil (do return (← pool.state.atomically get).wake.items.toArray.size == 80)
    let queuedAt ← IO.monoMsNow
    IO.sleep 100
    let registered ← pool.state.atomically get
    check (registered.wake.next == 80 && registered.wake.items.toArray.size == 80)
      "blocked requests repeatedly re-registered with the resource pool"
    let liveChecks ← calls.mapM (·.get)
    check (liveChecks.all (· < 20)) "event waiter still spins at millisecond frequency"
    if closing then pool.close dispose
    else
      for (live,index) in lives.zipIdx do
        if index % 3 == 0 then live.set false
      waitUntil (do return (← pool.state.atomically get).wake.items.toArray.size == 53)
    let stateBeforeReturn ← pool.state.atomically get
    check ((← disposed.atomically get) == 0 && stateBeforeReturn.slots.size == 2)
      "cancellation or shutdown stopped an unrelated active owner"
    pool.giveBack first true dispose
    pool.giveBack second true dispose
    let rows ← tasks.mapM fun task => do return (← IO.wait task).isOk
    let expected := if closing then 0 else 53
    check ((rows.filter id).size == expected) "cancelled or closed requests crossed admission"
    check ((← maximum.atomically get) ≤ 2) "notification enlarged the inference capacity"
    let state ← pool.state.atomically get
    check (state.waiting == 0 && state.wake.items.isEmpty && (← active.atomically get).isEmpty)
      "event admission leaked a subscriber, demand or resource owner"
    pool.close dispose
    check ((← disposed.atomically get) ≥ 2) "event admission lost a resource during shutdown"
    return Json.mkObj [("blockedRequests",toJson (80 : Nat)),("completedRequests",toJson expected),
      ("rejectedRequests",toJson (80-expected)),("closedWhileQueued",toJson closing),
      ("maximumConcurrentCreditOwners",toJson (← maximum.atomically get)),
      ("oneSubscriptionDuringBlockedInterval",toJson true),
      ("observedCooperativeLiveChecks",toJson liveChecks),
      ("wallMsAfterRegistration",toJson ((← IO.monoMsNow)-queuedAt)),
      ("noRemainingWaitersOrOwners",toJson true)]
  finally
    for live in lives do live.set false
    pool.close dispose
    for task in tasks do IO.cancel task
    for task in tasks do discard <| IO.wait task

def run (output : System.FilePath) : IO Unit := do
  let stage := fun name action => do
    IO.eprintln ("checking "++name)
    action
  let report := Json.mkObj [("overlap",← stage "overlap" overlap),("retirement",← stage "retirement" retiring),
    ("failureAndShutdown",← stage "failureAndShutdown" failureAndClose),("idlePreferred",← stage "idlePreferred" idlePreferred),
    ("demandAndStandby",← stage "demandAndStandby" demandAndStandby),("cancelledWaiter",← stage "cancelledWaiter" cancelledWaiter),
    ("notificationBeforeWait",← stage "notificationBeforeWait" notificationBeforeWait),
    ("eightyWithCancellation",← stage "eightyWithCancellation" (eightyWaiters false)),
    ("eightyWithShutdown",← stage "eightyWithShutdown" (eightyWaiters true)),("allPassed",toJson true),
    ("realModelOrFullHookCapacity",toJson false),("adopted",toJson false)]
  IO.FS.writeFile output report.pretty
end Eggshell.Research.EncoderPoolControls
def main (args : List String) : IO Unit := do
  let [output] := args | throw (IO.userError "output required")
  Eggshell.Research.EncoderPoolControls.run (.mk output)
