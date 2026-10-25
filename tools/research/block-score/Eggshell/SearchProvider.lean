module
public import Eggshell.PreparationDebt

public import Eggshell.SearchRank
public import Eggshell.MiniLM
public import Eggshell.Sha256
public import Eggshell.Persistence
public import Eggshell.SemanticMatcher
public import Eggshell.Receipt
public import tools.DirectoryReads
public import tools.WindowCentroid
public import Eggshell.VectorMatrix
public import Eggshell.BlockScore
public import Lean.Data.Json.FromToJson

@[expose] public section

namespace Eggshell.SearchProvider
open Lean

structure EncodingCoverage where
  characters : Nat
  visibleCharacters : Nat
  tokenizerMappedCharacters : Nat
  embeddedCharacters : Nat
  sourceTokens : Nat
  segments : Nat
  contextTokens : Nat
  overlapTokens : Nat
  completeTokenOffsets : Bool
  deriving ToJson, FromJson

def EncodingCoverage.valid (c : EncodingCoverage) : Bool :=
  c.characters ≤ 512 && c.embeddedCharacters == c.tokenizerMappedCharacters &&
  c.tokenizerMappedCharacters ≤ c.visibleCharacters && c.visibleCharacters ≤ c.characters &&
  0 < c.segments && c.segments ≤ 512 && 2 < c.contextTokens &&
  c.overlapTokens < c.contextTokens - 2 && c.sourceTokens ≤ c.segments * c.contextTokens &&
  c.completeTokenOffsets

/-- Counts window/reference positions, not unique whole-document characters. -/
structure InputTotals where
  windows : Nat := 0
  characters : Nat := 0
  visibleCharacters : Nat := 0
  tokenizerMappedCharacters : Nat := 0
  embeddedCharacters : Nat := 0
  vectors : Nat := 0
  tokens : Nat := 0
  deriving ToJson

def InputTotals.add (t : InputTotals) (c : EncodingCoverage) : InputTotals := {
  windows := t.windows + 1, characters := t.characters + c.characters
  visibleCharacters := t.visibleCharacters + c.visibleCharacters
  tokenizerMappedCharacters := t.tokenizerMappedCharacters + c.tokenizerMappedCharacters
  embeddedCharacters := t.embeddedCharacters + c.embeddedCharacters
  vectors := t.vectors + c.segments, tokens := t.tokens + c.sourceTokens }

structure CacheProbes where
  hit : Nat := 0
  absent : Nat := 0
  unusable : Nat := 0
  deriving ToJson

structure EncoderSample where
  startupUs : Nat
  leaseUs : Nat
  initializeUs : Nat
  encodeUs : Nat
  scoreUs : Nat
  requestUs : Nat
  modelLoaded : Bool
  deriving FromJson

structure EncoderTiming where
  replies : Nat := 0
  startupUs : Nat := 0
  leaseUs : Nat := 0
  initializeUs : Nat := 0
  queryEncodeUs : Nat := 0
  sourceEncodeUs : Nat := 0
  scoreUs : Nat := 0
  requestUs : Nat := 0
  modelLoaded : Bool := false
  deriving ToJson

structure IndexedMetrics where
  scoringPolicy : String := "window centroid weighted by newly covered source tokens"
  source : CacheProbes := {}
  query : CacheProbes := {}
  cacheMs : Nat := 0
  queryMs : Nat := 0
  scoreMs : Nat := 0
  scoredWindows : Nat := 0
  blockReadMsWithinScore : Nat := 0
  blockHits : Nat := 0
  blockMisses : Nat := 0
  blockRetainedBytes : Nat := 0
  matrixRows : Nat := 0
  matrixOpens : Nat := 0
  matrixOpenMs : Nat := 0
  sourceInput : InputTotals := {}
  queryInput : InputTotals := {}
  encoder : Option EncoderTiming := none
  phase : String := "source-cache"
  deriving ToJson

structure MetricsSink where
  receipt : Option String
  stage : String
  started : Nat
  corpus : Json
  state : IO.Ref IndexedMetrics

def MetricsSink.flush (sink : MetricsSink) (status : String) : IO Unit := do
  Receipt.observe sink.receipt sink.stage (Json.mkObj [
    ("status", toJson status), ("elapsedMs", toJson ((← IO.monoMsNow) - sink.started)),
    ("corpus", sink.corpus), ("counters", toJson (← sink.state.get))])

structure Options where
  cache : System.FilePath
  fallback : Option System.FilePath := none
  privateWrite : Option System.FilePath := none
  owner : Option DB.Sidecar.Owner := none
  models : System.FilePath
  model : String := MiniLM.model
  mode : String := "hybrid"
  topK : Nat := 8
  anchorK : Nat := 2
  threshold : Float := 0.38
  trace : Option System.FilePath := none
  lane : SemanticMatcher.Lane := .search
  metrics : Option MetricsSink := none
  directories : Option DirectoryReads := none
  matrices : Option (IO.Ref (Std.HashMap String (Option VectorMatrix.Ready))) := none

def observeInput (options : Options) (query : Bool) (c : EncodingCoverage) : IO Unit := do
  let some sink := options.metrics | return
  sink.state.modify fun s => if query then {s with queryInput := s.queryInput.add c}
    else {s with sourceInput := s.sourceInput.add c}

def encoderContract : String := Sha256.hex MiniLM.embeddingSource.toUTF8

def number (json : Json) : Except String Float := do
  match json with
  | .num value =>
    let result := value.toFloat
    if result.isFinite then pure result else throw "expected finite JSON number"
  | _ => throw "expected finite JSON number"

