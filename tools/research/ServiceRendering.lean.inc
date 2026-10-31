structure PendingRendering where
  families : List SharedRangeAdapter.Family
  mandatory : List TransportSlice
  bundles : Array Synapses.AdvisoryBundles.Bundle
  ceiling : Nat × Nat
  cost : List TransportSlice → Nat × Nat
  localPlan : Unit → Option SharedRangeAdapter.RenderChoice
  finish : Option SharedRangeAdapter.RenderChoice → Option Handoff
  captureRanges : Bool
  captureInput : Bool

inductive PreparedRendering where
  | done (result : Option Handoff)
  | plan (pending : PendingRendering)

def PreparedRendering.localResult : PreparedRendering → Option Handoff
  | .done result => result
  | .plan pending => pending.finish (pending.localPlan ())

def TransportSlice.sourceOwners (slice : TransportSlice) : List String :=
  match slice.shared with
  | some shared => shared.owners
  | none => slice.shell.map (·.owners) |>.getD []

namespace SharedRangeAdapter

def Family.isFile (family : Family) : Bool := !family.cached.isEmpty || family.template.shell.isSome

def genericPieces (scale familyIndex : Nat) (family : Family) (units : List UnitPlan) : List CuePiece :=
  if family.template.context.isNone then
    match Matcher.atomText? family.owner.outcome with
    | some source => if source.isEmpty then [] else
        [{family := familyIndex,first := 0,last := source.length,weight := scale/(61+familyIndex)}]
    | none => []
  else
    let ownerCues := rankedCues family
    let baseCues := rankedCues {family with synapticRanges := []}
    let endpoints := ((units.filter (·.family == familyIndex)).flatMap (fun unit =>
        unit.ranges.flatMap (fun (a,b) => [a,b])) ++ ownerCues.flatMap (fun cue => [cue.first,cue.last]))
      |>.eraseDups.mergeSort (· ≤ ·)
    (endpoints.zip (endpoints.drop 1)).filterMap fun (first,last) => do
      if first ≥ last then none else do
        let cue ← coveringCue? ownerCues first last
        let baseWeight := (coveringCue? baseCues first last).map (fun hint =>
          (last-first)*(scale/(61+familyIndex)+scale/(61+hint.priority))) |>.getD 0
        let graphWeight := (last-first)*(scale/(61+familyIndex)+scale/(61+cue.priority))
        pure {family := familyIndex,first,last,weight := max baseWeight graphWeight,baseWeight}

end SharedRangeAdapter

/-- Only coordinates and exact costs leave the renderer. Original general
output units stay local; a reply can select their IDs but cannot replace them. -/
def PendingRendering.query? (pending : PendingRendering) :
    Option (SharedRangeAdapter.ServiceQuery × Array SharedRangeAdapter.UnitPlan) := do
  let families := pending.families.map SharedRangeAdapter.Family.contextualOutputs
  let false := families.any (fun family => !family.isFile &&
    family.template.context.isSome && family.original.isNone) | none
  let templates := families.map (·.template) ++ pending.mandatory
  let allCost := pending.cost templates
  let dataCost := templates.foldl (fun total slice =>
    (total.1+slice.text.length+1,total.2+slice.text.utf8ByteSize+1)) (0,0)
  if allCost.1 < dataCost.1 || allCost.2 < dataCost.2 then none else do
    let fixedData := pending.mandatory.foldl (fun total slice =>
      (total.1+slice.text.length+1,total.2+slice.text.utf8ByteSize+1)) (0,0)
    let sharedFrame := if families.any (·.isFile) then
      Synapses.CanonicalSource.Packet.wrapper ++ Synapses.CanonicalSource.Packet.footer ++ "\n" else ""
    let fixed := (allCost.1-dataCost.1+fixedData.1+sharedFrame.length,
      allCost.2-dataCost.2+fixedData.2+sharedFrame.utf8ByteSize)
    let generic := families.zipIdx.flatMap fun (family,index) =>
      if family.isFile then (SharedRangeAdapter.prepareOutputs index family).1 else
        (SharedRangeAdapter.prepare index family).1
    let packed ← LinearOutput.pairLoop (SharedRangeAdapter.LinearNodes.step {} {}) generic #[] {} []
    let closures := packed.2.2.toArray
    let genericWire ← generic.toArray.mapIdxM fun index unit => do
      let closure ← closures[index]?
      if closure.head? != some unit.family then none else some {
        family := unit.family,ranges := unit.ranges,payloads := closure.drop 1,
        contextual := unit.slice.context.isSome : SharedRangeAdapter.GenericUnit}
    let depth := max families.length (families.foldl (fun n family =>
      max n (max family.windows.length family.references.length)) 0)
    let scale := (List.range depth).foldl (fun value rank => Nat.lcm value (61+rank)) 1
    let pieces := families.zipIdx.flatMap fun (family,index) =>
      if family.isFile then [] else SharedRangeAdapter.genericPieces scale index family generic
    let files := families.zipIdx.filterMap fun (family,index) =>
      if !family.isFile then none else some {
        family := index,owner := relationKey family.owner.relation
        baseCues := SharedRangeAdapter.rankedCues {family with synapticRanges := []}
        allCues := SharedRangeAdapter.rankedCues family
        groups := family.referenceRanges.map Prod.snd ++
          family.synapticRanges.map (fun (_,first,last) => [(first,last)]) ++ family.synapticUnits
        : SharedRangeAdapter.FileQuery}
    let frames := families.map fun family => match family.template.context with
      | none => (0,0)
      | some context =>
        let text := context.leading ++ context.sourceNotice ++ context.trailing
        (text.length,text.utf8ByteSize)
    let query : SharedRangeAdapter.ServiceQuery := {
      owners := (families.map (fun family => relationKey family.owner.relation)).toArray
      works := (families.map (fun family => (relationKey family.owner.work,
        ((Matcher.atomText? family.owner.work).getD "").length))).toArray
      frameCosts := frames.toArray,scale,genericCosts := packed.1,generic := genericWire,pieces,files := files.toArray
      bundles := pending.bundles,fixed,ceiling := pending.ceiling,
      captureRanges := pending.captureRanges,captureInput := pending.captureInput}
    return (query,generic.toArray)

