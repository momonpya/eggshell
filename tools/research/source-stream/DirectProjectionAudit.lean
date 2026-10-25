import PartitionBuild
import ProjectionCache
import Eggshell.Install
import Eggshell.KeyedSearchProvider

namespace Eggshell.DirectProjectionAudit
open Lean DB Persistence.Store

def check (condition : Bool) (message : String) : IO Unit := do
  unless condition do throw (IO.userError message)

run_meta do
  for name in #[``ProjectionCursor.Raw.actual_bytes_bounded,``ProjectionCache.State.actual_bytes_bounded,
      ``BlockScore.Frame.byte_count,``VectorMatrix.row_roundtrip,
      ``VectorMatrix.row_chunks_preserved_by_append,``VectorPartition.training_preserves_samples] do
    for dependency in ← Lean.collectAxioms name do
      unless #[``propext,``Classical.choice,``Quot.sound].contains dependency do
        throwError "Unapproved direct-projection proof dependency: {name}: {dependency}"
  logInfo "Direct projection bytes, cache, frame, append prefix and sample preservation checked"

def stage (path : System.FilePath) : IO Unit := do
  let layout := Install.Layout.at path
  check (path.isAbsolute && !(← layout.executable.pathExists)) "new absolute research prefix required"
  -- This local macOS experiment stages a separate inode with shared APFS
  -- extents, avoiding another full executable allocation on the test disk.
  IO.FS.createDirAll layout.executable.parent.get!
  let copied ← IO.Process.output {cmd := "/bin/cp",args := #["-c",(← IO.appPath).toString,layout.executable.toString]}
  check (copied.exitCode == 0) "research executable clone failed"
  IO.FS.createDirAll (layout.plugin / ".codex-plugin")
  IO.FS.createDirAll (layout.plugin / "hooks")
  IO.FS.writeFile (layout.plugin / Install.ownerMarkerName) Install.ownerMarkerContents
  IO.FS.writeFile (layout.plugin / ".codex-plugin/plugin.json") Install.pluginManifest
  IO.FS.writeFile (layout.plugin / "hooks/hooks.json") Install.hooksManifest
  Install.writeExecutable layout.launcher Install.commandLauncher
  for name in ["egg","eggshelld"] do
    Install.writeExecutable (layout.plugin / "bin" / name) (Install.pluginLauncher path)

def outcome (index : Nat) : IO Value := IO.ofExcept (Plugin.relation? .outcome [
  .semantic (.text s!"direct projection question {index}"),
  .semantic (.text s!"direct projection original {index}")])

def publish (source : Snapshot) (values : List Value) : IO Snapshot := do
  let _ ← PageMap.withWriter source fun writer => do
    let intern : Intern := ⟨writer,← IO.mkRef {}⟩
    let ids ← values.mapM intern.root
    writeChange writer ⟨ids,[],false⟩
  PageMap.pin source.directory

def reject (message : String) (action : IO α) : IO Bool := do
  try let _ ← action; return false
  catch error => return decide ((error.toString.splitOn message).length > 1)

def prepare (root : System.FilePath) (model encoder : String) (source : Snapshot) :
    IO (VectorMatrix.Ready × VectorPartition.Ready) := do
  let some matrix ← VectorMatrix.open? root model encoder | throw (IO.userError "fixture projections missing")
  let _ ← PartitionBuild.prepare root model encoder source matrix
  let some partition ← PartitionBuild.open? root model encoder source matrix | throw (IO.userError "fixture model missing")
  return (matrix,partition)

/-- Independent pre-existing hex reader versus the raw cursor and row cache.
Only a single row's expected bytes are retained by the audit. -/
def compare (matrix : VectorMatrix.Ready) : IO Nat := do
  let rows ← ProjectionCursor.catalogue matrix
  let cache ← ProjectionCache.Cache.make
  let identity := ProjectionCache.scope matrix
  ProjectionCursor.checkExtent matrix.snapshot
  for row in rows.rows do
    let actual ← ProjectionCache.read matrix cache identity row.key
    let (coverage,hex) ← VectorMatrix.readRow matrix.snapshot row.value
    let expected ← IO.ofExcept (VectorMatrix.decodeHex hex)
    check (actual.payload.bytes == expected && actual.row.value.coverage == coverage)
      "direct projection bits or coverage differ from the original reader"
  ProjectionCursor.checkExtent matrix.snapshot
  return rows.rows.size

def fixture (output : System.FilePath) : IO Unit := do
  check (!(← output.pathExists)) "preserve earlier direct fixture"
  FileSystem.privateDirectory output
  let base ← PageMap.create (output / "source.egg") (Persistence.valueToJson (.text "direct-fixture-authority")).compress
  let source ← publish base (← (List.range 65).mapM outcome)
  let documents ← searchDocuments source
  let keys := hashDistinct (documents.flatMap (·.windows))
  let root := (← Sidecar.prepare (Sidecar.Owner.ofSnapshot source) .user).semantic
  let model := "direct-fixture"
  let encoder := SearchProvider.encoderContract
  let focus := Sha256.hex "focus-only".toUTF8
  let all := keys++[focus]
  let bytes := "000000000000f03f0000000000000000"
  let _ ← VectorMatrix.ensureUsing root model encoder all fun key => pure ⟨key,"fixture-coverage",bytes⟩
  let some matrix ← VectorMatrix.open? root model encoder | throw (IO.userError "fixture matrix missing")
  check ((← PartitionBuild.open? root model encoder source matrix).isNone) "cold source unexpectedly prepared"
  let (matrix,partition) ← prepare root model encoder source
  let compared ← compare matrix
  let isolated := {matrix with snapshot := ← PageMap.pin matrix.snapshot.directory}
  isolated.snapshot.reads.set 0
  let delta ← ProjectionCursor.select isolated [focus]
  let metadataReads ← isolated.snapshot.reads.get
  ProjectionCursor.walk delta #[0] fun _ row raw =>
    check (row.key == focus && raw.size == 16) "delta read another row"
  check (delta.rows.size == 1 && metadataReads ≤ (isolated.snapshot.head.root.map (·.height+1)).getD 0)
    "delta request enumerated the source population"
  check (← reject "requested projection is absent" (ProjectionCursor.select matrix [Sha256.hex "absent".toUTF8]))
    "missing delta key was silently omitted"
  check (← reject "duplicate projection cursor request" (ProjectionCursor.select matrix [focus,focus]))
    "duplicate delta request was accepted"
  let repeated ← PartitionBuild.prepare root model encoder source matrix
  check (repeated.mode == "warm" && repeated.writtenBytes == 0) "ready partition was rebuilt"
  let cache ← ProjectionCache.Cache.make 32
  let pages ← IO.mkRef ({} : PageMap.PageCache)
  let key := keys[0]!
  let input := BlockScore.Input.indexed (Sidecar.Owner.ofSnapshot source) key
  let body := (Json.mkObj [("queries",toJson #[bytes]),("blockRows",toJson #[input])]).compress
  let frame ← BlockScore.prepare model cache pages body ((← IO.monoMsNow)+10000) (pure false)
  let hit ← BlockScore.prepare model cache pages body ((← IO.monoMsNow)+10000) (pure false)
  check (frame.raw == (← IO.ofExcept (VectorMatrix.decodeHex (bytes++bytes))) &&
    frame.projectionHits == 0 && frame.projectionMisses == 1 && hit.projectionHits == 1 &&
    hit.projectionMisses == 0 && frame.coverage == #[some "fixture-coverage"] &&
    (← cache.state.get).bytes == 16) "native frame or authenticated cache reuse differs"
  for other in keys.take 5 do
    let _ ← ProjectionCache.read matrix cache (ProjectionCache.scope matrix) other
  check ((← cache.state.get).bytes ≤ 32 && (← cache.state.get).entries.size ≤ 2)
    "cache retained bytes exceeded its shared allowance"
  check (← reject "expired" (BlockScore.prepare model cache pages body (← IO.monoMsNow) (pure false)))
    "expired numerical frame was accepted"
  check (← reject "expired" (BlockScore.prepare model cache pages body ((← IO.monoMsNow)+10000) (pure true)))
    "cancelled numerical frame was accepted"
  let changed ← publish source [← outcome 100]
  check ((← PartitionBuild.open? root model encoder changed matrix).isNone) "new original owner reused an old model"
  let nextDocuments ← searchDocuments changed
  let nextKeys := hashDistinct (nextDocuments.flatMap (·.windows))++[focus]
  let _ ← VectorMatrix.ensureUsing root model encoder nextKeys fun newKey => pure ⟨newKey,"fixture-coverage",bytes⟩
  let (newMatrix,_) ← prepare root model encoder changed
  check ((← compare matrix) == compared && (← compare newMatrix) == compared+1)
    "pinned old or updated projection rows were lost"
  check (ProjectionCache.scope matrix != ProjectionCache.scope newMatrix) "changed matrix reused an old cache scope"
  let wideRoot := output / "wide"
  FileSystem.privateDirectory wideRoot
  let wideKey := Sha256.hex "maximum-row".toUTF8
  let _ ← VectorMatrix.ensureUsing wideRoot model encoder [wideKey] fun newKey =>
    pure ⟨newKey,"wide-coverage",String.join (List.replicate 4096 "000000000000f03f")⟩
  let some wide ← VectorMatrix.open? wideRoot model encoder | throw (IO.userError "wide fixture missing")
  let one ← ProjectionCursor.select wide [wideKey]
  let some row := one.rows[0]? | throw (IO.userError "wide row missing")
  let raw ← ProjectionCursor.read wide row
  let (_,hex) ← VectorMatrix.readRow wide.snapshot row.value
  check (raw.bytes.size == VectorMatrix.maxRowBytes && row.value.chunks.length == 8 &&
    raw.bytes == (← IO.ofExcept (VectorMatrix.decodeHex hex))) "multi-chunk cursor differs from original reader"
  let corrupt := output / "corrupt.egg"
  FileSystem.privateDirectory corrupt
  let file ← IO.FS.readBinFile (PageMap.dataPath wide.snapshot.directory wide.snapshot.head)
  let some first := row.value.chunks.head? | throw (IO.userError "wide chunk absent")
  IO.FS.writeBinFile (PageMap.dataPath corrupt wide.snapshot.head) (file.set! first.offset (file[first.offset]! ^^^ 1))
  IO.FS.writeFile (corrupt / "head") (toJson wide.snapshot.head).compress
  IO.FS.writeBinFile (corrupt / "writer") {}
  let corrupted := {wide with snapshot := ← PageMap.pin corrupt}
  check (← reject "corrupted or truncated body chunk" (ProjectionCache.read corrupted cache (ProjectionCache.scope corrupted) wideKey))
    "corrupted original chunk was accepted"
  let truncated := output / "truncated.egg"
  FileSystem.privateDirectory truncated
  IO.FS.writeBinFile (PageMap.dataPath truncated wide.snapshot.head) file
  IO.FS.writeFile (truncated / "head") (toJson wide.snapshot.head).compress
  IO.FS.writeBinFile (truncated / "writer") {}
  let truncatedMatrix := {wide with snapshot := ← PageMap.pin truncated}
  IO.FS.writeBinFile (PageMap.dataPath truncated wide.snapshot.head) (file.extract 0 (file.size-1))
  check (← reject "truncated" (ProjectionCursor.checkExtent truncatedMatrix.snapshot))
    "truncated committed prefix was accepted"
  check (!(← (root / "routing").pathExists) && !(← (root / "blocks").pathExists) &&
    !(← (root / "clustered").pathExists)) "direct preparation created another vector body copy"
  IO.FS.writeFile (output / "result.json") (Json.mkObj [
    ("comparedRows",toJson compared),("updatedRows",toJson (compared+1)),
    ("metadataReadsForOneKey",toJson metadataReads),("selectedRows",toJson delta.rows.size),
    ("duplicateVectorDirectoriesAbsent",toJson true),("coldDoesNotPrepare",toJson true),
    ("oldPinPreserved",toJson true),("changedOwnerRejected",toJson true),
    ("wideBytes",toJson raw.bytes.size),("wideChunks",toJson row.value.chunks.length),
    ("corruptionRejected",toJson true),("truncationRejected",toJson true),
    ("frameBytesEqual",toJson true),("residentHits",toJson hit.projectionHits),
    ("tinyCacheBytes",toJson (← cache.state.get).bytes),("repeatWrites",toJson repeated.writtenBytes),
    ("partition",toJson partition.snapshot.head),("modelCalls",toJson (0 : Nat))]).pretty

def scale (database root output : System.FilePath) : IO Unit := do
  check (!(← output.pathExists)) "preserve earlier direct scale audit"
  let source ← PageMap.pin database
  let model := "sentence-transformers/paraphrase-multilingual-MiniLM-L12-v2"
  let encoder := SearchProvider.encoderContract
  let some matrix ← VectorMatrix.open? root model encoder | throw (IO.userError "scale projections missing")
  let some _ ← PartitionBuild.open? root model encoder source matrix | throw (IO.userError "scale model missing")
  let compared ← compare matrix
  check (compared == matrix.metadata.rows && !(← (root / "routing").pathExists) &&
    !(← (root / "blocks").pathExists) && !(← (root / "clustered").pathExists))
    "direct scale retained a second vector body copy or lost rows"
  FileSystem.privateDirectory output
  IO.FS.writeFile (output / "result.json") (Json.mkObj [
    ("source",toJson source.head),("matrix",toJson matrix.snapshot.head),("rows",toJson compared),
    ("allOriginalBitsAndCoverageEqual",toJson true),("duplicateVectorDirectoriesAbsent",toJson true),
    ("modelCalls",toJson (0 : Nat))]).pretty

end Eggshell.DirectProjectionAudit