def natural (value : String) : Except String Nat :=
  match value.toNat? with
  | some n => .ok n
  | none => .error "expected a natural number"

def parse (defaults : Options) : List String → Except String Options
  | [] => .ok defaults
  | "--cache" :: v :: rest => parse { defaults with cache := .mk v } rest
  | "--model-cache" :: v :: rest => parse { defaults with models := .mk v } rest
  | "--model" :: v :: rest => parse { defaults with model := v } rest
  | "--mode" :: v :: rest =>
      if ["lexical", "semantic", "hybrid"].contains v then parse { defaults with mode := v } rest
      else .error "unsupported search mode"
  | "--top-k" :: v :: rest => do parse { defaults with topK := ← natural v } rest
  | "--anchor-k" :: v :: rest => do parse { defaults with anchorK := ← natural v } rest
  | "--threshold" :: v :: rest => do parse { defaults with threshold := ← number (← Json.parse v) } rest
  | "--trace" :: v :: rest => parse { defaults with trace := some (.mk v) } rest
  | "--lane" :: "index" :: rest => parse { defaults with lane := .index } rest
  | "--lane" :: "search" :: rest => parse { defaults with lane := .search } rest
  | _ => .error "invalid search-provider arguments"

/-- A requesting pinned document/index batch supplies its DB-owned cache.
Requests without a durable owner retain only the process's temporary hints. -/
def cacheOptions (options : Options) (request : Json)
    (write : Option DB.Sidecar.Storage := none) : IO Options := do
  match (request.getObjVal? "cache").toOption with
  | none | some .null => pure options
  | some value =>
      let owner ← IO.ofExcept (fromJson? value : Except String DB.Sidecar.Owner)
      let snapshot ← owner.pin
      DB.Sidecar.observe snapshot
      let primary := DB.Sidecar.ofSnapshot snapshot
      let overlay ← DB.Sidecar.locate snapshot .user
      match write with
      | some storage =>
          let sidecar ← DB.Sidecar.prepare owner storage
          pure {options with
            cache := sidecar.semantic, owner := some owner
            fallback := some (if storage == .database then overlay.semantic else primary.semantic)
            privateWrite := none}
      | none =>
          pure {options with
            cache := primary.semantic, fallback := some overlay.semantic
            privateWrite := some overlay.semantic, owner := some owner}

def queryOptions (options : Options) : IO Options := do
  pure {options with
    cache := (← Paths.dataRoot) / "queries"
    owner := none, fallback := none, privateWrite := none}

abbrev Encoder := IO.Process.Child { stdin := .piped, stdout := .piped, stderr := .inherit }

def encoder (options : Options) : IO Encoder := do
  let layout := MiniLM.layout (← Paths.installRoot)
  let python ← (MiniLM.runtimePython? layout) >>= fun
    | some python => pure python
    | none => throw (IO.userError "MiniLM runtime is not installed")
  let binary ← IO.appPath
  IO.Process.spawn {
    cmd := binary.toString
    args := #["codex-numerical-client",options.model,options.models.toString,python.toString]
    stdin := .piped,stdout := .piped,stderr := .inherit }

def stopEncoder (child : Encoder) : IO Unit := do
  child.stdin.putStr "C\n"
  child.stdin.flush
  let deadline := (← IO.monoMsNow)+10000
  repeat
    if let some code ← child.tryWait then
      unless code == 0 do throw (IO.userError "numerical client exited unsuccessfully")
      return
    unless (← IO.monoMsNow) < deadline do
      child.kill
      let _ ← child.wait
      throw (IO.userError "numerical client did not close")
    IO.sleep 5

def exchange (child : Encoder) (input : Json)
    (observe : Json → IO Unit := fun _ => pure ()) : IO Json := do
  child.stdin.putStr (if (input.getObjVal? "texts").isOk then "E"
    else if (input.getObjVal? "blockRows").isOk then "B" else "S")
  child.stdin.putStrLn input.compress
  child.stdin.flush
  let result ← IO.ofExcept (Json.parse (← child.stdout.getLine))
  observe result
  if let .ok error := result.getObjValAs? String "error" then throw (IO.userError error)
  pure result

def measuredExchange (options : Options) (child : Encoder) (input : Json)
    (phase : String) : IO Json := do
  if let some sink := options.metrics then
    sink.state.modify fun state => {state with phase}
    if phase != "score" || (← sink.state.get).encoder.isNone then sink.flush "running"
  exchange child input fun result => do
    let some sink := options.metrics | return
    let .ok sample := result.getObjValAs? EncoderSample "timing" | return
    let previous ← sink.state.get
    let before := previous.encoder.getD {}
    let after : EncoderTiming := {
      replies := before.replies + 1
      startupUs := before.startupUs + sample.startupUs
      leaseUs := before.leaseUs + sample.leaseUs
      initializeUs := before.initializeUs + sample.initializeUs
      queryEncodeUs := before.queryEncodeUs + if phase == "query-embedding" then sample.encodeUs else 0
      sourceEncodeUs := before.sourceEncodeUs + if phase == "source-embedding" then sample.encodeUs else 0
      scoreUs := before.scoreUs + sample.scoreUs
      requestUs := before.requestUs + sample.requestUs
      modelLoaded := before.modelLoaded || sample.modelLoaded }
    sink.state.modify fun state => {state with encoder := some after, phase := "encoder-reply"}
    if before.replies == 0 || phase != "score" then sink.flush "running"

/-- Numerical hints retain only model/window digests and bounded vectors.
    They never establish source identity or completion authority. -/
structure CachedVector where
  model : String
  window : String
  contract : String
  coverage : EncodingCoverage
  vector : Array String
  deriving ToJson, FromJson

