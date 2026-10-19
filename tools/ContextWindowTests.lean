import Eggshell.Install

open Lean Eggshell

private def require (ok : Bool) (message : String) : IO Unit :=
  unless ok do throw (IO.userError message)

private def checks : IO Unit := IO.FS.withTempDir fun root => do
  let root ← IO.FS.realPath root
  let options : SearchProvider.Options := {cache := root, models := root / "unused-models"}
  let text := "保存した本文"
  let coverage : SearchProvider.EncodingCoverage := {
    characters := text.length, visibleCharacters := text.length
    tokenizerMappedCharacters := text.length, embeddedCharacters := text.length
    sourceTokens := 6, segments := 2, contextTokens := 128, overlapTokens := 16
    completeTokenOffsets := true }
  let group := toJson (#[#[1.0, 0.0], #[0.0, 1.0]] : Array (Array Float))
  require ((← SearchProvider.readVector options text).isNone) "An absent vector was warm"
  SearchProvider.saveVector options text group coverage
  let path := root / "vectors" / (SearchProvider.cacheKey options.model text ++ ".json")
  let cached ← SearchProvider.loadVector path
  require ((SearchProvider.CheckedVector.make? cached).isSome) "A valid group was rejected"
  require ((← SearchProvider.vectors options text) == toJson cached.vector) "Query groups were nested or omitted"
  require ((← SearchProvider.indexedVectors options [cached.window]) == toJson cached.vector)
    "Original window groups were nested or omitted"
  let oldKey := Sha256.hex options.model.toUTF8 ++ "-" ++ cached.window
  require (oldKey != SearchProvider.cacheKey options.model text) "The original cache key was reused"
  for bad in [
      {cached with contract := Sha256.hex "different-policy".toUTF8},
      {cached with vector := #[]},
      {cached with coverage := {coverage with segments := 1}},
      {cached with coverage := {coverage with completeTokenOffsets := false}},
      {cached with coverage := {coverage with embeddedCharacters := text.length - 1}},
      {cached with coverage := {coverage with visibleCharacters := 0}},
      {cached with vector := #["ffffffffffffffff", "0000000000000000"]}] do
    require ((SearchProvider.CheckedVector.make? bad).isNone) "An invalid group was accepted"
  let legacy := Json.mkObj [("model", toJson cached.model), ("window", toJson cached.window),
    ("contract", toJson cached.contract), ("coverage", toJson coverage), ("vector", .str "000000000000f03f")]
  require ((fromJson? legacy : Except String SearchProvider.CachedVector).toOption.isNone)
    "A legacy one-vector string was decoded as a complete group"
  let rejected ← try
      SearchProvider.saveVector options text group {coverage with characters := text.length + 1}
      pure false
    catch _ => pure true
  require rejected "Coverage for another text was saved"
  let state ← IO.mkRef ({} : SearchProvider.IndexedMetrics)
  let sink : SearchProvider.MetricsSink := {
    receipt := none, stage := "context-window-control"
    started := 0, corpus := Json.null, state}
  let _ ← SearchProvider.indexedVectors {options with metrics := some sink} [cached.window]
  let totals := (← state.get).sourceInput
  require (totals.windows == 1 && totals.vectors == 2 && totals.embeddedCharacters == text.length)
    "Receipt totals confuse windows, vectors or character positions"
  let _ ← SearchProvider.vectors {options with metrics := some sink} text
  require ((← state.get).queryInput.vectors == 2) "Query receipt omitted segment counts"
  let checkpoint : Warm.Checkpoint := {
    database := "fixture", provider := "fixture", revision := 1
    roots := 1, candidates := 1, encoderContract := SearchProvider.encoderContract}
  require (checkpoint.sameSources checkpoint &&
      !checkpoint.sameSources {checkpoint with encoderContract := "different"})
    "A stale warm checkpoint hid a changed encoder contract"
  IO.println "context window: grouped IO, query/source flattening, changed contract, 7 invalid records, source binding and receipt counts passed"

private def prepare (directory : System.FilePath) : IO Json := do
  IO.FS.createDirAll directory
  let directory ← IO.FS.realPath directory
  let database := directory / "source.egg"
  let work := "保存済み記録の本文配送と期限管理を調査する"
  let body := String.join (List.replicate 18
    "保存済みの記録から検索して元の本文を配送する。質問の意味を優先して照合する。") ++
    "\nCONTEXT_ORIGINAL_BODY: deadline fallback delivers the saved body."
  let pending : Plugin.PendingTurn := {
    sessionId := "context-source", turnId := "context-source-turn", cwd := directory.toString
    prompt := work, profile := "work", semanticMatcher := none
    read := [database.toString], write := some database.toString
    projection := .automatic, handoffChars := 120000, finalMessage := some body }
  let _ ← Plugin.promote pending database
  let snapshot ← DB.PageMap.pin database
  let documents ← Persistence.Store.searchDocuments snapshot
  pure (Json.mkObj [("database", toJson database.toString), ("head", toJson snapshot.head),
    ("documents", toJson documents.length), ("windows", toJson (documents.map (·.windows.length)).sum),
    ("body", toJson body), ("question", toJson work)])

def main (args : List String) : IO UInt32 := do
  if args.isEmpty then
    checks
    return 0
  let command := [(← IO.appPath).withFileName "eggshell" |>.toString, "search-provider"]
  let result ← match args with
    | ["prepare", directory] => prepare (.mk directory)
    | ["inspect", database] => do
      let snapshot ← DB.PageMap.pin (.mk database)
      pure (toJson (← Warm.inspect snapshot (← Warm.options snapshot command)).coverage)
    | ["warm", database] => do
      pure (toJson (← Warm.run (← DB.PageMap.pin (.mk database)) command))
    | ["warm-private", database] => do
      pure (toJson (← Warm.run (← DB.PageMap.pin (.mk database)) command false))
    | _ => throw (IO.userError "context window: prepare DIR | inspect DB | warm DB | warm-private DB")
  IO.println result.compress
  pure 0
