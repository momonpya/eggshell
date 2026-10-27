import Eggshell.BatchedBindings
import Eggshell.SynapseBuild
import Eggshell.SynapticRoutingStore
import Lean.Data.Json.Parser

open Lean Eggshell Eggshell.Synapses Eggshell.DB Eggshell.Persistence.Store

namespace Eggshell.Research.BatchedBindingsAudit

private def read (path : String) : IO Json :=
  IO.FS.readFile (.mk path) >>= fun text => IO.ofExcept (Json.parse text)
private def check (value : Bool) (message : String) : IO Unit :=
  unless value do throw (IO.userError message)

structure Settings where
  database : String
  domain : String
  synaptic : String
  output : String
  deriving FromJson

private def same (wanted : Array Range) (left right : IndexedBindings.Resolved) : Bool :=
  left.complete == right.complete && left.requests == right.requests && left.inspected == right.inspected &&
  left.bytes == right.bytes && left.unresolved == right.unresolved && left.unusable == right.unusable &&
  left.rows.size == right.rows.size && wanted.all (fun source => left.rows[source]? == right.rows[source]?)

private def summary (result : IndexedBindings.Resolved) : Json := Json.mkObj [
  ("complete",toJson result.complete),("requests",toJson result.requests),("inspected",toJson result.inspected),
  ("bytes",toJson result.bytes),("unresolved",toJson result.unresolved),("unusable",toJson result.unusable)]

private def fresh (original : Index.Reader) : IO Index.Reader := do
  let index ← PageMap.pin original.index.directory
  check (index.head == original.index.head) "source postings changed between comparison arms"
  return ⟨index,original.manifest⟩

