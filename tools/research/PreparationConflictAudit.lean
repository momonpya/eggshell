import tools.RetrievalIndex
import Eggshell.SourceDelta

open Lean Eggshell DB Persistence.Store

private def check (value : Bool) (message : String) : IO Unit :=
  unless value do throw (IO.userError message)

/-- Reproduce the publication/preparation interleaving without a timing race:
the current source retains the exact historical root and its open descriptor.
No source, source head, or shared derived index is modified. -/
private partial def historical (source current : PageMap.Snapshot) : IO PageMap.Snapshot := do
  check (current.head.revision > 0) "no earlier source publication"
  let publication ← readPublication current current.head.revision
  let some retained ← PageMap.HistoryReader.make? source publication.parent |
    throw (IO.userError "source does not retain its parent")
  let previous := retained.snapshot
  if (← RetrievalResearch.Index.stamp previous) != (← RetrievalResearch.Index.stamp source) &&
      (← getNat previous.get "candidates") > 0 then return previous
  historical source previous

def main (args : List String) : IO Unit := do
  let [directory,output] := args |
    throw (IO.userError "PreparationConflictAudit SOURCE OUTPUT")
  let source ← PageMap.pin (.mk directory)
  let previous ← historical source source
  let some delta ← SourceDelta.read? source previous.head |
    throw (IO.userError "historical source is not on the verified publication chain")
  let entries ← directoryEntries previous
  let some (_,owner) := entries.head? | throw (IO.userError "no historical candidate")
  let documents ← SourceDelta.documents previous [owner]
  let some document := documents.head? | throw (IO.userError "historical candidate disappeared")
  let original ← readSearchWindow previous document 0
  check (!original.isEmpty) "pinned original is empty"
  let beforeReady ← RetrievalResearch.Index.ready previous
  check (!beforeReady) "audit needs an isolated, initially cold read-cache"
  let failure ← try
    let _ ← RetrievalResearch.Index.warm previous .user
    pure (none : Option String)
    catch error => pure (some error.toString)
  let some error := failure | throw (IO.userError "baseline no longer reproduces the head conflict")
  check ((error.splitOn "source changed before lexical warm").length > 1)
    "baseline failed for a different reason"
  check ((← PageMap.pin source.directory).head == source.head)
    "diagnostic source advanced; repeat against a quiescent input"
  check ((← readSearchWindow previous document 0) == original)
    "historical original changed"
  let report := Json.mkObj [
    ("currentSource",toJson source.head),("preparedSource",toJson previous.head),
    ("verifiedPublicationsBetween",toJson delta.records),
    ("changedOwnersBetween",toJson delta.owners.length),
    ("originalOwner",toJson owner),("originalCharacters",toJson original.length),
    ("originalSha256",toJson (Sha256.hex original.toUTF8)),
    ("pinnedOriginalReadableBeforeAndAfter",toJson true),
    ("currentCandidates",toJson (← getNat source.get "candidates")),
    ("preparedCandidates",toJson (← getNat previous.get "candidates")),
    ("warmError",toJson error),("sourceHeadUnchanged",toJson true),
    ("historicalInterleaving",toJson true),("concurrentLoadTest",toJson false),
    ("answeringModelCalls",toJson (0 : Nat)),("productFixImplemented",toJson false)]
  IO.FS.writeFile (.mk output) report.pretty
  IO.println report.compress
where
  directoryEntries (source : PageMap.Snapshot) : IO (List (Nat × Nat)) :=
    Persistence.Store.directory source "searchCandidate"
