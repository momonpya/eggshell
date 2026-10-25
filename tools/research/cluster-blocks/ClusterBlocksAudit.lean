import ClusterBlocks
import PartitionNativeAudit

namespace Eggshell.ClusterBlocksAudit
open Lean DB ClusterBlocks

run_meta do
  for name in #[``ClusterBlocks.Buffer.original_byte_count,``ClusterBlocks.Buffer.bytes_bounded,
      ``VectorBlocks.Verified.slice_size,``VectorBlocks.committed_block_preserved_by_append] do
    for dependency in ← Lean.collectAxioms name do
      unless #[``propext,``Classical.choice,``Quot.sound].contains dependency do
        throwError "Unapproved clustered-vector proof dependency: {name}: {dependency}"
  logInfo "Clustered block byte count, buffer bound, original slicing and prefix preservation checked"

def inputs (root : System.FilePath) (model encoder : String) (source : PageMap.Snapshot) :
    IO (VectorMatrix.Ready × VectorBlocks.Ready × VectorPartition.Ready) := do
  let some matrix ← VectorMatrix.open? root model encoder | throw (IO.userError "audit matrix missing")
  let _ ← VectorRoute.refresh root model encoder matrix
  let some route ← VectorRoute.open? root model encoder matrix | throw (IO.userError "audit layout missing")
  let _ ← VectorBlocks.prepare root model encoder matrix route
  let some blocks ← VectorBlocks.open? root model encoder matrix route | throw (IO.userError "audit blocks missing")
  let _ ← PartitionBuild.prepare root model encoder source matrix blocks
  let some partition ← PartitionBuild.open? root model encoder source matrix blocks | throw (IO.userError "audit partition missing")
  return (matrix,blocks,partition)

def reject (action : IO α) : IO Bool := do
  try let _ ← action; return false
  catch error => return decide ((error.toString.splitOn "vector block checksum mismatch").length > 1)

def compare (original aligned : VectorBlocks.Ready) : IO Nat := do
  let catalogue ← PartitionBuild.catalogue original
  let before ← VectorBlocks.Cache.make
  let after ← VectorBlocks.Cache.make
  for row in catalogue.rows do
    let a ← VectorBlocks.read original before row.key
    let b ← VectorBlocks.read aligned after row.key
    check (a.bytes == b.bytes && a.coverage == b.coverage) "original row bytes or coverage changed"
  return catalogue.rows.size

def fixture (output : System.FilePath) : IO Unit := do
  check (!(← output.pathExists)) "preserve earlier clustered fixture"
  FileSystem.privateDirectory output
  let base := output / "base"
  PartitionNativeAudit.fixture base
  let source ← PageMap.pin (base / "source.egg")
  let root := base / "vectors"
  let model := "partition-scope-fixture"
  let encoder := "original-synthetic-bits"
  let focus := Sha256.hex "projection-only-focus".toUTF8
  let _ ← VectorMatrix.ensureUsing root model encoder [focus] fun key =>
    pure ⟨key,"focus-coverage","0000000000000000000000000000f03f"⟩
  let (matrix,original,partition) ← inputs root model encoder source
  check (matrix.metadata.rows == partition.header.basis.rows+1) "focus fixture entered discovery membership"
  let packed := output / "packed"
  FileSystem.privateDirectory packed
  check ((← ClusterBlocks.open? packed model encoder matrix partition).isNone &&
    !(← (ClusterBlocks.folder packed model encoder).pathExists)) "cold query prepared physical vectors"
  let first ← ClusterBlocks.prepare packed model encoder matrix original partition
  let some old ← ClusterBlocks.open? packed model encoder matrix partition | throw (IO.userError "prepared cluster missing")
  let repeated ← ClusterBlocks.prepare packed model encoder matrix original partition
  check (first.mode == "prepared" && first.peakBufferedBytes ≤ bufferCapacity &&
    repeated.mode == "warm" && repeated.writtenBytes == 0) "clustered preparation was not idempotent"
  let compared ← compare original old
  check (compared == matrix.metadata.rows) "clustered fixture did not read every source projection"
  let table ← PartitionBuild.catalogue old
  let runtime ← ClusterBlocks.geometry partition
  let rowsCache ← VectorBlocks.Cache.make
  for row in table.rows do
    let some raw ← old.snapshot.get (s!"cell:{row.block}") | throw (IO.userError "missing physical cell witness")
    let (cell,tail) ← IO.ofExcept (Wire.natural.decode raw.toList)
    let vector ← VectorBlocks.read old rowsCache row.key
    check (tail.isEmpty && (← IO.ofExcept (VectorPartition.assign runtime row.key
      (← IO.ofExcept (VectorPartition.decode vector.bytes)))) == cell) "physical block mixes model cells"
  let later := Sha256.hex "later-focus-projection".toUTF8
  let _ ← VectorMatrix.ensureUsing root model encoder [later] fun key =>
    pure ⟨key,"later-coverage","000000000000f03f000000000000f03f"⟩
  let some changedMatrix ← VectorMatrix.open? root model encoder | throw (IO.userError "changed matrix missing")
  check ((← ClusterBlocks.open? packed model encoder changedMatrix partition).isNone)
    "changed matrix accepted stale physical rows"
  let (newMatrix,newOriginal,newPartition) ← inputs root model encoder source
  let replaced ← ClusterBlocks.prepare packed model encoder newMatrix newOriginal newPartition
  let some newer ← ClusterBlocks.open? packed model encoder newMatrix newPartition | throw (IO.userError "replacement cluster missing")
  check (replaced.mode == "replaced" && (← compare original old) == compared &&
    (← compare newOriginal newer) == compared+1) "old pin or updated rows were lost"
  let corruptRoot := output / "corrupt"
  FileSystem.privateDirectory (corruptRoot / "clustered")
  let corrupt := ClusterBlocks.folder corruptRoot model encoder
  FileSystem.privateDirectory corrupt
  let head := newer.snapshot.head
  let bytes ← IO.FS.readBinFile (PageMap.dataPath newer.snapshot.directory head)
  let offset := newer.manifest.offset
  IO.FS.writeBinFile (PageMap.dataPath corrupt head) (bytes.set! offset (bytes[offset]! ^^^ 1))
  IO.FS.writeFile (corrupt / "head") (toJson head).compress
  IO.FS.writeBinFile (corrupt / "writer") {}
  let some damaged ← ClusterBlocks.open? corruptRoot model encoder newMatrix newPartition |
    throw (IO.userError "corrupt fixture header could not open")
  let firstKey := (← PartitionBuild.catalogue newer).rows[0]!.key
  check (← reject (VectorBlocks.read damaged (← VectorBlocks.Cache.make) firstKey)) "corrupted original bytes were accepted"
  check ((← PageMap.pin source.directory).head == source.head) "fixture changed the source graph"
  IO.FS.writeFile (output / "result.json") (Json.mkObj [
    ("comparedRows",toJson compared),("updatedRows",toJson (compared+1)),
    ("coldDoesNotPrepare",toJson true),("idempotent",toJson true),("projectionOnlyPreserved",toJson true),
    ("modelCellsPreserved",toJson true),("changedMatrixRejected",toJson true),
    ("oldPinnedPreserved",toJson true),("corruptionRejected",toJson true),
    ("first",toJson first),("repeated",toJson repeated),("replacement",toJson replaced),
    ("modelCalls",toJson (0 : Nat))]).pretty

