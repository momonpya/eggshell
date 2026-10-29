import Eggshell.SynapseJournal
open Lean Eggshell Eggshell.Synapses

def main (args : List String) : IO Unit := do
  let [database,output] := args | throw (IO.userError "prepared DB and new report required")
  let destination := System.FilePath.mk output
  unless !(← destination.pathExists) do throw (IO.userError "preserve usage preparation evidence")
  let source ← DB.PageMap.pin (.mk database)
  let some before ← Journal.open? source | throw (IO.userError "raw native journal missing")
  let cache ← StoredReadLookup.create
  let started ← IO.monoMsNow
  let refreshed ← Journal.refresh source .database (started+120000) 64 (some cache)
  let elapsed := (← IO.monoMsNow)-started
  unless refreshed.complete && refreshed.pending == 0 && !(← Journal.required source) do
    throw (IO.userError "usage preparation left unprocessed evidence")
  let some usage ← UsageCache.open? source | throw (IO.userError "usage preparation did not publish")
  let some after ← Journal.open? source | throw (IO.userError "usage preparation lost native observations")
  let count ← Persistence.Store.getNat before.get "count"
  for ordinal in [:count] do
    unless (← Journal.entry before ordinal) == (← Journal.entry after ordinal) do
      throw (IO.userError "usage preparation changed a native observation")
  let study : System.FilePath := "/Users/ovm/.codex/experiments/eggshell/scope-token-study-20261028"
  let mut queries := #[]
  for topic in [1,2,3] do
    let prompt ← IO.FS.readFile (study / "prompts" / s!"topic-{topic}.txt")
    let found ← usage.lookup (.query (Sha256.hex prompt.toUTF8)) 100000 ((← IO.monoMsNow)+5000)
    unless found.complete do throw (IO.userError "incomplete query-root diagnostic")
    queries := queries.push (topic,found.facts.size)
  let state ← cache.state.get
  let result := Json.mkObj [("source",toJson source.head),("result",toJson refreshed),
    ("elapsedMs",toJson elapsed),("usageFacts",toJson usage.manifest.facts),
    ("queryRootFacts",toJson queries),("lookupHits",toJson state.hits),("lookupMisses",toJson state.misses),
    ("lookupRows",toJson state.rows),("lookupBytes",toJson state.bytes),
    ("originalEntriesExact",toJson true),("rawEntries",toJson count),
    ("actualHookCalls",toJson (0 : Nat)),("answeringModelCalls",toJson (0 : Nat))]
  IO.FS.writeFile destination result.pretty
  IO.println result.compress
