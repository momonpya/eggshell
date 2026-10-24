import Eggshell.LexicalReads
import Eggshell.SearchRank

open Lean Eggshell Eggshell.DB Eggshell.Persistence.Store

private def check (condition : Bool) (message : String) : IO Unit :=
  unless condition do throw (IO.userError message)

private def capture (action : IO (List Nat × Nat)) : IO (Except String (List Nat × Nat)) := do
  try return .ok (← action) catch error => return .error error.toString

private structure Trace where
  bytes : ByteArray
  charged : Nat
  complete : Bool
  deriving BEq

private def Trace.json (trace : Trace) : Json := Json.mkObj [
  ("sha256",toJson (Sha256.hex trace.bytes)),("bytes",toJson trace.bytes.size),
  ("chargedBytes",toJson trace.charged),("complete",toJson trace.complete)]

private def trace (source : PageMap.Snapshot) : IO Trace := do
  let some trace ← source.trace.get | throw (IO.userError "missing read trace")
  return ⟨((Wire.list PageMap.readObservationCodec).encode trace.operations.reverse).toByteArray,
    trace.encodedBytes,trace.complete⟩

private def compare (reference : RetrievalResearch.Index.Reader source)
    (actual : RetrievalResearch.Index.Reader other) (unit : String)
    (lookup : String → IO (List Nat × Nat)) : IO (Json × Bool) := do
  source.trace.set (some {})
  other.trace.set (some {})
  reference.index.trace.set (some {})
  actual.index.trace.set (some {})
  let started ← IO.monoMsNow
  let expected ← capture (reference.posting unit)
  let referenceMs := (← IO.monoMsNow)-started
  let started ← IO.monoMsNow
  let result ← capture (lookup unit)
  let actualMs := (← IO.monoMsNow)-started
  check (match result,expected with
    | .ok a,.ok b => a == b
    | .error a,.error b => a == b
    | _,_ => false) "batched lexical posting changed original order/count/error"
  check ((← trace source) == (← trace other)) "batch prefetch changed logical source dependencies"
  check ((← trace reference.index) == (← trace actual.index)) "batch prefetch changed logical index dependencies"
  return (Json.mkObj [("unit",toJson unit),("referenceMs",toJson referenceMs),
    ("actualMs",toJson actualMs),("owners",toJson ((result.toOption.map (·.1.length)).getD 0)),
    ("rejected",toJson (!result.isOk)),("sourceTrace",(← trace other).json)],!result.isOk)

