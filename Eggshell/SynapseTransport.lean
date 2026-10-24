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
  document : Document
  located : Array Located
  outputs : Array (LocatedOutput document)

structure Observation where
  database : String
  owner : String
  work : String
  occurrence : Occurrence
  age : ObservationAge.Assessment
  metadataFailure : Option String := none
  deriving ToJson

structure Plan where
  results : Array Recommend.Result := #[]
  owners : Array LocatedOwner := #[]
  documents : Array Document := #[]
  rows : Array Read := #[]
  unsupported : Nat := 0
  unlocatedFileOwners : Nat := 0
  observations : Array Observation := #[]

def Plan.complete (plan : Plan) : Bool := plan.results.all (·.complete)

def Plan.ranges (plan : Plan) : List (Value × List (Nat × Nat × Nat)) :=
  plan.owners.toList.map fun owner =>
    (owner.owner.relation, (owner.located.toList.filterMap fun located =>
      if located.source.file?.isNone then none else some
      (located.offer.priority, located.row.binding.first, located.row.binding.limit)).eraseDups)

structure OutputRange where
  priority : Nat
  first : Nat
  limit : Nat
  path : Option (List JsonScalars.Segment)
  deriving BEq

def LocatedOwner.originalRanges (owner : LocatedOwner) : Array (Range × OutputRange) := Id.run do
  let raw := owner.document.source.getD ""
  let json := JsonScalars.prepare? raw
  return owner.located.filterMap fun located => do
    let .original _ := located.source.subject | none
    some (located.source,{
      priority := located.offer.priority
      first := located.row.binding.first
      limit := located.row.binding.limit
      path := (json.bind (·.cover? located.row.binding.first located.row.binding.limit)).map (·.path)})

def Plan.outputRanges (plan : Plan) : List (Value × List OutputRange) := Id.run do
  let mut originals : Std.HashMap Range (Value × OutputRange) := {}
  for owner in plan.owners do
    for (source,range) in owner.originalRanges do
      if (originals[source]?).all (fun prior => range.priority < prior.2.priority) then
        originals := originals.insert source (owner.owner.relation,range)
  return plan.owners.toList.map fun owner =>
    let shared := originals.toArray.filterMap fun (_,origin,range) =>
      if origin == owner.owner.relation then some range else none
    let shared := shared.qsort fun a b => if a.first == b.first then a.limit < b.limit else a.first < b.first
    (owner.owner.relation, ((owner.outputs.toList.map fun located =>
      ({priority := located.offer.priority,first := located.fragment.binding.first
        limit := located.fragment.binding.limit,path := located.fragment.address.map (·.path)} : OutputRange)) ++
      shared.toList).eraseDups)

/-- Stored original rows are the only source of transport coordinates.
Neither a graph hint nor its priority may invent a range or an owner. -/
def build (prepared : Array Recommend.Prepared) (answers : Array (String × Nat))
    (owners : Array Owner) (query : String) (deadline : Nat) : IO Plan := do
  let mut plan : Plan := {}
  let assessedUnixMs ← ObservationAge.now
  for source in prepared do
    let consumers := owners.flatMap fun owner =>
      if owner.database != source.source.head.identity then #[] else
      let priorities := answers.filterMap fun (key,priority) =>
        if key == Persistence.selectionKey owner.original.relation then some priority else none
      (Provenance.identities owner.original).flatMap fun occurrence =>
        priorities.map fun priority => (occurrence,priority)
    plan := {plan with results := plan.results.push (← source.collect answers query deadline {} consumers)}
  let offers := plan.results.flatMap (·.admitted)
  if offers.isEmpty then return plan
  for owner in owners do
    let .ok document := owner.document | plan := {plan with unsupported := plan.unsupported+1}; continue
    let recorded := recordedRows owner.database document
    let context := ObservationContext.prepare? document
    let wanted := (offers.toList.filterMap (·.target.source?)).eraseDups.toArray
    let originalRows := wanted.filterMap fun source => context.bind (·.bindSource? owner.database source)
    let rows := recorded.toOption.getD #[] ++ originalRows
    let located := Recommend.locate offers rows
    let outputs := context.map (Recommend.locateOutputsUsing offers owner.database) |>.getD #[]
    -- Metadata is fetched only for offered native origins, once per occurrence,
    -- with a fixed cap and the existing request deadline. It cannot block or
    -- filter the historical body when unavailable, expired, or clock-skewed.
    if !located.isEmpty || !outputs.isEmpty then
      for occurrence in document.occurrences do
        if plan.observations.any (fun prior => prior.database == owner.database &&
            prior.owner == document.owner && prior.occurrence == occurrence) then continue
        let (receivedUnixMs,metadataFailure) ←
          if plan.observations.size ≥ 256 || (← IO.monoMsNow) ≥ deadline then
            pure (none,some "metadata-budget")
          else if let some source := prepared.find? (·.source.head.identity == owner.database) then
            try
              let origin ← Provenance.lookup? source.source owner.original occurrence
              pure (origin.bind (·.receivedUnixMs),if origin.isNone then some "unrecorded" else none)
            catch _ => pure (none,some "metadata-unverified")
          else pure (none,some "source-unavailable")
        plan := {plan with observations := plan.observations.push {
          database := owner.database,owner := document.owner,work := document.work,occurrence
          age := ObservationAge.assess assessedUnixMs receivedUnixMs,metadataFailure}}
    plan := {plan with
      documents := plan.documents.push document
      rows := plan.rows ++ rows
      unlocatedFileOwners := plan.unlocatedFileOwners +
        if !document.files.isEmpty && recorded.toOption.isNone then 1 else 0
      owners := plan.owners.push ⟨owner.original,document,located,outputs⟩}
  return plan

def Plan.receipt (plan : Plan) (text : String) : Json :=
  let delivery := Extraction.presented text plan.documents plan.rows
  let originals := ((plan.results.flatMap (·.admitted)).toList.filterMap fun offer => do
    let source ← offer.target.source?
    let .original _ := source.subject | none
    some source).eraseDups.toArray
  Json.mkObj [
    ("complete", toJson plan.complete), ("unsupportedOwners", toJson plan.unsupported),
    ("unlocatedFileOwners",toJson plan.unlocatedFileOwners),
    ("observationAges",toJson plan.observations),
    ("inputs", toJson (plan.results.map Recommend.Result.receipt)),
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
            located.offer.identity == offer.identity && delivery.coversBinding located.fragment.binding
      Json.mkObj [("offer", offer.json), ("bodyDelivered", toJson delivered)]))]

end Eggshell.Synapses.Transport