/-- This independent audit alone holds a bounded complete expected column.
Production preparation and foreground scoring do not retain that column. -/
def scale (database root output : System.FilePath) : IO Unit := do
  check (!(← output.pathExists)) "preserve the complete scale audit"
  let source ← PageMap.pin database
  let model := "sentence-transformers/paraphrase-multilingual-MiniLM-L12-v2"
  let encoder := SearchProvider.encoderContract
  let some matrix ← VectorMatrix.open? root model encoder | throw (IO.userError "scale matrix missing")
  let some route ← VectorRoute.open? root model encoder matrix | throw (IO.userError "scale original layout missing")
  let some original ← VectorBlocks.open? root model encoder matrix route | throw (IO.userError "scale original blocks missing")
  let some partition ← PartitionBuild.open? root model encoder source matrix original | throw (IO.userError "scale partition missing")
  let some aligned ← ClusterBlocks.open? root model encoder matrix partition | throw (IO.userError "scale aligned blocks missing")
  check (matrix.metadata.rows ≤ 100000 && matrix.metadata.rows*aligned.manifest.rowBytes ≤ 512*1024*1024)
    "independent audit expected column exceeds its frozen bound"
  let oldCatalogue ← PartitionBuild.catalogue original
  let oldCoverage ← ClusterBlocks.coverages original oldCatalogue
  let expected ← IO.mkRef ({} : Std.HashMap String (ByteArray × String))
  let started ← IO.monoMsNow
  PartitionBuild.walk oldCatalogue (List.range oldCatalogue.rows.size).toArray fun _ row raw =>
    expected.modify (·.insert row.key (raw,oldCoverage[row.position]!))
  let newCatalogue ← PartitionBuild.catalogue aligned
  let newCoverage ← ClusterBlocks.coverages aligned newCatalogue
  check (newCatalogue.rows.size == oldCatalogue.rows.size && (← expected.get).size == oldCatalogue.rows.size)
    "complete aligned directory lost original keys"
  let count ← IO.mkRef 0
  PartitionBuild.walk newCatalogue (List.range newCatalogue.rows.size).toArray fun _ row raw => do
    let some (before,coverage) := (← expected.get)[row.key]? | throw (IO.userError "foreign aligned key")
    check (before == raw && coverage == newCoverage[row.position]!) "aligned bits or metadata differ from original"
    count.modify (·+1)
  FileSystem.privateDirectory output
  IO.FS.writeFile (output / "result.json") (Json.mkObj [
    ("source",toJson source.head),("original",toJson original.snapshot.head),
    ("aligned",toJson aligned.snapshot.head),("rows",toJson (← count.get)),
    ("bytes",toJson (matrix.metadata.rows*aligned.manifest.rowBytes)),
    ("blocks",toJson aligned.manifest.blocks),("allOriginalBitsAndCoverageEqual",toJson true),
    ("elapsedMs",toJson ((← IO.monoMsNow)-started)),("modelCalls",toJson (0 : Nat))]).pretty

end Eggshell.ClusterBlocksAudit
