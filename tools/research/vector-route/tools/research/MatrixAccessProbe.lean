import Eggshell.SearchProvider
import Eggshell.CandidateDomain

open Lean Eggshell Eggshell.DB

private def check (condition : Bool) (message : String) : IO Unit :=
  unless condition do throw (IO.userError message)

private structure Timings where
  lookupNs : Nat := 0
  descriptorNs : Nat := 0
  beforeNs : Nat := 0
  blobNs : Nat := 0
  afterNs : Nat := 0
  hexNs : Nat := 0
  coverageNs : Nat := 0
  finiteNs : Nat := 0
  frameNs : Nat := 0
  deriving ToJson

private def timedStage (totals : IO.Ref Timings) (field : Timings → Nat → Timings)
    (action : Unit → IO α) : IO α := do
  let started ← IO.monoNanosNow
  let value ← action ()
  let elapsed := (← IO.monoNanosNow)-started
  totals.modify (field · elapsed)
  return value

private def profiledRead (ready : VectorMatrix.Ready) (key : String) (totals : IO.Ref Timings) :
    IO (Option (String × String)) := do
  check (Receipt.validId key) "invalid projection key"
  let some encoded ← timedStage totals (fun t n => {t with lookupNs := t.lookupNs+n})
    (fun _ => ready.snapshot.get ("row:"++key)) | return none
  let row ← timedStage totals (fun t n => {t with descriptorNs := t.descriptorNs+n})
    (fun _ => VectorMatrix.decodeRow encoded)
  timedStage totals (fun t n => {t with beforeNs := t.beforeNs+n}) fun _ => do
    check ((← FileSystem.readVersion ready.snapshot.handle).bytes ≥ ready.snapshot.head.bytes)
      "projection committed prefix was truncated"
  let bytes ← timedStage totals (fun t n => {t with blobNs := t.blobNs+n}) fun _ => do
    let mut bytes := ByteArray.empty
    for chunk in row.chunks do
      check (chunk.bytes == min 4096 (row.bytes-bytes.size)) "invalid projection chunk shape"
      bytes := bytes ++ (← ready.snapshot.readBlob chunk)
    return bytes
  timedStage totals (fun t n => {t with afterNs := t.afterNs+n}) fun _ => do
    check (bytes.size == row.bytes &&
      (← FileSystem.readVersion ready.snapshot.handle).bytes ≥ ready.snapshot.head.bytes)
      "projection committed prefix changed"
  let vector ← timedStage totals (fun t n => {t with hexNs := t.hexNs+n}) (fun _ => pure (Blake3.hex bytes))
  return some (row.coverage,vector)

def main (args : List String) : IO Unit := do
  let [database,root,limit,output] := args |
    throw (IO.userError "MatrixAccessProbe DB MATRIX-ROOT COUNT NEW-OUTPUT.json")
  let some count := limit.toNat? | throw (IO.userError "invalid count")
  let output := System.FilePath.mk output
  check (!(← output.pathExists)) "keep earlier matrix profile"
  let source ← PageMap.pin (.mk database)
  let some domain ← CandidateDomain.openShared? source | throw (IO.userError "prepared domain unavailable")
  let keys := ((domain.documents.flatMap (·.windows)).take count).toArray
  check (keys.size == count && count > 0) "profile count exceeds source windows"
  let some reference ← VectorMatrix.open? (.mk root) MiniLM.model SearchProvider.encoderContract |
    throw (IO.userError "prepared matrix unavailable")
  let some actual ← VectorMatrix.open? (.mk root) MiniLM.model SearchProvider.encoderContract |
    throw (IO.userError "same matrix unavailable")
  check (reference.snapshot.head == actual.snapshot.head) "profile snapshots differ"
  let began ← IO.monoMsNow
  let mut expected := #[]
  for key in keys do expected := expected.push (← VectorMatrix.read reference key)
  let referenceMs := (← IO.monoMsNow)-began
  let totals ← IO.mkRef ({} : Timings)
  let began ← IO.monoMsNow
  let mut bytes := 0
  let mut batch := #[]
  for i in [:keys.size] do
    let got ← profiledRead actual keys[i]! totals
    check (got == expected[i]!) "profile split changed original row or absence"
    let some (coverage,vector) := got | throw (IO.userError "missing fixed-source vector")
    timedStage totals (fun t n => {t with coverageNs := t.coverageNs+n}) fun _ => do
      let checked ← IO.ofExcept (Json.parse coverage >>= fromJson? (α := SearchProvider.EncodingCoverage))
      check checked.valid "invalid original coverage"
    timedStage totals (fun t n => {t with finiteNs := t.finiteNs+n}) fun _ => do
      check (SearchProvider.packedFinite vector) "invalid original numerical value"
    batch := batch.push (Json.arr #[Json.str vector])
    if batch.size == 256 then
      let framed ← timedStage totals (fun t n => {t with frameNs := t.frameNs+n})
        (fun _ => pure ((Json.mkObj [("candidates",Json.arr batch)]).compress))
      bytes := bytes+framed.utf8ByteSize
      batch := #[]
  if !batch.isEmpty then
    let framed ← timedStage totals (fun t n => {t with frameNs := t.frameNs+n})
      (fun _ => pure ((Json.mkObj [("candidates",Json.arr batch)]).compress))
    bytes := bytes+framed.utf8ByteSize
  let profiledMs := (← IO.monoMsNow)-began
  check ((← PageMap.pin actual.snapshot.directory).head == actual.snapshot.head) "matrix publication changed"
  check ((← PageMap.pin source.directory).head == source.head) "source publication changed"
  let result := Json.mkObj [("source",toJson source.head),("matrix",toJson actual.snapshot.head),
    ("matrixDirectory",toJson actual.snapshot.directory.toString),("count",toJson count),
    ("originalReadMs",toJson referenceMs),("profiledWithValidationAndFramingMs",toJson profiledMs),
    ("stages",toJson (← totals.get)),("referencePageReads",toJson (← reference.snapshot.reads.get)),
    ("referenceReadBytes",toJson (← reference.snapshot.readBytes.get)),
    ("profilePageReads",toJson (← actual.snapshot.reads.get)),
    ("profileReadBytes",toJson (← actual.snapshot.readBytes.get)),("framedBytes",toJson bytes),
    ("allOriginalRowsEqual",toJson true),("sourceAndMatrixHeadsUnchanged",toJson true),
    ("firstPassWarmsOSCache",toJson true),("answeringModelCalls",toJson (0 : Nat)),("adopted",toJson false)]
  IO.FS.writeFile output result.pretty
  IO.println result.compress
