import Eggshell.SynapticRoutingStore
import Eggshell.Handoff
open Lean Eggshell Eggshell.Synapses Eggshell.Synapses.Routing

example (edge : Consumption) :
    toJson (Fact.consumed edge) = toJson (Bundles.Reason.consumed edge) := rfl
example (usage : Usage) :
    toJson (Fact.used usage) = toJson (Bundles.Reason.used usage) := rfl
example (group : Group) :
    toJson (Store.QuotedCause.quoted group) = toJson (Bundles.Reason.quoted group) := rfl

private def read (path : String) : IO Json := do
  IO.ofExcept (Json.parse (← IO.FS.readFile (.mk path)))

private def emit (root : System.FilePath) (value : Json) : IO Unit := do
  IO.FS.withFile (root / "events.jsonl") .append fun handle => handle.putStr (value.compress ++ "\n")
  IO.println value.compress

private def ordered (hints : Array Store.Hint) : Array String := Id.run do
  let missing := hints.foldl (fun sources hint =>
    if hint.kind == 3 || hint.kind == 4 then
      hint.target.source?.map sources.insert |>.getD sources
    else sources) ({} : Std.HashSet Range)
  return (hints.filter fun hint =>
    hint.kind != 5 || hint.target.source?.all (fun source => !missing.contains source)).map
      (fun hint => hint.json.compress)

