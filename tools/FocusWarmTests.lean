import Eggshell.Install

open Lean Eggshell Plugin

private def check (accepted : Bool) (message : String) : IO Unit :=
  unless accepted do throw (IO.userError message)

private def coverage (text : String) : SearchProvider.EncodingCoverage :=
  let visible := (text.toList.filter (!·.isWhitespace)).length
  {characters := text.length, visibleCharacters := visible
   tokenizerMappedCharacters := visible, embeddedCharacters := visible
   sourceTokens := if text.isEmpty then 0 else 1, segments := 1
   contextTokens := 128, overlapTokens := 16, completeTokenOffsets := true}

private def save (snapshot : DB.PageMap.Snapshot) (options : SearchProvider.Options)
    (windows : List Warm.Window) : IO Unit := do
  for window in windows do
    let original ← Persistence.Store.readSearchWindow snapshot window.document window.index
    let text := (original.drop window.start).copy
    check (Persistence.Store.windowKey text == window.key) "planned input differs from original suffix"
    SearchProvider.saveVector options text (.arr #[.arr #[toJson (1 : Nat)]]) (coverage text)

private def records (options : SearchProvider.Options) : IO (List (String × FileSystem.ReadVersion)) := do
  let paths := ((← (options.cache / "vectors").readDir).toList.filter (·.fileName.endsWith ".json"))
    |>.mergeSort (fun a b => a.fileName ≤ b.fileName)
  paths.mapM fun path => do
    pure (path.fileName, ← FileSystem.readVersion (← FileSystem.openRead path.path.toString))

private def requestWindow : IO UInt32 := do
  let _ ← (← IO.getStdin).getLine
  let output ← IO.getStdout
  output.putStrLn "{\"need_windows\":{\"document\":0,\"indices\":[0]}}"
  output.flush
  let _ ← (← IO.getStdin).getLine
  pure 0

private def scenario (temporary : System.FilePath) : IO Unit := do
  let root ← IO.FS.realPath temporary
  let database := root / "source.egg"
  let command := ["/unavailable-provider", "search-provider", "--model", "synthetic-focus-tests"]
  let work := String.ofList (List.replicate 700 '調')
  let pending : PendingTurn := {
    sessionId := "focus-warm", turnId := "initial", cwd := root.toString
    prompt := work, profile := "work", semanticMatcher := some command
    read := [database.toString], write := some database.toString, handoffChars := 24000
    projection := .automatic
    finalMessage := some ("Independent observed condition 日本語🐣. " ++
      String.ofList (List.replicate 900 '結')) }
  let _ ← promote pending database
  let snapshot ← DB.PageMap.pin database
  let head ← IO.FS.readFile (database / "head")
  let options ← Warm.options snapshot command
  let (discovery, focus) ← Warm.planWindows snapshot
  check (!discovery.isEmpty && discovery.length == focus.length &&
      (discovery.zip focus).all (fun (a, b) =>
        a.document.owner == b.document.owner && a.document.work == b.document.work &&
        a.document.windows == b.document.windows && a.index == b.index) &&
      focus.any (·.key == Persistence.Store.windowKey "") &&
      focus.any (·.start == 0)) "focus plan lost original coordinates, empty prefix or unchanged suffix"
  let cold ← Warm.inspect snapshot options
  check (cold.coverage.valid == 0 && cold.needed.length == cold.coverage.windows &&
      cold.coverage.windows > cold.coverage.discovery.windows)
    "cold coverage did not include the unique focus inputs"
  let _ ← DB.Sidecar.prepare (DB.Sidecar.Owner.ofSnapshot snapshot) .database
  save snapshot options discovery
  let originals ← records options
  let sourceOnly ← Warm.inspect snapshot options
  check (sourceOnly.coverage.discovery.missing == 0 && sourceOnly.coverage.discovery.invalid == 0 &&
      sourceOnly.coverage.discovery.valid == sourceOnly.coverage.discovery.windows &&
      sourceOnly.coverage.focus.missing > 0 && sourceOnly.needed.length == sourceOnly.coverage.focus.missing)
    "original-only warm incorrectly certified complete focus coverage"
  save snapshot options sourceOnly.needed
  let full ← Warm.inspect snapshot options
  let allRecords ← records options
  check (full.needed.isEmpty && full.coverage.valid == full.coverage.windows &&
      full.coverage.focus.valid == full.coverage.focus.windows &&
      allRecords.length == full.coverage.windows && originals.all allRecords.contains)
    "focus difference duplicated an input or rewrote an original vector"
  let some suffix := sourceOnly.needed.head? | throw (IO.userError "missing derived focus input")
  let path := (SearchProvider.vectorPaths options
    (SearchProvider.windowCacheKey options.model suffix.key)).head!
  IO.FS.writeFile path "damaged focus vector"
  let damaged ← Warm.inspect snapshot options
  check (damaged.coverage.invalid == 1 && damaged.coverage.discovery.invalid == 0 &&
      damaged.coverage.focus.invalid == 1 && damaged.needed.length == 1)
    "focus corruption was hidden by original discovery coverage"
  save snapshot options damaged.needed
  let repairedRecords ← records options
  let target : IndexTarget := {owner := DB.Sidecar.Owner.ofSnapshot snapshot, command}
  let repeated ← Warm.runTarget snapshot target
  let stamp ← Warm.checkpoint target snapshot
  check (stamp.sameSources stamp &&
      !stamp.sameSources {stamp with focusContract := "different-view-implementation"} &&
      !(← Warm.required target snapshot)) "warm scheduling ignored the actual focus implementation"
  check (repeated.requested == 0 && repeated.batches == 0 && (← records options) == repairedRecords)
    "complete focus warm started the unavailable provider or rewrote valid records"
  -- Durable focus may inspect the few Work-prefix slots to derive their keys,
  -- but must never answer the provider's subsequent source-repair request.
  let documents ← Persistence.Store.searchDocuments snapshot
  let prefixReads ← IO.mkRef 0
  let outcomeReads ← IO.mkRef 0
  let reader ← Persistence.Store.NodeReader.new snapshot
  let result ← focusIndexedEvidence [(← IO.appPath).toString, "request-window"] "condition" documents
    (fun document => do
      let work ← reader.read document.work
      pure ((Matcher.atomText? work).getD ""))
    (fun document index => do
      prefixReads.modify (· + 1)
      let text ← Persistence.Store.readSearchWindow snapshot document index.val
      if index.val * 384 >= work.length + 1 then outcomeReads.modify (· + 1)
      pure text)
  let expectedReads := focus.countP (·.start > 0)
  check (result.isNone && (← prefixReads.get) == expectedReads && (← outcomeReads.get) == 0)
    "durable source focus repaired an input inside the foreground hook"
  check ((← IO.FS.readFile (database / "head")) == head)
    "focus warm changed original graph publication"

def main (arguments : List String) : IO UInt32 := do
  if arguments == ["request-window"] then return ← requestWindow
  IO.FS.withTempDir scenario
  IO.println (Json.mkObj [("passed", toJson true), ("syntheticVectors", toJson true),
    ("generationModelCalls", toJson (0 : Nat)), ("productionAdoption", toJson false)]).compress
  pure 0
