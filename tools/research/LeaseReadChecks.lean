import Main
import Eggshell.ContractAudit
open Lean Eggshell Eggshell.Synapses Eggshell.DB
namespace Eggshell.Research.LeaseReadChecks
open CanonicalSource.Leases
def check (ok : Bool) (message : String) : IO Unit := unless ok do throw (IO.userError message)
def rejects (work : IO α) : IO Bool := try discard work; pure false catch _ => pure true

#print axioms ReadCut.live
#print axioms ReadCut.same_source
#print axioms ReadCut.reader_owned
#print axioms ReadCut.budget_unchanged
#print axioms ReadCut.descriptors_unchanged

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
    let some value := (env.find? name).bind (·.value?) | throwError "missing actual lease implementation {name}"
    pure value
  let reading ← body ``Pool.withHeld
  unless occurrences ``Std.Mutex.atomically reading == 1 &&
      occurrences ``Pool.reap reading == 0 && occurrences ``State.readCut reading == 1 &&
      occurrences ``Pool.finishRead reading == 1 do
    throwError "lease reading repeats a sweep, drops its checked boundary or loses the finalizer"
  unless occurrences ``Pool.reap (← body ``Pool.retain) == 1 do
    throwError "admission must reclaim expired tokens before retaining more memory"
  let mut pending := [``State.readCut,``ReadCut.next,``ReadCut.descriptor]
  let mut seen : Std.HashSet Name := {}
  while let some name := pending.head? do
    pending := pending.tail!
    if seen.contains name then continue
    seen := seen.insert name
    if ["Std.Mutex.","IO.Ref.","IO.Promise.","IO.asTask","IO.wait","IO.sleep","IO.Prim."].any
        (fun stem => name.toString.startsWith stem) then
      throwError "pure checked descriptor reaches synchronization {name}"
    if let some value := (env.find? name).bind (·.value?) then pending := value.getUsedConstants.toList++pending
  logInfo m!"Actual lease path: one borrow boundary, no sweep; {seen.size} checked descriptor dependencies have no shared synchronization"