/-- Canonical little-endian IEEE binary64, two lowercase hexadecimal digits
per byte. JSON transports a string rather than reparsing decimal coefficients.
The exponent occupies the last byte's low seven bits and its neighbor's high
nibble; all-ones rejects both infinities and every NaN payload. -/
def packedFinite (encoded : String) : Bool := Id.run do
  let bytes := encoded.toUTF8
  if bytes.size == 0 || bytes.size > 4096 * 16 || bytes.size % 16 != 0 then return false
  for index in [:bytes.size] do
    let byte := bytes[index]!
    unless (48 ≤ byte && byte ≤ 57) || (97 ≤ byte && byte ≤ 102) do return false
  for word in [:bytes.size / 16] do
    let last := bytes[word * 16 + 14]!
    if (last == 55 || last == 102) && bytes[word * 16 + 15]! == 102 &&
        bytes[word * 16 + 12]! == 102 then return false
  return true

def packVector (vector : Json) : Except String String := do
  let .arr values := vector | throw "expected numerical vector array"
  unless 0 < values.size && values.size ≤ 4096 do throw "invalid numerical vector dimension"
  let mut bytes := ByteArray.empty
  for value in values do
    let bits := (← number value).toBits
    for index in [:8] do bytes := bytes.push ((bits >>> (index * 8).toUInt64).toUInt8)
  pure (Blake3.hex bytes)

structure CheckedVector (cached : CachedVector) : Type where
  valid : Receipt.validId cached.window = true ∧
    cached.contract = encoderContract ∧ cached.coverage.valid = true ∧
    cached.vector.size = cached.coverage.segments ∧
    cached.vector.all packedFinite = true

def CheckedVector.make? (cached : CachedVector) : Option (CheckedVector cached) :=
  if valid : Receipt.validId cached.window = true ∧
      cached.contract = encoderContract ∧ cached.coverage.valid = true ∧
      cached.vector.size = cached.coverage.segments ∧ cached.vector.all packedFinite = true then
    some ⟨valid⟩ else none

theorem CheckedVector.source_shape (checked : CheckedVector cached) :
    ∃ encodings : Array String, cached.vector = encodings ∧ encodings.all packedFinite = true :=
  ⟨cached.vector, rfl, checked.valid.2.2.2.2⟩


def cacheMatches (model text : String) (cached : CachedVector) : Bool :=
  decide (cached.model = model ∧ cached.window = Persistence.Store.windowKey text)

theorem accepted_cache_identity (model text : String) (cached : CachedVector)
    (h : cacheMatches model text cached = true) :
    cached.model = model ∧ cached.window = Persistence.Store.windowKey text := by
  exact of_decide_eq_true h

theorem changed_cache_window_rejected (model text : String) (cached : CachedVector)
    (h : cached.window ≠ Persistence.Store.windowKey text) : cacheMatches model text cached = false := by
  simp [cacheMatches, h]

theorem changed_cache_model_rejected (model text : String) (cached : CachedVector)
    (h : cached.model ≠ model) : cacheMatches model text cached = false := by
  simp [cacheMatches, h]

def windowCacheKey (model window : String) : String :=
  Sha256.hex (model.toUTF8 ++ encoderContract.toUTF8) ++ "-" ++ window

def cacheKey (model text : String) : String :=
  windowCacheKey model (Persistence.Store.windowKey text)

def vectorPaths (options : Options) (key : String) : List System.FilePath :=
  (options.cache :: options.fallback.toList).map (· / "vectors" / (key ++ ".json"))

/-- Count the actual initial availability probes, including repeated window
references. These are not DB coverage or an inferred whole-corpus hit rate. -/
def observeProbe (options : Options) (query hit : Bool) (path : System.FilePath)
    (elapsed : Nat) : IO Unit := do
  let some sink := options.metrics | return
  let absent ← if hit then pure false else
    try
      let paths := path :: options.fallback.toList.map (· / "vectors" / path.fileName.getD "")
      pure (← paths.allM fun path => return (← FileSystem.symlinkMetadata? path).isNone)
    catch _ => pure false
  sink.state.modify fun state =>
    let before := if query then state.query else state.source
    let after : CacheProbes := {
      hit := before.hit + if hit then 1 else 0
      absent := before.absent + if !hit && absent then 1 else 0
      unusable := before.unusable + if !hit && !absent then 1 else 0 }
    if query then {state with query := after, cacheMs := state.cacheMs + elapsed}
    else {state with source := after, cacheMs := state.cacheMs + elapsed}
  let state ← sink.state.get
  let count := state.source.hit + state.source.absent + state.source.unusable
  if query || count == 1 || count % 32 == 0 then sink.flush "running"

/-- Cache records are bounded numerical windows, never arbitrary-size source
bodies. Read through one secure descriptor so replacement cannot grow a
checked record between stat and allocation. Damage is a miss/pending search. -/
def loadVector (path : System.FilePath) : IO CachedVector := do
  let bytes ← FileSystem.boundedBytes path 1048576
  let some text := String.fromUTF8? bytes | throw (IO.userError "invalid embedding cache text")
  let cached ← IO.ofExcept (fromJson? (← IO.ofExcept (Json.parse text)) : Except String CachedVector)
  let some _ := CheckedVector.make? cached |
    throw (IO.userError "embedding window or dimension exceeds its resource contract")
  pure cached

def decodeVectorBytes (bytes : ByteArray) : IO CachedVector := do
  let some text := String.fromUTF8? bytes | throw (IO.userError "invalid embedding cache text")
  let cached ← IO.ofExcept (fromJson? (← IO.ofExcept (Json.parse text)) : Except String CachedVector)
  let some _ := CheckedVector.make? cached |
    throw (IO.userError "embedding window or dimension exceeds its resource contract")
  pure cached