/-- Build a streaming, publication-bound topology view and reopen it without
the compiler's heap. Compare disk traversal with the earlier independent
complete source walk. Neither the model nor the product hook is called. -/
def main (args : List String) : IO Unit := do
  let [rootPath,sourcePath,domainPath,promptPath,referencePath] := args |
    throw (IO.userError "SynapticRoutingStoreAudit ROOT SOURCE DOMAIN PROMPT REFERENCE")
  let root := System.FilePath.mk rootPath
  unless root.isAbsolute && !(← (root / "store-report.json").pathExists) do
    throw (IO.userError "absolute root and unused report required")
  let source ← DB.PageMap.pin (.mk sourcePath)
  let prepared ← Recommend.prepare source true
  let some shared := prepared.shared | throw (IO.userError "shared basis unavailable")
  let mut construction := #[]
  for (label,basis) in #[ ("shared",some shared),("usage",prepared.usage)] do
    let some basis := basis | continue
    let path := root / (label ++ "-view")
    unless !(← path.pathExists) do throw (IO.userError "keep earlier projection build")
    let started ← IO.monoMsNow
    emit root (Json.mkObj [("phase",toJson "build-start"),("scope",toJson label)])
    let built ← Store.build basis path
    let result := Json.mkObj [("scope",toJson label),("elapsedMs",toJson ((← IO.monoMsNow)-started)),
      ("head",toJson built.snapshot.head),("manifest",toJson built.manifest)]
    construction := construction.push result
    emit root (result.setObjVal! "phase" (toJson "build-end"))
  -- Open fresh PageMap readers. No Arena, all-facts array or builder cache
  -- is retained as the query's resident database.
  let some sharedView ← Store.open? shared (root / "shared-view") |
    throw (IO.userError "shared projection unavailable after reopening")
  let usageView ← prepared.usage.mapM fun basis => do
    let some view ← Store.open? basis (root / "usage-view") |
      throw (IO.userError "private projection unavailable after reopening")
    pure view
  if let some usage := prepared.usage then
    unless (← Store.open? usage (root / "shared-view")).isNone do
      throw (IO.userError "shared projection admitted as private usage")
    unless (← Store.open? shared (root / "usage-view")).isNone do
      throw (IO.userError "private usage admitted as shared projection")
  let unsealed ← DB.PageMap.create (root / "unsealed-view") "unsealed-projection-fixture"
  unless (← Store.open? shared unsealed.directory).isNone do
    throw (IO.userError "unsealed projection became readable")
  let sample : Store.Arc := ⟨String.ofList (List.replicate 64 'a'),0,some 3,#[1],#[2]⟩
  unless (← Store.decode (Store.encode sample)) == sample do throw (IO.userError "arc roundtrip failed")
  let rejected ← try
    let _ ← Store.decode (Store.encode sample |>.push 0)
    pure false
    catch _ => pure true
  unless rejected do throw (IO.userError "trailing projection bytes accepted")
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
  let reference ← read referencePath
  let referenceTrials ← IO.ofExcept (reference.getObjValAs? (Array Json) "trials")
  let some referenceTrial := referenceTrials.find? (fun trial =>
      (trial.getObjValAs? String "label").toOption == some "full-diagnostic") |
    throw (IO.userError "independent complete reference missing")
  let expectedResult := referenceTrial.getObjValD "result"
  unless (expectedResult.getObjValAs? Bool "complete").toOption == some true do
    throw (IO.userError "reference is incomplete")
  let expected ← IO.ofExcept (expectedResult.getObjValAs? (Array Json) "offers")
  let expected := expected.map Json.compress
  let mut reasons : Std.HashMap String (String × Option Group) := {}
  let coquotedSource ← IO.mkRef (none : Option Range)
  for basis in #[some shared,prepared.usage] do
    let some basis := basis | continue
    reasons ← basis.index.foldRange ⟨"fact:","fact;"⟩ (fun reasons row => do
      let some bytes := row.2 | return reasons
      let fact ← Index.decode (α := Fact) bytes
      if let .coquoted _ source := fact then
        if (← coquotedSource.get).isNone then coquotedSource.set (some source)
      let some reason := Bundles.reason? fact | return reasons
      let group := match reason with | .quoted group => some group | _ => none
      return reasons.insert (Index.contentKey fact) (Index.contentKey reason,group)) reasons
  let capped ← sharedView.walk roots ((← IO.monoMsNow)+30000) {arcs := 1}
  unless !capped.complete do throw (IO.userError "projection arc cap was ignored")
  let mut trials := #[]
  for budget in [500,1500,5000] do
    let started ← IO.monoMsNow
    let deadline := started+budget
    let found ← Store.walk sharedView usageView roots deadline
    let elapsed := (← IO.monoMsNow)-started
    let complete := found.complete
    let actual := ordered found.hints
    let same := complete && actual == expected
    if complete && !same then throw (IO.userError s!"projection differs: {actual.size}/{expected.size}")
    for hint in found.hints do
      let some (key,group) := reasons[hint.evidence]? | throw (IO.userError "projection reason has no source")
      unless hint.reasonKey == key && hint.group == group do
        throw (IO.userError "projection changed the grouping used by delivery selection")
    let result := Json.mkObj [("budgetMs",toJson budget),("elapsedMs",toJson elapsed),
      ("complete",toJson complete),("referenceExact",toJson same),
      ("nodes",toJson found.nodes),("arcs",toJson found.arcs),
      ("payloadBytes",toJson found.bytes),("hints",toJson actual.size)]
    trials := trials.push result
    emit root (result.setObjVal! "phase" (toJson "walk"))
  unless trials.any (fun trial => (trial.getObjValAs? Bool "referenceExact").toOption == some true) do
    throw (IO.userError "disk traversal never completed within the diagnostic budgets")
  -- Force a positive usage→shared coquotation path. Existing private queries
  -- need not match this topic, so they alone cannot test reader dispatch.
  let some quoted := ← coquotedSource.get | throw (IO.userError "shared coquotation fixture absent")
  let fixtureQuery := Index.contentKey ("private-usage-projection-fixture" : String)
  let fixtureUsage : Usage := {
    event := {occurrence := ⟨"synthetic-private-usage","fixture-turn","fixture-use"⟩,ordinal := 1}
    query := fixtureQuery
    source := quoted
    kind := .omittedThenRead}
  let fixtureIndex ← DB.PageMap.create (root / "fixture-usage-index") "synthetic-private-usage"
  let fixtureManifest : Index.Manifest := ⟨source.head,Index.implementation,.usage,1⟩
  let (_,_,_) ← DB.PageMap.withWriter fixtureIndex fun writer => do
    let _ ← Index.insert writer source.head.identity .usage (.used fixtureUsage)
    writer.put "manifest" (some (← Index.checkedBytes fixtureManifest))
  let fixtureBasis : Index.Reader := ⟨← DB.PageMap.pin fixtureIndex.directory,fixtureManifest⟩
  let fixtureView ← Store.build fixtureBasis (root / "fixture-usage-view")
  let oldUsage ← Recommend.collect shared (some fixtureBasis) #[] #[] fixtureQuery ((← IO.monoMsNow)+30000)
    {requests := 100000,facts := 100000,bytes := 64*1024*1024}
  let newUsage ← Store.walk sharedView (some fixtureView) #[(.query fixtureQuery,0)] ((← IO.monoMsNow)+5000)
  unless oldUsage.complete && newUsage.complete &&
      ordered newUsage.hints == oldUsage.admitted.map (fun offer => offer.json.compress) &&
      newUsage.hints.any (·.kind == 2) do
    throw (IO.userError "private usage did not retain shared coquotation closure and order")
  unless (← DB.PageMap.pin source.directory).head == source.head do
    throw (IO.userError "source changed during projection audit")
  let report := Json.mkObj [("construction",toJson construction),("trials",toJson trials),
    ("referenceOfferDigest",toJson (Index.contentKey expected)),
    ("batchFactLimit",toJson (1024 : Nat)),("batchByteLimit",toJson (8*1024*1024 : Nat)),
    ("wholeFactArenaRetained",toJson false),
    ("sourceWrites",toJson (0 : Nat)),("scopeIsolation",toJson true),
    ("unsealedViewRejected",toJson true),("trailingArcBytesRejected",toJson true),
    ("deliveryGroupingPreserved",toJson true),
    ("offerOrderPreserved",toJson true),
    ("syntheticPrivateUsageToSharedCoquotation",Json.mkObj [
      ("referenceExact",toJson true),("hints",toJson newUsage.hints.size),
      ("sharedCoquotationHints",toJson ((newUsage.hints.filter (·.kind == 2)).size))]),
    ("arcLimitEnforced",toJson true),("deltaPublicationConnected",toJson false),
    ("productHookConnected",toJson false),("answeringModelCalls",toJson (0 : Nat)),
    ("productionAdoption",toJson false)]
  IO.FS.writeFile (root / "store-report.json") (report.pretty ++ "\n")
  IO.println report.compress
