module
public import tools.research.DraftUnitsAdapter
@[expose] public section
open Lean

namespace Eggshell.Plugin.SharedRangeAdapter

def preparedDrafts (families : List Family) : List DraftUnit :=
  families.zipIdx.flatMap fun (family,index) =>
    if family.isFile then (prepareOutputsWith emitDraft index family).1 else (prepareDraft index family).1

def preparedReference (families : List Family) : List UnitPlan :=
  families.zipIdx.flatMap fun (family,index) =>
    if family.isFile then (prepareOutputs index family).1 else (prepare index family).1

theorem prepared_drafts_exact (families : List Family) :
    (preparedDrafts families).map DraftUnit.realize = preparedReference families := by
  unfold preparedDrafts preparedReference
  rw [List.map_flatMap]
  congr 1
  funext pair
  rcases pair with ⟨family,index⟩
  by_cases file : family.isFile = true
  · have same := congrArg Prod.fst (outputs_map DraftUnit.realize emitDraft emitUnit emit_draft_exact index family)
    simpa [file,outputs_reference_exact,projectProduced] using same
  · have same := congrArg Prod.fst (prepare_draft_exact index family)
    simpa [file,projectProduced] using same

def wireUnit (closures : Array (List Nat)) (index : Nat) (unit : UnitPlan) : Option GenericUnit := do
  let closure ← closures[index]?
  if closure.head? != some unit.family then none else some {
    family := unit.family,ranges := unit.ranges,payloads := closure.drop 1,
    contextual := unit.slice.context.isSome}

def wirePrepared (closures : Array (List Nat)) (units : List UnitPlan) : Option (Array GenericUnit) :=
  units.toArray.mapIdxM (wireUnit closures)

theorem wire_view_exact (closures : Array (List Nat)) (index : Nat) (draft : DraftUnit) :
    wireUnit closures index draft.pricing = wireUnit closures index draft.realize := by
  rcases draft with ⟨family,payload,ranges,coverage⟩
  cases payload <;> rfl

theorem draft_wire_exact (closures : Array (List Nat)) (drafts : List DraftUnit) :
    wirePrepared closures (drafts.map DraftUnit.pricing) =
      wirePrepared closures (drafts.map DraftUnit.realize) := by
  have loop (rest : List DraftUnit) (acc : Array GenericUnit) :
      List.mapIdxM.go (wireUnit closures) (rest.map DraftUnit.pricing) acc =
        List.mapIdxM.go (wireUnit closures) (rest.map DraftUnit.realize) acc := by
    induction rest generalizing acc with
    | nil => rfl
    | cons draft rest ih =>
      simp only [List.map_cons,List.mapIdxM.go,wire_view_exact]
      cases result : wireUnit closures acc.size draft.realize <;> simp_all [Bind.bind]
  simp only [wirePrepared,List.mapIdxM_toArray,List.mapIdxM]
  rw [loop]

end Eggshell.Plugin.SharedRangeAdapter

namespace Eggshell.Plugin

def PendingRendering.queryDraftWith (pending : PendingRendering) (view : SharedRangeAdapter.DraftUnit → SharedRangeAdapter.UnitPlan) :
    Option (SharedRangeAdapter.ServiceQuery × Array SharedRangeAdapter.DraftUnit) := do
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
    let drafts := SharedRangeAdapter.preparedDrafts families
    let generic := drafts.map view
    let packed ← LinearOutput.pairLoop (SharedRangeAdapter.LinearNodes.step {} {}) generic #[] {} []
    let closures := packed.2.2.toArray
    let genericWire ← SharedRangeAdapter.wirePrepared closures generic
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
    return (query,drafts.toArray)

theorem PendingRendering.query_draft_view_exact (pending : PendingRendering) :
    pending.queryDraftWith SharedRangeAdapter.DraftUnit.pricing =
      pending.queryDraftWith SharedRangeAdapter.DraftUnit.realize := by
  unfold PendingRendering.queryDraftWith
  simp only [SharedRangeAdapter.draft_prices_exact,SharedRangeAdapter.draft_wire_exact,
    SharedRangeAdapter.draft_generic_pieces_exact]

