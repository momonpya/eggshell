module
public import Main
public import Eggshell.ContractAudit
public import tools.research.PinnedReads
@[expose] public section

namespace Eggshell.Research.PinnedReadsChecks
open Lean Eggshell Eggshell.Synapses Eggshell.DB
open CanonicalSource.Leases CanonicalSource.Leases.PinnedReads

def check (ok : Bool) (message : String) : IO Unit := unless ok do throw (IO.userError message)
def rejects (work : IO α) : IO Bool := try discard work; pure false catch _ => pure true

#print axioms Pin.original_source
#print axioms Pin.live_on_admission
#print axioms Pin.expires_at_original_boundary
#print axioms Read.original_source
#print axioms Read.original_metadata
#print axioms acquire_budget
#print axioms acquire_descriptors

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
    let some value := (env.find? name).bind (·.value?) | throwError "missing actual implementation {name}"
    pure value
  let mut pending := [``resolve,``acquire,``finish,``Read.loaded]
  let mut seen : Std.HashSet Name := {}
  while let some name := pending.head? do
    pending := pending.tail!
    if seen.contains name then continue
    seen := seen.insert name
    if ["Std.Mutex.","IO.Ref.","IO.Promise.","IO.asTask","IO.wait","IO.sleep","IO.Prim."].any
        (fun stem => name.toString.startsWith stem) then
      throwError "immutable source resolution reaches synchronization {name}"
    if let some value := (env.find? name).bind (·.value?) then pending := value.getUsedConstants.toList++pending
  unless occurrences ``Std.Mutex.atomically (← body ``withBatch) == 2 do
    throwError "pinning must synchronize only at entry and finalization"
  let reading ← body ``Plugin.Publication.Service.readSourceViews
  unless occurrences ``withBatch reading == 1 &&
      occurrences ``Plugin.Publication.Service.authorizeBatch reading == 1 &&
      occurrences ``Plugin.Publication.Service.readPinnedSourceViews reading == 1 do
    throwError "ordinary source views bypass their one pin boundary"
  let inner ← body ``Plugin.Publication.Service.readPinnedSourceViews
  unless occurrences ``Plugin.Publication.Service.withBatchSource inner == 0 &&
      occurrences ``withBatch inner == 0 do
    throwError "ordinary retained source reads still reborrow the mutable registry"
  logInfo m!"{seen.size} pure source-resolution dependencies without synchronization; actual ordinary batch connected"

def prepare (root : System.FilePath) : IO (PageMap.Snapshot × CanonicalSource.Cache.Manifest × System.FilePath) := do
  let source ← PageMap.create (root/"source.egg") "pin-boundary-control"
  let tool : Plugin.ToolEvent := {
    name := "mcp__catalog__read",useId := "original",
    input := "{\"resource\":\"catalog://one\"}",response := "{\"id\":\"ORIGINAL_VALUE\"}"}
  let relation := (Plugin.compileOperationOutcomes (.text "seed") (.text "turn") tool).2
  discard <| PageMap.withWriter source fun writer => do
    let intern : Persistence.Store.Intern := ⟨writer,← IO.mkRef {}⟩
    let id ← intern.root relation
    Persistence.Store.writeChange writer {added := [id],removed := [],unionsChanged := false,affected := [id]}
  let source ← PageMap.pin source.directory
  discard <| Build.refresh source .database
  let ready ← CanonicalSource.Cache.refresh source .database
  let directory ← CanonicalSource.Cache.directory source .database
  return (source,ready.metadata,directory)