theorem load_vector_original (path : System.FilePath) :
    loadVector path = (do decodeVectorBytes (← FileSystem.boundedBytes path 1048576)) := by
  rfl

def loadIndexedVector (options : Options) (path : System.FilePath) : IO CachedVector := do
  let bytes ← match options.directories with
    | none => FileSystem.boundedBytes path 1048576
    | some reads => FileSystem.boundedRead (← reads.open path) 1048576
  decodeVectorBytes bytes

def readCachedVector (options : Options) (text : String) : IO (Option CachedVector) := do
  for path in vectorPaths options (cacheKey options.model text) do
    try
      let cached ← loadVector path
      if cacheMatches options.model text cached then return some cached
    catch _ => pure ()
  pure none

def readVector (options : Options) (text : String) : IO (Option Json) := do
  pure ((← readCachedVector options text).map (fun c => toJson c.vector))

def saveVector (options : Options) (text : String) (vector : Json)
    (coverage : EncodingCoverage) : IO Unit := do
  unless text.length ≤ 512 do throw (IO.userError "index window exceeds source contract")
  unless coverage.characters == text.length do throw (IO.userError "embedding coverage source mismatch")
  let group ← IO.ofExcept vector.getArr?
  let encodings ← IO.ofExcept (group.mapM packVector)
  let cached : CachedVector := {
    model := options.model, window := Persistence.Store.windowKey text
    contract := encoderContract, coverage, vector := encodings}
  let some _ := CheckedVector.make? cached | throw (IO.userError "invalid numerical window for indexing")
  let encoded := (toJson cached).compress
  unless encoded.utf8ByteSize ≤ 1048576 do throw (IO.userError "oversized numerical window for indexing")
  let root := options.privateWrite.getD options.cache / "vectors"
  let path := root / (cacheKey options.model text ++ ".json")
  if let some owner := options.owner then
    let _ ← owner.pin
    if options.privateWrite.isSome then
      let _ ← DB.Sidecar.prepare owner .user
      pure ()
    FileSystem.atomicExistingBytes path encoded.toUTF8
  else
    Persistence.rejectSymlinkAncestors root
    Persistence.privateDirectory (options.privateWrite.getD options.cache)
    Persistence.privateDirectory root
    FileSystem.atomicBytes path encoded.toUTF8
  if let some reads := options.directories then reads.invalidate path

def storeWindows (options : Options) (child : Encoder) (windows : List String)
    (queryProbe : Bool := false) : IO Unit := do
  let parts := windows.eraseDups
  let mut missing := []
  for part in parts do
    unless part.length ≤ 512 do throw (IO.userError "index window exceeds the original-window contract")
    let started ← IO.monoMsNow
    let available ← readCachedVector options part
    if queryProbe then
      observeProbe options true available.isSome
        (options.cache / "vectors" / (cacheKey options.model part ++ ".json")) ((← IO.monoMsNow) - started)
    if available.isNone then missing := missing ++ [part]
  if missing.isEmpty then return
  let response ← measuredExchange options child (Json.mkObj [("texts", toJson missing)])
    (if queryProbe then "query-embedding" else "source-embedding")
  let vectors ← IO.ofExcept (response.getObjValAs? (Array Json) "vectors")
  if vectors.size != missing.length then throw (IO.userError "embedding count mismatch")
  let coverage ← IO.ofExcept (response.getObjValAs? (Array EncodingCoverage) "coverage")
  unless coverage.size == vectors.size do throw (IO.userError "embedding coverage count mismatch")
  for ((text, vector), measured) in (missing.zip vectors.toList).zip coverage.toList do
    saveVector options text vector measured

def store (options : Options) (child : Encoder) (texts : List String)
    (queryProbe : Bool := false) : IO Unit :=
  storeWindows options child (texts.flatMap SearchRank.windows) queryProbe

def vectors (options : Options) (text : String) : IO Json := do
  let values ← (SearchRank.windows text).mapM fun part => do
    let some cached ← readCachedVector options part | throw (IO.userError "missing indexed embedding")
    observeInput options true cached.coverage
    let pooled ← IO.ofExcept (Eggshell.WindowCentroid.project cached.vector
      cached.coverage.sourceTokens (cached.coverage.contextTokens - 2) cached.coverage.overlapTokens)
    pure #[Json.str pooled]
  pure (.arr values.toArray.flatten)

/-- Window hashes only nominate numerical hints. A hint cannot establish Work
identity or completion. Original graph owners are hydrated and checked by the
requesting pinned reader after selection. No source body is opened here. -/
def indexedWindow (options : Options) (window : String) : IO CachedVector := do
  unless Receipt.validId window do throw (IO.userError "invalid indexed vector locator")
  for path in vectorPaths options (windowCacheKey options.model window) do
    try
      let cached ← loadIndexedVector options path
      if cached.model == options.model && cached.window == window then return cached
    catch _ => pure ()
  throw (IO.userError "missing or unusable indexed embedding")

