import DirectProjectionAudit

namespace Eggshell.PartitionDeltaAudit
open Lean DB Persistence.Store

def test := DirectProjectionAudit.check

def mutate (source : Snapshot) (added : List Value) (removed : List Nat := []) : IO (Snapshot × List Nat) := do
  let (ids,_,_) ← PageMap.withWriter source fun writer => do
    for owner in removed do removeRoot writer owner
    let intern : Intern := ⟨writer,← IO.mkRef {}⟩
    let ids ← added.mapM intern.root
    writeChange writer ⟨ids,removed,false⟩
    return ids
  return (← PageMap.pin source.directory,ids)

def simple := DirectProjectionAudit.outcome

def shared (index : Nat) : IO Value := IO.ofExcept (Plugin.relation? .outcome [
  .semantic (.text (String.join (List.replicate 180 "shared original window ")++s!" tail {index}")),
  .semantic (.text "shared result")])

def documents (source : Snapshot) : IO (List SearchDocument) := do
  SourceDelta.documents source (← rootIds source)

def populate (root : System.FilePath) (source : Snapshot) : IO VectorMatrix.Ready := do
  let keys := hashDistinct ((← documents source).flatMap (·.windows))
  let _ ← VectorMatrix.ensureUsing root "delta-fixture" SearchProvider.encoderContract keys fun key =>
    pure ⟨key,"fixture-coverage","000000000000f03f0000000000000000"⟩
  let some matrix ← VectorMatrix.open? root "delta-fixture" SearchProvider.encoderContract |
    throw (IO.userError "fixture projections absent")
  return matrix

def model (root : System.FilePath) (source : Snapshot) (matrix : VectorMatrix.Ready) : IO VectorPartition.Ready := do
  let some ready ← PartitionBuild.open? root "delta-fixture" SearchProvider.encoderContract source matrix |
    throw (IO.userError "current fixture model absent")
  return ready

def members (ready : VectorPartition.Ready) : IO (List (String × Nat)) := do
  let rows ← ready.snapshot.foldRange ⟨"member:","member;"⟩ (fun result (stored,raw) => do
    let some raw := raw | throw (IO.userError "retired member payload")
    let references ← VectorPartition.decodeCount raw
    let parts := stored.splitOn ":"
    let ["member",cell,key] := parts | throw (IO.userError "invalid member key")
    test (cell.toNat?.any (· < ready.header.cells) && Receipt.validId key) "foreign member"
    return if references == 0 then result else (key,references)::result) []
  return rows.mergeSort (fun a b => a.1 ≤ b.1)

def census (source : Snapshot) (ready : VectorPartition.Ready) : IO Unit := do
  let expected := (PartitionDelta.counts ((← documents source).flatMap (·.windows))).toList.mergeSort
    (fun a b => a.1 ≤ b.1)
  test ((← members ready) == expected && ready.header.basis.rows == expected.length)
    "incremental model differs from independent original-window census"
  let mut total := 0
  for id in [:ready.header.cells] do total := total+(← VectorPartition.cell ready id).2
  test (total == expected.length) "cell counts lost unique source windows"

def geometryHash (ready : VectorPartition.Ready) : IO String := do
  let mut bytes := ByteArray.empty
  for id in [:ready.header.nodes] do
    let some raw ← ready.snapshot.get (s!"node:{id}") | throw (IO.userError "missing geometry")
    bytes := bytes++raw
  for id in [:ready.header.cells] do bytes := bytes++(← VectorPartition.cell ready id).1
  return Sha256.hex bytes

def apply (root : System.FilePath) (source : Snapshot) (matrix : VectorMatrix.Ready) :
    IO (PartitionBuild.Preparation × VectorPartition.Ready) := do
  let result ← PartitionBuild.prepare root "delta-fixture" SearchProvider.encoderContract source matrix
  test (result.mode == "publication-delta" && result.trainingMs == 0) "delta retrained the complete corpus"
  let ready ← model root source matrix
  census source ready
  return (result,ready)

