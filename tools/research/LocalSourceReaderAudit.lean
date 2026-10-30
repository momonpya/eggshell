import Eggshell.PublicationService
import Eggshell.SynapseTransport
import Eggshell.SynapseBundles

open Lean Eggshell Eggshell.Plugin Eggshell.Synapses
open CanonicalSource

private def check (ok : Bool) (message : String) : IO Unit :=
  unless ok do throw (IO.userError message)

private def rejected (action : IO α) : IO Bool :=
  try let _ ← action; pure false catch _ => pure true

private def server : IO Publication.Service.Server := return {
  state := ← Std.Mutex.new {},resident := ← Std.Mutex.new 0,stopping := ← IO.mkRef false
  sources := ← Std.Mutex.new #[],prepared := ← Shared.Pool.new
  structures := ← ObservedRecordView.Cache.new,sourceReplies := ← Std.Mutex.new 0
  deferredReplies := ← Std.Mutex.new #[]}

private def request (access : Shared.Access) (extra : List (String × Json) := []) : Json :=
  Json.mkObj ([ ("database",toJson access.database),("scope",toJson access.scope),
    ("source",toJson access.source),("metadata",toJson access.metadata)] ++ extra)

private def prepare (service : Publication.Service.Server) (source : DB.PageMap.Snapshot)
    (storage : DB.Sidecar.Storage) : IO Shared.Access := do
  let found ← Publication.Service.prepareSource service (Json.mkObj [
    ("directory",toJson source.directory.toString),("source",toJson source.head),
    ("storage",toJson storage)]) ((← IO.monoMsNow)+60000)
  IO.ofExcept (fromJson? found)

/-- Exercise the existing JSON handler and the original client checks. This
is deliberately not a socket benchmark; the adapter forwarding is proved
separately, and the physical transport audit remains a separate result. -/
private def handlerReader (service : Publication.Service.Server) (access : Shared.Access) : PreparedSource.Reader :=
  {access
   rows := fun owners deadline => do
     let owners := (hashDistinct owners.toList).toArray
     let result ← Publication.Service.sourceRows service access.capability
       (request access [("owners",toJson owners)]) deadline
     PreparedSource.checkedRows access owners (← IO.ofExcept (fromJson? result))
   bindings := fun wanted allowed deadline => do
     let result ← Publication.Service.sourceBindings service access.capability
       (request access [("wanted",toJson wanted),("allowed",toJson allowed.toArray)]) deadline
     PreparedSource.checkedBindings access wanted allowed (← IO.ofExcept (fromJson? result))
   records := fun owners deadline => do
     let owners := (hashDistinct owners.toList).toArray
     let result ← Publication.Service.sourceRecords service access.capability
       (request access [("owners",toJson owners)]) deadline
     PreparedSource.checkedRecords access owners (← IO.ofExcept (fromJson? result))}

private def rowsEqual (a b : Shared.Projection) : Bool :=
  a.identity == b.identity && a.rows == b.rows && a.layouts == b.layouts

private def bindingsEqual (a b : IndexedBindings.Resolved) : Bool :=
  a.complete == b.complete && a.requests == b.requests && a.inspected == b.inspected &&
  a.bytes == b.bytes && a.unresolved == b.unresolved && a.unusable == b.unusable &&
  a.rows.size == b.rows.size && a.rows.toArray.all (fun (key,value) => b.rows[key]? == some value)

private def memberIdentity (member : Bundles.Member) : Json :=
  let choices := member.choices.map fun choice => Json.mkObj [
    ("owner",toJson choice.owner),("rows",toJson choice.rows),("spans",toJson choice.spans)]
  Json.mkObj [("source",toJson member.source),("choices",Json.arr choices)]

private def bundleIdentity (bundle : Bundles.Projected) : Json := Json.mkObj [
  ("key",toJson bundle.demand.key),("kind",toJson bundle.demand.kind),
  ("priority",toJson bundle.demand.priority),("members",Json.arr (bundle.members.map memberIdentity))]

private def planIdentity (plan : Transport.Plan) : Json := Json.mkObj [
  ("results",toJson (plan.results.map fun result => result.receipt)),
  ("ranges",toJson (plan.ranges.map fun (owner,ranges) => (Persistence.selectionKey owner,ranges))),
  ("outputRanges",toJson (plan.outputRanges.map fun (owner,ranges) =>
    (Persistence.selectionKey owner,ranges.map fun (range : Transport.OutputRange) => (range.priority,range.first,range.limit,range.path)))),
  ("canonical",toJson (plan.canonical.toArray.qsort (fun a b => a.1 < b.1))),
  ("layouts",toJson (plan.canonicalLayouts.toArray.qsort (fun a b => a.1 < b.1))),
  ("structures",toJson (plan.originalStructures.toArray.qsort (fun a b => a.1 < b.1))),
  ("bundles",Json.arr ((Bundles.project plan).map bundleIdentity)),
  ("unsupported",toJson plan.unsupported),("unlocated",toJson plan.unlocatedFileOwners),
  ("complete",toJson plan.complete),("bindingComplete",toJson plan.bindingComplete),
  ("bindingRequests",toJson plan.bindingRequests),("bindingBytes",toJson plan.bindingBytes),
  ("bindingUnresolved",toJson plan.bindingUnresolved),("failures",toJson plan.canonicalFailure)]

private def inspect (service : Publication.Service.Server) (source : DB.PageMap.Snapshot)
    (storage : DB.Sidecar.Storage) (transport : Bool) : IO Json := do
  let access ← prepare service source storage
  let remote := handlerReader service access
  let some index ← Index.open? source storage .shared | throw (IO.userError "original index is cold")
  let some ready ← Cache.open? source storage | throw (IO.userError "canonical cache is cold")
  let ownerIds := (Shared.allOwners ready.registry).toArray.map Prod.snd |>.qsort (· < ·)
  let ownerIds := (hashDistinct ownerIds.toList).toArray
  check (!ownerIds.isEmpty) "source fixture has no canonical rows"
  let nodeReader ← Persistence.Store.NodeReader.new source
  let mut owners : Array Transport.Owner := #[]
  for entry in ← Build.entries source do
    owners := owners.push ⟨source.head.identity,← nodeReader.outcome (← nodeReader.locateOutcome entry.id),
      ← nodeReader.sources entry.id⟩
  let allIds := owners.map fun owner => Persistence.selectionKey owner.original.relation
  let facts ← Index.allFacts index.index
  let wanted := (hashDistinct (facts.toList.filterMap fun fact => (Index.bindingCandidate? fact).map (·.source))).toArray
  let deadline := (← IO.monoMsNow)+120000
  let checks ← IO.mkRef (0 : Nat)
  let recordCount ← IO.mkRef (0 : Nat)
  let transportReport ← IO.mkRef Json.null
  Publication.Service.withSourceReader service access.capability (request access) deadline fun direct => do
    check (direct.identity == remote.identity) "local reader changed source identity"
    for selected in [ownerIds,#[],#[ownerIds[0]!,ownerIds[0]!,"absent-owner"]] do
      let a ← remote.rows selected deadline
      let b ← direct.rows selected deadline
      check (rowsEqual a b) "local rows changed text, origins, order or layouts"
      checks.modify (·+1)
    for allowed in [Std.HashSet.ofArray allIds,Std.HashSet.ofArray #[ownerIds[0]!],{}] do
      let a ← remote.bindings wanted allowed deadline
      let b ← direct.bindings wanted allowed deadline
      check (bindingsEqual a b) "local bindings changed scope, order or completeness"
      checks.modify (·+1)
    for selected in [allIds,#[],#[allIds[0]!,allIds[0]!,"absent-owner"]] do
      let a ← remote.records selected deadline
      let b ← direct.records selected deadline
      check (a.source == b.source && toJson a.rows == toJson b.rows) "local general original geometry changed"
      recordCount.modify (·+(a.rows.filterMap Prod.snd).size)
      checks.modify (·+1)
    check (← rejected (direct.rows ownerIds 0)) "local reader ignored inner expiry"
    let usage ← UsageCache.open? source
    let prepared : Recommend.Prepared := {source,shared := some index,usage,canonical := some remote}
    let some replacement := prepared.withReader? direct | throw (IO.userError "matching source rejected local reader")
    check (prepared.identity == replacement.identity) "reader replacement changed memo identity or caller usage"
    let wrong := {direct with access := {direct.access with database := "other-database"}}
    check ((prepared.withReader? wrong).isNone) "reader replacement crossed database"
    if transport then
      let answers := (allIds.extract 0 (min 8 allIds.size)).mapIdx fun priority owner => (owner,priority)
      let query := Sha256.hex "generic source reader equivalence".toUTF8
      let start ← IO.monoMsNow
      let a ← Transport.build #[prepared] answers owners query deadline
      let middle ← IO.monoMsNow
      let b ← Transport.build #[replacement] answers owners query deadline
      let finish ← IO.monoMsNow
      let left := planIdentity a
      let right := planIdentity b
      check (left == right) "local reader changed admitted offers, bundles or original planning"
      check (a.complete && b.complete) "transport comparison silently used incomplete plans"
      transportReport.set (Json.mkObj [
        ("handlerMs",toJson (middle-start)),("localMs",toJson (finish-middle)),
        ("planSha256",toJson (Sha256.hex left.compress.toUTF8)),("samePlan",toJson true),
        ("offers",toJson (a.results.foldl (fun sum result => sum+result.admitted.size) 0)),
        ("canonicalOwners",toJson a.canonical.size),("usagePresent",toJson usage.isSome)])
  let bad := {access with scope := "other-scope"}
  check (← rejected (Publication.Service.withSourceReader service access.capability (request bad) deadline
    fun _ => pure ())) "local reader accepted a foreign scope"
  check (← rejected (Publication.Service.withSourceReader service "wrong-secret" (request access) deadline
    fun _ => pure ())) "local reader accepted a wrong capability"
  check (← rejected (Publication.Service.withSourceReader service access.capability (request access) 0
    fun _ => pure ())) "local borrow ignored expiry"
  let state ← service.prepared.state.atomically get
  check (state.entries.toArray.all (fun (_,entry) => entry.borrowers == 0)) "prepared borrow escaped continuation"
  let escaped ← Publication.Service.withSourceReader service access.capability (request access) deadline pure
  check (← rejected (escaped.rows #[] deadline)) "escaped reader survived pool release"
  check (← rejected (Publication.Service.withSourceReader service access.capability (request access) deadline
    fun _ => throw (IO.userError "deliberate callback failure") : IO Unit)) "callback failure was swallowed"
  let state ← service.prepared.state.atomically get
  check (state.entries.toArray.all (fun (_,entry) => entry.borrowers == 0)) "callback exception leaked a borrow"
  return Json.mkObj [("source",toJson source.head),("owners",toJson allIds.size),
    ("fileOwners",toJson ownerIds.size),("wanted",toJson wanted.size),("checks",toJson (← checks.get)),
    ("generalRecordViews",toJson (← recordCount.get)),("transport",← transportReport.get),
    ("authScopeExpiryAndRelease",toJson true)]

private def publish (source : DB.PageMap.Snapshot) (values : List Value) : IO DB.PageMap.Snapshot := do
  let _ ← DB.PageMap.withWriter source fun writer => do
    let intern : Persistence.Store.Intern := ⟨writer,← IO.mkRef {}⟩
    let ids ← values.mapM intern.root
    Persistence.Store.writeChange writer {added := ids,removed := [],unionsChanged := false}
  DB.PageMap.pin source.directory

private def observation (work output : String) (call : String) : Value :=
  let work := Value.text work
  let output := Value.text output
  let event := Value.applyList .occurrence [Ref.semantic output,Ref.semantic work,
    Ref.exact (.text "local-reader-fixture"),Ref.exact (.text "turn"),Ref.exact (.text call)]
  (OutcomeEdge.make work output [event] (by simp) (by simp [maxOutcomeObservations])).relation

def main (args : List String) : IO Unit := do
  let [output] := args | throw (IO.userError "fresh local reader audit output required")
  let root : System.FilePath := .mk output
  check (!(← root.pathExists)) "preserve previous local reader audit"
  IO.FS.createDir root
  let service ← server
  try
    let study : System.FilePath := "/Users/ovm/.codex/experiments/eggshell/scope-token-study-20261028"
    let source ← DB.PageMap.pin (study / "r0/stage1/history/source.egg")
    let _ ← Build.refresh source .user
    let _ ← Cache.refresh source .user
    let actual ← inspect service source .user true
    IO.FS.writeFile (root / "actual.json") actual.pretty
    let path := root / "fixture"
    IO.FS.createDir path
    IO.FS.writeFile (path / "source.cpp") "first();\nsecond();\nthird();\n"
    let command := "nl -ba source.cpp | sed -n '1,3p'"
    let input := Json.mkObj [("command",toJson command)]
    let captured ← SourceEvidence.capture path input ((← IO.monoMsNow)+10000)
    let work := "shell\n" ++ input.compress
    let text := "     1\tfirst();\n     2\tsecond();\n     3\tthird();\n"
    let owner := observation work text "file"
    let receipt := SourceEvidence.receipt (.text "local-reader-fixture") (.text "turn") (.text "file") owner captured.record
    let raw ← DB.PageMap.create (path / "source.egg") "local reader fixture"
    let first ← publish raw [owner,receipt,observation "mcp-resource\n{}" "{\"path\":\"日本語\",\"items\":[1,2,3]}" "json"]
    let _ ← Build.refresh first .database
    let _ ← Cache.refresh first .database
    let fixture ← inspect service first .database true
    IO.FS.writeFile (root / "fixture.json") fixture.pretty
    let old ← prepare service first .database
    let changed ← IO.Process.output {cmd := "/bin/chmod",args := #["-R","a-w",first.directory.toString]}
    check (changed.exitCode == 0) "could not set read-only fixture"
    try
      Publication.Service.withSourceReader service old.capability (request old) ((← IO.monoMsNow)+10000) fun reader => do
        let rows ← reader.rows #[Persistence.selectionKey owner] ((← IO.monoMsNow)+10000)
        check (rows.rows.size == 1 && rows.rows[0]!.2.size == 3) "local reader failed on read-only source"
    finally
      let restored ← IO.Process.output {cmd := "/bin/chmod",args := #["-R","u+w",first.directory.toString]}
      check (restored.exitCode == 0) "could not restore owned fixture permissions"
    let next ← publish first [observation "mcp-resource\n{}" "{\"items\":[4,5]}" "later"]
    let _ ← Build.refresh next .database
    let _ ← Cache.refresh next .database
    let current ← prepare service next .database
    check (old.source != current.source) "publication did not advance"
    Publication.Service.withSourceReader service old.capability (request old) ((← IO.monoMsNow)+10000) fun reader => do
      check (reader.access.source == first.head) "new publication changed old reader pin"
      service.stopping.set true
      check (← rejected (reader.rows #[] ((← IO.monoMsNow)+10000))) "borrowed reader ignored stop"
    check (← rejected (Publication.Service.withSourceReader service current.capability (request current)
      ((← IO.monoMsNow)+10000) fun _ => pure ())) "new local borrow started after stop"
    check ((← DB.PageMap.pin source.directory).head == source.head) "local reader mutated original source"
    let report := Json.mkObj [("actual",actual),("fixture",fixture),
      ("oldPinAfterPublication",toJson true),("stop",toJson true),("service",← service.prepared.stats),
      ("readOnlyFilesystem",toJson true),("escapedReaderRejected",toJson true),
      ("answeringModels",toJson (0 : Nat)),("socketBenchmark",toJson false),
      ("hookMeasured",toJson false),("adopted",toJson false)]
    IO.FS.writeFile (root / "results.json") report.pretty
    IO.println report.compress
  finally service.prepared.close
