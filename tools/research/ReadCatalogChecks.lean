import Eggshell.ReadCatalog
import Eggshell.PluginModel
import Eggshell.Persistence

open Lean Eggshell Eggshell.Synapses Eggshell.Synapses.Extraction

private def check (ok : Bool) (message : String) : IO Unit :=
  unless ok do throw (IO.userError message)
private def rejects (action : IO α) : IO Bool := do
  try let _ ← action; return false catch _ => return true

private def append (path : System.FilePath) (values : List Value)
    (stage : Persistence.Store.Intern → Unit → IO Persistence.Store.MetadataChange := fun _ _ => pure {}) : IO DB.PageMap.Head := do
  let committed ← Persistence.appendPrepared path (fun graph => do
    let some transaction := (Transaction.begin graph).stageValues? values |
      throw "invalid native test transaction"
    return (transaction,())) stage
  return committed.head

/-- Actual page publications exercise unrelated graph growth, negative metadata
dependencies, pinned historical recovery and eighty concurrent cache misses.
This is a component test, not an eighty-user workday or hook latency claim. -/
def main (args : List String) : IO Unit := do
  let [directory] := args | throw (IO.userError "NEW-NATIVE-FIXTURE")
  let root := System.FilePath.mk directory
  check (root.isAbsolute && !(← root.pathExists)) "new absolute fixture required"
  IO.FS.createDirAll root
  let path := root / "project.egg"
  let tool : Plugin.ToolEvent := {
    name := "mcp__fixture__read",useId := "native-tool"
    input := (Json.mkObj [("resource",toJson "fixture://ticket/17")]).compress
    response := (Json.mkObj [("result",toJson "alpha\nbeta\ngamma\n"),("revision",toJson (7 : Nat))]).compress}
  let owner := (Plugin.compileOperationOutcomes (.text "session") (.text "turn") tool).2
  let some edge := OutcomeEdge.fromValue? owner | throw (IO.userError "native owner absent")
  let document : Document := {
    owner := Persistence.selectionKey edge.relation,work := Persistence.selectionKey edge.work
    workText := Persistence.Store.text? edge.work,source := Persistence.Store.text? edge.outcome
    native := true,occurrences := Provenance.identities edge,files := #[]}
  let base ← append path [owner] (fun intern _ => do
    let id ← intern.value owner
    let changed ← ObservedRecords.stage intern.writer id document
    return {changed,affected := [id]})
  let initial ← DB.PageMap.pin path
  let some id ← Persistence.Store.findNode? initial owner | throw (IO.userError "missing published owner")
  let unrelated ← append path [.text "an unrelated project's imported advisory"]
  let changed ← append path [] (fun intern _ => do
    let bad ← IO.ofExcept (MetadataBytes.checked "invalid metadata".toUTF8)
    let changed ← MetadataBytes.put intern.writer (ContentMetadata.ownerKey id) bad
    return {changed,affected := [id]})
  let source ← DB.PageMap.pin path
  let pool ← ReadCatalog.create source none
  pool.preparePublication base none #[id]
  let ownerKeys := ["h:" ++ document.owner]
  let some delivered ← pool.acknowledged? base none id ownerKeys | throw (IO.userError "ACK projection missing")
  check (!delivered.isEmpty) "native raw output lost its ACK ranges"
  let prepared ← pool.state.get
  check (prepared.compiled == 1 && prepared.uncached == 0) "one native observation was not compiled once"
  pool.preparePublication unrelated none #[]
  let some old ← pool.get? unrelated none id | throw (IO.userError "unrelated graph append lost its catalog")
  let some shown ← pool.acknowledged? unrelated none id (ownerKeys ++ ["h:unrelated-owner"]) |
    throw (IO.userError "unrelated ACK lost its projection")
  check (shown == delivered) "unrelated ACK or publication changed delivered originals"
  let afterUnrelated ← pool.state.get
  check (afterUnrelated.compiled == 1 && afterUnrelated.ackReused == 1)
    "unrelated publication reconstructed an old original catalog"
  check (← rejects (pool.get? changed none id)) "new previously absent metadata reused stale coordinates"
  check (← rejects (pool.acknowledged? changed none id ownerKeys)) "changed metadata reused a stale ACK projection"
  let some recovered ← pool.get? base none id | throw (IO.userError "pinned previous catalog was lost")
  check (old.doc.source == recovered.doc.source) "historical pin changed original bytes"
  let foreign ← Persistence.ensureSnapshot (root / "foreign.egg")
  check ((← pool.get? foreign.head none id).isNone) "foreign project entered a catalog pool"
  let concurrent ← ReadCatalog.create source none
  let jobs ← (List.range 80).mapM fun _ => IO.asTask (do
    let some found ← concurrent.get? base none id | throw (IO.userError "concurrent projection missing")
    check (found.doc.source == document.source) "concurrent reader received another original") .dedicated
  for job in jobs do let _ ← IO.ofExcept job.get
  let coalesced ← concurrent.state.get
  check (coalesced.compiled == 1 && coalesced.reused == 79)
    "concurrent readers duplicated catalog compilation"
  let constrained := {pool with state := ← IO.mkRef {entries := {}},maxBytes := 1}
  let some first ← constrained.get? base none id | throw (IO.userError "bounded uncached result missing")
  let some second ← constrained.get? base none id | throw (IO.userError "bounded repeated result missing")
  let bounded ← constrained.state.get
  check (bounded.entries.isEmpty && bounded.bytes == 0 && bounded.uncached == 2 &&
    first.doc.source == second.doc.source) "oversize projection escaped the shared allowance"
  let report := Json.mkObj [
    ("unrelatedPublicationOldCompilations",toJson (afterUnrelated.compiled-prepared.compiled)),
    ("newMetadataInvalidated",toJson true),("historicalOriginalExact",toJson true),
    ("unrelatedAckOldCompilations",toJson (afterUnrelated.compiled-prepared.compiled)),
    ("ackProjectionExact",toJson true),
    ("foreignProjectRejected",toJson true),("concurrentRequests",toJson (80 : Nat)),
    ("concurrentCompilations",toJson coalesced.compiled),("concurrentReuses",toJson coalesced.reused),
    ("oversizeEntries",toJson bounded.entries.size),("oversizeChargedBytes",toJson bounded.bytes),
    ("answeringModelCalls",toJson (0 : Nat)),("eightyUserWorkdayValidated",toJson false)]
  IO.FS.writeFile (root / "results.json") report.pretty
  IO.println report.compress
