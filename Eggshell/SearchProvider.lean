module

public import Eggshell.SearchRank
public import Eggshell.MiniLM
public import Eggshell.Sha256
public import Eggshell.Persistence
public import Eggshell.SemanticMatcher
public import Lean.Data.Json.FromToJson

@[expose] public section

namespace Eggshell.SearchProvider
open Lean

structure Options where
  cache : System.FilePath
  models : System.FilePath
  model : String := MiniLM.model
  mode : String := "hybrid"
  topK : Nat := 8
  anchorK : Nat := 2
  threshold : Float := 0.38
  trace : Option System.FilePath := none
  lane : SemanticMatcher.Lane := .search

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
def cacheOptions (options : Options) (request : Json) : Except String Options := do
  match (request.getObjVal? "cache").toOption with
  | none | some .null => pure options
  | some (.str path) =>
      let path := System.FilePath.mk path
      unless path.isAbsolute do throw "DB vector cache must be an absolute path"
      pure {options with cache := path}
  | _ => throw "invalid DB vector cache locator"

abbrev Encoder := IO.Process.Child { stdin := .piped, stdout := .piped, stderr := .inherit }

def spawnEncoder (options : Options) (python lease : System.FilePath)
    (lane : String) : IO Encoder :=
  IO.Process.spawn {
    cmd := python.toString
    args := #["-c", MiniLM.embeddingSource, options.model, options.models.toString,
      "4", lease.toString, lane]
    stdin := .piped, stdout := .piped, stderr := .inherit }

def encoder (options : Options) : IO Encoder := do
  let layout := MiniLM.layout (← Paths.installRoot) options.cache
  let some python ← MiniLM.runtimePython? layout | throw (IO.userError "MiniLM runtime is not installed")
  let reservation ← SemanticMatcher.lanePath options.lane
  let lease := reservation.withFileName ("model-" ++ reservation.fileName.getD "lane.guard")
  Persistence.rejectSymlinkAncestors lease
  let _ ← IO.FS.Handle.mk lease .append
  Persistence.privateFile lease
  -- The numerical process owns this second lease throughout model lifetime.
  -- It survives a killed caller until that process actually exits.
  let lane : String := match options.lane with | .index => "index" | .search => "search"
  spawnEncoder options python lease lane

def exchange (child : Encoder) (input : Json) : IO Json := do
  child.stdin.putStrLn input.compress
  child.stdin.flush
  let result ← IO.ofExcept (Json.parse (← child.stdout.getLine))
  if let .ok error := result.getObjValAs? String "error" then throw (IO.userError error)
  pure result

/-- Persisted vectors carry the exact model and source bytes. The hash is only
    a locator; a collision or damaged record cannot authorize different text. -/
structure CachedVector where
  model : String
  text : String
  vector : Json
  deriving ToJson, FromJson

structure CheckedVector (cached : CachedVector) where
  values : Array Json
  exact : cached.vector = .arr values
  window : cached.text.length ≤ 512
  dimensions : 0 < values.size ∧ values.size ≤ 4096
  finite : values.all (fun value => (number value).isOk) = true

def CheckedVector.make? (cached : CachedVector) : Option (CheckedVector cached) :=
  match shape : cached.vector with
  | .arr values =>
      if valid : cached.text.length ≤ 512 ∧ 0 < values.size ∧ values.size ≤ 4096 ∧
          values.all (fun value => (number value).isOk) = true then
        some ⟨values, shape, valid.1, ⟨valid.2.1, valid.2.2.1⟩, valid.2.2.2⟩ else none
  | _ => none

theorem CheckedVector.source_shape (checked : CheckedVector cached) :
    cached.vector = .arr checked.values := checked.exact

def cacheMatches (model text : String) (cached : CachedVector) : Bool :=
  decide (cached.model = model ∧ cached.text = text)

theorem accepted_cache_identity (model text : String) (cached : CachedVector)
    (h : cacheMatches model text cached = true) : cached.model = model ∧ cached.text = text := by
  exact of_decide_eq_true h

theorem changed_cache_text_rejected (model text : String) (cached : CachedVector)
    (h : cached.text ≠ text) : cacheMatches model text cached = false := by
  simp [cacheMatches, h]

theorem changed_cache_model_rejected (model text : String) (cached : CachedVector)
    (h : cached.model ≠ model) : cacheMatches model text cached = false := by
  simp [cacheMatches, h]

