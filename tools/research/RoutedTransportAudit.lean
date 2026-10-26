import Eggshell.SynapseBundles
open Lean Eggshell Eggshell.Synapses

private def read (path : String) : IO Json := do
  IO.ofExcept (Json.parse (← IO.FS.readFile (.mk path)))

private def emit (value : Json) : IO Unit := do
  IO.println value.compress
  (← IO.getStdout).flush

private def place (basis : Index.Reader) (origin : System.FilePath) : IO Unit := do
  let destination := basis.index.directory / "routing"
  if !(← destination.pathExists) then IO.FS.rename origin destination
  let some _ ← Routing.Store.open? basis destination |
    throw (IO.userError "verified routing image does not match original basis")

/-- No model, hook launcher or task-specific evidence is sent to the product.
The recorded nomination and admitted owner domain are replayed unchanged. -/
def main (args : List String) : IO Unit := do
  let [sourcePath,domainPath,promptPath,referencePath,outputPath] := args |
    throw (IO.userError "RoutedTransportAudit SOURCE DOMAIN PROMPT REFERENCE NEW-REPORT")
  unless !(← (System.FilePath.mk outputPath).pathExists) do throw (IO.userError "keep previous transport result")
  let core := System.FilePath.mk "/Users/ovm/.codex/experiments/eggshell/routed-transport-20261026/checkout/Eggshell"
  let embedded ← #["SynapseRecommend.lean","ObservationContext.lean","JsonScalars.lean",
    "SynapseTransport.lean","SynapseUsage.lean","SynapticTransport.lean","SynapticRoutingStore.lean"].mapM
      (fun name => return (← IO.FS.readFile (core / System.FilePath.mk name)).toUTF8)
  unless Recommend.implementation == Blake3.hex (Blake3.digest "eggshell.observation-recommendation".toUTF8 embedded.toList) do
    throw (IO.userError "cached implementation identity omitted changed include_str bytes")
  let source ← DB.PageMap.pin (.mk sourcePath)
  let prepared ← Recommend.prepare source true
  let some shared := prepared.shared | throw (IO.userError "shared original index unavailable")
  let parent := System.FilePath.mk "/Users/ovm/.codex/experiments/eggshell/synaptic-routing-store-20261026/with-order"
  place shared (parent / "shared-view")
  if let some usage := prepared.usage then place usage (parent / "usage-view")
  let domain := (← read domainPath).getObjValD "data"
  let ranking ← IO.ofExcept (domain.getObjValAs? (Array String) "nominated")
  let hydrated ← IO.ofExcept (domain.getObjValAs? (Array String) "hydrated")
  let answers := ranking.mapIdx fun priority owner => (owner,priority)
  let reader ← Persistence.Store.NodeReader.new source
  let mut owners : Array Transport.Owner := #[]
  for entry in ← Build.entries source do
    let edge ← reader.outcome (← reader.locateOutcome entry.id)
    if !hydrated.contains (Persistence.selectionKey edge.relation) then continue
    owners := owners.push ⟨source.head.identity,edge,← reader.sources entry.id⟩
  let consumers := owners.flatMap fun owner =>
    let priorities := answers.filterMap fun (key,priority) =>
      if key == Persistence.selectionKey owner.original.relation then some priority else none
    (Provenance.identities owner.original).flatMap fun occurrence =>
      priorities.map (occurrence,·)
  let query := Sha256.hex (← IO.FS.readFile (.mk promptPath)).toUTF8
  emit (Json.mkObj [("phase",toJson "graph"),("owners",toJson owners.size)])
  let started ← IO.monoMsNow
  let found ← Routed.collect prepared answers query (started+5000) consumers
  let graphMs := (← IO.monoMsNow)-started
  unless found.complete && found.failure.isNone do throw (IO.userError "routed graph did not complete")
  let reference ← read referencePath
  let trials ← IO.ofExcept (reference.getObjValAs? (Array Json) "trials")
  let some trial := trials.find? (fun trial => (trial.getObjValAs? String "label").toOption == some "full-diagnostic") |
    throw (IO.userError "independent reference missing")
  let expected ← IO.ofExcept ((trial.getObjValD "result").getObjValAs? (Array Json) "offers")
  unless found.admitted.map (fun hint => hint.json.compress) == expected.map Json.compress do
    throw (IO.userError "ordered hints differ from full walk")
  emit (Json.mkObj [("phase",toJson "bind"),("graphMs",toJson graphMs),("hints",toJson found.admitted.size)])
  let started ← IO.monoMsNow
  let plan ← Transport.build #[prepared] answers owners query (started+30000)
  let bindingMs := (← IO.monoMsNow)-started
  unless plan.complete do throw (IO.userError "transport graph incomplete")
  emit (Json.mkObj [("phase",toJson "bundles"),("bindingMs",toJson bindingMs)])
  let started ← IO.monoMsNow
  let demands := Bundles.demands plan
  let projected := Bundles.project plan
  emit (Json.mkObj [("phase",toJson "projected"),("demands",toJson demands.size),("projected",toJson projected.size)])
  let projectionMs := (← IO.monoMsNow)-started
  let bindings := plan.owners.flatMap fun owner => owner.located.map (·.row.binding)
  let report := Json.mkObj [
    ("source",toJson source.head),("graphMs",toJson graphMs),("bindingMs",toJson bindingMs),
    ("projectionMs",toJson projectionMs),("complete",toJson plan.complete),
    ("orderedReferenceExact",toJson true),("embeddedIdentityExact",toJson true),("hints",toJson found.admitted.size),
    ("owners",toJson owners.size),("located",toJson bindings.size),
    ("outputWitnesses",toJson (plan.owners.foldl (fun n owner => n+owner.outputs.size) (0 : Nat))),
    ("demands",toJson demands.size),("projected",toJson projected.size),
    ("originalRanges",toJson plan.outputRanges.length),
    ("routingDirectories",toJson (#[some shared,prepared.usage].filterMap id |>.map fun basis =>
      (basis.index.directory / "routing").toString)),
    ("sourceWrites",toJson (0 : Nat)),("answeringModelCalls",toJson (0 : Nat)),
    ("actualHookConnected",toJson false),("selectorChecked",toJson false)]
  unless (← DB.PageMap.pin source.directory).head == source.head do throw (IO.userError "original DB changed")
  IO.FS.writeFile (.mk outputPath) report.pretty
  emit report