def indexedVectors (options : Options) (windows : List String) : IO Json := do
  let load := fun root => do
    let started ← IO.monoMsNow
    let ready ← try VectorMatrix.open? root options.model encoderContract catch _ => pure none
    if let some sink := options.metrics then
      let elapsed := (← IO.monoMsNow) - started
      sink.state.modify fun state => {state with
        matrixOpens := state.matrixOpens + 1
        matrixOpenMs := state.matrixOpenMs + elapsed}
    pure ready
  let values ← windows.mapM fun window => do
    if options.owner.isSome then
      for root in options.cache :: options.fallback.toList do
        try
          let ready ← match options.matrices with
            | none => load root
            | some known =>
                match (← known.get)[root.toString]? with
                | some ready => pure ready
                | none => do
                    let ready ← load root
                    known.modify (·.insert root.toString ready)
                    pure ready
          if let some ready := ready then
            if let some (metadata,pooled) ← VectorMatrix.read ready window then
              let coverage ← IO.ofExcept (Json.parse metadata >>= fromJson? (α := EncodingCoverage))
              unless coverage.valid && packedFinite pooled do throw (IO.userError "invalid projected numerical row")
              observeInput options false coverage
              if let some sink := options.metrics then
                sink.state.modify fun state => {state with matrixRows := state.matrixRows + 1}
              return #[Json.str pooled]
        catch _ => pure ()
    let cached ← indexedWindow options window
    observeInput options false cached.coverage
    let pooled ← IO.ofExcept (Eggshell.WindowCentroid.project cached.vector
      cached.coverage.sourceTokens (cached.coverage.contextTokens - 2) cached.coverage.overlapTokens)
    pure #[Json.str pooled]
  pure (.arr values.toArray.flatten)

/-- Prepare source-only pooled hints after raw-cache coverage is checked.
Questions remain private and do not enter this DB-owned matrix. -/
def prepareMatrix (options : Options) (keys : List String) : IO VectorMatrix.Result := do
  let keys := hashDistinct keys
  VectorMatrix.ensureUsing options.cache options.model encoderContract keys fun key => do
    let cached ← indexedWindow options key
    let pooled ← IO.ofExcept (Eggshell.WindowCentroid.project cached.vector
      cached.coverage.sourceTokens (cached.coverage.contextTokens - 2) cached.coverage.overlapTokens)
    return ⟨key,(toJson cached.coverage).compress,pooled⟩


abbrev RepairWindows := Nat → List (Nat × String) → IO (List String)

def unavailableRepair : RepairWindows := fun _ _ => throw (IO.userError "missing indexed embedding")

/-- Only missing windows are re-encoded. Exact locator verification precedes
inference and acknowledgement; a corrupted/missing hint cannot omit evidence
or substitute another source. The batch makes one repair attempt. -/
def repairBatch (options : Options) (child : Encoder) (document offset : Nat)
    (windows : List String) (repair : RepairWindows) : IO (Array BlockScore.Input) := do
  if let some owner := options.owner then
    return windows.toArray.map (BlockScore.Input.indexed owner)
  let mut missing : List (Nat × String) := []
  let mut retained : Array (Option Json) := #[]
  for (window, index) in windows.zipIdx do
    let started ← IO.monoMsNow
    let available ← try some <$> indexedVectors options [window] catch _ => pure none
    observeProbe options false available.isSome
      (options.cache / "vectors" / (windowCacheKey options.model window ++ ".json")) ((← IO.monoMsNow) - started)
    retained := retained.push available
    if available.isNone then missing := (offset + index, window) :: missing
  missing := missing.reverse
  unless missing.isEmpty do
    if let some owner := options.owner then
      PreparationDebt.record owner options.model encoderContract .unavailableInput missing.length
    let texts ← repair document missing
    unless texts.length == missing.length do throw (IO.userError "numerical window repair count mismatch")
    for (text, (_, digest)) in texts.zip missing do
      unless text.length ≤ 512 && Persistence.Store.windowKey text == digest do
        throw (IO.userError "numerical window repair source mismatch")
    storeWindows options child texts
  -- Each valid numerical window is already checked and read. Hold only this
  -- bounded batch; reread repaired misses, never all successful cache hits.
  windows.zipIdx.toArray.mapM fun (window, index) => do
    let vector ← match retained[index]?.getD none with
      | some vector => pure vector
      | none => indexedVectors options [window]
    let values ← IO.ofExcept (fromJson? vector : Except String (Array String))
    unless values.size == 1 do throw (IO.userError "transient projection count disagrees")
    return .projected values[0]!

def trace (options : Options) (record : Json) : IO Unit := do
  if let some path := options.trace then
    try
      if let some parent := path.parent then Persistence.privateDirectory parent
      let file ← IO.FS.Handle.mk path .append
      Persistence.privateFile path
      file.putStrLn record.compress
      file.flush
    catch error => IO.eprintln s!"Eggshell trace: {error}"

/-- This is optional process-local acceleration, not a source-data limit.
Keeping the previous input permits delta frequency repair on a repeated
provider request. Large requests are still evaluated, then not retained. -/
def corpusBytes (texts : List String) : Nat := (texts.map String.utf8ByteSize).sum

structure RetainedCorpus where
  texts : List String
  corpus : SearchRank.Corpus texts
  bounded : corpusBytes texts ≤ 1048576

def retainCorpus (texts : List String) (corpus : SearchRank.Corpus texts) : Option RetainedCorpus :=
  if bounded : corpusBytes texts ≤ 1048576 then some ⟨texts, corpus, bounded⟩ else none

theorem oversized_corpus_not_retained (texts : List String) (corpus : SearchRank.Corpus texts)
    (large : 1048576 < corpusBytes texts) : retainCorpus texts corpus = none := by
  have outside : ¬ corpusBytes texts ≤ 1048576 := by omega
  simp only [retainCorpus, dif_neg outside]

