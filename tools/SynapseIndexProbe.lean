import Eggshell.SynapseIndex

open Lean Eggshell Eggshell.Synapses Eggshell.Synapses.Index

def lookupOnly (database lane kind value : String) : IO Unit := do
  let started ← IO.monoMsNow
  let snapshot ← DB.PageMap.pin (.mk database)
  let scope ← match lane with
    | "shared" => pure Scope.shared
    | "usage" => pure Scope.usage
    | _ => throw (IO.userError "invalid scope")
  let key ← match kind with
    | "answer" => pure (Key.answer snapshot.head.identity value)
    | "owner" => pure (Key.owner snapshot.head.identity value)
    | "query" => pure (Key.query value)
    | _ => throw (IO.userError "invalid lookup key")
  let reader ← if scope == .shared then Index.openShared? snapshot else Index.open? snapshot .user scope
  let some reader := reader | throw (IO.userError "no current DB-owned synaptic index")
  let opened ← IO.monoMsNow
  let result ← reader.lookup key 4096 (started + 3000)
  IO.println (Json.mkObj [
    ("scope", toJson scope), ("complete", toJson result.complete),
    ("facts", toJson result.facts.size), ("postingScanPages", toJson result.postingPages),
    ("readerMs", toJson (opened-started)), ("lookupMs", toJson ((← IO.monoMsNow)-opened)),
    ("indexHead", toJson result.index), ("elapsedMs", toJson ((← IO.monoMsNow)-started)),
    ("indexWrites", toJson (0 : Nat)), ("frozenFactFileRead", toJson false)]).compress

/-- Research adapter: import already extracted, frozen facts into a private
overlay of a pinned real DB. It does not assert production hook integration. -/
def main (args : List String) : IO Unit := do
  if let [database, lane, "lookup", kind, value] := args then
    return ← lookupOnly database lane kind value
  let [database, input, lane] := args | throw (IO.userError "SynapseIndexProbe DB FROZEN-FACTS shared|usage")
  let scope ← match lane with
    | "shared" => pure Scope.shared
    | "usage" => pure Scope.usage
    | _ => throw (IO.userError "invalid scope")
  let snapshot ← DB.PageMap.pin (.mk database)
  let json ← IO.ofExcept (Json.parse (← IO.FS.readFile (.mk input)))
  let facts ← IO.ofExcept (json.getObjValAs? (Array Fact) "facts")
  let graph ← IO.ofExcept (Graph.ofFacts facts)
  let started ← IO.monoMsNow
  let first ← Index.replace snapshot .user scope graph.snapshot
  let second ← Index.replace snapshot .user scope graph.snapshot
  let warmMs := (← IO.monoMsNow)-started
  unless first == second do throw (IO.userError "same frozen facts appended another index publication")
  let reopenStarted ← IO.monoMsNow
  let some reader ← Index.open? snapshot .user scope | throw (IO.userError "new reader could not reuse index")
  let reopenMs := (← IO.monoMsNow)-reopenStarted
  let some fact := facts[0]? | throw (IO.userError "empty fixture")
  let key := match fact with
    | .used usage => Key.query usage.query
    | .supports support => .answer support.claim.database support.claim.answer
    | .read recorded => .owner recorded.binding.database recorded.binding.owner
    | .coquoted group _ => .group group
    | .consumed edge => .consumer edge.consumer
  let lookupStarted ← IO.monoMsNow
  let result ← reader.lookup key 4096 (lookupStarted + 3000)
  let lookupMs := (← IO.monoMsNow)-lookupStarted
  unless result.complete && !result.facts.isEmpty do throw (IO.userError "new reader lost its inverse postings")
  unless (← DB.PageMap.pin snapshot.directory).head == snapshot.head do
    throw (IO.userError "private indexing changed source publication")
  IO.println (Json.mkObj [
    ("scope", toJson scope), ("sourceHead", toJson snapshot.head),
    ("indexHead", toJson first), ("facts", toJson graph.evidenceCount),
    ("queriedFacts", toJson result.facts.size), ("postingScanPages", toJson result.postingPages),
    ("warmTwiceMs", toJson warmMs), ("reopenMs", toJson reopenMs), ("lookupMs", toJson lookupMs),
    ("elapsedMs", toJson ((← IO.monoMsNow)-started)),
    ("repeatAppended", toJson false), ("sourceHeadUnchanged", toJson true)]).compress