def run (root : System.FilePath) : IO Unit := do
  check (!(← root.pathExists)) "new lease read controls root required"
  IO.FS.createDirAll root
  let path : System.FilePath := "/Users/ovm/.codex/experiments/eggshell/scope-token-study-20261028/fixed-frame-study/frontend-quiescence-fixture-small1/work.project/owners/0/source.egg"
  let source ← PageMap.pin path
  let head ← IO.FS.readFile (path/"head")
  discard <| Build.refresh source .user
  let refreshed ← CanonicalSource.Cache.refresh source .user
  let cachePath ← CanonicalSource.Cache.directory source .user
  let originals ← CanonicalSource.Shared.Pool.new
  let pool ← Pool.new originals
  let deadline := (← IO.monoMsNow)+28000
  let scope := "private-native-control"
  let (token,loaded,_) ← pool.retain scope source cachePath refreshed.metadata deadline deadline
  try
    let before ← pool.stats
    let now ← IO.monoMsNow
    let state ← pool.state.atomically get
    let cut ← IO.ofExcept (state.readCut token scope source.head refreshed.metadata now deadline)
    check (cut.descriptor.loaded.metadata == loaded.metadata && cut.next.budget.used == state.budget.used)
      "checked borrow changed its manifest or memory charge"
    let some held := state.entries[token]? | throw (IO.userError "missing control token")
    let some descriptor := state.descriptors[held.descriptor]? | throw (IO.userError "missing control descriptor")
    let variants : Array (State × String × String × PageMap.Head × CanonicalSource.Cache.Manifest × Nat × Nat) := #[
      (state,token,scope,source.head,refreshed.metadata,now,deadline),
      (state,"missing",scope,source.head,refreshed.metadata,now,deadline),
      (state,token,"foreign",source.head,refreshed.metadata,now,deadline),
      (state,token,scope,{source.head with revision := source.head.revision+1},refreshed.metadata,now,deadline),
      (state,token,scope,source.head,{refreshed.metadata with payload := "foreign"},now,deadline),
      (state,token,scope,source.head,refreshed.metadata,held.deadline,deadline),
      (state,token,scope,source.head,refreshed.metadata,now,now),
      ({state with closed := true},token,scope,source.head,refreshed.metadata,now,deadline),
      ({state with entries := state.entries.insert token {held with released := true}},token,scope,source.head,refreshed.metadata,now,deadline),
      ({state with descriptors := state.descriptors.erase held.descriptor},token,scope,source.head,refreshed.metadata,now,deadline)]
    let mut comparisons := 0
    for (s,t,sc,h,m,n,d) in variants do
      let expected := match s.entries[t]? with
        | none => false
        | some held => match s.descriptors[held.descriptor]? with
          | none => false
          | some desc => !s.closed && !held.released && n < held.deadline && n < d && desc.accepts sc h m
      check ((s.readCut t sc h m n d).isOk == expected) "checked read differs from the exact parent read predicate"
      comparisons := comparisons+1
    -- A due token for another borrower remains charged during reads. A reader
    -- neither sweeps it nor grants it authority; explicit admission reaps it.
    let stale := "expired-other-reader"
    pool.state.atomically do
      let state ← get
      let some (state,_,_) := state.admit? stale descriptor 0 | throw (IO.userError "stale token setup failed")
      set {state with nextExpiry := some 0}
    let began ← IO.monoMsNow
    let actors ← (Array.range 80).mapM fun _ => IO.asTask (do
      for _ in [:128] do
        pool.withHeld token scope source.head refreshed.metadata deadline fun ready _ =>
          check (ready.metadata == loaded.metadata) "parallel read changed its source") .dedicated
    try
      for task in actors do Eggshell.TaskDeadline.wait task deadline
    finally
      for task in actors do IO.cancel task
      for task in actors do discard <| IO.wait task
    let elapsed := (← IO.monoMsNow)-began
    let remained ← pool.state.atomically do return (← get).entries.contains stale
    check remained "a read still sweeps unrelated tokens"
    check (← rejects (pool.withHeld stale scope source.head refreshed.metadata deadline (fun _ _ => pure ())))
      "expired unrelated token gained read authority"
    let (extra,_,_) ← pool.retain scope source cachePath refreshed.metadata deadline deadline
    check (!(← pool.state.atomically do return (← get).entries.contains stale)) "explicit reclaim stopped working"
    pool.release extra scope
    -- Revocation while reading keeps the descriptor and its charge until the
    -- existing finalizer returns; new readers are rejected immediately.
    pool.withHeld token scope source.head refreshed.metadata deadline fun _ _ => do
      pool.release token scope
      check (← rejects (pool.withHeld token scope source.head refreshed.metadata deadline (fun _ _ => pure ())))
        "released token admitted a new reader"
      let during ← pool.stats
      check (during.getObjValD "readers" == toJson (1 : Nat) && during.getObjValD "active" == toJson (1 : Nat))
        "release disposed an actively borrowed descriptor"
    let after ← pool.stats
    check (after.getObjValD "active" == toJson (0 : Nat) && after.getObjValD "chargedBytes" == toJson (0 : Nat))
      "final reader leaked its descriptor or charge"
    let (cancelling,_,_) ← pool.retain scope source cachePath refreshed.metadata deadline deadline
    let entered : IO.Promise Unit ← IO.Promise.new
    let actor ← IO.asTask (pool.withHeld cancelling scope source.head refreshed.metadata deadline fun _ _ => do
      entered.resolve ()
      repeat
        if ← IO.checkCanceled then throw (IO.userError "cancelled descriptor borrower")
        IO.sleep 1) .dedicated
    try
      Eggshell.TaskDeadline.wait (Std.Async.AsyncTask.ofPurePromise entered) deadline
      pool.close
      check (← rejects (pool.withHeld cancelling scope source.head refreshed.metadata deadline (fun _ _ => pure ())))
        "closed pool admitted a new reader"
      let closing ← pool.stats
      check (closing.getObjValD "readers" == toJson (1 : Nat)) "close dropped an active borrower"
    finally
      IO.cancel actor
      discard <| IO.wait actor
    let cancelled ← pool.stats
    check (cancelled.getObjValD "active" == toJson (0 : Nat) && cancelled.getObjValD "chargedBytes" == toJson (0 : Nat))
      "cancellation or close leaked its descriptor charge"
    check ((← IO.FS.readFile (path/"head")) == head) "read controls changed original DB head"
    IO.FS.writeFile (root/"report.json") (Json.mkObj [("parentPolicyComparisons",toJson comparisons),
      ("parallelReaders",toJson (80 : Nat)),("readsEach",toJson (128 : Nat)),("elapsedMs",toJson elapsed),
      ("unrelatedSweepAbsent",toJson true),("expiredReadRejected",toJson true),
      ("explicitReclaimWorks",toJson true),("activeReleaseAndFinalizerPreserved",toJson true),
      ("closeAndCancellationReleaseCharges",toJson true),
      ("fullSourceManifestLifetimeChecks",toJson true),("originalHeadUnchanged",toJson true),
      ("before",before),("after",after),("wholeSearchLockFree",toJson false),("adopted",toJson false)]).compress
  finally
    pool.close
    originals.close
def main (args : List String) : IO Unit := do
  let [root] := args | throw (IO.userError "fresh lease read controls root required")
  run (.mk root)
end Eggshell.Research.LeaseReadChecks
def main := Eggshell.Research.LeaseReadChecks.main