def selection (options : Options) (candidates : Array Json) (lexical anchors : List Nat)
    (scored : List (Float × Nat)) : IO Json := do
  let ordered := scored.mergeSort SearchRank.scoreOrder
  let semantic := (ordered.filter (·.1 ≥ options.threshold)).map (·.2)
  let hybrid := (SearchRank.fused [lexical, semantic]).take options.topK
  let base := if options.mode == "hybrid" then hybrid else if options.mode == "lexical" then lexical else semantic
  let selected := SearchRank.select candidates.size options.topK (anchors.take options.anchorK) base
  trace options (Json.mkObj [("mode", .str options.mode), ("candidate_count", toJson candidates.size),
    ("candidate_ids", .arr (candidates.map (·.getObjValD "id"))),
    ("lexical_rank", toJson lexical), ("anchor_rank", toJson anchors),
    ("semantic_rank", toJson (ordered.map (·.2))), ("semantic_threshold_rank", toJson semantic),
    ("hybrid_rank", toJson hybrid), ("selected", toJson selected)])
  pure (Json.mkObj [("related", toJson selected)])

structure WindowBatch (source : List String) where
  front : List String
  rest : List String
  complete : front ++ rest = source
  bounded : front.length ≤ 32
  decreases : source ≠ [] → rest.length < source.length

def WindowBatch.make (source : List String) : WindowBatch source := {
  front := source.take 32, rest := source.drop 32
  complete := List.take_append_drop 32 source
  bounded := by simp only [List.length_take]; exact Nat.min_le_left _ _
  decreases := by
    intro nonempty
    have positive := List.length_pos_iff.mpr nonempty
    simp only [List.length_drop]
    omega }

theorem WindowBatch.existing (batch : WindowBatch source) (window : String)
    (present : window ∈ batch.front) : window ∈ source := by
  rw [← batch.complete]
  exact List.mem_append_left _ present

/-- Presentation keeps the configured retrieval policy throughout the
admitted graph, instead of reverting to a purely numerical order after hybrid
retrieval. Admission anchors do not override the current-question fusion.
No owner is excluded by this order; nominations are computed separately. -/
def presentationRanking (mode : String) (count : Nat) (semantic lexical : List Nat) : List Nat :=
  let combined := if mode == "lexical" then lexical
    else if mode == "semantic" then semantic
    else SearchRank.fused [semantic, lexical]
  (combined ++ semantic ++ lexical ++ List.range count).eraseDups.filter (· < count)

def presentationRankingIndexed (mode : String) (count : Nat) (semantic lexical : List Nat) : List Nat :=
  let combined := if mode == "lexical" then lexical
    else if mode == "semantic" then semantic
    else SearchRank.fused [semantic, lexical]
  (hashDistinct (combined ++ semantic ++ lexical ++ List.range count)).filter (· < count)

@[csimp] theorem presentation_ranking_compiled : presentationRanking = presentationRankingIndexed := by
  funext mode count semantic lexical
  simp only [presentationRanking, presentationRankingIndexed, HashDistinct.reference]

theorem presentation_ranking_original (mode : String) (count : Nat)
    (semantic lexical : List Nat) (index : Nat)
    (present : index ∈ presentationRanking mode count semantic lexical) : index < count := by
  exact of_decide_eq_true (List.mem_filter.mp present).2

theorem presentation_ranking_complete (mode : String) (count : Nat)
    (semantic lexical : List Nat) (index : Nat) (valid : index < count) :
    index ∈ presentationRanking mode count semantic lexical := by
  apply List.mem_filter.mpr
  refine ⟨List.mem_eraseDups.mpr ?_, by simpa using valid⟩
  exact List.mem_append_right _ (List.mem_range.mpr valid)

theorem presentation_ranking_no_duplicates (mode : String) (count : Nat)
    (semantic lexical : List Nat) :
    (presentationRanking mode count semantic lexical).Nodup :=
  List.filter_sublist.nodup (SearchRank.deduplicated_nodup _)

structure WindowScore where
  best : Option Float := none
  positions : List (Float × Nat) := []

def WindowScore.add (state : WindowScore) (score : Float) (position : Nat) : WindowScore := {
  best := some (state.best.map (fun previous => if score > previous then score else previous) |>.getD score)
  positions := ((score, position) :: state.positions).mergeSort SearchRank.scoreOrder |>.take 16 }

structure ScoringWindow where
  document : Nat
  position : Nat
  vector : BlockScore.Input

/-- Scoring transport is independent of the encoder's 32-segment inference
batch. Every window keeps its original document/position, and NumPy still
evaluates each original dot product independently in the same order. -/
def scoreWindows (options : Options) (child : Encoder) (queries : Json)
    (batch : Array ScoringWindow) (totals : Array WindowScore) : IO (Array WindowScore) := do
  unless !batch.isEmpty && batch.size ≤ 256 do throw (IO.userError "invalid numerical scoring batch")
  let started ← IO.monoMsNow
  let response ← measuredExchange options child (Json.mkObj [
    ("queries", queries), ("blockRows", toJson (batch.map (·.vector)))]) "score"
  let coverages ← IO.ofExcept (response.getObjValAs? (Array (Option String)) "coverage")
  unless coverages.size == batch.size do throw (IO.userError "block coverage count mismatch")
  for metadata in coverages do
    if let some metadata := metadata then
      let coverage ← IO.ofExcept (Json.parse metadata >>= fromJson? (α := EncodingCoverage))
      unless coverage.valid do throw (IO.userError "invalid blocked projection coverage")
      observeInput options false coverage
  if let some sink := options.metrics then
    let reads ← IO.ofExcept (response.getObjValAs? Nat "sourceReadMs")
    let hits ← IO.ofExcept (response.getObjValAs? Nat "blockHits")
    let misses ← IO.ofExcept (response.getObjValAs? Nat "blockMisses")
    let retained ← IO.ofExcept (response.getObjValAs? Nat "retainedBytes")
    let durable := coverages.toList.countP Option.isSome
    sink.state.modify fun state => {state with
      blockReadMsWithinScore := state.blockReadMsWithinScore + reads
      blockHits := state.blockHits + hits
      blockMisses := state.blockMisses + misses
      blockRetainedBytes := retained
      matrixRows := state.matrixRows + durable
      source := {state.source with hit := state.source.hit + durable}}
  let scores ← IO.ofExcept (response.getObjValAs? (Array Json) "scores")
  unless scores.size == batch.size do throw (IO.userError "indexed similarity count mismatch")
  if let some sink := options.metrics then
    let elapsed := (← IO.monoMsNow) - started
    sink.state.modify fun state => {state with
      scoreMs := state.scoreMs + elapsed, scoredWindows := state.scoredWindows + batch.size}
  let mut totals := totals
  for (value, window) in scores.toList.zip batch.toList do
    let score ← IO.ofExcept (number value)
    unless window.document < totals.size do throw (IO.userError "numerical score names a foreign document")
    totals := totals.modify window.document (·.add score window.position)
  pure totals

