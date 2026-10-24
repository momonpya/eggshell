import Eggshell.SearchProvider

open Lean Eggshell Eggshell.DB

private def check (condition : Bool) (message : String) : IO Unit :=
  unless condition do throw (IO.userError message)

/-- Independent reader for the already audited flat reference artifact only.
It is not a fallback or another format accepted by the product candidate. -/
private structure FlatRow where
  key : String
  coverage : String
  offset : Nat
  bytes : Nat
  digest : String

private def flatRowCodec := (Wire.text.product (Wire.text.product
  (Wire.natural.product (Wire.natural.product Wire.text)))).iso
    (fun row : FlatRow => (row.key,row.coverage,row.offset,row.bytes,row.digest))
    (fun (key,coverage,offset,bytes,digest) => FlatRow.mk key coverage offset bytes digest)
    (by intro row; cases row; rfl)

private structure FlatManifest where
  model : String
  encoder : String
  implementation : String
  rows : Nat
  bytes : Nat
  directoryBytes : Nat
  directoryDigest : String
  deriving FromJson

private structure Flat where
  manifest : FlatManifest
  rows : List FlatRow
  byKey : Std.HashMap String FlatRow
  handle : FileSystem.ReadHandle
  version : FileSystem.ReadVersion

private def openFlat (root : System.FilePath) : IO Flat := do
  let path := root / "matrix"
  let metadata : FlatManifest ← IO.ofExcept (Json.parse (← IO.FS.readFile (path / "ready.json")) >>= fromJson?)
  check (metadata.encoder == SearchProvider.encoderContract && metadata.directoryBytes ≤ 64*1024*1024)
    "foreign or oversized reference matrix"
  let directory ← FileSystem.boundedBytes (path / "directory") (64*1024*1024)
  check (directory.size == metadata.directoryBytes && Sha256.hex directory == metadata.directoryDigest)
    "reference directory changed"
  let (rows,tail) ← IO.ofExcept ((Wire.list flatRowCodec).decode directory.toList)
  check (tail.isEmpty && rows.length == metadata.rows) "invalid reference population"
  let mut offset := 0
  let mut index : Std.HashMap String FlatRow := {}
  for row in rows do
    check (Receipt.validId row.key && Receipt.validId row.digest && !index.contains row.key &&
      row.offset == offset && 0 < row.bytes && row.bytes ≤ 32768 && row.bytes % 8 == 0 &&
      row.coverage.utf8ByteSize ≤ 4096) "invalid reference row"
    offset := offset+row.bytes
    index := index.insert row.key row
  check (offset == metadata.bytes) "reference extent differs"
  let handle ← FileSystem.openRead (path / "rows").toString
  let version ← FileSystem.readVersion handle
  check (version.bytes == metadata.bytes) "reference data changed"
  return ⟨metadata,rows,index,handle,version⟩

private def Flat.read (flat : Flat) (row : FlatRow) : IO VectorMatrix.Entry := do
  check ((← FileSystem.readVersion flat.handle) == flat.version) "reference changed before read"
  let mut bytes := ByteArray.empty
  while bytes.size < row.bytes do
    let count := min 4096 (row.bytes-bytes.size)
    let part ← FileSystem.readPage flat.handle (row.offset+bytes.size).toUInt64 ⟨count,Nat.min_le_left _ _⟩
    check (part.size == count) "reference row truncated"
    bytes := bytes ++ part
  check ((← FileSystem.readVersion flat.handle) == flat.version && Sha256.hex bytes == row.digest)
    "reference projected digest differs"
  return ⟨row.key,row.coverage,Blake3.hex bytes⟩