def fixture (output : System.FilePath) : IO Unit := do
  test (!(← output.pathExists)) "preserve earlier delta fixture"
  FileSystem.privateDirectory output
  let base ← PageMap.create (output / "source.egg") (Persistence.valueToJson (.text "delta-originals")).compress
  let firstShared ← shared 1
  let secondShared ← shared 2
  let (source,owners) ← mutate base ((← (List.range 65).mapM simple)++[firstShared,secondShared])
  let _ ← CandidateDomain.refresh source .user
  let root := output / "vectors"
  FileSystem.privateDirectory root
  let matrix ← populate root source
  let initial ← PartitionBuild.prepare root "delta-fixture" SearchProvider.encoderContract source matrix
  let old ← model root source matrix
  census source old
  let frozen ← geometryHash old
  let beforeCounts ← members old
  let sharedKey := (beforeCounts.find? (fun item => item.2 > 1)).map Prod.fst
  test sharedKey.isSome "fixture did not share an original window"
  let some sharedKey := sharedKey | throw (IO.userError "shared fixture absent")
  let (added,_) ← mutate source [← simple 200]
  let nextMatrix ← populate root added
  nextMatrix.snapshot.readBytes.set 0
  let addedStats ← PartitionBuild.prepare root "delta-fixture" SearchProvider.encoderContract added nextMatrix
  let newReadBytes ← nextMatrix.snapshot.readBytes.get
  test (addedStats.mode == "publication-delta" && addedStats.projectionRows == 1 && addedStats.trainingMs == 0)
    "one new source window scanned the old projection column"
  let updated ← model root added nextMatrix
  census added updated
  test ((← geometryHash updated) == frozen) "incremental addition changed trained geometry"
  let (oneRemoved,_) ← mutate added [] [owners[65]!]
  let (removedStats,retained) ← apply root oneRemoved nextMatrix
  test ((← members retained).any (fun item => item.1 == sharedKey && item.2 > 0))
    "deleting one owner removed another owner's shared window"
  let (lastRemoved,_) ← mutate oneRemoved [] [owners[66]!]
  let (lastStats,dead) ← apply root lastRemoved nextMatrix
  test (!(← members dead).any (fun item => item.1 == sharedKey)) "last removed reference remained live"
  let slots := dead.header.slots
  let (readded,_) ← mutate lastRemoved [firstShared]
  let (reactivated,again) ← apply root readded nextMatrix
  test (again.header.slots == slots && (← members again).any (fun item => item.1 == sharedKey))
    "reinsert allocated duplicate member coordinates or lost a reused window"
  let focus := Sha256.hex "new-focus-only".toUTF8
  let _ ← VectorMatrix.ensureUsing root "delta-fixture" SearchProvider.encoderContract [focus] fun key =>
    pure ⟨key,"focus-only","000000000000f03f0000000000000000"⟩
  let some focused ← VectorMatrix.open? root "delta-fixture" SearchProvider.encoderContract |
    throw (IO.userError "focus projection missing")
  let (focusStats,withFocus) ← apply root readded focused
  test (focusStats.projectionRows == 0 && focusStats.changedOwners == 0 &&
    withFocus.header.basis.rows == again.header.basis.rows) "focus-only row entered discovery"
  let liveOwners ← rootIds readded
  let (empty,_) ← mutate readded [] liveOwners
  let (emptyStats,noMembers) ← apply root empty focused
  test (noMembers.header.basis.rows == 0) "last original source windows remained live"
  let emptyResult ← VectorPartition.nominate noMembers #[#[1.0,0.0].toList.toFloatArray] 16
  test (emptyResult.val.keys.isEmpty && emptyResult.val.physicalRows == 0) "empty source still consumed members"
  let (revived,_) ← mutate empty [← simple 0]
  let (_,alive) ← apply root revived focused
  test ((← geometryHash alive) == frozen && alive.header.slots == withFocus.header.slots)
    "empty-source recovery retrained or duplicated coordinates"
  census source old
  test ((← geometryHash old) == frozen) "old pinned reader changed after later publications"
  let budgetRoot := output / "budget"
  FileSystem.privateDirectory budgetRoot
  let budgetBase ← PageMap.create (budgetRoot / "source.egg") (Persistence.valueToJson (.text "bounded-dead-members")).compress
  let (budgetSource,_) ← mutate budgetBase (← (List.range 9).mapM simple)
  let _ ← CandidateDomain.refresh budgetSource .user
  let budgetVectors := budgetRoot / "vectors"
  FileSystem.privateDirectory budgetVectors
  let budgetMatrix ← populate budgetVectors budgetSource
  let _ ← PartitionBuild.prepare budgetVectors "delta-fixture" SearchProvider.encoderContract budgetSource budgetMatrix
  let docs ← documents budgetSource
  let sorted := docs.mergeSort (fun a b => a.windows[0]! ≤ b.windows[0]!)
  let some last := sorted.getLast? | throw (IO.userError "empty bounded fixture")
  let keep := last.owner
  let removed := (← rootIds budgetSource).filter (· != keep)
  let (onlyLast,_) ← mutate budgetSource [] removed
  let (_,tombstones) ← apply budgetVectors onlyLast budgetMatrix
  let bounded ← VectorPartition.nominate tombstones #[#[1.0,0.0].toList.toFloatArray] 1
  test (bounded.val.keys.isEmpty && bounded.val.physicalRows == 2 && bounded.val.partialCell)
    "retired members escaped the physical search allowance"
  let _ ← CandidateDomain.refresh onlyLast .user
  let compact ← PartitionBuild.rebuild budgetVectors "delta-fixture" SearchProvider.encoderContract onlyLast budgetMatrix
  let compacted ← model budgetVectors onlyLast budgetMatrix
  let found ← VectorPartition.nominate compacted #[#[1.0,0.0].toList.toFloatArray] 1
  test (compacted.header.slots == 1 && found.val.keys == last.windows &&
    found.val.physicalRows == 1) "explicit retraining did not compact retired member slots"
  let malformed : PartitionDelta.Change := ⟨sharedKey,2,0⟩
  test ((PartitionDelta.checked 1 malformed).toOption.isNone) "reference-count underflow accepted"
  IO.FS.writeFile (output / "result.json") (Json.mkObj [
    ("initial",toJson initial),("addition",toJson addedStats),("additionProjectionReadBytes",toJson newReadBytes),
    ("sharedDeletion",toJson removedStats),("lastDeletion",toJson lastStats),
    ("reactivation",toJson reactivated),("focusOnly",toJson focusStats),("empty",toJson emptyStats),
    ("compacted",toJson compact),("boundedRows",toJson bounded.val.physicalRows),
    ("sharedReferenceRetained",toJson true),("lastReferenceRemoved",toJson true),
    ("coordinateReused",toJson true),("geometryFrozen",toJson true),("oldPinPreserved",toJson true),
    ("independentCensus",toJson true),("sourceEmbeddingCalls",toJson (0 : Nat)),
    ("answeringModelCalls",toJson (0 : Nat))]).pretty