private def invalidCases (root : System.FilePath) : IO Json := do
  IO.FS.createDirAll root
  let source ← PageMap.create (root / "source.egg") "lexical source fixture"
  let index ← PageMap.create (root / "index.egg") "lexical index fixture"
  let unit := "wunique-fixture"
  let _ ← PageMap.withWriter index fun writer => do
    let intern : Intern := ⟨writer,← IO.mkRef {}⟩
    let term ← intern.term unit
    putNat writer (key (key "posting" term) 2) 7
    putNat writer (key "frequency" term) 1
    putNat writer (key "owner" 7) 2
  let mut records := #[]
  for mode in ["valid","wrong-member","not-candidate","missing-member","corrupt-member","wrong-index-owner"] do
    let source ← PageMap.pin source.directory
    let _ ← PageMap.withWriter source fun writer => do
      putNat writer (key "member" 7) (if mode == "wrong-member" then 3 else 2)
      putNat writer (key "candidate" 7) (if mode == "not-candidate" then 0 else 1)
      if mode == "missing-member" then writer.put (key "member" 7) none
      if mode == "corrupt-member" then writer.put (key "member" 7) (some ⟨#[255]⟩)
    let index ← PageMap.pin index.directory
    let _ ← PageMap.withWriter index fun writer =>
      putNat writer (key "owner" 7) (if mode == "wrong-index-owner" then 3 else 2)
    let first ← PageMap.pin source.directory
    let second ← PageMap.pin source.directory
    let firstReader : RetrievalResearch.Index.Reader first := ⟨← PageMap.pin index.directory,← RetrievalResearch.Index.stamp first⟩
    let secondReader : RetrievalResearch.Index.Reader second := ⟨← PageMap.pin index.directory,← RetrievalResearch.Index.stamp second⟩
    let (result,rejected) ← compare firstReader secondReader unit (← LexicalReads.make secondReader)
    check (rejected == (mode != "valid")) "invalid lexical membership was not rejected"
    records := records.push (result.setObjVal! "case" (toJson mode))
  return toJson records

private def pointCases (root : System.FilePath) : IO Json := do
  IO.FS.createDirAll root
  let source ← PageMap.create (root / "points.egg") "bounded point batch fixture"
  let _ ← PageMap.withWriter source fun writer => do
    for index in [:6000] do
      if index % 11 != 0 then
        writer.put (key "point" (100000+2*index)) (some ((Wire.natural.encode index).toByteArray))
    writer.put (key "point" 100002) none
  let reference ← PageMap.pin source.directory
  let actual ← PageMap.pin source.directory
  check (actual.head.root.any (fun root => root.height > 0)) "point audit requires multiple leaves"
  let names := ["","point:","point:999999","zz"] ++
    (List.range 1020).map (fun index => key "point" (100000+(index*37)%12000))
  reference.trace.set (some {})
  actual.trace.set (some {})
  let batch ← LexicalReads.load actual names
  check ((← trace actual).charged == 0) "speculative point batches recorded logical dependencies"
  for name in names do
    check ((← reference.get name) == (← batch.read name)) "point batch changed a present/absent value"
  check ((← trace reference) == (← trace actual)) "point batch changed complete ordered dependencies"
  let escaped ← try let _ ← batch.read "not-requested"; pure false catch _ => pure true
  check escaped "batch invented an unrequested absent result"
  let tooLarge ← try
    let _ ← LexicalReads.load actual (List.replicate (LexicalReads.batchLimit+1) "point:100004")
    pure false
    catch _ => pure true
  check tooLarge "batch accepted an unbounded request"
  let empty ← LexicalReads.load actual []
  check (empty.values.size == 0) "empty batch is not empty"
  -- A descriptor is not evidence of absence. The underlying checksum must be
  -- checked first even when the requested key lies outside the root fences.
  let some root := actual.head.root | throw (IO.userError "missing point fixture root")
  let bad := {root with checksum := "damaged-checksum"}
  let broken := {actual with head := {actual.head with root := some bad},cache := ← IO.mkRef {}}
  let referenceFailure ← try let _ ← broken.get "zz"; pure none catch error => pure (some error.toString)
  let failedBatch ← LexicalReads.load broken ["zz"]
  let batchFailure ← try let _ ← failedBatch.read "zz"; pure none catch error => pure (some error.toString)
  check (referenceFailure.isSome && referenceFailure == batchFailure)
    "batch converted unchecked out-of-fence corruption to absence"
  return Json.mkObj [("keys",toJson names.length),("branchHeight",toJson root.height),
    ("completeOrderedTraceEqual",toJson true),("keyBoundRejected",toJson true),
    ("unknownKeyRejected",toJson true),("outOfFenceCorruptionRejected",toJson true)]

def main (args : List String) : IO Unit := do
  let [database,output] := args | throw (IO.userError "LexicalReadsAudit DB NEW-OUTPUT")
  let output := System.FilePath.mk output
  check (!(← output.pathExists)) "keep earlier lexical audit"
  IO.FS.createDirAll output
  let source ← PageMap.pin (.mk database)
  let other ← PageMap.pin (.mk database)
  let some reference ← RetrievalResearch.Index.open? source | throw (IO.userError "original lexical index not warm")
  let some actual ← RetrievalResearch.Index.open? other | throw (IO.userError "same lexical index not warm")
  check (reference.index.head == actual.index.head) "different saved lexical snapshots"
  let lookup ← LexicalReads.make actual
  let units := hashDistinct ((["kernel realtime clock monotonic scheduling elapsed timers", "source 0 1 9968 49968",
    "no-such-quantum-xyz", "日本語 커널 café", "exec_command arbitrary.json"].flatMap SearchRank.terms))
  let mut records := #[]
  for unit in units do
    let (result,rejected) ← compare reference actual unit lookup
    check (!rejected) "valid published posting rejected"
    records := records.push result
  let invalid ← invalidCases (output / "invalid")
  let points ← pointCases (output / "points")
  check ((← PageMap.pin source.directory).head == source.head) "source publication changed"
  check ((← PageMap.pin reference.index.directory).head == reference.index.head) "lexical index rewritten"
  let report := Json.mkObj [("source",toJson source.head),("index",toJson reference.index.head),
    ("queries",toJson records),("invalidCases",invalid),("pointCases",points),("completeOrderedPostingsEqual",toJson true),
    ("originalLogicalReadTracesEqual",toJson true),("sourceAndIndexUnchanged",toJson true),
    ("answeringModelCalls",toJson (0 : Nat)),("adopted",toJson false)]
  IO.FS.writeFile (output / "result.json") report.pretty
  IO.println (Json.mkObj [("queries",toJson records.size),("completeOrderedPostingsEqual",toJson true),
    ("originalLogicalReadTracesEqual",toJson true),("sourceAndIndexUnchanged",toJson true)]).compress