def main (args : List String) : IO Unit := do
  let [reference,raw,directory,output] := args |
    throw (IO.userError "IncrementalMatrixAudit FLAT-REFERENCE RAW-CACHE STORE NEW-OUTPUT")
  let root := System.FilePath.mk directory
  let output := System.FilePath.mk output
  check (!(← output.pathExists)) "keep earlier matrix audit"
  let resumed ← root.pathExists
  IO.FS.createDirAll output
  FileSystem.privateDirectory root
  let started ← IO.monoMsNow
  let flat ← openFlat (.mk reference)
  let referenceOpenMs := (← IO.monoMsNow)-started
  let some last := flat.rows.getLast? | throw (IO.userError "empty reference")
  let baseKeys := (flat.rows.dropLast).map (·.key)
  let prepared ← VectorMatrix.ensureUsing root flat.manifest.model flat.manifest.encoder baseKeys fun key => do
    let some row := flat.byKey[key]? | throw (IO.userError "missing reference key")
    flat.read row
  let some before ← VectorMatrix.open? root flat.manifest.model flat.manifest.encoder |
    throw (IO.userError "missing initial projection store")
  check (before.metadata.rows == baseKeys.length && (← VectorMatrix.read before last.key).isNone)
    "base store is not the expected pre-addition population"
  let originalBytes ← IO.FS.readBinFile (PageMap.dataPath before.snapshot.directory before.snapshot.head)
  let options : SearchProvider.Options := {
    cache := root
    fallback := some (.mk raw)
    models := .mk "/unused-by-pure-projection"
    model := flat.manifest.model }
  let added ← SearchProvider.prepareMatrix options (flat.rows.map (·.key))
  check (added.produced == 1 && added.added == 1 && added.reused == baseKeys.length)
    "actual prepareMatrix reproduced unchanged projections"
  let started ← IO.monoMsNow
  let some ready ← VectorMatrix.open? root flat.manifest.model flat.manifest.encoder |
    throw (IO.userError "incremental projection store not published")
  let openMs := (← IO.monoMsNow)-started
  let openReads ← ready.snapshot.reads.get
  let pathBound := ready.snapshot.head.root.map (·.height+1) |>.getD 0
  check (openReads ≤ pathBound)
    "projection open exceeded a bounded statistics path"
  check (before.snapshot.head.identity == ready.snapshot.head.identity &&
    before.snapshot.head.revision+1 == ready.snapshot.head.revision &&
    ((← IO.FS.readBinFile (PageMap.dataPath ready.snapshot.directory ready.snapshot.head)).extract 0 originalBytes.size) == originalBytes)
    "one addition replaced or rewrote the base publication"
  check ((← VectorMatrix.read before last.key).isNone) "old reader gained the new row"
  let unchanged ← SearchProvider.prepareMatrix options (flat.rows.map (·.key))
  check (unchanged.produced == 0 && unchanged.writtenBytes == 0) "unchanged prepareMatrix wrote projections"
  let mut originalMs := 0
  let mut candidateMs := 0
  let mut checked := 0
  for row in flat.rows do
    let started ← IO.monoMsNow
    let expected ← flat.read row
    originalMs := originalMs+((← IO.monoMsNow)-started)
    let started ← IO.monoMsNow
    let actual ← VectorMatrix.read ready row.key
    candidateMs := candidateMs+((← IO.monoMsNow)-started)
    check (actual == some (expected.coverage,expected.projected)) "incremental projection changed original bits or coverage"
    if row.key != last.key then
      check ((← before.snapshot.get ("row:"++row.key)) == (← ready.snapshot.get ("row:"++row.key)))
        "unchanged row moved to new blob references"
    checked := checked+1
  check (ready.metadata.rows == flat.manifest.rows && ready.metadata.bytes == flat.manifest.bytes)
    "paged population or projected byte count differs"
  let report := Json.mkObj [("referenceDirectoryOpenMs",toJson referenceOpenMs),
    ("resumedBaseAfterMissingRawCache",toJson resumed),("addedKey",toJson last.key),
    ("prepared",toJson prepared),("oneAdditionViaSearchProvider",toJson added),
    ("unchangedViaSearchProvider",toJson unchanged),("openMs",toJson openMs),("checkedKeys",toJson checked),
    ("originalMs",toJson originalMs),("candidateMs",toJson candidateMs),
    ("head",toJson ready.snapshot.head),("physicalPageReads",toJson (← ready.snapshot.reads.get)),
    ("physicalReadBytes",toJson (← ready.snapshot.readBytes.get)),
    ("projectedBitsAndCoverageEqual",toJson true),("openDirectoryPageReads",toJson openReads),
    ("originalPrefixAndReferencesUnchanged",toJson true),
    ("allProviderRanksChecked",toJson false),("answeringModelCalls",toJson (0 : Nat)),("adopted",toJson false)]
  IO.FS.writeFile (output / "result.json") report.pretty
  IO.println report.compress
