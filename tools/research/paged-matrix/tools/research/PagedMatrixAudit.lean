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
  let [directory,output] := args | throw (IO.userError "PagedMatrixAudit SEMANTIC-ROOT NEW-OUTPUT")
  let root := System.FilePath.mk directory
  let output := System.FilePath.mk output
  check (!(← output.pathExists)) "keep earlier matrix audit"
  IO.FS.createDirAll output
  let started ← IO.monoMsNow
  let flat ← openFlat root
  let referenceOpenMs := (← IO.monoMsNow)-started
  let prepared ← VectorMatrix.writeUsing root flat.manifest.model flat.manifest.encoder (flat.rows.map (·.key)) fun key => do
    let some row := flat.byKey[key]? | throw (IO.userError "missing reference key")
    flat.read row
  let started ← IO.monoMsNow
  let some ready ← VectorMatrix.open? root flat.manifest.model flat.manifest.encoder |
    throw (IO.userError "paged matrix not published")
  let openMs := (← IO.monoMsNow)-started
  check ((← ready.snapshot.reads.get) == 0 && (← ready.snapshot.readBytes.get) == 0)
    "matrix open materialized directory pages"
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
    check (actual == some (expected.coverage,expected.projected)) "paged matrix changed original bits or coverage"
    checked := checked+1
  check (ready.metadata.rows == flat.manifest.rows && ready.metadata.bytes == flat.manifest.bytes)
    "paged population or projected byte count differs"
  let report := Json.mkObj [("referenceDirectoryOpenMs",toJson referenceOpenMs),
    ("prepared",toJson prepared),("openMs",toJson openMs),("checkedKeys",toJson checked),
    ("originalMs",toJson originalMs),("candidateMs",toJson candidateMs),
    ("head",toJson ready.snapshot.head),("physicalPageReads",toJson (← ready.snapshot.reads.get)),
    ("physicalReadBytes",toJson (← ready.snapshot.readBytes.get)),
    ("projectedBitsAndCoverageEqual",toJson true),("openDirectoryPageReads",toJson (0 : Nat)),
    ("allProviderRanksChecked",toJson false),("answeringModelCalls",toJson (0 : Nat)),("adopted",toJson false)]
  IO.FS.writeFile (output / "result.json") report.pretty
  IO.println report.compress
