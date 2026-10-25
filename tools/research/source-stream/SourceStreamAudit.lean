import PartitionDeltaAudit

namespace Eggshell.SourceStreamAudit
open Lean DB Persistence.Store

def check := DirectProjectionAudit.check

run_meta do
  for name in #[``BoundedSample.resident_bounded,``BoundedSample.insert_bounded] do
    for dependency in ← Lean.collectAxioms name do
      unless #[``propext,``Classical.choice,``Quot.sound].contains dependency do
        throwError "Unapproved sample proof dependency: {name}: {dependency}"

def sampleCheck (capacity : Nat) (keys : List String) : IO Unit := do
  let actual := keys.foldl (fun state key => state.insert key key)
    (BoundedSample.empty (α := String) (capacity := capacity))
  let expected := (keys.eraseDups.mergeSort (· ≤ ·)).take capacity
  check (actual.entries.toList.map Prod.fst == expected && actual.entries.size ≤ capacity)
    "bounded sample differs from independent sort/take"

def fixture (output : System.FilePath) : IO Unit := do
  check (!(← output.pathExists)) "preserve earlier streaming fixture"
  FileSystem.privateDirectory output
  let keys := (List.range 1000).map fun i => Sha256.hex s!"sample-{i}".toUTF8
  for capacity in [0,1,17,1000,1200] do
    sampleCheck capacity keys
    sampleCheck capacity (keys.reverse++keys.take 50)
  PartitionDeltaAudit.fixture (output / "delta")
  let source ← PageMap.pin (output / "delta/source.egg")
  let expected ← searchDocuments source
  let observed ← SourceCatalogue.fold source (fun rows ordinal document =>
    pure ((ordinal,document)::rows)) []
  let actual := (observed.mergeSort fun a b => a.1 ≤ b.1).map Prod.snd
  let describe := fun rows : List SearchDocument => rows.map fun row =>
    (row.owner,row.work,row.windows,row.cache)
  check (toJson (describe actual) == toJson (describe expected))
    "original document stream changes numeric order or identity"
  let expectedPlans ← Warm.planDocuments source expected fun document =>
    readNode source source.get document.work
  let plans ← Warm.planWindows source
  let describePlan := fun rows : List Warm.Window => rows.map fun row =>
    (row.document.owner,row.document.work,row.index,row.key,row.start)
  check (describePlan plans.1 == describePlan expectedPlans.1 &&
    describePlan plans.2 == describePlan expectedPlans.2) "streaming warm changes planned input or batch order"
  let expectedCounts := PartitionDelta.counts (expected.flatMap (·.windows))
  let counts ← SourceCatalogue.references source
  check (counts.size == expectedCounts.size && counts.toList.all fun (key,count) => expectedCounts[key]? == some count)
    "original stream loses shared references"
  -- A malformed original directory must not look like a smaller complete domain.
  let _ ← PageMap.withWriter source fun writer => writer.put "candidates"
    (some (Wire.natural.encode (expected.length+1)).toByteArray)
  let malformed ← PageMap.pin source.directory
  check (← DirectProjectionAudit.reject "incomplete" (SourceCatalogue.references malformed))
    "incomplete original stream accepted"
  check ((← SourceCatalogue.references source).size == counts.size) "old source pin changed"
  IO.FS.writeFile (output / "result.json") (Json.mkObj [
    ("sampleSortTakeChecks",toJson (10 : Nat)),("sourceOrderEqual",toJson true),
    ("sharedReferencesEqual",toJson true),("warmPlanEqual",toJson true),("incompleteRejected",toJson true),
    ("oldPinPreserved",toJson true),("answeringModelCalls",toJson (0 : Nat))]).pretty

def scale (database root reference output : System.FilePath) : IO Unit := do
  check (!(← output.pathExists)) "preserve earlier scale stream audit"
  let source ← PageMap.pin database
  let name := "sentence-transformers/paraphrase-multilingual-MiniLM-L12-v2"
  let some matrix ← VectorMatrix.open? root name SearchProvider.encoderContract |
    throw (IO.userError "scale original projection missing")
  let counts ← SourceCatalogue.references source
  let documents ← searchDocuments source
  let expected := PartitionDelta.counts (documents.flatMap (·.windows))
  check (counts.size == expected.size && counts.toList.all fun (key,count) => expected[key]? == some count)
    "scale original reference census differs"
  let (sample,eligible) ← PartitionBuild.selectSample matrix counts
  -- The old full directory/sort is an audit oracle only, outside preparation.
  let full ← ProjectionCursor.catalogue matrix
  let ranked := (full.rows.toList.filter (fun row => counts.contains row.key)).map fun row =>
    (Sha256.hex ("training\n"++row.key).toUTF8 ++ "/" ++ row.key,row.key)
  let expectedSample := ((ranked.mergeSort fun a b => a.1 ≤ b.1).take VectorPartition.sampleCapacity).map Prod.fst
  check (sample.entries.toList.map Prod.fst == expectedSample && eligible == counts.size)
    "streaming training sample differs from the full-directory oracle"
  let prepared ← PartitionBuild.prepare root name SearchProvider.encoderContract source matrix
  let some ready ← PartitionBuild.open? root name SearchProvider.encoderContract source matrix |
    throw (IO.userError "streaming scale model absent")
  let some before ← VectorPartition.load? reference | throw (IO.userError "reference model absent")
  check (ready.header.basis == before.header.basis && ready.header.nodes == before.header.nodes &&
    ready.header.root == before.header.root && ready.header.cells == before.header.cells &&
    ready.header.slots == before.header.slots) "streaming model basis differs"
  let compared ← before.snapshot.foldRange ⟨"",String.singleton (Char.ofNat 0x10ffff)⟩
    (fun count (key,raw) => do
      if key == "ready" then return count
      check ((← ready.snapshot.get key) == raw) "streaming cell, geometry or member differs"
      return count+1) 0
  check (ready.snapshot.head.root.map (·.rows) == before.snapshot.head.root.map (·.rows))
    "streaming model has additional records"
  let repeated ← PartitionBuild.prepare root name SearchProvider.encoderContract source matrix
  check (repeated.mode == "warm" && repeated.projectionRows == 0 && repeated.writtenBytes == 0)
    "streaming ready model repeated preparation"
  let target : Plugin.IndexTarget := {
    owner := Sidecar.Owner.ofSnapshot source
    command := [(Install.Layout.at (← Paths.installRoot)).executable.toString,"search-provider"]
    storage := .user }
  Warm.mark target source
  FileSystem.privateDirectory output
  IO.FS.writeFile (output / "result.json") (Json.mkObj [
    ("source",toJson source.head),("matrix",toJson matrix.snapshot.head),
    ("reference",toJson before.snapshot.head),("partition",toJson ready.snapshot.head),
    ("owners",toJson documents.length),("originalWindows",toJson counts.size),
    ("projectionMetadataRows",toJson full.rows.size),("sampleRows",toJson sample.entries.size),
    ("sampleEqual",toJson true),("originalReferencesEqual",toJson true),
    ("allPartitionRecordsEqual",toJson true),("comparedRecords",toJson compared),
    ("prepared",toJson prepared),("repeat",toJson repeated),
    ("answeringModelCalls",toJson (0 : Nat)),("sourceEmbeddingWindows",toJson (0 : Nat))]).pretty

end Eggshell.SourceStreamAudit
