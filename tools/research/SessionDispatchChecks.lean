import Main
import Eggshell.ContractAudit
open Lean Eggshell Eggshell.Plugin
namespace Eggshell.Research.SessionDispatchChecks
#print axioms OperationPlan.requests_bounded
#print axioms OperationPlan.bytes_bounded
#print axioms OperationPlan.searches_bounded
#print axioms OperationPlan.closed_starts_no_search
#print axioms Worker.SearchEnvironment.foreign_session_rejected
def check (accepted : Bool) (message : String) : IO Unit := unless accepted do throw (IO.userError message)
def job (id session : String) (role : OperationWire.Role := .search) (bytes : Nat := 10) : OperationPlan.Job :=
  ⟨id,role,bytes,1000,session⟩
def policy : IO Unit := do
  let mut state := OperationPlan.initial
  for index in [:80] do
    let (next,accepted) := OperationPlan.admit state (job s!"query-{index}" s!"chat-{index}")
    check accepted "eighty independent chats were not admitted"
    state := next
  let mut active := #[]
  for _ in [:80] do
    let (next,some running) := OperationPlan.takeSearch state 0 | throw (IO.userError "search actor waited for a process lane")
    state := next
    active := active.push running
  check (state.contents.searches.size == 80 && state.contents.pending.isEmpty) "eighty actors did not start independently"
  let some first := active[0]? | throw (IO.userError "active query missing")
  let stale := OperationPlan.finishSearch state first.job.id (first.token+1)
  check (stale.contents.searches.size == 80) "foreign token completed another actor"
  let done := OperationPlan.finishSearch state first.job.id first.token
  check (done.contents.searches.size == 79) "correct actor did not finish independently"
  let (queued,accepted) := OperationPlan.admit state (job "same-chat" first.job.session)
  check accepted "same chat request could not wait"
  check ((OperationPlan.takeSearch queued 0).2.isNone) "same chat mutated two reader lifetimes concurrently"
  let freed := OperationPlan.finishSearch queued first.job.id first.token
  let (_,some second) := OperationPlan.takeSearch freed 0 | throw (IO.userError "next request did not inherit its own chat")
  check (second.job.id == "same-chat" && second.token != first.token) "request token was reused"
  let stopped := OperationPlan.close state
  check ((OperationPlan.takeSearch stopped 0).2.isNone &&
    !(OperationPlan.admit stopped (job "closed" "closed")).2) "closed dispatcher started work"
  let saveLane : OperationPlan.Lane := ⟨0,by decide⟩
  let (withSave,accepted) := OperationPlan.admit state (job "save" "writer" .save)
  check accepted "save could not enter its independent route"
  check ((OperationPlan.take withSave saveLane 0).2.isSome) "eighty searches blocked a save lane"
  let mut full := OperationPlan.initial
  for index in [:OperationPlan.maxRequests] do
    let (next,ok) := OperationPlan.admit full (job (toString index) (toString index))
    check ok "request bound was reduced accidentally"
    full := next
  check (!(OperationPlan.admit full (job "overflow" "overflow")).2) "metadata count bound overflowed"
  let (large,_) := OperationPlan.admit OperationPlan.initial (job "large" "large" .search OperationPlan.maxBytes)
  check (!(OperationPlan.admit large (job "overflow" "overflow")).2) "metadata byte bound overflowed"

def cancellation : IO Unit := do
  let retiredA ← IO.mkRef false
  let retiredB ← IO.mkRef false
  let now ← IO.monoMsNow
  let action := fun (retired : IO.Ref Bool) (result duration : Nat) (ready : IO Unit) => do
    try
      ready
      let finishAt := (← IO.monoMsNow)+duration
      while (← IO.monoMsNow) < finishAt do
        TaskDeadline.ensureLive (now+2000)
        IO.sleep 2
      return result
    finally retired.set true
  let a ← IO.asTask (OperationPool.ownedPhase (now+2000) (now+1000) (action retiredA 3 1500) (fun _ => pure ())) .dedicated
  let b ← IO.asTask (OperationPool.ownedPhase (now+2000) (now+1000) (action retiredB 7 60) (fun _ => pure ())) .dedicated
  IO.sleep 20
  IO.cancel a
  let failed ← IO.wait a
  let succeeded ← IO.wait b
  check (failed.toOption.isNone && succeeded.toOption == some 7 && (← retiredA.get) && (← retiredB.get))
    "cancelling one actor stopped a peer or left its own task running"
  let deadline ← IO.monoMsNow
  let retired ← IO.mkRef false
  let short ← try
    let _ ← OperationPool.ownedPhase (deadline+200) (deadline+25) (fun _ => do
      try
        repeat
          TaskDeadline.ensureLive (deadline+1000)
          IO.sleep 2
        pure (0 : Nat)
      finally retired.set true) (fun _ => pure ())
    pure false
    catch _ => pure true
  check (short && (← retired.get)) "expired actor was not cancelled and joined"
  let quick ← OperationPool.ownedPhase ((← IO.monoMsNow)+200) ((← IO.monoMsNow)+100)
    (fun _ => pure (11 : Nat)) (fun _ => pure ())
  check (quick == 11) "completed actor without readiness stranded its observer"

def run (root : System.FilePath) : IO Unit := do
  check (!(← root.pathExists)) "preserve previous actor policy check"
  IO.FS.createDirAll root
  policy
  cancellation
  IO.FS.writeFile (root/"report.json") (Json.mkObj [("independentSearchActors",toJson (80 : Nat)),
    ("sameChatSequential",toJson true),("metadataAndCountBounds",toJson true),
    ("saveLanesRemainIndependent",toJson true),("staleTokensRejected",toJson true),
    ("cancelledTaskJoinedPeerCompleted",toJson true),("expiredTaskJoined",toJson true),
    ("actualHookCapacityTested",toJson false),("adopted",toJson false)]).pretty
end Eggshell.Research.SessionDispatchChecks
def main (args : List String) : IO UInt32 := do
  match args with
  | ["session-dispatch-policy",root] => Eggshell.Research.SessionDispatchChecks.run (.mk root); return 0
  | ["front-traffic-audit",source] =>
    let result ← IO.Process.output {
      cmd := "/Users/ovm/.codex/experiments/eggshell/scope-token-study-20261028/fixed-frame-study/metadata-ingress-candidate-build/StudyMain"
      args := #["front-traffic-audit",source]}
    IO.print result.stdout
    IO.eprint result.stderr
    return result.exitCode
  | other => sourceRouteEngine other