theorem PendingRendering.query_draft_reference_exact (pending : PendingRendering) :
    (pending.queryDraftWith SharedRangeAdapter.DraftUnit.realize).map
      (fun result => (result.1,result.2.map SharedRangeAdapter.DraftUnit.realize)) = pending.query? := by
  let families := pending.families.map SharedRangeAdapter.Family.contextualOutputs
  cases invalid : families.any (fun family => !family.isFile &&
      family.template.context.isSome && family.original.isNone) with
  | true =>
    dsimp only [families] at invalid
    simp only [PendingRendering.queryDraftWith,PendingRendering.query?,invalid,Option.map_none]
  | false =>
    dsimp only [families] at invalid
    let templates := families.map (·.template) ++ pending.mandatory
    let allCost := pending.cost templates
    let dataCost := templates.foldl (fun total slice =>
      (total.1+slice.text.length+1,total.2+slice.text.utf8ByteSize+1)) (0,0)
    by_cases small : (decide (allCost.1 < dataCost.1) || decide (allCost.2 < dataCost.2)) = true
    · dsimp only [allCost,dataCost,templates,families] at small
      simp only [PendingRendering.queryDraftWith,PendingRendering.query?,invalid,small,↓reduceIte,Option.map_none]
    · dsimp only [allCost,dataCost,templates,families] at small
      simp only [PendingRendering.queryDraftWith,PendingRendering.query?,invalid,small,Bool.false_eq_true,↓reduceIte]
      dsimp only [Bind.bind,Pure.pure]
      simp only [Option.map_bind,Option.map_some,Function.comp_def,List.map_toArray,SharedRangeAdapter.prepared_drafts_exact,
        SharedRangeAdapter.preparedReference,SharedRangeAdapter.wirePrepared]
      delta SharedRangeAdapter.wireUnit
      dsimp only [Bind.bind,Pure.pure]
      all_goals rfl

def PendingRendering.queryDraft? (pending : PendingRendering) :
    Option (SharedRangeAdapter.ServiceQuery × Array SharedRangeAdapter.DraftUnit) :=
  pending.queryDraftWith SharedRangeAdapter.DraftUnit.pricing

theorem PendingRendering.query_draft_exact (pending : PendingRendering) :
    (pending.queryDraft?).map
      (fun result => (result.1,result.2.map SharedRangeAdapter.DraftUnit.realize)) = pending.query? := by
  rw [PendingRendering.queryDraft?,PendingRendering.query_draft_view_exact]
  exact pending.query_draft_reference_exact

def PendingRendering.materializeDraftReport (pending : PendingRendering) (choice : SharedRangeAdapter.ServiceChoice)
    (generic : Array SharedRangeAdapter.DraftUnit) (rows : Option Synapses.CanonicalSource.Delivery.Merged) :
    Except String SharedRangeAdapter.RenderChoice := do
  let some slices := SharedRangeAdapter.materializeDraftFetched generic choice.generic.toList rows |
    throw ("selected original units cannot be combined; generic=" ++
      (toJson (choice.generic.filterMap fun index => generic[index]?.map fun unit =>
        (index,unit.family,unit.payload.context.isSome,unit.payload.shared.isSome))).compress)
  let result := pending.mandatory ++ slices
  let price := pending.cost result
  unless price.1 ≤ pending.ceiling.1 && price.2 ≤ pending.ceiling.2 do
    throw s!"materialized packet price chars={price.1},bytes={price.2} exceeds ceiling chars={pending.ceiling.1},bytes={pending.ceiling.2}"
  return {slices := result,receipt := choice.receipt,selectorInput := choice.selectorInput}

theorem PendingRendering.materialize_draft_report_exact (pending : PendingRendering)
    (choice : SharedRangeAdapter.ServiceChoice) (units : Array SharedRangeAdapter.DraftUnit)
    (rows : Option Synapses.CanonicalSource.Delivery.Merged) :
    pending.materializeDraftReport choice units rows =
      pending.materializeReport choice (units.map SharedRangeAdapter.DraftUnit.realize) rows := by
  unfold PendingRendering.materializeDraftReport PendingRendering.materializeReport
  simp only [SharedRangeAdapter.materialize_draft_fetched_exact,Array.getElem?_map,Option.map_map,Function.comp_def,
    SharedRangeAdapter.DraftUnit.realize,← SharedRangeAdapter.draft_context_exact,← SharedRangeAdapter.draft_shared_exact]
  all_goals rfl

end Eggshell.Plugin

#print axioms Eggshell.Plugin.SharedRangeAdapter.prepared_drafts_exact
#print axioms Eggshell.Plugin.SharedRangeAdapter.draft_wire_exact
#print axioms Eggshell.Plugin.PendingRendering.query_draft_view_exact
#print axioms Eggshell.Plugin.PendingRendering.query_draft_reference_exact
#print axioms Eggshell.Plugin.PendingRendering.query_draft_exact
#print axioms Eggshell.Plugin.PendingRendering.materialize_draft_report_exact
