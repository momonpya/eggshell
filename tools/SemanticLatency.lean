module

public import Eggshell.Install

@[expose] public section

namespace Eggshell.SemanticLatency
open Lean Plugin

def command : IO (List String) := do
  pure [(← IO.appPath).withFileName "eggshell" |>.toString, "search-provider"]

def sourceWork (index : Nat) : String :=
  s!"Inspect kernel realtime clock source {index}: monotonic scheduling and elapsed timer observations"

def sourceBody (index : Nat) : String :=
  s!"ORIGINAL_CLOCK_BODY_{index}: observed kernel timer and monotonic clock scheduling source {index}."

def prepare (directory : System.FilePath) (count : Nat) : IO Json := do
  unless count > 0 && count ≤ 4096 do throw (IO.userError "source count must be in 1..4096")
  FileSystem.privateDirectory directory
  let directory ← IO.FS.realPath directory
  let database := directory / "source.egg"
  let start ← match ← DB.PageMap.open? database with
    | none => pure 0
    | some snapshot => do
        let documents ← Persistence.Store.searchDocuments snapshot
        unless documents.length ≤ count do throw (IO.userError "saved fixture exceeds requested source count")
        let reader ← Persistence.Store.NodeReader.new snapshot
        for (document, index) in documents.zipIdx do
          let owner ← reader.outcome (← Persistence.Store.locateOutcome snapshot document.owner)
          unless owner.work == .text (sourceWork index) && owner.outcome == .text (sourceBody index) do
            throw (IO.userError "saved fixture is not the exact expected source prefix")
        IO.eprintln s!"resuming verified source prefix: {documents.length}/{count}"
        pure documents.length
  for index in (List.range count).drop start do
    let pending : PendingTurn := {
      sessionId := "latency-source", turnId := s!"source-{index}", cwd := directory.toString
      prompt := sourceWork index
      profile := "work", semanticMatcher := none, read := [database.toString], write := some database.toString
      projection := .automatic, handoffChars := 120000
      finalMessage := some (sourceBody index) }
    let _ ← promote pending database
    if index % 256 == 0 then IO.eprintln s!"saved {index + 1}/{count} latency sources"
  let snapshot ← DB.PageMap.pin database
  let head ← IO.FS.readBinFile (database / "head")
  let warmed ← Warm.run snapshot (← command)
  let documents ← Persistence.Store.searchDocuments snapshot
  let inspection ← Warm.inspect snapshot (← Warm.options snapshot (← command))
  unless inspection.needed.isEmpty && (← IO.FS.readBinFile (database / "head")) == head do
    throw (IO.userError "latency fixture is not a warm unchanged publication")
  let result := Json.mkObj [
    ("requestedSources", toJson count), ("documents", toJson documents.length),
    ("windows", toJson inspection.coverage.windows), ("warm", toJson warmed),
    ("head", toJson snapshot.head), ("headSha256", toJson (Sha256.hex head)),
    ("database", toJson database.toString), ("llmGenerationCalls", toJson (0 : Nat))]
  writeJson (directory / "fixture.json") result
  pure result

def prime (database : System.FilePath) (question : String) : IO Json := do
  let snapshot ← DB.PageMap.pin database
  let documents ← Persistence.Store.searchDocuments snapshot
  let receipt ← Receipt.fresh
  let some result ← SemanticMatcher.nominateIndexed (← command) question documents [] []
      (fun document index => Persistence.Store.readSearchWindow snapshot document index.val)
      false (some receipt) "discovery" |
    throw (IO.userError "standalone query priming did not complete")
  pure (Json.mkObj [("receipt", toJson receipt), ("order", toJson result.order.indices),
    ("documents", toJson documents.length), ("purpose", toJson "unmeasured-question-cache-setup")])

/-- Complete the same read-only matching path outside the hook's semantic
allocation, to locate censored phases. Never count this as a delivery sample. -/
def inspect (database : System.FilePath) (question : String) : IO Json := do
  let receipt ← Receipt.fresh
  let started ← IO.monoMsNow
  let selection : Config.Selection := {
    label := "latency-inspection", read := [⟨"source", database⟩], write := none
    semanticMatcher := some (← command), handoffChars := 120000
    handoffBytes := some Config.nativeHandoffBytes }
  let context : SourceContext := {
    workspace := (← IO.currentDir)
    deadline := started + 29000
    question
    receipt := some receipt }
  let result ← automaticHandoff selection question [] false (sourceContext := some context)
  pure (Json.mkObj [("receipt", toJson receipt), ("elapsedMs", toJson ((← IO.monoMsNow) - started)),
    ("purpose", toJson "standalone-phase-inspection"), ("handoff", toJson result)])

structure CacheCost where
  attempts : Nat := 0
  hits : Nat := 0
  bytes : Nat := 0
  openUs : Nat := 0
  readUs : Nat := 0
  decodeUs : Nat := 0
  checkUs : Nat := 0
  deriving ToJson

