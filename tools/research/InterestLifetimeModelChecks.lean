import Eggshell.PreparationPlan

open Lean Eggshell
namespace Eggshell.Research.InterestLifetimeModelChecks
open PreparationPlan

def lane : Lane := ⟨0,by decide⟩
def otherLane : Lane := ⟨1,by decide⟩

def check (condition : Bool) (message : String) : IO Unit :=
  unless condition do throw (IO.userError message)

def key : String := String.ofList (List.replicate 64 'a')

def job (name : String := "shared") : Job :=
  {key := name,source := name,semantic := none,payload := Json.null,bytes := 128,durable := false}

def grant (state : State) (expires : Nat := 1000) (now : Nat := 0) : IO (State × Ticket) := do
  let (next,some token) := openWaiter state key expires now |
    throw (IO.userError "waiter registration refused")
  return (next,token)

def audit : IO Unit := do
  let mut state := initial
  let mut tickets := #[]
  for _ in [:80] do
    let (next,token) ← grant state
    let (next,accepted) := demand next job token 0
    check accepted "one of eighty waiters was refused"
    state := next
    tickets := tickets.push token
  check (state.contents.pending.size == 1 && state.contents.waiters.size == 80 &&
    state.contents.claimReferences == 80) "shared preparation multiplied into per-waiter jobs"
  let (next,some active) := take state lane 1 | throw (IO.userError "shared work did not start")
  state := next
  for token in tickets.extract 0 79 do
    state := release state token 2
  check (state.contents.pending.isEmpty && state.contents.active.size == 1 &&
    state.contents.active.all (·.job.live 2) && state.contents.claimReferences == 1)
    "cancelling other waiters stopped the remaining live waiter"
  let (same,stop) := claimRetirement state lane active.token 2
  check (!stop && same.contents.retirements == 0) "live shared work was retired"
  let some last := tickets[79]? | throw (IO.userError "missing last waiter")
  state := release state last 3
  check (state.contents.active.size == 1 && state.contents.claimReferences == 0 &&
    state.contents.waiters.isEmpty) "active slot was recycled before its IO stopped"
  let (_,revived) := demand state job last 3
  check (!revived) "late demand reopened a released ticket"
  let (next,stop) := claimRetirement state lane active.token 3
  check stop "unneeded active attempt was not marked retiring"
  let (next,newTicket) ← grant next 1000 3
  check (newTicket.id > last.id) "waiter serial was reused"
  let (next,admitted) := demand next job newTicket 3
  check (admitted && next.contents.pending.size == 1) "late valid waiter revived a retiring attempt"
  let (_,early) := take next otherLane 3
  check early.isNone "same source ran while the old IO still owned it"
  let next := finish next lane active.token 4 false
  check (next.contents.retried == 0 && next.contents.active.isEmpty) "cancelled attempt retried"
  let (next,some successor) := take next lane 4 | throw (IO.userError "successor did not start")
  let (same,stop) := claimRetirement next lane active.token 1001
  check (!stop && same.contents.retirements == next.contents.retirements &&
    (finish same lane active.token 1001 true).contents.active.size == 1)
    "stale attempt token changed its successor"
  let ended := finish (release next newTicket 5) lane successor.token 5 false
  check (ended.contents.count == 0 && ended.contents.charge == 0) "last release leaked charged metadata"

  let (pending,token) ← grant initial 100 0
  let mut saturated := pending
  for index in [:maxRequests] do
    let (next,accepted) := demand saturated (job s!"source-{index}") token 0
    check accepted "bounded queue refused an in-bound source"
    saturated := next
  let (_,overflow) := demand saturated (job "overflow") token 0
  check (!overflow && saturated.contents.count == maxRequests) "queue capacity was bypassed"
  let expired := reap saturated 100
  check (expired.contents.count == 0 && expired.contents.charge == 0 &&
    expired.contents.expiredReferences == maxRequests) "expired requests filled the queue permanently"
  let (_,revived) := demand expired job token 100
  check (!revived) "late demand reopened an expired ticket"
  let (again,newTicket) ← grant expired 200 100
  let (again,accepted) := demand again job newTicket 100
  check (accepted && again.contents.count == 1) "saturated queue failed to recover after expiry"
  let empty := release again newTicket 100
  check (empty.contents.count == 0 && empty.contents.charge == 0) "pending release did not refund admission"

  let mut grants := initial
  for _ in [:maxRequests] do
    let (next,_) ← grant grants
    grants := next
  check (openWaiter grants key 1000 0).2.isNone "waiter grants were unbounded"
  check ((reap grants 1000).contents.charge == 0) "unused expired grants leaked metadata"

  let (mixed,token) ← grant initial
  let (mixed,_) := demand mixed job token 0
  let (mixed,accepted) := notify mixed {job "durable" with durable := true}
  check accepted "durable publication wake refused"
  let mixed := release mixed token 1
  check (mixed.contents.pending.size == 1 && mixed.contents.pending.all (·.durable))
    "releasing a query deleted durable publication work"
  let (mixed,some active) := take mixed lane 1 | throw (IO.userError "durable work did not start")
  let (mixed,accepted) := notify mixed active.job
  check (accepted && mixed.contents.pending.size == 1) "new durable wake vanished into active work"
  let mixed := finish mixed lane active.token 2 true
  check (mixed.contents.pending.size == 1) "older completion cleared a newer durable wake"
  let closed := close mixed
  check ((openWaiter closed key 1000 2).2.isNone && !(notify closed job).2 &&
    (take closed lane 2).2.isNone && closed.contents.waiters.isEmpty)
    "terminal closure allowed new work"
  check ((openWaiter initial "bad" 1000 0).2.isNone &&
    (openWaiter initial key 0 0).2.isNone) "malformed or expired grant was accepted"
  IO.println "80 shared waiters; independent release; retirement; stale tokens; expiry; saturation; durable wakes: PASS"

end Eggshell.Research.InterestLifetimeModelChecks
