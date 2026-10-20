import Eggshell.Install
import tools.RetrievalIndex

open Lean Eggshell Persistence

/-- Unmeasured phase inspection of the exact production nomination function.
It reads one pinned, already-warm index, retains its full ranking and starts
neither a hook nor a numerical provider. -/
def nominationProfile (database question : String) : IO Json := do
  let pinStarted ← IO.monoNanosNow
  let source ← DB.PageMap.pin (.mk database)
  let pinUs := ((← IO.monoNanosNow) - pinStarted) / 1000
  let openStarted ← IO.monoNanosNow
  let some reader ← RetrievalResearch.Index.open? source |
    throw (IO.userError "phase inspection requires an already-complete lexical index")
  let openUs := ((← IO.monoNanosNow) - openStarted) / 1000
  let postings ← IO.mkRef (#[] : Array Json)
  let postingUs ← IO.mkRef 0
  let ordinalUs ← IO.mkRef 0
  let ordinalCalls ← IO.mkRef 0
  let posting := fun unit => do
    let sourceReads ← source.reads.get
    let indexReads ← reader.index.reads.get
    let started ← IO.monoNanosNow
    let result ← reader.posting unit
    let elapsed := ((← IO.monoNanosNow) - started) / 1000
    let sourceAfter ← source.reads.get
    let indexAfter ← reader.index.reads.get
    postingUs.modify (· + elapsed)
    postings.modify (·.push (Json.mkObj [
      ("term", toJson unit), ("owners", toJson result.1.length),
      ("frequency", toJson result.2), ("elapsedUs", toJson elapsed),
      ("sourcePageReads", toJson (sourceAfter - sourceReads)),
      ("indexPageReads", toJson (indexAfter - indexReads))]))
    pure result
  let ordinal := fun owner => do
    let started ← IO.monoNanosNow
    let result ← IO.ofExcept (Store.payloadSize (← source.get (Store.key "member" owner)))
    let elapsed := ((← IO.monoNanosNow) - started) / 1000
    ordinalUs.modify (· + elapsed)
    ordinalCalls.modify (· + 1)
    pure result
  let started ← IO.monoNanosNow
  let nominations ← Plugin.lexicalNominations reader.expected.candidates posting ordinal question []
  let total := ((← IO.monoNanosNow) - started) / 1000
  let postingTime ← postingUs.get
  let ordinalTime ← ordinalUs.get
  pure (Json.mkObj [
    ("purpose", toJson "standalone-lexical-nomination-profile"),
    ("sourcePinUs", toJson pinUs), ("indexOpenUs", toJson openUs),
    ("head", toJson source.head), ("indexHead", toJson reader.index.head),
    ("contract", toJson RetrievalResearch.Index.contract),
    ("question", toJson question), ("population", toJson reader.expected.candidates),
    ("postings", toJson (← postings.get)), ("postingUs", toJson postingTime),
    ("ordinalCalls", toJson (← ordinalCalls.get)), ("ordinalUs", toJson ordinalTime),
    ("otherNominationUs", toJson (total - postingTime - ordinalTime)),
    ("totalUs", toJson total), ("ranking", toJson nominations.durableRanking),
    ("selected", toJson nominations.durable),
    ("sourcePageReads", toJson (← source.reads.get)),
    ("sourcePageBytes", toJson (← source.readBytes.get)),
    ("indexPageReads", toJson (← reader.index.reads.get)),
    ("indexPageBytes", toJson (← reader.index.readBytes.get)),
    ("newNativeHooks", toJson (0 : Nat)), ("generationModelCalls", toJson (0 : Nat)),
    ("productionAdoption", toJson false)])

/-- Separate the complete semantic domain from the postings-only lexical lane.
No provider or original Outcome body is read to construct this catalogue. -/
def domainProfile (database : String) : IO Json := do
  let source ← DB.PageMap.pin (.mk database)
  let started ← IO.monoNanosNow
  let documents ← Store.searchDocuments source
  let domainUs := ((← IO.monoNanosNow) - started) / 1000
  let started ← IO.monoNanosNow
  let children ← Plugin.savedSemanticChildren source (Std.HashSet.ofList (documents.map (·.work)))
  let topologyUs := ((← IO.monoNanosNow) - started) / 1000
  pure (Json.mkObj [
    ("purpose", toJson "standalone-semantic-domain-profile"), ("head", toJson source.head),
    ("documents", toJson documents.length),
    ("windowReferences", toJson ((documents.map (·.windows.length)).sum)),
    ("uniqueWindows", toJson ((Std.HashSet.ofList (documents.flatMap (·.windows))).size)),
    ("semanticChildren", toJson children.size), ("searchDocumentsUs", toJson domainUs),
    ("savedSemanticChildrenUs", toJson topologyUs),
    ("sourcePageReads", toJson (← source.reads.get)),
    ("sourcePageBytes", toJson (← source.readBytes.get)),
    ("generationModelCalls", toJson (0 : Nat)), ("productionAdoption", toJson false)])

/-- Run the complete single-DB fallback implementation outside a hook deadline.
Existing production trace labels locate Work admission, discovery and rendering.
This is not an additional fixed gate sample or a transport/ACK measurement. -/
def lexicalProfile (database question : String) : IO Json := do
  let receipt ← Receipt.fresh
  let started ← IO.monoMsNow
  let selection : Config.Selection := {
    label := "lexical-phase-inspection", read := [⟨"source", .mk database⟩], write := none
    semanticMatcher := none, handoffChars := 120000
    handoffBytes := some Config.nativeHandoffBytes }
  let context : Plugin.SourceContext := {
    workspace := (← IO.currentDir), deadline := started + 890000, question, receipt := some receipt }
  let result ← Plugin.automaticHandoff selection question [] false
    (sourceContext := some context) (publishMemo := false)
  pure (Json.mkObj [
    ("purpose", toJson "standalone-complete-lexical-fallback-profile"),
    ("elapsedMs", toJson ((← IO.monoMsNow) - started)), ("receipt", toJson receipt),
    ("semanticProviderConfigured", toJson false), ("handoff", toJson result),
    ("newNativeHooks", toJson (0 : Nat)), ("generationModelCalls", toJson (0 : Nat)),
    ("productionAdoption", toJson false)])

def main (arguments : List String) : IO UInt32 := do
  let result ← match arguments with
    | ["--domain", database] => domainProfile database
    | ["--lexical", database, question] => lexicalProfile database question
    | [database, question] => nominationProfile database question
    | _ => throw (IO.userError "lexical_scale_profile [--domain DB | --lexical DB QUESTION | DB QUESTION]")
  IO.println result.compress
  pure 0