def prepareScale (database root output : System.FilePath) : IO Unit := do
  test (!(← output.pathExists)) "preserve earlier scale preparation"
  let source ← PageMap.pin database
  let name := "sentence-transformers/paraphrase-multilingual-MiniLM-L12-v2"
  let some matrix ← VectorMatrix.open? root name SearchProvider.encoderContract |
    throw (IO.userError "scale original projections missing")
  let prepared ← PartitionBuild.prepare root name SearchProvider.encoderContract source matrix
  let some ready ← PartitionBuild.open? root name SearchProvider.encoderContract source matrix |
    throw (IO.userError "scale model missing after preparation")
  let target : Plugin.IndexTarget := {
    owner := Sidecar.Owner.ofSnapshot source
    command := [(Install.Layout.at (← Paths.installRoot)).executable.toString,"search-provider"]
    storage := .user }
  Warm.mark target source
  test (!(← Warm.required target source)) "new model or existing source indexes not prepared"
  FileSystem.privateDirectory output
  IO.FS.writeFile (output / "result.json") (Json.mkObj [
    ("source",toJson source.head),("matrix",toJson matrix.snapshot.head),
    ("partition",toJson ready.snapshot.head),("prepared",toJson prepared),
    ("priorOriginalColumnAuditReused",toJson true),("answeringModelCalls",toJson (0 : Nat))]).pretty

