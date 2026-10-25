import Eggshell.VectorBlocks
import Eggshell.SearchProvider
import Lean

open Lean Eggshell Eggshell.DB

private def check (condition : Bool) (message : String) : IO Unit :=
  unless condition do throw (IO.userError message)

private structure Document where
  windows : Array String
  deriving FromJson
private structure Request where
  documents : Array Document
  deriving FromJson

private structure OriginalPass where
  rows : Array (String × String)
  elapsedMs : Nat
  forcedBytes : Nat
private structure BlockPass where
  rows : Array (String × ByteArray)
  elapsedMs : Nat
  forcedBytes : Nat

private def originals (matrix : VectorMatrix.Ready) (keys : Array String) : IO OriginalPass := do
  let started ← IO.monoMsNow
  let mut rows := #[]
  let mut forcedBytes := 0
  for key in keys do
    let some row ← VectorMatrix.read matrix key | throw (IO.userError "original routed key is absent")
    forcedBytes := forcedBytes+row.1.utf8ByteSize+row.2.utf8ByteSize
    rows := rows.push row
  let elapsedMs := (← IO.monoMsNow)-started
  return ⟨rows,elapsedMs,forcedBytes⟩

private def blocks (ready : VectorBlocks.Ready) (cache : VectorBlocks.Cache)
    (keys : Array String) : IO BlockPass := do
  let started ← IO.monoMsNow
  let mut rows := #[]
  let mut forcedBytes := 0
  for key in keys do
    let row ← VectorBlocks.read ready cache key
    forcedBytes := forcedBytes+row.coverage.utf8ByteSize+row.bytes.size*2
    rows := rows.push (row.coverage,row.bytes)
  let elapsedMs := (← IO.monoMsNow)-started
  return ⟨rows,elapsedMs,forcedBytes⟩

private def assertEqual (keys : Array String) (baseline : OriginalPass) (candidate : BlockPass) : IO Unit := do
  check (baseline.rows.size == keys.size && candidate.rows.size == keys.size &&
    baseline.forcedBytes == candidate.forcedBytes) "routed original counts disagree"
  for index in [:keys.size] do
    let original := baseline.rows[index]!
    let actual := candidate.rows[index]!
    check (original.1 == actual.1 && original.2 == Blake3.hex actual.2) s!"original bits changed at routed key {keys[index]!}"

private def run (sourceRoot blockRoot requestPath output : System.FilePath) (repetition : Nat) : IO Unit := do
  check (!(← output.pathExists)) "preserve earlier read comparison"
  FileSystem.privateDirectory output
  let requestBytes ← IO.FS.readBinFile requestPath
  let some requestText := String.fromUTF8? requestBytes | throw (IO.userError "request is not UTF-8")
  let request : Request ← IO.ofExcept (Json.parse requestText >>= fromJson?)
  let mut keys : Array String := #[]
  let mut seen : Std.HashSet String := {}
  for document in request.documents do
    for key in document.windows do
      check (!seen.contains key && Receipt.validId key) "routed request repeats a key"
      seen := seen.insert key
      keys := keys.push key
  check (0 < keys.size && keys.size ≤ 4096) "routed request is outside the frozen allowance"
  let some matrix ← VectorMatrix.open? sourceRoot MiniLM.model SearchProvider.encoderContract |
    throw (IO.userError "original matrix unavailable")
  let some route ← VectorRoute.open? sourceRoot MiniLM.model SearchProvider.encoderContract matrix |
    throw (IO.userError "original router unavailable")
  let some ready ← VectorBlocks.open? blockRoot MiniLM.model SearchProvider.encoderContract matrix route |
    throw (IO.userError "original-basis blocks unavailable")
  let cache ← VectorBlocks.Cache.make
  let baselineFirst ← IO.mkRef (none : Option OriginalPass)
  let baselineRepeat ← IO.mkRef (none : Option OriginalPass)
  let blockedFirst ← IO.mkRef (none : Option BlockPass)
  let blockedRepeat ← IO.mkRef (none : Option BlockPass)
  let afterFirst ← IO.mkRef (0,0)
  let orders := if repetition%2 == 0 then ["original","blocked"] else ["blocked","original"]
  for method in orders do
    if method == "original" then
      baselineFirst.set (some (← originals matrix keys))
      baselineRepeat.set (some (← originals matrix keys))
    else
      blockedFirst.set (some (← blocks ready cache keys))
      afterFirst.set (← cache.hits.get,← cache.misses.get)
      blockedRepeat.set (some (← blocks ready cache keys))
  let some a ← baselineFirst.get | throw (IO.userError "missing original first pass")
  let some b ← baselineRepeat.get | throw (IO.userError "missing original repeated pass")
  let some c ← blockedFirst.get | throw (IO.userError "missing blocked first pass")
  let some d ← blockedRepeat.get | throw (IO.userError "missing blocked repeated pass")
  assertEqual keys a c
  assertEqual keys b d
  let (firstHits,firstMisses) ← afterFirst.get
  check ((← cache.misses.get) == firstMisses && (← cache.hits.get) == firstHits+keys.size)
    "resident routed blocks were read or hashed again"
  let state ← cache.state.get
  IO.FS.writeFile (output / "result.json") (Json.mkObj [
    ("repetition",toJson repetition),("methodOrder",toJson orders),
    ("request",toJson requestPath.toString),("requestSha256",toJson (Sha256.hex requestBytes)),
    ("keys",toJson keys.size),("keySequenceSha256",toJson (Sha256.hex (toJson keys).compress.toUTF8)),
    ("originalFirstMs",toJson a.elapsedMs),("originalRepeatMs",toJson b.elapsedMs),
    ("blockedFirstMs",toJson c.elapsedMs),("blockedResidentMs",toJson d.elapsedMs),
    ("originalRowsAndCoverageExactlyEqual",toJson true),("forcedEncodedBytes",toJson a.forcedBytes),
    ("rawBytes",toJson (keys.size*ready.manifest.rowBytes)),
    ("firstBlockReadsAndHashes",toJson firstMisses),("firstCacheHits",toJson firstHits),
    ("residentBlockReadsAndHashes",toJson ((← cache.misses.get)-firstMisses)),
    ("residentCacheHits",toJson ((← cache.hits.get)-firstHits)),
    ("cacheBytes",toJson state.bytes),("cacheBlocks",toJson state.entries.length),
    ("sharedCacheCapacity",toJson cache.capacity),("originalMatrix",toJson matrix.snapshot.head),
    ("originalRoute",toJson route.snapshot.head),("blocked",toJson ready.snapshot.head),
    ("scope",toJson "read-only block backend; no scoring, hook, source encoding or answering model; OS cache not flushed")]).pretty

def main (args : List String) : IO Unit := do
  match args with
  | [sourceRoot,blockRoot,requestPath,output,repetition] =>
    let some number := repetition.toNat? | throw (IO.userError "invalid repetition")
    run (.mk sourceRoot) (.mk blockRoot) (.mk requestPath) (.mk output) number
  | _ => throw (IO.userError "VectorBlocksReadAudit SOURCE BLOCKS REQUEST OUT REPETITION")
