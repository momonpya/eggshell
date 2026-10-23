module
public import Eggshell.SynapseTransport
@[expose] public section

namespace Eggshell.Synapses.Bundles
open Lean Persistence.Store Recommend

inductive Reason where
  | quoted (group : Group)
  | consumed (edge : Consumption)
  | used (usage : Usage)
  deriving BEq, Hashable, ToJson

def reason? : Fact → Option Reason
  | .supports value => some (.quoted (.claim value.claim))
  | .coquoted group _ => some (.quoted group)
  | .consumed value => some (.consumed value)
  | .used value => some (.used value)
  | .read _ => none

structure Demand where
  reason : Reason
  offers : Array Offer
  nonempty : offers.isEmpty = false
  same : offers.all (fun offer => reason? offer.fact == some reason) = true

def Demand.check? (reason : Reason) (offers : Array Offer) : Option Demand :=
  if nonempty : offers.isEmpty = false then
    if same : offers.all (fun offer => reason? offer.fact == some reason) = true then
      some ⟨reason,offers,nonempty,same⟩ else none
  else none

def Demand.sources (demand : Demand) : Array Range :=
  (demand.offers.toList.map (·.source)).eraseDups.toArray

def Demand.priority (demand : Demand) : Nat :=
  demand.offers.foldl (fun priority offer => min priority offer.priority)
    ((demand.offers[0]?).map (·.priority) |>.getD 0)

def Demand.key (demand : Demand) : String := Index.contentKey demand.reason

def Demand.kind (demand : Demand) : String := match demand.reason with
  | .quoted (.claim _) => "claim"
  | .quoted (.answer ..) => "answer"
  | .consumed _ => "consumption"
  | .used usage => usage.kind.label

def demands (plan : Transport.Plan) : Array Demand := Id.run do
  let mut groups : Std.HashMap Reason (Array Offer) := {}
  for offer in plan.results.flatMap (·.admitted) do
    let some reason := reason? offer.fact | continue
    groups := groups.insert reason (groups[reason]?.getD #[] |>.push offer)
  return (groups.toArray.filterMap fun (reason,offers) => Demand.check? reason offers).qsort fun a b =>
    if a.priority == b.priority then a.key < b.key else a.priority < b.priority

/-- The original owner and every scalar row remain attached to their range.
No graph relation is sufficient to invent a source binding. -/
structure Bound (source : Range) where
  original : OutcomeEdge
  owner : String
  ownerExact : owner = Persistence.selectionKey original.relation
  rows : Array Read
  valid : rows.all Read.valid = true
  inside : rows.all (fun row => source.contains row.source) = true
  owned : rows.all (fun row => row.binding.owner == owner) = true
  complete : covered source (rows.map (·.source)) = true

def Bound.spans (bound : Bound source) : List (Nat × Nat) :=
  (bound.rows.toList.map fun row => (row.binding.first,row.binding.limit)).eraseDups

structure Member where
  source : Range
  choices : Array (Bound source)
  located : choices.isEmpty = false

structure Projected where
  demand : Demand
  members : Array Member
  sourcesExact : members.map (·.source) = demand.sources

structure OwnerRows where
  original : Transport.LocatedOwner
  key : String
  keyExact : key = Persistence.selectionKey original.owner.relation

def bind? (source : Range) (owner : OwnerRows) : Option (Bound source) :=
  let rows := (owner.original.located.toList.filterMap fun located =>
    if located.offer.source == source then some located.row else none).eraseDups.toArray
  if valid : rows.all Read.valid = true then
    if inside : rows.all (fun row => source.contains row.source) = true then
      if owned : rows.all (fun row => row.binding.owner == owner.key) = true then
        if complete : covered source (rows.map (·.source)) = true then
          some ⟨owner.original.owner,owner.key,owner.keyExact,rows,valid,inside,owned,complete⟩ else none
      else none
    else none
  else none

def project? (owners : Array OwnerRows) (demand : Demand) : Option Projected := do
  let members ← demand.sources.mapM fun source => do
    let choices := owners.filterMap (bind? source)
    if located : choices.isEmpty = false then some (Member.mk source choices located) else none
  if sourcesExact : members.map (·.source) = demand.sources then
    some ⟨demand,members,sourcesExact⟩ else none

def project (plan : Transport.Plan) : Array Projected :=
  let owners := plan.owners.map fun original =>
    (⟨original,Persistence.selectionKey original.owner.relation,rfl⟩ : OwnerRows)
  (demands plan).filterMap (project? owners)

theorem projected_sources_unchanged (projected : Projected) :
    projected.members.map (·.source) = projected.demand.sources := projected.sourcesExact

def receipt (plan : Transport.Plan) (projected : Array Projected) (text : String) : Json :=
  let shown := Extraction.presented text plan.documents plan.rows
  (plan.receipt text).setObjVal! "bundles" (toJson ((demands plan).map fun demand =>
    Json.mkObj [("identity",toJson demand.key), ("kind",toJson demand.kind),
      ("priority",toJson demand.priority), ("members",toJson demand.sources),
      ("located",toJson (projected.any (·.demand.key == demand.key))),
      ("bodyDelivered",toJson (demand.sources.all fun source => covered source shown.ranges))]))

end Eggshell.Synapses.Bundles
