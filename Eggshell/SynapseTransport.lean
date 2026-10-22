module

public import Eggshell.SynapseRecommend

@[expose] public section

namespace Eggshell.Synapses.Transport
open Lean Persistence.Store _root_.Eggshell.Synapses.Extraction Recommend

structure Owner where
  database : String
  original : OutcomeEdge
  provenance : List SourceEvidence.Record

def Owner.document (owner : Owner) : Except String Document := do
  return {
    owner := Persistence.selectionKey owner.original.relation
    work := Persistence.selectionKey owner.original.work
    workText := text? owner.original.work
    source := text? owner.original.outcome
    native := owner.original.observations.any
      (Relation.observesOutcomeWork owner.original.outcome owner.original.work)
    occurrences := Provenance.identities owner.original
    files := ← fileMap (owner.provenance.toArray.map toJson) }

structure LocatedOwner where
  owner : OutcomeEdge
  located : Array Located

structure Plan where
  results : Array Recommend.Result := #[]
  owners : Array LocatedOwner := #[]
  documents : Array Document := #[]
  rows : Array Read := #[]
  unsupported : Nat := 0

def Plan.complete (plan : Plan) : Bool := plan.results.all (·.complete)

def Plan.ranges (plan : Plan) : List (Value × List (Nat × Nat × Nat)) :=
  plan.owners.toList.map fun owner =>
    (owner.owner.relation, (owner.located.toList.map fun located =>
      (located.offer.priority, located.row.binding.first, located.row.binding.limit)).eraseDups)

/-- Stored original rows are the only source of transport coordinates.
Neither a graph hint nor its priority may invent a range or an owner. -/
def build (prepared : Array Recommend.Prepared) (answers : Array (String × Nat))
    (owners : Array Owner) (query : String) (deadline : Nat) : IO Plan := do
  let mut plan : Plan := {}
  for source in prepared do
    plan := {plan with results := plan.results.push (← source.collect answers query deadline)}
  let offers := plan.results.flatMap (·.admitted)
  if offers.isEmpty then return plan
  for owner in owners do
    let .ok document := owner.document | plan := {plan with unsupported := plan.unsupported+1}; continue
    let .ok rows := recordedRows owner.database document | plan := {plan with unsupported := plan.unsupported+1}; continue
    plan := {plan with
      documents := plan.documents.push document
      rows := plan.rows ++ rows
      owners := plan.owners.push ⟨owner.original, Recommend.locate offers rows⟩}
  return plan

def Plan.receipt (plan : Plan) (text : String) : Json :=
  let delivery := Extraction.presented text plan.documents plan.rows
  Json.mkObj [
    ("complete", toJson plan.complete), ("unsupportedOwners", toJson plan.unsupported),
    ("inputs", toJson (plan.results.map Recommend.Result.receipt)),
    ("offers", toJson (plan.results.flatMap fun result => result.admitted.map fun offer =>
      Json.mkObj [("offer", offer.json), ("bodyDelivered", toJson (covered offer.source delivery.ranges))]))]

end Eggshell.Synapses.Transport
