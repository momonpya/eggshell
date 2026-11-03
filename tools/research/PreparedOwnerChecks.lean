import tools.research.PreparedInputChecks
import Eggshell.PreparedOwners
import Eggshell.FederatedSearch

open Lean Eggshell Eggshell.DB Eggshell.Persistence.Store
namespace Eggshell.Research.PreparedOwnerChecks

private def check (condition : Bool) (message : String) : IO Unit :=
  unless condition do throw (IO.userError message)

private def producer : String := PreparedOwners.implementation

private def value (lane n : Nat) : Value :=
  let key := if n%8 == 0 then s!"shared{n}" else s!"lane{lane}record{n}"
  let work := Value.text ("inspect kernel evidence "++key)
  let body := Value.text (key++"\n"++String.ofList (List.replicate 5000 'x'))
  (OutcomeEdge.make work body [.text ("original dependency "++key)]
    (by simp) (by simp [maxOutcomeObservations])).relation

private def variant (lane : Nat) (structured : Bool) : Value :=
  let work := if structured then Value.applyList .inquiry [(.semantic,.text "structured Work")]
    else Value.text "inspect kernel evidence shared0"
  let body := if structured then Value.text "structured result"
    else Value.text ("shared0\n"++String.ofList (List.replicate 5000 'x'))
  (OutcomeEdge.make work body [.text s!"distinct Exact dependency {lane}"]
    (by simp) (by simp [maxOutcomeObservations])).relation

private def source (root : System.FilePath) (lane count : Nat) : IO System.FilePath := do
  let path := root/s!"owner-{lane}.egg"
  let original ← PageMap.create path (Persistence.valueToJson (.text s!"prepared-owner-{lane}")).compress
  let _ ← PageMap.withWriter original fun writer => do
    let intern : Intern := ⟨writer,← IO.mkRef {}⟩
    let mut added := []
    for n in [:count] do added := (← intern.root (value lane n))::added
    writeChange writer {added := added.reverse,removed := [],unionsChanged := false}
  return path

private def revise (path : System.FilePath) (lane : Nat) (added removed : List Nat) : IO Unit := do
  let current ← PageMap.pin path
  let _ ← PageMap.withWriter current fun writer => do
    let intern : Intern := ⟨writer,← IO.mkRef {}⟩
    let mut deleted := []
    for n in removed do
      let some id ← findNode? current (value lane n) | throw (IO.userError "fixture removal not allocated")
      removeRoot writer id
      deleted := id::deleted
    let ids ← added.mapM fun n => intern.root (value lane n)
    writeChange writer {added := ids,removed := deleted.reverse,unionsChanged := false}
  return ()

private def audit (reader : PreparedOwners.Reader) : IO Json := do
  let started ← IO.monoMsNow
  let sourceHeads ← reader.sources.mapM fun source => do return (← PageMap.pin source.directory).head
  let reference ← Federated.prepare reader.sources
  let counts ← reader.counts
  check (counts == (reference.owners.size,reference.documents.length)) "distinct owner/candidate count differs from full catalogue"
  let mut expectedOrigins := 0
  let mut mapped : Std.HashMap Nat Nat := {}
  let mut ordering := []
  let mut terms : Std.HashSet String := {}
  for (canonical,originals) in reference.ownerOrigins.toList do
    let mut expected := []
    let mut resolved := none
    for original in originals do
      let some actual ← reader.owner? original.source.val original.id |
        throw (IO.userError "prepared owner absent from complete original set")
      if let some previous := resolved then check (previous == actual.id) "duplicate original has different prepared owner"
      resolved := some actual.id
      expectedOrigins := expectedOrigins+1
      let ordinal ← getNat original.snapshot.get (key "member" original.id)
      expected := expected++[(original.source.val,original.id,ordinal)]
      let located ← locateOutcome original.snapshot original.id
      let originReader ← NodeReader.new original.snapshot
      let owner ← originReader.outcome located
      for term in ownerTermsFor owner do terms := terms.insert term
    let some first := originals.head? | throw (IO.userError "empty oracle origins")
    let some entry ← reader.owner? first.source.val first.id | throw (IO.userError "first original missing")
    let actual := entry.originals.map fun original => (original.source,original.node,original.ordinal)
    check (actual == expected) "full ordered original inventory differs"
    mapped := mapped.insert entry.id canonical
    let some representative := entry.originals.head? | throw (IO.userError "live entry has no representative")
    ordering := (reference.orders.getD canonical 0,representative.rank reader.manifest.stride)::ordering
  let sorted := ordering.mergeSort (fun a b => a.1 ≤ b.1)
  check ((sorted.zip sorted.tail).all fun (left,right) => left.2 < right.2)
    "prepared order embedding differs from complete source-root order"
  for term in terms.toList++["ABSENT_GLOBAL_TERM"] do
    let postings ← Federated.postings reference term false
    let actual ← reader.postings term
    let canonicalIds ← actual.mapM fun id => do
      let some canonical := mapped[id]? | throw (IO.userError "posting names foreign prepared owner")
      return canonical
    check (Std.HashSet.ofList canonicalIds == Std.HashSet.ofList postings.toList &&
      (← reader.frequency term) == postings.size) "deduplicated lexical frequency/postings differ from full catalogue"
  check ((← reader.sources.mapM fun source => do return (← PageMap.pin source.directory).head) == sourceHeads)
    "read-only full-source audit changed original heads"
  return Json.mkObj [("fullOwnerInventoryEqual",toJson true),("orderedOriginsEqual",toJson true),
    ("orderEmbeddingEqual",toJson true),("allLexicalTermsEqual",toJson true),
    ("outcomes",toJson counts.1),("candidates",toJson counts.2),("originals",toJson expectedOrigins),
    ("oracleAuditMs",toJson ((← IO.monoMsNow)-started))]