def PendingRendering.materialize? (pending : PendingRendering) (choice : SharedRangeAdapter.ServiceChoice)
    (generic : Array SharedRangeAdapter.UnitPlan) (rows : Array Synapses.CanonicalSource.StoredRow) :
    Option SharedRangeAdapter.RenderChoice := do
  let slices ← SharedRangeAdapter.materialize generic choice.generic.toList rows
  let result := pending.mandatory ++ slices
  unless (pending.cost result).1 ≤ pending.ceiling.1 && (pending.cost result).2 ≤ pending.ceiling.2 do none
  return {slices := result,receipt := choice.receipt,selectorInput := choice.selectorInput}

def PreparedRendering.usingService (rendering : PreparedRendering)
    (batch : Option Publication.Client.SourceBatch) (deadline : Nat) : IO (Option Handoff) := do
  match rendering with
  | .done result => return result
  | .plan pending =>
    let some batch := batch | return pending.finish (pending.localPlan ())
    let some (query,generic) := pending.query? | throw (IO.userError "invalid prepared renderer request")
    let selectedJson ← batch.select (toJson query) deadline
    let choice ← IO.ofExcept (fromJson? (α := SharedRangeAdapter.ServiceChoice) selectedJson)
    unless choice.generic.all (· < generic.size) &&
        (hashDistinct choice.generic.toList).length == choice.generic.size &&
        (hashDistinct choice.sourceKeys.toList).length == choice.sourceKeys.size do
      throw (IO.userError "prepared selector changed its finite unit domain")
    let selected := Std.HashSet.ofArray choice.sourceKeys
    let owners := Std.HashSet.ofArray (query.files.map (·.owner))
    let mut requests := #[]
    for source in [:batch.palette.owners.size] do
      let some descriptors := batch.palette.owners[source]? | throw (IO.userError "selected source view disappeared")
      let mut parts := #[]
      for (owner,descriptor) in descriptors do
        if !owners.contains owner then continue
        let some keys := Synapses.PreparedPlanMetadata.descriptorKeys descriptor |
          throw (IO.userError "invalid original row keys")
        let indices := keys.zipIdx.filterMap fun (key,index) => if selected.contains key then some index else none
        if !indices.isEmpty then parts := parts.push ({owner,indices} : Synapses.OwnerPalette.Fetch)
      if !parts.isEmpty then requests := requests.push ({source,requests := parts} : Synapses.SourceViewBatch.Fetch)
    let rows ← if choice.sourceKeys.isEmpty then pure #[] else batch.fetch requests deadline
    unless rows.map (·.key) == choice.sourceKeys do throw (IO.userError "selected original payload domain changed")
    let some choice := pending.materialize? choice generic rows |
      throw (IO.userError "selected original packet does not fit its checked local budget")
    return pending.finish (some choice)
