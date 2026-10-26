import Eggshell.SynapseBundles
open Lean Eggshell Eggshell.Synapses Eggshell.Synapses.Transport Eggshell.Synapses.Bundles
namespace Eggshell.Research.ReceiptPlanBefore
def receipt (plan : Plan) (text : String) : Json :=
  let delivery := Extraction.presented text plan.documents plan.rows
  let originals := ((plan.results.flatMap (·.admitted)).toList.filterMap fun offer => do
    let source ← offer.target.source?
    let .original _ := source.subject | none
    some source).eraseDups.toArray
  Json.mkObj [
    ("complete", toJson plan.complete), ("unsupportedOwners", toJson plan.unsupported),
    ("unlocatedFileOwners",toJson plan.unlocatedFileOwners),
    ("observationAges",toJson plan.observations),
    ("inputs", toJson (plan.results.map Routed.Result.receipt)),
    ("originalReferences",toJson (originals.map fun source =>
      let bindings := plan.owners.flatMap fun owner => owner.located.filterMap fun located =>
        if located.source == source then some located.row.binding else none
      let origins := bindings.foldl (fun known binding => known.insert binding) ({} : Std.HashSet Binding)
      let origins := origins.toArray.qsort fun a b => (toJson a).compress < (toJson b).compress
      Json.mkObj [
      ("source",toJson source), ("bodyDelivered",toJson (covered source delivery.ranges)),
      ("origins",toJson origins)])),
    ("originalOutputs",toJson (plan.owners.flatMap fun owner => owner.outputs.map fun located =>
      Json.mkObj [
        ("evidence",toJson located.offer.identity), ("binding",toJson located.fragment.binding),
        ("path",toJson (located.fragment.address.map (fun address => JsonScalars.pathJson address.path))),
        ("bodyDelivered",toJson (delivery.coversBinding located.fragment.binding)),
        ("addressDelivered",toJson (located.fragment.address.map (fun address =>
          delivery.coversAddress located.fragment.binding address.path)))])),
    ("offers", toJson (plan.results.flatMap fun result => result.admitted.map fun offer =>
      let delivered := match offer.target with
        | .range source => covered source delivery.ranges
        | .output _ => plan.owners.any fun owner => owner.outputs.any fun located =>
            located.offer.identity == offer.evidence && delivery.coversBinding located.fragment.binding
      Json.mkObj [("offer", offer.json), ("bodyDelivered", toJson delivered)]))]

def bundles (plan : Transport.Plan) (projected : Array Projected) (text : String) : Json :=
  let shown := Extraction.presented text plan.documents plan.rows
  (receipt plan text).setObjVal! "bundles" (toJson ((demands plan).map fun demand =>
    Json.mkObj [("identity",toJson demand.key), ("kind",toJson demand.kind),
      ("priority",toJson demand.priority), ("members",toJson demand.sources),
      ("located",toJson (projected.any (·.demand.key == demand.key))),
      ("bodyDelivered",toJson (demand.sources.all fun source => covered source shown.ranges))]))

end Eggshell.Research.ReceiptPlanBefore