private def prepared (path : System.FilePath) (sources : Array PageMap.Snapshot) : IO (PreparedOwners.Reader × Json) := do
  let before ← PageMap.pin path
  let started ← IO.monoMsNow
  let (_,result) ← PreparedOwners.prepare before sources "project/read-scope" producer
  let preparationMs := (← IO.monoMsNow)-started
  let index ← PageMap.pin path
  let openStarted ← IO.monoMsNow
  let some reader ← PreparedOwners.open? index sources "project/read-scope" producer |
    throw (IO.userError "completed prepared view did not reopen")
  let admissionMs := (← IO.monoMsNow)-openStarted
  return (reader,Json.mkObj [("result",toJson result),("preparationMs",toJson preparationMs),
    ("admissionMs",toJson admissionMs)])

def run (root : System.FilePath) (count : Nat) : IO Unit := do
  check (root.isAbsolute && !(← root.pathExists) && [16,64,256].contains count) "fresh controlled fixture required"
  FileSystem.privateDirectory root
  let paths ← (List.range 16).toArray.mapM fun lane => source root lane count
  let sources ← paths.mapM PageMap.pin
  let heads := sources.map (·.head)
  let indexPath := root/"prepared.egg"
  let _ ← PageMap.create indexPath "prepared-owner-derived-index"
  let (original,build) ← prepared indexPath sources
  let initial ← audit original
  let originalIndexHead := original.index.head
  IO.FS.writeFile (root/"captured.json") ((toJson (originalIndexHead,original.manifest)).pretty++"\n")
  -- New empty scope and producer cannot reuse an unrelated complete view.
  check ((← PreparedOwners.open? original.index sources "other-project" producer).isNone) "foreign scope accepted"
  check ((← PreparedOwners.open? original.index sources "project/read-scope" (Sha256.hex "different compiler".toUTF8)).isNone)
    "foreign producer accepted"
  let mut foreignPreparationRefused := false
  try
    let _ ← PreparedOwners.prepare original.index sources "project/read-scope" (Sha256.hex "caller supplied digest".toUTF8)
  catch _ => foreignPreparationRefused := true
  check foreignPreparationRefused "caller supplied digest bypassed actual compiled implementation identity"
  let (same,unchanged) ← prepared indexPath sources
  check (same.index.head == originalIndexHead) "unchanged cut republished or rebuilt owner view"
  -- One owner changes. Unrelated originals must not be enumerated.
  revise paths[0]! 0 [count+1] [0]
  let next ← paths.mapM PageMap.pin
  check ((← PreparedOwners.open? original.index next "project/read-scope" producer).isNone) "stale owner view accepted new source"
  let (updated,change) ← prepared indexPath next
  let changedResult := change.getObjValD "result"
  check (changedResult.getObjValD "changedRoots" == toJson (2 : Nat) &&
    changedResult.getObjValD "publications" == toJson (1 : Nat)) "one publication enumerated unrelated owners"
  let afterOne ← audit updated
  check ((← original.counts) == (← same.counts)) "old pinned view changed during publication"
  let oldAudit ← audit original
  -- Remove remaining copies. The final copy alone retracts global frequency.
  for lane in [1:16] do revise paths[lane]! lane [] [0]
  let (removed,removeReport) ← prepared indexPath (← paths.mapM PageMap.pin)
  let afterAll ← audit removed
  check ((← removed.frequency "shared0") == 0) "last duplicate retraction left a global posting"
  -- Reinsertion reuses structural identity but gets the new original ordinal.
  revise paths[7]! 7 [0] []
  let (reinserted,reinsertReport) ← prepared indexPath (← paths.mapM PageMap.pin)
  let afterReinsert ← audit reinserted
  let some oldSource := sources[7]? | throw (IO.userError "source seven absent")
  let some oldNode ← findNode? oldSource (value 7 0) | throw (IO.userError "old duplicate absent")
  let some previous ← original.owner? 7 oldNode | throw (IO.userError "original prepared duplicate absent")
  let some current ← reinserted.owner? 7 oldNode | throw (IO.userError "reinserted prepared duplicate absent")
  check (previous.id == current.id && current.originals.length == 1) "reinsertion changed stable owner namespace or kept stale copies"
  -- Certification-only owners stay in the domain; equal Work/result bytes do
  -- not collapse different Exact dependencies into one Outcome.
  for lane in [:16] do
    let snapshot ← PageMap.pin paths[lane]!
    let _ ← PageMap.withWriter snapshot fun writer => do
      let intern : Intern := ⟨writer,← IO.mkRef {}⟩
      let added ← [variant lane false,variant lane true].mapM intern.root
      writeChange writer {added,removed := [],unionsChanged := false}
  let (withVariants,variantsReport) ← prepared indexPath (← paths.mapM PageMap.pin)
  let afterVariants ← audit withVariants
  let beforeCounts ← reinserted.counts
  check ((← withVariants.counts) == (beforeCounts.1+32,beforeCounts.2+16))
    "structured owners or Exact distinctions disappeared from the complete domain"
  let mut variantIds : Std.HashSet Nat := {}
  for lane in [:16] do
    let some snapshot := withVariants.sources[lane]? | throw (IO.userError "variant source absent")
    for structured in [false,true] do
      let some node ← findNode? snapshot (variant lane structured) | throw (IO.userError "variant original absent")
      let some entry ← withVariants.owner? lane node | throw (IO.userError "variant prepared owner absent")
      variantIds := variantIds.insert entry.id
  check (variantIds.size == 32 && !variantIds.contains current.id)
    "different Exact dependencies were treated as identity"
  -- Source permutation and missing/foreign inventory need explicit new preparation.
  let reversed := withVariants.sources.reverse
  check ((← PreparedOwners.open? withVariants.index reversed "project/read-scope" producer).isNone) "permuted source order accepted"
  let mut refused := false
  try
    let _ ← PreparedOwners.prepare withVariants.index reversed "project/read-scope" producer
  catch _ => refused := true
  check refused "incremental preparation silently accepted a changed source order"
  let mut oldCutRefused := false
  try
    let _ ← PreparedOwners.prepare withVariants.index sources "project/read-scope" producer
  catch _ => oldCutRefused := true
  check oldCutRefused "unavailable backward publication chain triggered an implicit rebuild"
  check ((← PageMap.pin indexPath).head == withVariants.index.head) "rejected source cut changed prepared head"
  check (heads.size == reinserted.sources.size) "test changed the declared complete inventory"
  let report := Json.mkObj [("allPassed",toJson true),("rawOutcomes",toJson (16*count)),
    ("build",build),("initial",initial),("unchanged",unchanged),("delta",change),("afterOne",afterOne),
    ("oldPinnedView",oldAudit),("remove",removeReport),("afterAll",afterAll),
    ("reinsertion",reinsertReport),("afterReinsert",afterReinsert),
    ("variants",variantsReport),("afterVariants",afterVariants),
    ("structuredOwnersAndExactDistinctionsPreserved",toJson true),
    ("stableOwnerIds",toJson true),("foreignProducerScopeAndSourceOrderRejected",toJson true),
    ("unavailableDeltaRejected",toJson true),
    ("normalHookIntegrated",toJson false),("answeringModelCalls",toJson (0 : Nat)),("adopted",toJson false)]
  IO.FS.writeFile (root/"report.json") (report.pretty++"\n")
  IO.println report.compress