def windowCacheKey (model window : String) : String :=
  Sha256.hex model.toUTF8 ++ "-" ++ window

def cacheKey (model text : String) : String :=
  windowCacheKey model (Persistence.Store.windowKey text)

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

def readVector (options : Options) (text : String) : IO (Option Json) := do
  let path := options.cache / "vectors" / (cacheKey options.model text ++ ".json")
  if !(← path.pathExists) then return none
  try
    let cached ← loadVector path
    if cacheMatches options.model text cached then return some cached.vector
    throw (IO.userError "embedding cache identity mismatch")
  catch _ => return none

def saveVector (options : Options) (text : String) (vector : Json) : IO Unit := do
  let cached : CachedVector := {model := options.model, text, vector}
  let some _ := CheckedVector.make? cached | throw (IO.userError "invalid numerical window for indexing")
  let encoded := (toJson cached).compress
  unless encoded.utf8ByteSize ≤ 1048576 do throw (IO.userError "oversized numerical window for indexing")
  let root := options.cache / "vectors"
  Persistence.rejectSymlinkAncestors root
  Persistence.privateDirectory root
  let path := root / (cacheKey options.model text ++ ".json")
  FileSystem.atomicBytes path encoded.toUTF8

def store (options : Options) (child : Encoder) (texts : List String) : IO Unit := do
  let parts := (texts.flatMap SearchRank.windows).eraseDups
  let mut missing := []
  for part in parts do if (← readVector options part).isNone then missing := missing ++ [part]
  if missing.isEmpty then return
  let response ← exchange child (Json.mkObj [("texts", toJson missing)])
  let vectors ← IO.ofExcept (response.getObjValAs? (Array Json) "vectors")
  if vectors.size != missing.length then throw (IO.userError "embedding count mismatch")
  for (text, vector) in missing.zip vectors.toList do saveVector options text vector

def vectors (options : Options) (text : String) : IO Json := do
  let values ← (SearchRank.windows text).mapM fun part => do
    let some value ← readVector options part | throw (IO.userError "missing indexed embedding")
    pure value
  pure (.arr values.toArray)

/-- Window hashes only nominate numerical hints. A hint cannot establish Work
identity or completion. Original graph owners are hydrated and checked by the
requesting pinned reader after selection. No source body is opened here. -/
def indexedVectors (options : Options) (windows : List String) : IO Json := do
  let values ← windows.mapM fun window => do
    unless window.length == 64 && window.toList.all (fun c =>
        ('0' ≤ c && c ≤ '9') || ('a' ≤ c && c ≤ 'f')) do
      throw (IO.userError "invalid indexed vector locator")
    let path := options.cache / "vectors" / (windowCacheKey options.model window ++ ".json")
    let cached ← loadVector path
    unless cached.model == options.model && Persistence.Store.windowKey cached.text == window do
      throw (IO.userError "indexed embedding locator mismatch")
    pure cached.vector
  pure (.arr values.toArray)

abbrev RepairWindows := Nat → List (Nat × String) → IO (List String)

def unavailableRepair : RepairWindows := fun _ _ => throw (IO.userError "missing indexed embedding")

/-- Only missing windows are re-encoded. Exact locator verification precedes
inference and acknowledgement; a corrupted/missing hint cannot omit evidence
or substitute another source. The batch makes one repair attempt. -/
def repairBatch (options : Options) (child : Encoder) (document offset : Nat)
    (windows : List String) (repair : RepairWindows) : IO (Array Json) := do
  let mut missing : List (Nat × String) := []
  let mut retained : Array (Option Json) := #[]
  for (window, index) in windows.zipIdx do
    let available ← try some <$> indexedVectors options [window] catch _ => pure none
    retained := retained.push available
    if available.isNone then missing := (offset + index, window) :: missing
  missing := missing.reverse
  unless missing.isEmpty do
    let texts ← repair document missing
    unless texts.length == missing.length do throw (IO.userError "numerical window repair count mismatch")
    for (text, (_, digest)) in texts.zip missing do
      unless text.length ≤ 512 && Persistence.Store.windowKey text == digest do
        throw (IO.userError "numerical window repair source mismatch")
    store options child texts
  -- Each valid numerical window is already checked and read. Hold only this
  -- bounded batch; reread repaired misses, never all successful cache hits.
  windows.zipIdx.toArray.mapM fun (window, index) =>
    match retained[index]?.getD none with
    | some vector => pure vector
    | none => indexedVectors options [window]

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

