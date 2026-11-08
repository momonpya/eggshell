import Eggshell.CanonicalSourcePrepared
import tools.research.BindingPageScan
open Lean Eggshell Eggshell.DB Eggshell.Synapses

run_elab do
  let some body := ((← getEnv).find? ``PageMap.PagePool.find).bind (·.value?) |
    throwError "Missing actual shared page lookup"
  if body.getUsedConstants.contains ``PageMap.SharedPageCache.touch then
    throwError "A cache hit still rewrites the shared page generations"

#print axioms PageMap.SharedPageCache.reader_seed_budget
#print axioms PageMap.SharedPageCache.find_rejects
#print axioms Eggshell.Research.WeighedCache.Cache.retained_bounded

namespace Eggshell.Research.BytePageControls
def check (valid : Bool) (message : String) : IO Unit := unless valid do throw (IO.userError message)

def same (a b : IndexedBindings.Resolved) : Bool :=
  a.complete == b.complete && a.requests == b.requests && a.bytes == b.bytes && a.inspected == b.inspected &&
    a.unresolved == b.unresolved && a.unusable == b.unusable && a.rows.size == b.rows.size &&
    a.rows.toArray.all (fun (source,rows) => b.rows[source]? == some rows)

def run (directory output : System.FilePath) : IO Unit := do
  check (!(← output.pathExists)) "fresh byte-page controls output required"
  IO.FS.createDirAll output
  let source ← PageMap.pin directory
  let mut ready : Option (System.FilePath × CanonicalSource.Cache.Manifest) := none
  for storage in [Sidecar.Storage.database,.user] do
    if let some found ← CanonicalSource.Cache.open? source storage then
      ready := some (← CanonicalSource.Cache.directory source storage,found.metadata)
      break
  let some (path,metadata) := ready | throw (IO.userError "original is not already prepared")
  let pool ← CanonicalSource.Shared.Pool.new
  let checked ← try
    pool.withReady source path metadata ((← IO.monoMsNow)+30000) fun loaded _ => do
      let some shared := loaded.originals | throw (IO.userError "prepared original bindings missing")
      let independent := {shared with index := ← shared.index.forkReader}
      let (ranges,owners) ← independent.index.foldRange ⟨"binding:","binding;"⟩ (fun (ranges,owners) (_,bytes) => do
        let some bytes := bytes | return (ranges,owners)
        let binding ← Index.decodeBinding bytes
        return (ranges.insert binding.read.source,owners.insert binding.read.binding.owner))
        (({} : Std.HashSet Range),({} : Std.HashSet String))
      let ranges := ranges.toArray.qsort fun a b => Index.contentKey a < Index.contentKey b
      check (!ranges.isEmpty && !owners.isEmpty) "real binding control domain is empty"
      let absent : Range := ⟨.file ⟨"not-in-the-index",String.ofList (List.replicate 64 '0'),1⟩,1,1⟩
      let variants := #[ranges,ranges.extract 0 960,#[ranges[0]!,ranges[0]!,absent]]
      let owners := owners.toArray
      let mut checked := 0
      for wanted in variants do
        for allowed in [owners,owners.extract 0 7,#[],#["foreign-owner"]] do
          let allowed := Std.HashSet.ofArray allowed
          let expected ← BindingPageScan.resolveReport independent wanted allowed ((← IO.monoMsNow)+30000)
          let actual ← BindingPageScan.resolveReport shared wanted allowed ((← IO.monoMsNow)+30000)
          check (expected.resolved.complete && actual.resolved.complete && same expected.resolved actual.resolved)
            "byte cache differs from an independently read original, including quotation hashes, order or counters"
          checked := checked+1
      let expired ← BindingPageScan.resolveReport shared ranges (Std.HashSet.ofArray owners) 0
      let reference ← BindingPageScan.resolveReport independent ranges (Std.HashSet.ofArray owners) 0
      check (!expired.resolved.complete && same expired.resolved reference.resolved) "expired scan changed completion or prefix"
      return checked
  finally pool.close
  let original ← PageMap.create (output/"pin.egg") "byte-page-pin-control"
  discard <| PageMap.withWriter original fun writer => writer.put "key" (some "before".toUTF8)
  let old ← PageMap.pin original.directory
  let pages ← PageMap.PagePool.new
  let old ← old.sharePages pages "project"
  check ((← old.get "key") == some "before".toUTF8) "initial pinned bytes differ"
  discard <| PageMap.withWriter old fun writer => writer.put "key" (some "after".toUTF8)
  let latest ← PageMap.pin original.directory
  let latest ← latest.sharePages pages "project"
  check ((← latest.get "key") == some "after".toUTF8 && (← old.get "key") == some "before".toUTF8)
    "cache changed a retained pin or reused it for a newer head"
  let before ← pages.stats
  let foreign ← old.sharePages pages "another-project"
  check ((← foreign.get "key") == some "before".toUTF8) "foreign scope read changed original bytes"
  let after ← pages.stats
  check ((after.getObjValAs? Nat "misses").toOption.getD 0 ==
    (before.getObjValAs? Nat "misses").toOption.getD 0+1) "another scope hit the original cache entry"
  let some root := old.head.root | throw (IO.userError "control root missing")
  let loaded ← old.load root
  let key := old.pageKey "project" root
  let cache := PageMap.SharedPageCache.touch ({} : PageMap.SharedPageCache) key ⟨root,loaded⟩
  check ((cache.find key root).isSome && (cache.find key {root with bytes := root.bytes+1}).isNone)
    "cache ignored the complete page descriptor"
  check ((← PageMap.pin directory).head == source.head) "controls changed the original publication"
  IO.FS.writeFile (output/"result.json") (Json.mkObj [("completeIndependentScanComparisons",toJson checked),
    ("quotationHashesAndOrderExact",toJson true),("emptyForeignDuplicateAbsentExpired",toJson true),
    ("oldAndNewPinsExact",toJson true),("fullPageDescriptorChecked",toJson true),
    ("scopeMissChecked",toJson true),("sharedHitDoesNotTouchGenerations",toJson true),
    ("readOnlySharedMutexRemoved",toJson false),("actualHookCalls",toJson (0 : Nat)),
    ("answeringModelCalls",toJson (0 : Nat)),("adopted",toJson false)]).pretty
end Eggshell.Research.BytePageControls

def main (args : List String) : IO Unit := do
  let [source,output] := args | throw (IO.userError "byte page controls ORIGINAL OUTPUT")
  Eggshell.Research.BytePageControls.run (.mk source) (.mk output)
