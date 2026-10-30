import Eggshell.Handoff
open Lean Eggshell Eggshell.Synapses

private def read (path : System.FilePath) : IO Json :=
  IO.FS.readFile path >>= fun text => IO.ofExcept (Json.parse text)
private def check (ok : Bool) (message : String) : IO Unit :=
  unless ok do throw (IO.userError message)
private def array (value : Json) (field : String) : IO (Array Json) :=
  IO.ofExcept (value.getObjValAs? _ field)

private def owner (reader : Persistence.Store.NodeReader source) (name : String) : IO OutcomeEdge := do
  check (name.startsWith "v") "non-native owner locator"
  let ids ← Persistence.Store.getIds source.get ("owner:" ++ (name.drop 1).toString)
  let live ← ids.filterM fun id => return (← source.get (Persistence.Store.key "member" id)).isSome
  let [id] := live | throw (IO.userError "missing or ambiguous recorded owner")
  let original ← reader.outcome (← reader.locateOutcome id)
  check (Persistence.selectionKey original.relation == name) "hash locator crossed native owner identity"
  return original

/- Recompute the production root construction from an unchanged recorded
domain, then project each already audited missing-evidence edge in isolation.
This is not observation of the old runtime's queue, a full graph replay,
or a claim that an offer was selected or delivered. -/
def main (args : List String) : IO Unit := do
  let [database,tracePath,signalsPath,destination] := args |
    throw (IO.userError "original DB, recorded-domain trace, frozen signals and fresh output")
  let output := System.FilePath.mk destination
  check (!(← output.pathExists)) "preserve previous root projection"
  let source ← DB.PageMap.pin (.mk database)
  let trace ← read tracePath
  let signals ← read signalsPath
  check (toJson source.head == trace.getObjValD "source" &&
    toJson source.head == signals.getObjValD "source") "root inputs differ from native source"
  let reader ← Persistence.Store.NodeReader.new source
  let mut cached : Std.HashMap String OutcomeEdge := {}
  let mut results := #[]
  for topic in ← array trace "topics" do
    let receipt : System.FilePath := .mk (← IO.ofExcept (topic.getObjValAs? String "receipt"))
    let domain := (← read (receipt / "delivery-domain.json")).getObjValD "data"
    let ranking : Array String ← IO.ofExcept (domain.getObjValAs? _ "nominated")
    let hydrated : Array String ← IO.ofExcept (domain.getObjValAs? _ "hydrated")
    for key in ranking ++ hydrated do
      unless cached.contains key do cached := cached.insert key (← owner reader key)
    let nominated ← ranking.toList.mapM fun key => match cached[key]? with
      | some value => pure value
      | none => throw (IO.userError "recorded nomination was not hydrated")
    let admitted ← hydrated.mapM fun key => match cached[key]? with
      | some value => pure value
      | none => throw (IO.userError "recorded domain was not hydrated")
    let roots := Plugin.synapticRoots (nominated.map (·.relation)) nominated
    let answers := roots.toArray.map fun (edge,priority) => (Persistence.selectionKey edge,priority)
    -- Same occurrence/priority construction used by Transport.build. Only
    -- recorded hydrated owners can contribute native consumer roots here.
    let consumers := admitted.flatMap fun original =>
      let key := Persistence.selectionKey original.relation
      let priorities := answers.filterMap fun (name,priority) => if name == key then some priority else none
      (Provenance.identities original).flatMap fun occurrence => priorities.map (occurrence,·)
    let mut requirements := #[]
    for unit in ← array signals "rows" do
      if unit.getObjValD "topic" != topic.getObjValD "topic" ||
          unit.getObjValD "missing" != toJson true then continue
      let mut edges := #[]
      for encoded in ← array unit "consumed" do
        let edge : Consumption ← IO.ofExcept (fromJson? encoded)
        let fact := Fact.consumed edge
        check fact.valid "recorded consumption evidence is invalid"
        let projected := Routing.project (.consumer edge.consumer) fact
        check ((Index.addresses fact).contains (.consumer edge.consumer)) "fact is not indexed at its consumer"
        let direct := consumers.filter (fun (occurrence,_) => occurrence == edge.consumer)
        let offers := direct.flatMap fun (_,priority) => projected.targets.filterMap fun target =>
          Recommend.Offer.check? target priority fact ⟨Index.contentKey fact,rfl⟩
        let origin : String ← match ← source.get (Provenance.name edge.consumer) with
          | none => throw (IO.userError "consumer lacks native provenance")
          | some bytes => do
            let stored ← Provenance.decode (α := Provenance.Stored) bytes
            check (stored.origin.occurrence == edge.consumer) "consumer metadata crossed occurrence"
            let doc ← Provenance.checkedDocument reader stored.origin
            pure doc.owner
        edges := edges.push (Json.mkObj [
          ("consumer",toJson edge.consumer),("consumerOwner",toJson origin),
          ("term",toJson edge.term),("evidence",toJson (Index.contentKey fact)),
          ("reconstructedDirectConsumerRoots",toJson direct),
          ("productionProjectionTargets",toJson projected.targets),
          ("isolatedEdgeOffers",toJson (offers.map Recommend.Offer.json)),
          ("observedHistoricalQueue",toJson false),("fullGraphReachability",Json.null)])
      requirements := requirements.push (Json.mkObj [("names",unit.getObjValD "names"),
        ("consumption",toJson edges),("supportCount",unit.getObjValD "supportCount"),
        ("coquotedCount",unit.getObjValD "coquotedCount")])
    results := results.push (Json.mkObj [("topic",topic.getObjValD "topic"),
      ("recordedDomain",toJson receipt.toString),("reconstructedAnswers",toJson answers),
      ("reconstructedConsumerRoots",toJson consumers),("requirements",toJson requirements)])
  check ((← DB.PageMap.pin source.directory).head == source.head) "root projection changed source"
  IO.FS.writeFile output (Json.mkObj [("source",toJson source.head),("topics",toJson results),
    ("productionSynapticRootsAndRoutingProjectUsed",toJson true),
    ("observedHistoricalQueue",toJson false),("fullGraphReplayed",toJson false),
    ("actualDeliveryChanged",toJson false),("originalSourceUnchanged",toJson true),
    ("dbOrCacheWrites",toJson (0 : Nat)),("answeringModelCalls",toJson (0 : Nat)),
    ("adopted",toJson false)]).pretty
  IO.println s!"Recomputed native roots and single-edge projections for {results.size} recorded domains"