def reopen (root : System.FilePath) : IO Unit := do
  let captured ← IO.ofExcept (Json.parse (← IO.FS.readFile (root/"captured.json")) >>=
    fromJson? (α := PageMap.Head × PreparedOwners.Manifest))
  let current ← PageMap.pin (root/"prepared.egg")
  let some index ← PageMap.HistoryReader.make? current captured.1 |
    throw (IO.userError "old prepared root was not retained")
  let sources ← captured.2.sources.mapM fun source => do
    let current ← PageMap.pin (.mk source.directory)
    let some history ← PageMap.HistoryReader.make? current source.head |
      throw (IO.userError "old original cut was not retained")
    return history.snapshot
  let some reader ← PreparedOwners.open? index.snapshot sources "project/read-scope" producer |
    throw (IO.userError "fresh process could not reopen the exact old view")
  let report := (← audit reader).setObjVal! "freshProcessRetainedOldCut" (toJson true)
  IO.FS.writeFile (root/"reopen.json") (report.pretty++"\n")
  IO.println report.compress

end Eggshell.Research.PreparedOwnerChecks

#print axioms Eggshell.PreparedOwners.Original.rank_order
#print axioms Eggshell.PreparedOwners.Entry.without_other

def main (args : List String) : IO UInt32 := do
  match args with
  | ["prepared-owners",root,count] =>
    let some count := count.toNat? | throw (IO.userError "count required")
    Eggshell.Research.PreparedOwnerChecks.run (.mk root) count
    pure 0
  | ["reopen-prepared-owners",root] =>
    Eggshell.Research.PreparedOwnerChecks.reopen (.mk root)
    pure 0
  | _ => preparedInputMain args