/-- Split the existing bounded cache read without starting an encoder. This
phase diagnostic is separate from the fixed native delivery measurements. -/
def cacheCost (database : System.FilePath) : IO Json := do
  let snapshot ← DB.PageMap.pin database
  let documents ← Persistence.Store.searchDocuments snapshot
  let options ← Warm.options snapshot (← command)
  let mut samples := []
  for repetition in [:3] do
    let mut cost : CacheCost := {}
    for window in documents.flatMap (·.windows) do
      let mut hit := false
      for path in SearchProvider.vectorPaths options (SearchProvider.windowCacheKey options.model window) do
        cost := {cost with attempts := cost.attempts + 1}
        let started ← IO.monoNanosNow
        let handle ← try some <$> FileSystem.openRead path.toString catch _ => pure none
        cost := {cost with openUs := cost.openUs + ((← IO.monoNanosNow) - started) / 1000}
        let some handle := handle | continue
        let started ← IO.monoNanosNow
        let before ← FileSystem.readVersion handle
        unless before.bytes ≤ 1048576 do throw (IO.userError "cache diagnostic exceeded byte budget")
        let mut bytes := ByteArray.empty
        while bytes.size < before.bytes do
          let count := min 4096 (before.bytes - bytes.size)
          let part ← FileSystem.readPage handle bytes.size.toUInt64 ⟨count, Nat.min_le_left _ _⟩
          unless part.size == count do throw (IO.userError "truncated cache diagnostic object")
          bytes := bytes ++ part
        unless (← FileSystem.readVersion handle) == before do
          throw (IO.userError "cache diagnostic object mutated during read")
        cost := {cost with
          readUs := cost.readUs + ((← IO.monoNanosNow) - started) / 1000
          bytes := cost.bytes + bytes.size}
        let started ← IO.monoNanosNow
        let some text := String.fromUTF8? bytes | throw (IO.userError "invalid cache diagnostic UTF-8")
        let cached ← IO.ofExcept
          (fromJson? (← IO.ofExcept (Json.parse text)) : Except String SearchProvider.CachedVector)
        cost := {cost with decodeUs := cost.decodeUs + ((← IO.monoNanosNow) - started) / 1000}
        let started ← IO.monoNanosNow
        let some _ := SearchProvider.CheckedVector.make? cached |
          throw (IO.userError "unusable cache diagnostic vector")
        unless cached.model == options.model && cached.window == window do
          throw (IO.userError "cache diagnostic locator changed")
        cost := {cost with
          checkUs := cost.checkUs + ((← IO.monoNanosNow) - started) / 1000
          hits := cost.hits + 1}
        hit := true
        break
      unless hit do throw (IO.userError "cache diagnostic needs every original window warm")
    samples := samples ++ [Json.mkObj [("repetition", toJson repetition), ("cost", toJson cost)]]
  pure (Json.mkObj [("purpose", toJson "standalone-cache-cost"),
    ("database", toJson snapshot.head.identity), ("samples", toJson samples)])

end Eggshell.SemanticLatency

def main (arguments : List String) : IO UInt32 := do
  try
    if arguments == ["pack-vectors"] then
      let input ← IO.getStdin
      let mut line ← input.getLine
      while !line.isEmpty do
        let vector ← IO.ofExcept (Lean.Json.parse line)
        let encoded ← IO.ofExcept (Eggshell.SearchProvider.packVector vector)
        IO.println (Lean.toJson encoded).compress
        (← IO.getStdout).flush
        line ← input.getLine
      return 0
    let result ← match arguments with
      | ["prepare", directory, count] => do
          let some count := count.toNat? | throw (IO.userError "invalid source count")
          Eggshell.SemanticLatency.prepare (.mk directory) count
      | ["prime", database, question] => Eggshell.SemanticLatency.prime (.mk database) question
      | ["inspect", database, question] => Eggshell.SemanticLatency.inspect (.mk database) question
      | ["cache-cost", database] => Eggshell.SemanticLatency.cacheCost (.mk database)
      | ["counts", database] => do
          let snapshot ← Eggshell.DB.PageMap.pin (.mk database)
          let rows ← ["alls", "indexedAllReferences", "liveOutcomes", "nodes"].mapM fun key => do
            pure (key, Lean.toJson (← Eggshell.Persistence.Store.getNat snapshot.get key))
          pure (Lean.Json.mkObj rows)
      | _ => throw (IO.userError "usage: semantic_latency prepare DIRECTORY COUNT | prime DB QUESTION | inspect DB QUESTION | cache-cost DB | pack-vectors | counts DB")
    IO.println result.compress
    pure 0
  catch error =>
    IO.eprintln s!"semantic latency: {error}"
    pure 1