/-- Candidate payloads never cross this protocol. Numerical scoring uses
bounded batches of pre-indexed vectors and the identical selection kernel.
Missing vectors fail explicitly; the search cannot silently omit a candidate. -/
def handleIndexed (options : Options) (child : Option Encoder) (query : String)
    (request : Json) (repair : RepairWindows := unavailableRepair) : IO Json := do
  let candidates ← IO.ofExcept (request.getObjValAs? (Array Json) "documents")
  let lexical ← IO.ofExcept (request.getObjValAs? (List Nat) "lexical")
  let anchors ← IO.ofExcept (request.getObjValAs? (List Nat) "anchors")
  let mut scored : List (Float × Nat) := []
  let mut evidence : List (Nat × List Nat) := []
  if let some child := child then
    -- One query vector serves the complete federated ranking. Keep it with
    -- the first durable source instead of a chat-specific vector directory.
    let queryCache := candidates.toList.find? fun candidate =>
      (candidate.getObjValAs? String "cache").isOk
    let queryOptions ← IO.ofExcept (cacheOptions options (queryCache.getD Json.null))
    store queryOptions child [query]
    let queries ← vectors queryOptions query
    for (candidate, index) in candidates.toList.zipIdx do
      let documentOptions ← IO.ofExcept (cacheOptions options candidate)
      let windows ← IO.ofExcept (candidate.getObjValAs? (List String) "windows")
      if windows.isEmpty then throw (IO.userError "empty indexed window directory")
      let mut remaining := windows
      let mut best : Option Float := none
      let mut positions : List (Float × Nat) := []
      while !remaining.isEmpty do
        let offset := windows.length - remaining.length
        let batch := WindowBatch.make remaining
        remaining := batch.rest
        let vectors ← repairBatch documentOptions child index offset batch.front repair
        let response ← exchange child (Json.mkObj [("queries", queries), ("candidates", .arr vectors)])
        let scores ← IO.ofExcept (response.getObjValAs? (Array Json) "scores")
        unless scores.size == batch.front.length do throw (IO.userError "indexed similarity count mismatch")
        for (value, localIndex) in scores.toList.zipIdx do
          let score ← IO.ofExcept (number value)
          -- Bounded ranked positions are transport hints. The document's
          -- maximum score and the existing relatedness selection stay exact.
          positions := ((score, offset + localIndex) :: positions).mergeSort SearchRank.scoreOrder |>.take 16
          best := some (best.map (fun previous => if score > previous then score else previous) |>.getD score)
      let some score := best | throw (IO.userError "indexed candidate has no numerical score")
      scored := (score, index) :: scored
      evidence := (index, positions.map Prod.snd) :: evidence
  let selected ← selection options candidates lexical anchors scored.reverse
  let related ← IO.ofExcept (selected.getObjValAs? (List Nat) "related")
  -- All cached similarities were already computed. Keep their complete order
  -- for graph-neighbor budgeting; this does not change relatedness admission.
  let ranked := presentationRanking options.mode candidates.size
    ((scored.reverse.mergeSort SearchRank.scoreOrder).map (·.2)) lexical
  let windows := ranked.filterMap fun index =>
    (evidence.find? (·.1 == index)).map fun row =>
      (⟨row.1, row.2⟩ : SemanticMatcher.WindowChoice)
  trace options (Json.mkObj [("evidence_windows", toJson windows)])
  pure (Json.mkObj [("related", toJson related), ("ranked", toJson ranked), ("evidence", toJson windows)])

def handle (options : Options) (child : Option Encoder)
    (previous : IO.Ref (Option RetainedCorpus)) (request : Json)
    (repair : RepairWindows := unavailableRepair) : IO (Option Json) := do
  if let .ok index := request.getObjValAs? (Array Json) "index" then
    if let some child := child then
      let options ← IO.ofExcept (cacheOptions options request)
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
    store options child (texts ++ [query])
    let response ← exchange child (Json.mkObj [("queries", ← vectors options query),
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
  let layout := MiniLM.layout (← Paths.installRoot) (← Paths.dataRoot)
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
      child.kill
      let _ ← child.wait
      pure ()

end Eggshell.SearchProvider
