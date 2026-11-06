import Main
import Eggshell.ContractAudit
open Lean Eggshell Eggshell.DB
#print axioms PageMap.LocalPages.readView_same
#print axioms PageMap.LocalPages.readView_valid
#print axioms PageMap.SharedPageCache.reader_seed_budget
#print axioms PageMap.PagePool.reader_find_is_local
#print axioms PageMap.PagePool.reader_insert_is_local
#print axioms PageMap.PagePool.reader_has_no_owner
def check (ok : Bool) (message : String) : IO Unit := unless ok do throw (IO.userError message)
def readonlyPages (root : System.FilePath) : IO Unit := do
  check (!(← root.pathExists)) "preserve previous readonly check"
  IO.FS.createDirAll root
  let source ← PageMap.pin "/Users/ovm/.codex/experiments/eggshell/scope-token-study-20261028/fixed-frame-study/frontend-quiescence-fixture-small1/work.project/owners/0/source.egg"
  let some ref := source.head.root | throw (IO.userError "readonly fixture has no root")
  let loaded ← source.load ref
  let key := source.pageKey "authorized/readonly-check" ref
  let owner ← PageMap.PagePool.new
  owner.insert key ⟨ref,loaded⟩
  let seed ← owner.captureSeed
  let a ← owner.forkPrivate seed
  let b ← owner.forkPrivate seed
  let .owner mutex := owner | throw (IO.userError "cache producer lost owner role")
  let entered : IO.Promise Unit ← IO.Promise.new
  let release : IO.Promise Unit ← IO.Promise.new
  let holding ← IO.asTask (mutex.atomically do
    entered.resolve ()
    discard <| IO.wait release.result!) .dedicated
  let mut reading : Option (Task (Except IO.Error Unit)) := none
  try
    TaskDeadline.wait (Std.Async.AsyncTask.ofPurePromise entered) ((← IO.monoMsNow)+2000)
    let task ← IO.asTask (do
      let some hit ← a.val.find key ref | throw (IO.userError "immutable seed miss")
      check (PageMap.pageCodec.encode hit.page == PageMap.pageCodec.encode loaded.page) "seed changed verified page bytes"
      check ((← a.val.find (key.1++"/foreign",key.2) ref).isNone) "foreign namespace accepted"
      check ((← a.val.find key {ref with checksum := ref.checksum++"changed"}).isNone) "changed reference accepted"
      let alternate : PageMap.SharedPageKey := (key.1++"/actor-a",key.2)
      a.val.insert alternate ⟨ref,loaded⟩
      check ((← a.val.find alternate ref).isSome && (← b.val.find alternate ref).isNone) "private reader mutation crossed actors"
      let stats ← a.val.stats
      check (stats.getObjValD "readOnly" == toJson true && stats.getObjValD "sharedCacheTouched" == toJson false) "reader statistics used shared owner"
      let frontStats := stats.getObjValD "privateFront"
      check ((frontStats.getObjValAs? Nat "encodedReferencedBytes").toOption.getD 2097153 ≤ 2097152) "reader page-byte bound exceeded") .dedicated
    reading := some task
    -- The owner stays locked until this exact read/insert/stats task finishes.
    -- A dependency on its mutex therefore fails this check,without stranding IO.
    TaskDeadline.wait task ((← IO.monoMsNow)+1000)
  finally
    release.resolve ()
    discard <| IO.wait holding
    if let some task := reading then discard <| IO.wait task
  let stats ← owner.stats
  check (stats.getObjValD "hits" == toJson (0 : Nat) && stats.getObjValD "misses" == toJson (0 : Nat) &&
    stats.getObjValD "pages" == toJson (1 : Nat)) "readonly operations changed the shared cache"
  IO.FS.writeFile (root/"report.json") (Json.mkObj [("ownerHeldThroughoutReads",toJson true),
    ("hitMissInsertStatsWithoutOwner",toJson true),("verifiedPageBytesExact",toJson true),
    ("foreignScopeAndChangedRefRejected",toJson true),("independentMutableFronts",toJson true),
    ("sharedCacheUnchanged",toJson true),("readerByteBound",toJson (2097152 : Nat)),
    ("immutableAndMutableEncodedBudget",toJson (134217728 : Nat)),
    ("notWholeHeapOrAllRetrievalLockProof",toJson true),("answeringModelCalls",toJson (0 : Nat)),("adopted",toJson false)]).pretty
def main (args : List String) : IO UInt32 := do
  match args with
  | ["readonly-page-check",root] => readonlyPages (.mk root); return 0
  | ["front-traffic-audit",source] =>
    let result ← IO.Process.output {
      cmd := "/Users/ovm/.codex/experiments/eggshell/scope-token-study-20261028/fixed-frame-study/metadata-ingress-candidate-build/StudyMain"
      args := #["front-traffic-audit",source]}
    IO.print result.stdout
    IO.eprint result.stderr
    return result.exitCode
  | other => sourceRouteEngine other
