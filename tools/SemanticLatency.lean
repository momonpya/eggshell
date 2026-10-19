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

end Eggshell.SemanticLatency

def main (arguments : List String) : IO UInt32 := do
  try
    let result ← match arguments with
      | ["prepare", directory, count] => do
          let some count := count.toNat? | throw (IO.userError "invalid source count")
          Eggshell.SemanticLatency.prepare (.mk directory) count
      | ["prime", database, question] => Eggshell.SemanticLatency.prime (.mk database) question
      | ["inspect", database, question] => Eggshell.SemanticLatency.inspect (.mk database) question
      | ["counts", database] => do
          let snapshot ← Eggshell.DB.PageMap.pin (.mk database)
          let rows ← ["alls", "indexedAllReferences", "liveOutcomes", "nodes"].mapM fun key => do
            pure (key, Lean.toJson (← Eggshell.Persistence.Store.getNat snapshot.get key))
          pure (Lean.Json.mkObj rows)
      | _ => throw (IO.userError "usage: semantic_latency prepare DIRECTORY COUNT | prime DB QUESTION | inspect DB QUESTION | counts DB")
    IO.println result.compress
    pure 0
  catch error =>
    IO.eprintln s!"semantic latency: {error}"
    pure 1
