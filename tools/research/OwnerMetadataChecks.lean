import Main
import Eggshell.ContractAudit
open Lean Eggshell Eggshell.DB Eggshell.Synapses
#print axioms OwnerMetadataImage.Image.insert_same
#print axioms OwnerMetadataImage.Image.foreign_rejected
#print axioms OwnerMetadataImage.Image.insert_other
#print axioms SharedReadViews.Source.metadata_lookup
def check (ok : Bool) (message : String) : IO Unit := unless ok do throw (IO.userError message)
def checks (root : System.FilePath) : IO Unit := do
  check (!(← root.pathExists)) "preserve prior metadata image checks"
  IO.FS.createDirAll root
  let source ← PageMap.pin "/Users/ovm/.codex/experiments/eggshell/scope-token-study-20261028/fixed-frame-study/frontend-quiescence-fixture-small1/work.project/owners/0/source.egg"
  let shared ← CanonicalSource.Shared.Pool.new
  let metadata : CanonicalSource.Cache.Manifest := {
    source := source.head,implementation := CanonicalSource.Cache.implementation,payload := "native-empty-owner",rows := 0,statistics := {}}
  let loaded : CanonicalSource.Shared.Loaded := ⟨metadata,source,none,shared.owners,shared.views,shared.files,"exact-native-publication"⟩
  let views ← SharedReadViews.Pool.new
  let deadline := (← IO.monoMsNow)+10000
  let owners := #["empty-a","empty-b","empty-a"]
  let token ← views.acquire "authorized-scope" source.head loaded owners 1024 deadline
  let before ← loaded.views.state.atomically do
    let state ← get
    return (state.hits,state.joins,state.loads,state.budget.used)
  let entered : IO.Promise Unit ← IO.Promise.new
  let release : IO.Promise Unit ← IO.Promise.new
  let holding ← IO.asTask (loaded.views.state.atomically do
    entered.resolve ()
    discard <| IO.wait release.result!) .dedicated
  let mut reading : Option (Task (Except IO.Error Unit)) := none
  try
    TaskDeadline.wait (Std.Async.AsyncTask.ofPurePromise entered) ((← IO.monoMsNow)+2000)
    let task ← IO.asTask (views.withView token "authorized-scope" fun view => do
      let some captured := view.sources[0]? | throw (IO.userError "captured source missing")
      for owner in owners do
        let ready ← IO.ofExcept (captured.readMetadata owner)
        let empty : CanonicalSource.Recipe.Stored := ⟨#[],[]⟩
        let layout ← IO.ofExcept (CanonicalSource.Recipe.check empty.rows empty.records)
        let expected ← IO.ofExcept (PreparedSourceView.decodeOwner source.head.identity owner
          (PreparedSourceView.ownerStored owner empty layout))
        check (ready.json == expected.json && ready.bytes == expected.bytes && ready.rows.isEmpty) "captured metadata changed original checked bytes"
      check ((captured.readMetadata "foreign-owner").toOption.isNone) "uncaptured owner accepted"
      check ((captured.metadata.lookup? "foreign-publication" "empty-a").isNone) "foreign immutable identity accepted"
      for _ in [:4096] do
        check ((captured.readMetadata "empty-a").toOption.isSome) "immutable metadata lookup became unavailable") .dedicated
    reading := some task
    TaskDeadline.wait task ((← IO.monoMsNow)+1000)
  finally
    release.resolve ()
    discard <| IO.wait holding
    if let some task := reading then discard <| IO.wait task
    views.release token "authorized-scope"
  let after ← loaded.views.state.atomically do
    let state ← get
    return (state.hits,state.joins,state.loads,state.budget.used)
  check (before == after) "immutable reads changed shared cache ownership or bookkeeping"
  let stats ← views.stats
  check (stats.getObjValD "chargedBytes" == toJson (0 : Nat) && stats.getObjValD "active" == toJson (0 : Nat)) "query view reservation survived release"
  views.close
  shared.close
  IO.FS.writeFile (root/"report.json") (Json.mkObj [("cacheMutexHeldThroughoutReads",toJson true),
    ("checkedMetadataJsonExact",toJson true),("duplicateAndMissingOwners",toJson true),
    ("foreignIdentityRejected",toJson true),("sharedCacheBookkeepingUnchanged",toJson true),
    ("reservationReleased",toJson true),("noWholeRetrievalLockFreedomClaim",toJson true),
    ("answeringModelCalls",toJson (0 : Nat)),("adopted",toJson false)]).compress
def main (args : List String) : IO UInt32 := do
  match args with
  | ["owner-metadata-check",root] => checks (.mk root); return 0
  | ["front-traffic-audit",source] =>
    let result ← IO.Process.output {
      cmd := "/Users/ovm/.codex/experiments/eggshell/scope-token-study-20261028/fixed-frame-study/metadata-ingress-candidate-build/StudyMain",
      args := #["front-traffic-audit",source]}
    IO.print result.stdout
    IO.eprint result.stderr
    return result.exitCode
  | other => sourceRouteEngine other