def indexedEvidenceWindows (evidence : List (Nat × List Nat))
    (ranked : List Nat) : List SemanticMatcher.WindowChoice :=
  ranked.filterMap fun index =>
    (evidence.find? (·.1 == index)).map fun row => ⟨row.1, row.2⟩

def indexedEvidenceWindowsUsing (evidence : List (Nat × List Nat))
    (ranked : List Nat) : List SemanticMatcher.WindowChoice :=
  let directory := FirstIndex.make Prod.fst evidence
  ranked.filterMap fun index => (directory.read index).map fun row => ⟨row.1, row.2⟩

@[csimp] theorem indexed_evidence_windows_compiled : indexedEvidenceWindows = indexedEvidenceWindowsUsing := by
  funext evidence ranked
  simp only [indexedEvidenceWindows, indexedEvidenceWindowsUsing, FirstIndex.read_exact]

/-- Candidate payloads never cross this protocol. Numerical scoring uses
bounded batches of pre-indexed vectors and the identical selection kernel.
Missing vectors fail explicitly; the search cannot silently omit a candidate. -/
def handleIndexedUsing (options : Options) (child : Option Encoder) (query : String)
    (request : Json) (repair : RepairWindows := unavailableRepair) : IO Json := do
  let options := {options with directories := some (← DirectoryReads.new), matrices := some (← IO.mkRef {})}
  let candidates ← IO.ofExcept (request.getObjValAs? (Array Json) "documents")
  let lexical ← IO.ofExcept (request.getObjValAs? (List Nat) "lexical")
  let anchors ← IO.ofExcept (request.getObjValAs? (List Nat) "anchors")
  let mut scored : List (Float × Nat) := []
  let mut evidence : List (Nat × List Nat) := []
  if let some child := child then
    -- Questions belong to the user, independently of every shared source DB.
    let prepared ← IO.mkRef ({} : Std.HashMap String Options)
    let resolve := fun candidate => do
      let key := candidate.getObjValD "cache" |>.compress
      if let some known := (← prepared.get)[key]? then return known
      let known ← cacheOptions options candidate
      prepared.modify (·.insert key known)
      pure known
    let queryOptions ← queryOptions options
    let queryVectors ← IO.mkRef (none : Option Json)
    let queries := do
      match ← queryVectors.get with
      | some queries => pure queries
      | none => do
          let started ← IO.monoMsNow
          store queryOptions child [query] true
          let queries ← vectors queryOptions query
          if let some sink := options.metrics then
            let elapsed := (← IO.monoMsNow) - started
            sink.state.modify fun state => {state with queryMs := state.queryMs + elapsed}
          queryVectors.set (some queries)
          pure queries
    let mut totals := Array.replicate candidates.size ({} : WindowScore)
    let mut pending : Array ScoringWindow := #[]
    for (candidate, index) in candidates.toList.zipIdx do
      let documentOptions ← resolve candidate
      let windows ← IO.ofExcept (candidate.getObjValAs? (List String) "windows")
      if windows.isEmpty then throw (IO.userError "empty indexed window directory")
      let mut remaining := windows
      while !remaining.isEmpty do
        let offset := windows.length - remaining.length
        let batch := WindowBatch.make remaining
        remaining := batch.rest
        let candidateVectors ← repairBatch documentOptions child index offset batch.front repair
        for (vector, localIndex) in candidateVectors.toList.zipIdx do
          pending := pending.push ⟨index, offset + localIndex, vector⟩
          if pending.size == 256 then
            -- A cold source is rejected before this batch starts inference.
            totals ← scoreWindows options child (← queries) pending totals
            pending := #[]
    if !pending.isEmpty then totals ← scoreWindows options child (← queries) pending totals
    for (result, index) in totals.toList.zipIdx do
      let some score := result.best | throw (IO.userError "indexed candidate has no numerical score")
      scored := (score, index) :: scored
      evidence := (index, result.positions.map Prod.snd) :: evidence
  let selected ← selection options candidates lexical anchors scored.reverse
  let related ← IO.ofExcept (selected.getObjValAs? (List Nat) "related")
  -- All cached similarities were already computed. Keep their complete order
  -- for graph-neighbor budgeting; this does not change relatedness admission.
  let ranked := presentationRanking options.mode candidates.size
    ((scored.reverse.mergeSort SearchRank.scoreOrder).map (·.2)) lexical
  let windows := indexedEvidenceWindows evidence ranked
  trace options (Json.mkObj [("evidence_windows", toJson windows)])
  pure (Json.mkObj [("related", toJson related), ("ranked", toJson ranked), ("evidence", toJson windows)])

