import Main
import Eggshell.ContractAudit
import Eggshell.SearchReaders
open Lean Eggshell Eggshell.DB

#print axioms PageMap.SharedPageCache.epoch_budget
#print axioms PageMap.LocalPages.State.full_preserved
#print axioms PageMap.LocalPages.readView_valid
#print axioms SearchReaders.baseAtBoundary_live
#print axioms SearchReaders.baseAtBoundary_quiescent
#print axioms PreparedReaders.CheckedFrame.withBase_image

namespace QuiescentPagesChecks
def check (ok : Bool) (message : String) : IO Unit := unless ok do throw (IO.userError message)

def run (root : System.FilePath) : IO Unit := do
  check (!(← root.pathExists)) "fresh component output required"
  IO.FS.createDirAll root
  let empty ← PageMap.create (root/"source.egg") "quiescent-pages-test"
  discard <| PageMap.withWriter empty fun writer => writer.put "alpha" (some "original".toUTF8)
  let source ← PageMap.pin empty.directory
  let some ref := source.head.root | throw (IO.userError "missing test root")
  let loaded ← source.load ref
  let key := source.pageKey "scope-a" ref
  let owner ← PageMap.PagePool.new
  owner.insert key ⟨ref,loaded⟩
  let base ← owner.captureBase
  let frontA ← PageMap.LocalPages.Front.new .empty base
  let frontB ← PageMap.LocalPages.Front.new .empty base
  let a := PageMap.PagePool.reader frontA
  let b := PageMap.PagePool.reader frontB
  let .owner mutex := owner | throw (IO.userError "producer lost ownership")
  let entered : IO.Promise Unit ← IO.Promise.new
  let released : IO.Promise Unit ← IO.Promise.new
  let holding ← IO.asTask (mutex.atomically do entered.resolve (); discard <| IO.wait released.result!) .dedicated
  let mut task : Option (Task (Except IO.Error Unit)) := none
  try
    TaskDeadline.wait (Std.Async.AsyncTask.ofPurePromise entered) ((← IO.monoMsNow)+2000)
    let running ← IO.asTask (do
      check ((← a.find key ref).isSome) "immutable base miss"
      check ((← a.find ("scope-b",key.2) ref).isNone) "foreign scope accepted"
      check ((← a.find key {ref with checksum := ref.checksum++"changed"}).isNone) "changed descriptor accepted"
      let extra := ("local",key.2)
      a.insert extra ⟨ref,loaded⟩
      check ((← a.find extra ref).isSome && (← b.find extra ref).isNone) "fronts share mutations"
      let stats ← a.stats
      check (stats.getObjValD "sharedCacheTouched" == toJson false) "read touched cache owner"
      check ((stats.getObjValD "privateFront").getObjValD "immutableBaseHits" == toJson (1 : Nat)) "base hit not counted") .dedicated
    task := some running
    TaskDeadline.wait running ((← IO.monoMsNow)+1500)
  finally
    released.resolve ()
    discard <| IO.wait holding
    if let some running := task then discard <| IO.wait running

  let mut pressure := PageMap.LocalPages.State.empty
  for i in [:513] do pressure := pressure.insert (toString i,key.2) ⟨ref,loaded⟩
  check (pressure.entries.size ≤ 512 && pressure.bytes ≤ 2097152) "front bound exceeded"
  check ((pressure.find ("0",key.2) ref).isSome && (pressure.find ("512",key.2) ref).isNone)
    "pressure discarded the initial validated pages"

  let coordinator ← SearchReaders.Coordinator.new
  try
    let frame ← PreparedReaders.Frame.capture #[] #[] none
    let deadline := (← IO.monoMsNow)+10000
    let first : SearchReaders.Retirement ← IO.Promise.new
    let second : SearchReaders.Retirement ← IO.Promise.new
    let third : SearchReaders.Retirement ← IO.Promise.new
    let fourth : SearchReaders.Retirement ← IO.Promise.new
    let one ← coordinator.borrow frame deadline (← IO.mkRef false) first
    one.pool.pages.insert key ⟨ref,loaded⟩
    let two ← coordinator.borrow frame deadline (← IO.mkRef false) second
    check ((← two.pool.pages.find key ref).isNone) "live epoch observed another reader's private pages"
    first.resolve (some (← one.pool.pages.captureSeed))
    let three ← coordinator.borrow frame deadline (← IO.mkRef false) third
    check ((← three.pool.pages.find key ref).isNone) "base changed while a reader remained live"
    second.resolve none
    third.resolve none
    let four ← coordinator.borrow frame deadline (← IO.mkRef false) fourth
    check ((← four.pool.pages.find key ref).isSome) "quiescent promotion lost returned page"
    fourth.resolve none
    for early in [false,true] do
      let retired : SearchReaders.Retirement ← IO.Promise.new
      if early then retired.resolve none
      let refused ← try
          discard <| coordinator.borrow frame deadline (← IO.mkRef (!early)) retired
          pure false
        catch _ => pure true
      check refused "cancelled or retired borrower was admitted"
      if !early then retired.resolve none
    let final : SearchReaders.Retirement ← IO.Promise.new
    let finalSession ← coordinator.borrow frame deadline (← IO.mkRef false) final
    check ((← finalSession.pool.pages.find key ref).isSome) "cancelled borrower poisoned the next epoch"
    final.resolve none
  finally coordinator.close

  let direct ← source.forkReader
  let cached ← source.sharePages a "scope-a"
  direct.trace.set (some {})
  cached.trace.set (some {})
  for name in ["alpha","absent"] do
    check ((← direct.get name) == (← cached.get name)) "cached value differs from original lookup"
  let observations := fun (snapshot : PageMap.Snapshot) => do
    let some trace ← snapshot.trace.get | throw (IO.userError "missing read trace")
    pure trace.operations
  check ((← observations direct) == (← observations cached)) "cached reads changed logical dependencies"
  discard <| PageMap.withWriter source fun writer => writer.put "alpha" (some "changed".toUTF8)
  let changed ← PageMap.pin source.directory
  let changed ← changed.sharePages a "scope-a"
  check ((← changed.get "alpha") == some "changed".toUTF8 && (← source.get "alpha") == some "original".toUTF8)
    "old page cache crossed a publication boundary"
  IO.FS.writeFile (root/"report.json") (Json.mkObj [
    ("immutableReadsWhileOwnerLocked",toJson true),("completeRefAndScopeRejection",toJson true),
    ("independentFronts",toJson true),("frontPressureRetainsPrefix",toJson true),
    ("liveEpochFrozen",toJson true),("retiredPagesPromotedAtQuiescence",toJson true),
    ("cancelledAndAlreadyRetiredRejected",toJson true),("originalLookupAndTraceEqual",toJson true),
    ("changedPublicationUsesChangedBytes",toJson true),("notWholeHeapOrDistributedProof",toJson true),
    ("publicEncodedPageAllowance",toJson (134217728 : Nat)),("adopted",toJson false),
    ("answeringModelCalls",toJson (0 : Nat))]).compress
end QuiescentPagesChecks
