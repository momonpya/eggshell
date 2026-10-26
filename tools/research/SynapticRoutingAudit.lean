import Eggshell.SynapticRouting
import Eggshell.Handoff
open Lean Eggshell Eggshell.Synapses

private def read (path : String) : IO Json := do
  IO.ofExcept (Json.parse (← IO.FS.readFile (.mk path)))

private def offers (values : Array Recommend.Offer) : Array String :=
  (values.map (fun offer => offer.json.compress)).qsort (· < ·)

/-- Compile a single fixed native graph and compare integer traversal with the
recorded independent complete walk. Full preparation is explicitly measured,
outside the query clock; this is not a product-resident-cache benchmark. -/
def main (args : List String) : IO Unit := do
  let [sourcePath,domainPath,promptPath,referencePath,outputPath] := args |
    throw (IO.userError "SynapticRoutingAudit SOURCE DOMAIN PROMPT WALK NEW-REPORT")
  unless !(← (System.FilePath.mk outputPath).pathExists) do throw (IO.userError "keep earlier routing audit")
  let source ← DB.PageMap.pin (.mk sourcePath)
  let prepared ← Recommend.prepare source true
  let some shared := prepared.shared | throw (IO.userError "shared view unavailable")
  let domain := (← read domainPath).getObjValD "data"
  let ranking ← IO.ofExcept (domain.getObjValAs? (Array String) "nominated")
  let hydrated ← IO.ofExcept (domain.getObjValAs? (Array String) "hydrated")
  let answers := ranking.mapIdx fun priority owner => (owner,priority)
  let nodeReader ← Persistence.Store.NodeReader.new source
  let mut consumers := #[]
  for entry in ← Build.entries source do
    let document ← Build.document nodeReader entry.id
    if !hydrated.contains document.owner then continue
    if let some (_,priority) := answers.find? (·.1 == document.owner) then
      consumers := consumers ++ document.occurrences.map (·,priority)
  let query := Sha256.hex (← IO.FS.readFile (.mk promptPath)).toUTF8
  let mut roots := answers.map fun (owner,priority) =>
    (Index.Key.answer shared.manifest.source.identity owner,priority)
  roots := roots ++ consumers.map (fun (consumer,priority) => (Index.Key.consumer consumer,priority))
  if prepared.usage.isSome && digest query then roots := roots.push (.query query,0)
  let preparationStarted ← IO.monoMsNow
  let mut facts ← Index.allFacts shared.index
  unless facts.all (fun fact => shared.manifest.scope.accepts fact &&
      Index.belongs shared.manifest.source.identity fact) do throw (IO.userError "shared scope changed")
  if let some usage := prepared.usage then
    let privateFacts ← Index.allFacts usage.index
    unless privateFacts.all (fun fact => usage.manifest.scope.accepts fact &&
        Index.belongs usage.manifest.source.identity fact) do throw (IO.userError "private scope changed")
    facts := facts ++ privateFacts
  let readMs := (← IO.monoMsNow)-preparationStarted
  let compilationStarted ← IO.monoMsNow
  let arena ← IO.ofExcept (Routing.Arena.prepare facts)
  let compilationMs := (← IO.monoMsNow)-compilationStarted
  let mut trials := #[]
  let mut actual := #[]
  for _ in [:3] do
    let started ← IO.monoMsNow
    let walked ← arena.walk roots (started+500) (1024*1024)
    let elapsed := (← IO.monoMsNow)-started
    let missing := walked.offers.foldl (fun ranges offer => match offer.fact with
      | .used value => if value.kind == .omittedThenRead || value.kind == .omittedThenConsumed then
          ranges.insert value.source else ranges
      | _ => ranges) ({} : Std.HashSet Range)
    let retained := walked.offers.filter fun offer => match offer.fact with
      | .used value => value.kind != .deliveredThenCited || !missing.contains value.source
      | _ => true
    unless walked.complete do throw (IO.userError "compiled traversal exceeded its query budget")
    let normalized := offers retained
    if !actual.isEmpty && actual != normalized then throw (IO.userError "compiled traversal changed between runs")
    actual := normalized
    trials := trials.push (Json.mkObj [
      ("elapsedMs",toJson elapsed),("complete",toJson walked.complete),
      ("nodes",toJson walked.nodes),("arcs",toJson walked.arcs),("offers",toJson retained.size)])
  let reference ← read referencePath
  let referenceTrials ← IO.ofExcept (reference.getObjValAs? (Array Json) "trials")
  let some referenceTrial := referenceTrials.find? (fun trial =>
      (trial.getObjValAs? String "label").toOption == some "full-diagnostic") |
    throw (IO.userError "independent complete reference missing")
  let expectedResult := referenceTrial.getObjValD "result"
  unless (expectedResult.getObjValAs? Bool "complete").toOption == some true do
    throw (IO.userError "reference is incomplete")
  let expected ← IO.ofExcept (expectedResult.getObjValAs? (Array Json) "offers")
  let expected := (expected.map Json.compress).qsort (· < ·)
  unless actual == expected do throw (IO.userError s!"reference offers differ: {actual.size}/{expected.size}")
  unless (← DB.PageMap.pin source.directory).head == source.head do
    throw (IO.userError "source changed during read-only audit")
  let report := Json.mkObj [
    ("source",toJson source.head),("index",toJson shared.index.head),
    ("sourceFacts",toJson facts.size),("nodes",toJson arena.keys.size),
    ("targets",toJson arena.targets.size),
    ("arcs",toJson (arena.adjacency.foldl (fun count arcs => count+arcs.size) 0)),
    ("factReadAndValidationMs",toJson readMs),("compilationMs",toJson compilationMs),
    ("trials",toJson trials),("independentReferenceExact",toJson true),
    ("offerDigest",toJson (Index.contentKey actual)),
    ("referenceElapsedMs",referenceTrial.getObjValD "elapsedMs"),
    ("sourceWrites",toJson (0 : Nat)),("answeringModelCalls",toJson (0 : Nat)),
    ("productHookConnected",toJson false),("productionAdoption",toJson false),
    ("scope",toJson "fixed snapshot; resident prototype; segmented persistence not implemented")]
  IO.FS.writeFile (.mk outputPath) (report.pretty ++ "\n")
  IO.println report.compress