def run (settings : Settings) : IO Unit := do
  let output := System.FilePath.mk settings.output
  check (!(← output.pathExists)) "preserve the previous paired comparison"
  IO.FS.createDirAll output
  let source ← PageMap.pin (.mk settings.database)
  let some shared ← Index.openShared? source | throw (IO.userError "fixed source postings are unprepared")
  let input := (← read settings.synaptic).getObjValD "data"
  let observed ← IO.ofExcept (input.getObjValAs? (Array Json) "inputs")
  check (observed.size == 1 && observed[0]!.getObjValD "index" == toJson shared.index.head)
    "prepared source differs from the actual hook's pinned index"
  let domain := (← read settings.domain).getObjValD "data"
  let nominated ← IO.ofExcept (domain.getObjValAs? (Array String) "nominated")
  let hydrated ← IO.ofExcept (domain.getObjValAs? (Array String) "hydrated")
  let reader ← NodeReader.new source
  let mut documents : Array Extraction.Document := #[]
  for owner in hydrated do
    let some id ← Build.ownerId? source owner | throw (IO.userError "a recorded owner is no longer live")
    documents := documents.push (← Build.document reader id)
  let answers := nominated.mapIdx fun rank owner => (owner,rank)
  let consumers := documents.flatMap fun doc => doc.occurrences.flatMap fun occurrence =>
    answers.filterMap fun (owner,rank) => if owner == doc.owner then some (occurrence,rank) else none
  let roots := (answers.map fun (owner,rank) => (Index.Key.answer source.head.identity owner,rank)) ++
    consumers.map (fun (occurrence,rank) => (Index.Key.consumer occurrence,rank))
  let some routing ← Routing.Store.open? shared | throw (IO.userError "the recorded routing projection is unavailable")
  let walked ← Routing.Store.walk routing none roots ((← IO.monoMsNow)+120000)
  check (walked.complete && walked.hints.all (·.kind ≤ 2)) "unexpected or incomplete shared-only routing"
  check (toJson walked.nodes == observed[0]!.getObjValD "requests" &&
    toJson walked.arcs == observed[0]!.getObjValD "facts") "the actual source graph changed"
  let wanted := (hashDistinct (walked.hints.toList.filterMap fun hint => do
    let source ← hint.target.source?
    let .file _ := source.subject | none
    some source)).toArray
  check (toJson wanted.size == input.getObjValD "bindingRequests") "binding query domain differs from the recorded hook"
  let allowed := ({} : Std.HashSet String).insertMany (documents.filter (·.native) |>.map (·.owner))
  IO.FS.writeFile (output / "queries.json") (toJson wanted).compress
  let mut rounds := #[]
  let mut pointPostingVisits := 0
  for round in [:3] do
    let mut reference : Option IndexedBindings.Resolved := none
    let mut candidate : Option BatchedBindings.Result := none
    let mut referenceMs := 0
    let mut candidateMs := 0
    let mut referencePhysicalReads := 0
    let mut referencePhysicalBytes := 0
    for batchFirst in (if round%2 == 0 then [false,true] else [true,false]) do
      let pinned ← fresh shared
      let started ← IO.monoMsNow
      if batchFirst then
        let found ← BatchedBindings.resolve pinned wanted allowed (started+120000)
        candidateMs := (← IO.monoMsNow)-started
        candidate := some found
      else
        let found ← IndexedBindings.resolve pinned wanted allowed (started+120000)
        referenceMs := (← IO.monoMsNow)-started
        referencePhysicalReads := ← pinned.index.reads.get
        referencePhysicalBytes := ← pinned.index.readBytes.get
        reference := some found
        -- Count logical visits independently after timing. This never changes
        -- either measured arm and is performed once, on the same source keys.
        if round == 0 then
          for key in wanted do
            let lookup ← pinned.lookup (.source key) 32768 ((← IO.monoMsNow)+120000)
            pointPostingVisits := pointPostingVisits+lookup.postingPages
    let some before := reference | throw (IO.userError "missing point comparison")
    let some after := candidate | throw (IO.userError "missing batch comparison")
    check (before.complete && after.resolved.complete && same wanted before after.resolved)
      "batched source lookup changed a result, order, empty result or counter"
    rounds := rounds.push (Json.mkObj [
      ("round",toJson round),("pointMs",toJson referenceMs),("batchMs",toJson candidateMs),
      ("pointPhysicalReads",toJson referencePhysicalReads),("pointPhysicalBytes",toJson referencePhysicalBytes),
      ("batch",toJson after.statistics),("sameAllResultsInInputOrder",toJson true),("result",summary before)])
  let pinned ← fresh shared
  let expired ← BatchedBindings.resolve pinned wanted allowed 0
  let empty ← BatchedBindings.resolve pinned #[] allowed 0
  let noneAllowed ← BatchedBindings.resolve pinned (wanted ++ wanted) {} ((← IO.monoMsNow)+120000)
  let referenceNone ← IndexedBindings.resolve pinned (wanted ++ wanted) {} ((← IO.monoMsNow)+120000)
  let bounded ← BatchedBindings.resolve pinned wanted allowed ((← IO.monoMsNow)+120000) (byteLimit := 1)
  let zeroRows ← BatchedBindings.resolve pinned wanted allowed ((← IO.monoMsNow)+120000) (perKeyLimit := 0)
  check (!expired.resolved.complete && expired.resolved.requests == 0) "expired lookup reported a complete result"
  check (empty.resolved.complete && empty.resolved.requests == 0) "valid empty result became incomplete"
  check (same wanted noneAllowed.resolved referenceNone && noneAllowed.resolved.rows.toArray.all (·.2.isEmpty))
    "duplicate inputs or the empty allowed-owner scope changed source bindings"
  check (!bounded.resolved.complete && !zeroRows.resolved.complete) "a resource limit silently reported completeness"
  check ((← PageMap.pin (.mk settings.database)).head == source.head) "read-only lookup changed the source"
  check ((← PageMap.pin shared.index.directory).head == shared.index.head) "read-only lookup changed the prepared index"
  IO.FS.writeFile (output / "result.json") (Json.mkObj [
    ("source",toJson source.head),("index",toJson shared.index.head),
    ("queryCount",toJson wanted.size),("pointPostingPageVisits",toJson pointPostingVisits),("rounds",toJson rounds),
    ("emptyResultRemainsComplete",toJson true),("expiredRemainsIncomplete",toJson true),
    ("duplicatesAndEmptyOwnerScopeChecked",toJson true),("resourceLimitsRemainExplicit",toJson true),
    ("answeringModelCalls",toJson (0 : Nat)),("warmCalls",toJson (0 : Nat)),
    ("actualHook",toJson false),("latencyAcceptance",toJson false),("adopted",toJson false)]).pretty
  IO.println (Json.mkObj [("queries",toJson wanted.size),("pointPostingPageVisits",toJson pointPostingVisits),
    ("rounds",toJson rounds)]).compress

end Eggshell.Research.BatchedBindingsAudit

#print axioms Eggshell.Synapses.BatchedBindings.pruned_request_exact
#print axioms Eggshell.Synapses.IndexedBindings.Origin.same_source
#print axioms Eggshell.Synapses.IndexedBindings.Origin.same_database
#print axioms Eggshell.Synapses.IndexedBindings.Origin.only_admitted_owner

def main (args : List String) : IO Unit := do
  let [settings] := args | throw (IO.userError "one paired diagnostic settings file")
  Eggshell.Research.BatchedBindingsAudit.run (← IO.ofExcept (Json.parse (← IO.FS.readFile (.mk settings)) >>=
    fromJson? (α := Eggshell.Research.BatchedBindingsAudit.Settings)))
