import Eggshell.Warm
import tools.research.ArtifactHash

open Lean Eggshell

private def check (condition : Bool) (message : String) : IO Unit :=
  unless condition do throw (IO.userError message)

private def provider (binary : String) (request : Json) : IO (Json × Nat) :=
  SemanticMatcher.withProvider [binary,"search-provider"] fun running => do
    let started ← IO.monoMsNow
    running.child.stdin.putStrLn request.compress
    running.child.stdin.flush
    let result ← IO.ofExcept (Json.parse (← running.child.stdout.getLine))
    check (!(result.getObjVal? "error").isOk && !(result.getObjVal? "need_windows").isOk)
      "prepared numerical provider failed or tried to encode source windows"
    return (result,(← IO.monoMsNow)-started)

def main (args : List String) : IO Unit := do
  let [database,reference,candidate,output] := args |
    throw (IO.userError "VectorMatrixAudit DB REFERENCE CANDIDATE NEW-OUTPUT")
  let output := System.FilePath.mk output
  check (!(← output.pathExists)) "keep earlier matrix audit"
  IO.FS.createDirAll output
  let source ← DB.PageMap.pin (.mk database)
  let owner := DB.Sidecar.Owner.ofSnapshot source
  let _ ← DB.Sidecar.prepare owner .user
  let options ← Warm.options source [candidate,"search-provider"] .user
  let (discovery,focus) ← Warm.planWindows source
  let keys := hashDistinct ((discovery ++ focus).map (·.key))
  let started ← IO.monoMsNow
  let prepared ← DB.Sidecar.withIndexClaim owner (fun _ => SearchProvider.prepareMatrix options keys) .user
  let prepareMs := (← IO.monoMsNow)-started
  let opened ← IO.monoMsNow
  let some ready ← VectorMatrix.open? options.cache options.model SearchProvider.encoderContract |
    throw (IO.userError "prepared matrix missing")
  let openMs := (← IO.monoMsNow)-opened
  let mut originalMs := 0
  let mut matrixMs := 0
  let mut checked := 0
  for key in keys do
    let started ← IO.monoMsNow
    let cached ← SearchProvider.indexedWindow options key
    let expected ← IO.ofExcept (WindowCentroid.project cached.vector cached.coverage.sourceTokens
      (cached.coverage.contextTokens-2) cached.coverage.overlapTokens)
    originalMs := originalMs + ((← IO.monoMsNow)-started)
    let started ← IO.monoMsNow
    let actual ← VectorMatrix.read ready key
    matrixMs := matrixMs + ((← IO.monoMsNow)-started)
    check (actual == some ((toJson cached.coverage).compress,expected)) "matrix changed original projected bits or coverage"
    checked := checked+1
  let repeatResult ← DB.Sidecar.withIndexClaim owner (fun _ => SearchProvider.prepareMatrix options keys) .user
  check (repeatResult.mode == "warm") "unchanged matrix rebuilt"
  IO.FS.writeFile (output / "rows.json") (Json.mkObj [
    ("prepared",toJson prepared),("prepareMs",toJson prepareMs),("openMs",toJson openMs),
    ("checkedKeys",toJson checked),("originalReadAndProjectionMs",toJson originalMs),
    ("matrixReadAndVerifyMs",toJson matrixMs),("repeat",toJson repeatResult),
    ("projectedBitsAndCoverageEqual",toJson true)]).pretty
  -- Damage and replacement are tested only in a tiny private scratch matrix.
  let fixture := output / "fixture"
  FileSystem.privateDirectory fixture
  let metadata := (toJson (← SearchProvider.indexedWindow options keys.head!).coverage).compress
  let first : VectorMatrix.Entry := ⟨keys.head!,metadata,"000000000000f03f"⟩
  let _ ← VectorMatrix.write fixture options.model SearchProvider.encoderContract #[first]
  let some old ← VectorMatrix.open? fixture options.model SearchProvider.encoderContract |
    throw (IO.userError "fixture matrix missing")
  let data := VectorMatrix.folder fixture / "rows"
  let original ← IO.FS.readBinFile data
  FileSystem.atomicExistingBytes data (original.set! 0 1)
  let corrupt ← VectorMatrix.open? fixture options.model SearchProvider.encoderContract
  check ((← try corrupt.mapM (fun matrix => VectorMatrix.read matrix first.key) catch _ => pure none).join.isNone)
    "corrupt matrix row accepted"
  FileSystem.atomicExistingBytes data original
  check ((← VectorMatrix.open? fixture "foreign-model" SearchProvider.encoderContract).isNone)
    "foreign model accepted"
  check ((← VectorMatrix.open? fixture options.model "foreign-encoder").isNone) "foreign encoder accepted"
  let _ ← VectorMatrix.write fixture options.model SearchProvider.encoderContract #[{first with projected := "0000000000000040"}]
  let oldResult ← try VectorMatrix.read old first.key catch _ => pure none
  check (oldResult.isNone || oldResult == some (metadata,first.projected)) "old descriptor returned replacement bytes"
  let question := "Find kernel realtime clock observations for monotonic scheduling and elapsed timers, question 1."
  let queryOptions ← SearchProvider.queryOptions options
  check ((← SearchProvider.readCachedVector queryOptions question).isSome) "fixed query must already be cached"
  let some domain ← CandidateDomain.openShared? source | throw (IO.userError "source catalogue not ready")
  let documents := domain.documents.map fun document => Json.mkObj [
    ("id",toJson document.owner),("windows",toJson document.windows),("cache",toJson document.cache)]
  let request := Json.mkObj [
    ("query",toJson (SemanticMatcher.item (.text question) question)), ("documents",toJson documents),
    ("lexical",toJson ([0,1,2] : List Nat)),("anchors",toJson ([2,0] : List Nat))]
  IO.FS.writeFile (output / "request.json") request.compress
  let (baseline,baselineMs) ← provider reference request
  IO.FS.writeFile (output / "reference.json") baseline.compress
  let (result,resultMs) ← provider candidate request
  IO.FS.writeFile (output / "candidate.json") result.compress
  check (result == baseline) "complete numerical ranking, thresholds or evidence windows changed"
  check ((← DB.PageMap.pin (.mk database)).head == source.head) "matrix audit changed source publication"
  let report := Json.mkObj [
    ("reference",toJson reference),("candidate",toJson candidate),
    ("referenceSha256",toJson (← Research.ArtifactHash.hex (.mk reference))),
    ("candidateSha256",toJson (← Research.ArtifactHash.hex (.mk candidate))),
    ("source",toJson source.head),("matrix",toJson prepared),("checkedKeys",toJson checked),
    ("originalReadAndProjectionMs",toJson originalMs),("matrixReadAndVerifyMs",toJson matrixMs),
    ("openMs",toJson openMs),("referenceProviderMs",toJson baselineMs),("candidateProviderMs",toJson resultMs),
    ("completeProviderOutputEqual",toJson true),("corruptionAndForeignIdentityRejected",toJson true),
    ("projectedBitsAndCoverageEqual",toJson true),("sourceUnchanged",toJson true),
    ("answeringModelCalls",toJson (0 : Nat)),("adopted",toJson false)]
  IO.FS.writeFile (output / "result.json") report.pretty
  IO.println report.compress