def run (root : System.FilePath) : IO Unit := do
  check (!(← root.pathExists)) "fresh private control root required"
  IO.FS.createDirAll root
  let (source,metadata,directory) ← prepare root
  let originalHead ← IO.FS.readFile (source.directory/"head")
  let originals ← CanonicalSource.Shared.Pool.new
  let pool ← Pool.new originals
  let scope := "scope-one"
  let deadline := (← IO.monoMsNow)+28000
  let (token,_,_) ← pool.retain scope source directory metadata deadline deadline
  let request : Request := ⟨token,scope,source.head,metadata⟩
  try
    let before ← pool.stats
    let requests := [request,request]
    let readMs ← withBatch pool requests deadline fun batch => do
      check (batch.pins.length == 2) "pin boundary dropped a repeated source"
      let began ← IO.monoMsNow
      pool.state.atomically do
        let actors ← (Array.range 80).mapM fun _ => IO.asTask (do
          for _ in [:128] do
            let read ← IO.ofExcept (resolve batch.pins request (← IO.monoMsNow))
            check (read.loaded.metadata == metadata && read.pin.descriptor.source == source.head)
              "immutable lookup changed original binding") .dedicated
        try
          for actor in actors do TaskDeadline.wait actor deadline
        finally
          for actor in actors do IO.cancel actor
          for actor in actors do discard <| IO.wait actor
      let elapsed := (← IO.monoMsNow)-began
      let now ← IO.monoMsNow
      let variants : List Request := [
        {request with token := "foreign"},{request with scope := "foreign"},
        {request with source := {source.head with revision := source.head.revision+1}},
        {request with metadata := {metadata with payload := "foreign"}}]
      for variant in variants do
        check (!(resolve batch.pins variant now).isOk) "foreign request resolved a pinned original"
      check (!(resolve batch.pins request deadline).isOk) "expired request resolved a pinned original"
      pool.release token scope
      check (← rejects (withBatch pool [request] deadline (fun _ => pure ()))) "release admitted a new batch"
      check ((resolve batch.pins request now).isOk) "revocation invalidated an already admitted operation"
      let held ← pool.stats
      check (held.getObjValD "readers" == toJson (2 : Nat) && held.getObjValD "active" == toJson (1 : Nat))
        "release retired an actively pinned descriptor"
      return elapsed
    let after ← pool.stats
    check (after.getObjValD "active" == toJson (0 : Nat) && after.getObjValD "chargedBytes" == toJson (0 : Nat))
      "batch finalization leaked an arena or a handle charge"
    let (token,_,_) ← pool.retain scope source directory metadata deadline deadline
    let request := {request with token}
    let beforeFailure ← pool.stats
    check (← rejects (withBatch pool [request,{request with token := "missing"}] deadline (fun _ => pure ())))
      "partial batch was admitted"
    let afterFailure ← pool.stats
    check (beforeFailure == afterFailure) "failed batch partially changed its registry"
    let entered : IO.Promise Unit ← IO.Promise.new
    let actor ← IO.asTask (withBatch pool [request] deadline fun _ => do
      entered.resolve ()
      repeat
        if ← IO.checkCanceled then throw (IO.userError "cancelled control")
        IO.sleep 1) .dedicated
    try
      TaskDeadline.wait (Std.Async.AsyncTask.ofPurePromise entered) deadline
      pool.close
      check (← rejects (withBatch pool [request] deadline (fun _ => pure ()))) "closed pool admitted a new batch"
    finally
      IO.cancel actor
      discard <| IO.wait actor
    let closed ← pool.stats
    check (closed.getObjValD "active" == toJson (0 : Nat) && closed.getObjValD "chargedBytes" == toJson (0 : Nat))
      "cancelled batch leaked a descriptor or charge"
    -- Empty batches have no lease registry dependency at all.
    pool.state.atomically do
      let work ← IO.asTask (withBatch pool [] deadline fun batch =>
        check batch.pins.isEmpty "empty batch invented a source") .dedicated
      try TaskDeadline.wait work deadline
      finally IO.cancel work; discard <| IO.wait work
    check ((← IO.FS.readFile (source.directory/"head")) == originalHead) "reader changed the original DB"
    IO.FS.writeFile (root/"report.json") (Json.mkObj [
      ("parallelReaders",toJson (80 : Nat)),("readsEach",toJson (128 : Nat)),("elapsedMs",toJson readMs),
      ("registryMutexHeldThroughoutReads",toJson true),("partialFailureAtomic",toJson true),
      ("fullScopeSourceManifestDeadlineChecked",toJson true),("releaseAndCloseRejectNewAdmissions",toJson true),
      ("existingBorrowSurvivesRevocation",toJson true),("duplicatePinsAndCancellationReleased",toJson true),
      ("emptyBatchDoesNotLock",toJson true),("originalHeadUnchanged",toJson true),
      ("before",before),("after",after),("closed",closed),
      ("wholeSearchLockFree",toJson false),("answeringModelCalls",toJson (0 : Nat)),("adopted",toJson false)]).compress
  finally
    pool.close
    originals.close

end Eggshell.Research.PinnedReadsChecks