/-- One new original window is encoded by the existing local MiniLM provider.
This measures the routing component, not all other warm/index producers. -/
def mutateScale (database root output : System.FilePath) : IO Unit := do
  test (!(← output.pathExists)) "preserve earlier scale mutation"
  let source ← PageMap.pin database
  let name := "sentence-transformers/paraphrase-multilingual-MiniLM-L12-v2"
  let some matrix ← VectorMatrix.open? root name SearchProvider.encoderContract |
    throw (IO.userError "scale original projections missing")
  let some before ← PartitionBuild.open? root name SearchProvider.encoderContract source matrix |
    throw (IO.userError "scale starting model missing")
  let previous ← members before
  let frozen ← geometryHash before
  let (changed,owners) ← mutate source [← simple 1000000]
  let docs ← SourceDelta.documents changed owners
  let mut items : List SemanticMatcher.Item := []
  for document in docs do
    for (key,index) in document.windows.zipIdx do
      let text ← readSearchWindow changed document index
      test (windowKey text == key) "new source window differs from original"
      items := items++[⟨key,text⟩]
  test (items.length == 1) "scale mutation is not one original window"
  let binary := (Install.Layout.at (← Paths.installRoot)).executable.toString
  let command := [binary,"search-provider"]
  SemanticMatcher.withIndexProvider command fun running => do
    let _ ← SemanticMatcher.indexWindows running items (Sidecar.Owner.ofSnapshot changed) .user
    pure ()
  let options ← Warm.options changed command .user
  let projected ← SearchProvider.prepareMatrix options (items.map (·.id))
  test (projected.produced == 1 && projected.added == 1) "scale mutation did not encode exactly its new row"
  let some current ← VectorMatrix.open? root name SearchProvider.encoderContract |
    throw (IO.userError "updated source projection missing")
  current.snapshot.reads.set 0
  current.snapshot.readBytes.set 0
  let prepared ← PartitionBuild.prepare root name SearchProvider.encoderContract changed current
  let bytes ← current.snapshot.readBytes.get
  let reads ← current.snapshot.reads.get
  test (prepared.mode == "publication-delta" && prepared.projectionRows == 1 && prepared.trainingMs == 0)
    "scale source delta retrained or scanned the complete projection column"
  let some updated ← PartitionBuild.open? root name SearchProvider.encoderContract changed current |
    throw (IO.userError "updated scale model missing")
  let expected := previous.foldl (fun map (key,count) => map.insert key count) ({} : Std.HashMap String Nat)
  let expected := items.foldl (fun map item => map.insert item.id (map[item.id]?.getD 0+1)) expected
  let expected := expected.toList.mergeSort (fun a b => a.1 ≤ b.1)
  test ((← members updated) == expected && (← geometryHash updated) == frozen &&
    (← members before) == previous) "scale membership, trained geometry or old pin differs"
  let repeated ← PartitionBuild.prepare root name SearchProvider.encoderContract changed current
  test (repeated.mode == "warm" && repeated.writtenBytes == 0 && repeated.projectionRows == 0)
    "repeat scale update repeated source work"
  FileSystem.privateDirectory output
  IO.FS.writeFile (output / "result.json") (Json.mkObj [
    ("sourceBefore",toJson source.head),("sourceAfter",toJson changed.head),
    ("matrixBefore",toJson matrix.snapshot.head),("matrixAfter",toJson current.snapshot.head),
    ("partitionBefore",toJson before.snapshot.head),("partitionAfter",toJson updated.snapshot.head),
    ("prepared",toJson prepared),("repeat",toJson repeated),
    ("projectionReadBytes",toJson bytes),("projectionReads",toJson reads),
    ("membershipMatchesIndependentDelta",toJson true),("geometryFrozen",toJson true),
    ("oldPinPreserved",toJson true),("sourceEmbeddingWindows",toJson items.length),
    ("wholeWarmMeasured",toJson false),("answeringModelCalls",toJson (0 : Nat))]).pretty

end Eggshell.PartitionDeltaAudit