def handleIndexed (options : Options) (child : Option Encoder) (query : String)
    (request : Json) (repair : RepairWindows := unavailableRepair) : IO Json := do
  let receipt := (request.getObjValAs? String "receipt").toOption.filter Receipt.validId
  if receipt.isNone then return ← handleIndexedUsing options child query request repair
  let documents ← IO.ofExcept (request.getObjValAs? (Array Json) "documents")
  let windows ← documents.toList.mapM fun document =>
    IO.ofExcept (document.getObjValAs? (List String) "windows")
  let sink : MetricsSink := {
    receipt, stage := s!"numerical-{← IO.Process.getPID}-{← IO.monoNanosNow}"
    started := ← IO.monoMsNow, state := ← IO.mkRef {}
    corpus := Json.mkObj [("documents", toJson documents.size),
      ("purpose", (request.getObjValAs? String "purpose").toOption.map toJson |>.getD Json.null),
      ("numerical", toJson child.isSome),
      ("windowReferences", toJson (windows.map List.length).sum),
      ("durableDocuments", toJson (documents.filter (fun document =>
        document.getObjValD "cache" != Json.null)).size)] }
  sink.flush "running"
  try
    let result ← handleIndexedUsing {options with metrics := some sink} child query request repair
    sink.flush "completed"
    pure result
  catch error =>
    sink.flush "failed"
    throw error

def handle (options : Options) (child : Option Encoder)
    (previous : IO.Ref (Option RetainedCorpus)) (request : Json)
    (repair : RepairWindows := unavailableRepair) : IO (Option Json) := do
  if let .ok index := request.getObjValAs? (Array Json) "index_windows" then
    if let some child := child then
      let options ← cacheOptions options request
        (some ((request.getObjValAs? DB.Sidecar.Storage "cache_storage").toOption.getD .database))
      let texts ← IO.ofExcept (index.toList.mapM (·.getObjValAs? String "text"))
      storeWindows options child texts
    let ids ← IO.ofExcept (index.toList.mapM (·.getObjValAs? String "id"))
    return some (Json.mkObj [("indexed", toJson ids)])
  if let .ok index := request.getObjValAs? (Array Json) "index" then
    if let some child := child then
      let options ← cacheOptions options request
        (some ((request.getObjValAs? DB.Sidecar.Storage "cache_storage").toOption.getD .database))
      let texts ← IO.ofExcept (index.toList.mapM (·.getObjValAs? String "text"))
      store options child texts
    let ids ← IO.ofExcept (index.toList.mapM (·.getObjValAs? String "id"))
    return some (Json.mkObj [("indexed", toJson ids)])
  let query ← IO.ofExcept ((request.getObjValD "query").getObjValAs? String "text")
  if (request.getObjVal? "documents").isOk then
    return some (← handleIndexed options child query request repair)
  let candidates ← IO.ofExcept (request.getObjValAs? (Array Json) "candidates")
  let texts ← IO.ofExcept (candidates.toList.mapM (·.getObjValAs? String "text"))
  let corpus := match ← previous.get with
    | some retained => retained.corpus.revise texts
    | none => SearchRank.Corpus.build texts
  previous.set (retainCorpus texts corpus)
  let lexical := corpus.rank query
  let anchors := corpus.rank query true
  let mut scored : List (Float × Nat) := []
  if let some child := child then
    let queryOptions ← queryOptions options
    store options child texts
    store queryOptions child [query]
    let response ← exchange child (Json.mkObj [("queries", ← vectors queryOptions query),
      ("candidates", .arr (← texts.toArray.mapM (vectors options)))])
    let scores ← IO.ofExcept (response.getObjValAs? (Array Json) "scores")
    if scores.size != candidates.size then throw (IO.userError "similarity count mismatch")
    scored ← IO.ofExcept (scores.toList.zipIdx.mapM fun (value, index) => do pure (← number value, index))
  let selected ← selection options candidates lexical anchors scored
  let related ← IO.ofExcept (selected.getObjValAs? (List Nat) "related")
  let ranked := presentationRanking options.mode candidates.size
    ((scored.mergeSort SearchRank.scoreOrder).map (·.2)) lexical
  pure (some (Json.mkObj [("related", toJson related), ("ranked", toJson ranked)]))

def run (args : List String) : IO UInt32 := IO.FS.withTempDir fun scratch => do
  let scratch ← IO.FS.realPath scratch
  let layout := MiniLM.layout (← Paths.installRoot)
  let options ← IO.ofExcept (parse { cache := scratch, models := layout.models } args)
  let child ← if options.mode == "lexical" then pure none else some <$> encoder options
  let previous ← IO.mkRef (none : Option RetainedCorpus)
  try
    let stdin ← IO.getStdin
    let stdout ← IO.getStdout
    let repair : RepairWindows := fun document windows => do
      stdout.putStrLn (Json.mkObj [("need_windows", Json.mkObj [
        ("document", toJson document), ("indices", toJson (windows.map Prod.fst))])]).compress
      stdout.flush
      let response ← IO.ofExcept (Json.parse (← stdin.getLine))
      IO.ofExcept (response.getObjValAs? (List String) "windows")
    repeat
      let line ← stdin.getLine
      if line.isEmpty then break
      try
        let request ← IO.ofExcept (Json.parse line)
        if let some result ← handle options child previous request repair then
          stdout.putStrLn result.compress
          stdout.flush
      catch error =>
        IO.eprintln s!"Eggshell search: {error}"
        stdout.putStrLn (Json.mkObj [("error", .str (toString error))]).compress
        stdout.flush
    pure 0
  finally
    if let some child := child then
      stopEncoder child

end Eggshell.SearchProvider
