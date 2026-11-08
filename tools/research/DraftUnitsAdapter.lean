module
public import Eggshell.Handoff
public import tools.research.ProjectedLoop
@[expose] public section

namespace Eggshell.Plugin.SharedRangeAdapter

/-- A contextual draft retains the first metadata and original fragments.
It never stores a separately rendered whole-unit envelope. Atomic and shared
units are retained verbatim. A selected draft is realized at the boundary. -/
inductive SliceDraft where
  | ready (slice : TransportSlice)
  | contextual (template : TransportSlice) (context : ContextDelivery)

def SliceDraft.realize : SliceDraft → TransportSlice
  | .ready slice => slice
  | .contextual template context =>
    {template with context := some context,keys := context.keys,text := context.render}

/-- LinearNodes reads shared rows or contextual fragments. Contextual text
and keys are not inputs to prices or payload identity. This view preserves
all fields the planner actually reads without constructing derived text. -/
def SliceDraft.pricing : SliceDraft → TransportSlice
  | .ready slice => slice
  | .contextual template context => {template with context := some context}

structure DraftUnit where
  family : Nat
  payload : SliceDraft
  ranges : List (Nat × Nat)
  coverage : CoverageIndex ranges := CoverageIndex.prepare ranges

def DraftUnit.realize (draft : DraftUnit) : UnitPlan :=
  ⟨draft.family,draft.payload.realize,draft.ranges,draft.coverage⟩

def DraftUnit.pricing (draft : DraftUnit) : UnitPlan :=
  ⟨draft.family,draft.payload.pricing,draft.ranges,draft.coverage⟩

def emitUnit (family : Nat) (template : TransportSlice) (context : ContextDelivery)
    (ranges : List (Nat × Nat)) : UnitPlan :=
  {family,slice := {template with context := some context,keys := context.keys,text := context.render},ranges}

def emitDraft (family : Nat) (template : TransportSlice) (context : ContextDelivery)
    (ranges : List (Nat × Nat)) : DraftUnit :=
  {family,payload := .contextual template context,ranges}

theorem emit_draft_exact (family : Nat) (template : TransportSlice) (context : ContextDelivery)
    (ranges : List (Nat × Nat)) : (emitDraft family template context ranges).realize =
      emitUnit family template context ranges := rfl

theorem draft_pricing_context (draft : DraftUnit) :
    draft.pricing.slice.context = draft.realize.slice.context := by
  rcases draft with ⟨family,payload,ranges,coverage⟩
  cases payload <;> rfl

theorem draft_pricing_shape (draft : DraftUnit) : draft.pricing.shape = draft.realize.shape := rfl

theorem draft_pricing_exact (fileIds : Std.HashMap Synapses.File Nat)
    (sourceIds : Std.HashMap Synapses.CanonicalSource.Key Nat)
    (state : LinearNodes.Costs × LinearNodes.Payloads) (draft : DraftUnit) :
    LinearNodes.step fileIds sourceIds state draft.pricing =
      LinearNodes.step fileIds sourceIds state draft.realize := by
  rcases draft with ⟨family,payload,ranges,coverage⟩
  cases payload with
  | ready slice => rfl
  | contextual template context =>
    unfold DraftUnit.pricing DraftUnit.realize SliceDraft.pricing SliceDraft.realize LinearNodes.step
    rfl

def outputStepWith {Output : Type}
    (emit : Nat → TransportSlice → ContextDelivery → List (Nat × Nat) → Output)
    (familyIndex : Nat) (template : TransportSlice) (source : String) (envelope : ContextDelivery)
    (original : IndexedCharacters source) (range : Synapses.Transport.OutputRange)
    (state : List Output × List (Nat × Nat)) : Id (ForInStep (List Output × List (Nat × Nat))) :=
  let first := range.first
  let last := range.limit
  if valid : first < last ∧ last ≤ source.length then
    let span : ContextSpan source := ⟨first,last,valid.1,valid.2⟩
    let fragments := span.ranges.map fun part => ({
      first := part.start,original := original.slice part.start (part.stop-part.start)
      decoded := false,path := range.path} : DeliveryFragment)
    let context := {envelope with fragments,cues := [(first,last)]}
    .yield (state.1 ++ [emit familyIndex template context [(first,last)]],state.2 ++ [(first,last)])
  else .yield state

def prepareOutputsWith {Output : Type} (emit : Nat → TransportSlice → ContextDelivery → List (Nat × Nat) → Output)
    (familyIndex : Nat) (family : Family) : List Output × List (Nat × Nat) := Id.run do
  if !Matcher.nativeOutcome family.owner then return ([],[])
  let some source := Matcher.atomText? family.owner.outcome | return ([],[])
  let some envelope := family.template.context | return ([],[])
  let original := IndexedCharacters.make source
  let state ← forIn family.outputRanges ([],[]) (outputStepWith emit familyIndex family.template source envelope original)
  return state

theorem outputs_reference_exact (familyIndex : Nat) (family : Family) :
    prepareOutputsWith emitUnit familyIndex family = prepareOutputs familyIndex family := by rfl

def recordStepWith {Output : Type}
    (emit : Nat → TransportSlice → ContextDelivery → List (Nat × Nat) → Output)
    (familyIndex : Nat) (template : TransportSlice) (source : String) (envelope : ContextDelivery)
    (original : IndexedCharacters source) (characters : Nat) (exact : characters = source.length)
    (cues : List (Nat × Nat)) (span : OriginalStructure.Span)
    (state : Option (List Output × List (Nat × Nat)) × List Output) :
    Id (ForInStep (Option (List Output × List (Nat × Nat)) × List Output)) := do
  let some required := span.rangeUsing? source characters exact | return .done (some ([],[]),state.2)
  let fragment := originalRecordFragment original required span.decoded
  let ranges := [(required.start,required.stop)]
  let selectedCues := cues.filterMap fun (a,b) =>
    let first := max a required.start
    let last := min b required.stop
    if first < last then some (first,last) else none
  let context := {envelope with fragments := [fragment],cues := selectedCues}
  return .yield (none,emit familyIndex template context ranges :: state.2)

def prepareRecordsWith {Output : Type} (emit : Nat → TransportSlice → ContextDelivery → List (Nat × Nat) → Output)
    (familyIndex : Nat) (family : Family) : List Output × List (Nat × Nat) := Id.run do
  let some source := Matcher.atomText? family.owner.outcome | return ([],[])
  let some envelope := family.template.context | return ([],[])
  let some prepared := family.original | return ([],[])
  if source.isEmpty then return ([],[])
  let characters := source.length
  let original := IndexedCharacters.make source
  let workChars := (Matcher.atomText? family.owner.work).getD "" |>.length
  let cues := ((rankedContextRanges source (workChars+1)
    (family.windows ++ family.references).eraseDups).map fun range => (range.start,range.stop)) ++
    (family.synapticRanges ++ family.outputCues).map (fun (_,a,b) => (a,b))
  let state ← forIn prepared (none,[]) (recordStepWith emit familyIndex family.template source envelope original characters rfl cues)
  match state.1 with
  | some result => return result
  | none => return (state.2.reverse,cues)


theorem records_reference_exact (familyIndex : Nat) (family : Family) :
    prepareRecordsWith emitUnit familyIndex family = prepareOriginalRecords familyIndex family := by
  cases source : Matcher.atomText? family.owner.outcome with
  | none => simp [prepareRecordsWith,prepareOriginalRecords,source]
  | some text =>
    cases context : family.template.context with
    | none => simp [prepareRecordsWith,prepareOriginalRecords,source,context]
    | some envelope =>
      cases spans : family.original with
      | none => simp [prepareRecordsWith,prepareOriginalRecords,source,context,spans]
      | some prepared =>
        by_cases empty : text.isEmpty = true
        · simp [prepareRecordsWith,prepareOriginalRecords,source,context,spans,empty]
        · simp only [prepareRecordsWith,prepareOriginalRecords,source,context,spans,empty,
            Bool.false_eq_true,↓reduceIte,Bind.bind,Pure.pure,Id.run]
          unfold recordStepWith emitUnit
          dsimp only [Bind.bind,Pure.pure]
          try delta prepareRecordsWith.match_1
          try delta Break.runK.match_1
          try delta recordStepWith.match_3
          try delta prepareOriginalRecords.match_1
          all_goals rfl

def projectProduced (project : A → B) (state : List A × List (Nat × Nat)) : List B × List (Nat × Nat) :=
  (state.1.map project,state.2)

theorem output_step_map {A B : Type} (project : A → B)
    (left : Nat → TransportSlice → ContextDelivery → List (Nat × Nat) → A)
    (right : Nat → TransportSlice → ContextDelivery → List (Nat × Nat) → B)
    (same : ∀ family template context ranges, project (left family template context ranges) = right family template context ranges)
    (family : Nat) (template : TransportSlice) (source : String) (envelope : ContextDelivery)
    (original : IndexedCharacters source) (range : Synapses.Transport.OutputRange) (state : List A × List (Nat × Nat)) :
    Research.ProjectedLoop.projectStep (projectProduced project)
      (outputStepWith left family template source envelope original range state) =
      outputStepWith right family template source envelope original range (projectProduced project state) := by
  by_cases valid : range.first < range.limit ∧ range.limit ≤ source.length <;>
    simp [outputStepWith,valid,Research.ProjectedLoop.projectStep,projectProduced,List.map_append,same]

theorem outputs_map {A B : Type} (project : A → B)
    (left : Nat → TransportSlice → ContextDelivery → List (Nat × Nat) → A)
    (right : Nat → TransportSlice → ContextDelivery → List (Nat × Nat) → B)
    (same : ∀ family template context ranges, project (left family template context ranges) = right family template context ranges)
    (familyIndex : Nat) (family : Family) :
    projectProduced project (prepareOutputsWith left familyIndex family) =
      prepareOutputsWith right familyIndex family := by
  cases native : Matcher.nativeOutcome family.owner with
  | false => simp [prepareOutputsWith,native,projectProduced]
  | true =>
    cases source : Matcher.atomText? family.owner.outcome with
    | none => simp [prepareOutputsWith,native,source,projectProduced]
    | some text =>
      cases context : family.template.context with
      | none => simp [prepareOutputsWith,native,source,context,projectProduced]
      | some envelope =>
        have loop := Research.ProjectedLoop.forIn_project (projectProduced project)
          (outputStepWith left familyIndex family.template text envelope (IndexedCharacters.make text))
          (outputStepWith right familyIndex family.template text envelope (IndexedCharacters.make text))
          (output_step_map project left right same familyIndex family.template text envelope (IndexedCharacters.make text))
          family.outputRanges ([],[])
        simpa [prepareOutputsWith,native,source,context,Bind.bind,Pure.pure,Id.run,projectProduced] using loop

def projectRecordState (project : A → B)
    (state : Option (List A × List (Nat × Nat)) × List A) :
    Option (List B × List (Nat × Nat)) × List B :=
  (state.1.map (projectProduced project),state.2.map project)

theorem record_step_map {A B : Type} (project : A → B)
    (left : Nat → TransportSlice → ContextDelivery → List (Nat × Nat) → A)
    (right : Nat → TransportSlice → ContextDelivery → List (Nat × Nat) → B)
    (same : ∀ family template context ranges, project (left family template context ranges) = right family template context ranges)
    (family : Nat) (template : TransportSlice) (source : String) (envelope : ContextDelivery)
    (original : IndexedCharacters source) (characters : Nat) (exact : characters = source.length)
    (cues : List (Nat × Nat)) (span : OriginalStructure.Span)
    (state : Option (List A × List (Nat × Nat)) × List A) :
    Research.ProjectedLoop.projectStep (projectRecordState project)
      (recordStepWith left family template source envelope original characters exact cues span state) =
      recordStepWith right family template source envelope original characters exact cues span (projectRecordState project state) := by
  cases found : span.rangeUsing? source characters exact <;>
    simp [recordStepWith,found,Pure.pure,Research.ProjectedLoop.projectStep,projectRecordState,projectProduced,same]

theorem records_map {A B : Type} (project : A → B)
    (left : Nat → TransportSlice → ContextDelivery → List (Nat × Nat) → A)
    (right : Nat → TransportSlice → ContextDelivery → List (Nat × Nat) → B)
    (same : ∀ family template context ranges, project (left family template context ranges) = right family template context ranges)
    (familyIndex : Nat) (family : Family) :
    projectProduced project (prepareRecordsWith left familyIndex family) =
      prepareRecordsWith right familyIndex family := by
  cases source : Matcher.atomText? family.owner.outcome with
  | none => simp [prepareRecordsWith,source,projectProduced]
  | some text =>
    cases context : family.template.context with
    | none => simp [prepareRecordsWith,source,context,projectProduced]
    | some envelope =>
      cases spans : family.original with
      | none => simp [prepareRecordsWith,source,context,spans,projectProduced]
      | some prepared =>
        by_cases empty : text.isEmpty = true
        · simp [prepareRecordsWith,source,context,spans,empty,projectProduced]
        · let original := IndexedCharacters.make text
          let workChars := (Matcher.atomText? family.owner.work).getD "" |>.length
          let cues := ((rankedContextRanges text (workChars+1)
            (family.windows ++ family.references).eraseDups).map fun range => (range.start,range.stop)) ++
            (family.synapticRanges ++ family.outputCues).map (fun (_,a,b) => (a,b))
          have loop := Research.ProjectedLoop.array_forIn_project (projectRecordState project)
            (recordStepWith left familyIndex family.template text envelope original text.length rfl cues)
            (recordStepWith right familyIndex family.template text envelope original text.length rfl cues)
            (record_step_map project left right same familyIndex family.template text envelope original text.length rfl cues)
            prepared (none,[])
          have initial : projectRecordState project ((none,[]) : Option (List A × List (Nat × Nat)) × List A) =
              (none,[]) := rfl
          rw [initial] at loop
          simp only [prepareRecordsWith,source,context,spans,empty,Bind.bind]
          change projectProduced project (match (forIn prepared (none,[]) (recordStepWith left familyIndex family.template text envelope original text.length rfl cues)).1 with
            | some result => result
            | none => ((forIn prepared (none,[]) (recordStepWith left familyIndex family.template text envelope original text.length rfl cues)).2.reverse,cues)) = _
          rw [← loop]
          cases state : forIn prepared (none,[]) (recordStepWith left familyIndex family.template text envelope original text.length rfl cues) with
          | mk returned units => cases returned <;> simp [projectRecordState,projectProduced,List.map_reverse,cues,workChars]

def readyDraft (unit : UnitPlan) : DraftUnit :=
  ⟨unit.family,.ready unit.slice,unit.ranges,unit.coverage⟩

theorem ready_draft_exact (unit : UnitPlan) : (readyDraft unit).realize = unit := rfl

def prepareDraft (familyIndex : Nat) (family : Family) : List DraftUnit × List (Nat × Nat) := Id.run do
  let outputs := prepareOutputsWith emitDraft familyIndex family
  if !family.cached.isEmpty then
    let records := prepareCached familyIndex family
    return (records.1.map readyDraft ++ outputs.1,records.2 ++ outputs.2)
  let some source := Matcher.atomText? family.owner.outcome | return ([],[])
  if family.template.context.isNone then
    return ([readyDraft (atomicUnit familyIndex source.length family)],[])
  let records := prepareRecordsWith emitDraft familyIndex family
  return (records.1 ++ outputs.1,records.2 ++ outputs.2)

theorem prepare_draft_exact (familyIndex : Nat) (family : Family) :
    projectProduced DraftUnit.realize (prepareDraft familyIndex family) = prepare familyIndex family := by
  have outputs := outputs_map DraftUnit.realize emitDraft emitUnit emit_draft_exact familyIndex family
  have records := records_map DraftUnit.realize emitDraft emitUnit emit_draft_exact familyIndex family
  rw [outputs_reference_exact] at outputs
  rw [records_reference_exact] at records
  have outputUnits := congrArg Prod.fst outputs
  have outputCues := congrArg Prod.snd outputs
  have recordUnits := congrArg Prod.fst records
  have recordCues := congrArg Prod.snd records
  simp only [projectProduced] at outputUnits outputCues recordUnits recordCues
  cases cached : family.cached.isEmpty with
  | false =>
    simp [prepareDraft,prepare,cached,projectProduced,List.map_map,Function.comp_def,ready_draft_exact,outputUnits,outputCues]
  | true =>
    cases source : Matcher.atomText? family.owner.outcome with
    | none => simp [prepareDraft,prepare,cached,source,projectProduced]
    | some text =>
      cases atomic : family.template.context.isNone <;>
        simp [prepareDraft,prepare,cached,source,atomic,projectProduced,ready_draft_exact,outputUnits,outputCues,recordUnits,recordCues]

theorem draft_prices_exact (fileIds : Std.HashMap Synapses.File Nat)
    (sourceIds : Std.HashMap Synapses.CanonicalSource.Key Nat) (drafts : List DraftUnit)
    (costs : LinearNodes.Costs) (payloads : LinearNodes.Payloads) (rows : List (List Nat)) :
    LinearOutput.pairLoop (LinearNodes.step fileIds sourceIds) (drafts.map DraftUnit.pricing) costs payloads rows =
      LinearOutput.pairLoop (LinearNodes.step fileIds sourceIds) (drafts.map DraftUnit.realize) costs payloads rows := by
  unfold LinearOutput.pairLoop
  simp only [List.forIn_map,draft_pricing_exact]

theorem draft_ranges_exact (extract : List (Nat × Nat) → List Output) (drafts : List DraftUnit) (family : Nat) :
    ((drafts.map DraftUnit.pricing).filter (·.family == family)).flatMap (fun unit => extract unit.ranges) =
      ((drafts.map DraftUnit.realize).filter (·.family == family)).flatMap (fun unit => extract unit.ranges) := by
  induction drafts with
  | nil => rfl
  | cons draft rest ih =>
    simp only [List.map_cons,List.filter_cons,DraftUnit.pricing,DraftUnit.realize]
    split <;> simp_all

theorem draft_generic_pieces_exact (scale familyIndex : Nat) (family : Family) (drafts : List DraftUnit) :
    genericPieces scale familyIndex family (drafts.map DraftUnit.pricing) =
      genericPieces scale familyIndex family (drafts.map DraftUnit.realize) := by
  unfold genericPieces
  rw [draft_ranges_exact]

def SliceDraft.context : SliceDraft → Option ContextDelivery
  | .ready slice => slice.context
  | .contextual _ context => some context

def SliceDraft.template : SliceDraft → TransportSlice
  | .ready slice => slice
  | .contextual template _ => template

def SliceDraft.merge (prior next : SliceDraft) : Option SliceDraft :=
  match prior.context,next.context with
  | some left,some right => (checkedPricedContextAssembly left right).map fun checked =>
      .contextual prior.template checked.val
  | none,none => if prior.template.text == next.template.text then some prior else none
  | _,_ => none

theorem draft_merge_exact (prior next : SliceDraft) :
    (prior.merge next).map SliceDraft.realize = join prior.realize next.realize := by
  cases prior with
  | ready prior =>
    cases next with
    | ready next =>
      cases left : prior.context <;> cases right : next.context <;>
        simp [SliceDraft.merge,SliceDraft.context,SliceDraft.template,SliceDraft.realize,join,left,right] <;>
        (rw [Option.map_eq_bind]; rfl)
    | contextual template context =>
      cases left : prior.context <;>
        simp [SliceDraft.merge,SliceDraft.context,SliceDraft.template,SliceDraft.realize,join,left] <;>
        (rw [Option.map_eq_bind]; rfl)
  | contextual template context =>
    cases next with
    | ready next =>
      cases right : next.context <;>
        simp [SliceDraft.merge,SliceDraft.context,SliceDraft.template,SliceDraft.realize,join,right] <;>
        (rw [Option.map_eq_bind]; rfl)
    | contextual following incoming =>
      simp [SliceDraft.merge,SliceDraft.context,SliceDraft.template,SliceDraft.realize,join]
      rw [Option.map_eq_bind]
      rfl

def projectDraftRows (rows : List (Nat × SliceDraft)) : List (Nat × TransportSlice) :=
  rows.map fun row => (row.1,row.2.realize)

def insertDraft (rows : List (Nat × SliceDraft)) (family : Nat) (next : SliceDraft) :
    Option (List (Nat × SliceDraft)) := do
  match rows.find? (·.1 == family) with
  | none => return rows ++ [(family,next)]
  | some (_,prior) =>
    let joined ← prior.merge next
    return rows.map fun row => if row.1 == family then (row.1,joined) else row

theorem draft_find_project (rows : List (Nat × SliceDraft)) (family : Nat) :
    (projectDraftRows rows).find? (·.1 == family) =
      (rows.find? (·.1 == family)).map (fun row => (row.1,row.2.realize)) := by
  simp only [projectDraftRows,List.find?_map,Function.comp_def]

theorem draft_update_project (rows : List (Nat × SliceDraft)) (family : Nat) (next : SliceDraft) :
    projectDraftRows (rows.map fun row => if row.1 == family then (row.1,next) else row) =
      (projectDraftRows rows).map (fun row => if row.1 == family then (row.1,next.realize) else row) := by
  unfold projectDraftRows
  simp only [List.map_map]
  congr 1
  funext row
  simp only [Function.comp_apply]
  split <;> rfl

theorem insert_draft_exact (rows : List (Nat × SliceDraft)) (family : Nat) (next : SliceDraft) :
    (insertDraft rows family next).map projectDraftRows =
      Research.DeferredAssembly.referenceRow contextAssemblyAlgebra (projectDraftRows rows) family next.realize := by
  unfold insertDraft Research.DeferredAssembly.referenceRow
  rw [draft_find_project]
  cases found : rows.find? (fun row => row.1 == family) with
  | none => simp [projectDraftRows]
  | some prior =>
    rcases prior with ⟨id,current⟩
    have one := draft_merge_exact current next
    cases advanced : current.merge next with
    | none =>
      rw [advanced] at one
      simp only [Option.map_none] at one
      simp [advanced,context_assembly_eager_exact,← one]
    | some updated =>
      rw [advanced] at one
      simp only [Option.map_some] at one
      simp [advanced,context_assembly_eager_exact,← one]
      simpa only [beq_iff_eq] using draft_update_project rows family updated

def SliceDraft.shared (draft : SliceDraft) : Option Synapses.CanonicalSource.Delivery.Part :=
  draft.template.shared

theorem draft_context_exact (draft : SliceDraft) : draft.context = draft.realize.context := by
  cases draft <;> rfl

theorem draft_shared_exact (draft : SliceDraft) : draft.shared = draft.realize.shared := by
  cases draft <;> rfl

abbrev DraftRows := List (Nat × SliceDraft)

def projectDraftState (state : DraftRows × OriginalRows) : List (Nat × TransportSlice) × OriginalRows :=
  (projectDraftRows state.1,state.2)

def advanceDraft (units : Array DraftUnit) (index : Nat) (state : DraftRows × OriginalRows) :
    Option (ForInStep (DraftRows × OriginalRows)) := do
  let unit ← units[index]?
  if let some shared := unit.payload.shared then
    return .yield (state.1,state.2 ++ shared.rows)
  let rows ← insertDraft state.1 unit.family unit.payload
  return .yield (rows,state.2)

theorem advance_draft_exact (units : Array DraftUnit) (index : Nat) (state : DraftRows × OriginalRows) :
    (advanceDraft units index state).map (Research.DeferredAssembly.projectStep projectDraftState) =
      referenceContexts (units.map DraftUnit.realize) index (projectDraftState state) := by
  cases present : units[index]? with
  | none => simp [advanceDraft,referenceContexts,Array.getElem?_map,present]
  | some unit =>
    cases shared : unit.payload.shared with
    | some part =>
      simp [advanceDraft,referenceContexts,Array.getElem?_map,present,projectDraftState,
        Research.DeferredAssembly.projectStep,DraftUnit.realize,← draft_shared_exact,shared]
    | none =>
      have packed : referenceContexts (units.map DraftUnit.realize) index (projectDraftState state) =
          (Research.DeferredAssembly.referenceRow contextAssemblyAlgebra
            (projectDraftRows state.1) unit.family unit.payload.realize).map
              (fun rows => ForInStep.yield (rows,state.2)) := by
        simp only [referenceContexts,projectDraftState,Bind.bind,Option.bind,Array.getElem?_map,
          present,Option.map,DraftUnit.realize,← draft_shared_exact,shared,
          Research.DeferredAssembly.referenceRow,context_assembly_eager_exact]
        cases found : (projectDraftRows state.1).find? (fun row => row.1 == unit.family) with
        | none => rfl
        | some prior =>
          rcases prior with ⟨family,current⟩
          cases joined : join current unit.payload.realize <;>
            simp only [joined] <;> rfl
      rw [packed,← insert_draft_exact]
      cases updated : insertDraft state.1 unit.family unit.payload <;>
        simp [advanceDraft,present,shared,updated,projectDraftState,Research.DeferredAssembly.projectStep]

/-- Keep fragments through selection and combination. Full keys and text are
produced once for each final family, including all original failure paths. -/
def materializeDraft (units : Array DraftUnit) (indices : List Nat) (requiredRows : OriginalRows := #[]) :
    Option (List TransportSlice) := do
  let state ← forIn indices ([],requiredRows) (advanceDraft units)
  finishMaterialized (projectDraftState state)

theorem materialize_draft_exact (units : Array DraftUnit) (indices : List Nat) (requiredRows : OriginalRows) :
    materializeDraft units indices requiredRows = materialize (units.map DraftUnit.realize) indices requiredRows := by
  rw [materialize_reference_definition]
  have loop := Research.DeferredAssembly.forIn_project projectDraftState (advanceDraft units)
    (referenceContexts (units.map DraftUnit.realize)) (advance_draft_exact units) indices ([],requiredRows)
  simpa only [materializeDraft,Bind.bind,Option.bind_map,Function.comp_def,projectDraftState,
    projectDraftRows,List.map_nil] using congrArg (fun value => value.bind finishMaterialized) loop

def materializeDraftFetched (units : Array DraftUnit) (indices : List Nat)
    (fetched : Option Synapses.CanonicalSource.Delivery.Merged) : Option (List TransportSlice) := do
  let some fetched := fetched | materializeDraft units indices #[]
  if indices.any (fun index => (units[index]?.map fun unit => unit.payload.shared.isSome).getD false) then
    materializeDraft units indices fetched.rows
  else
    let legacy ← materializeDraft units indices #[]
    if fetched.rows.isEmpty then return legacy
    let shared ← Synapses.CanonicalSource.Delivery.Part.check? fetched.rows
    return legacy ++ [{owner := none,keys := shared.keys,text := shared.render,shared := some shared,members := [],visibleKeys := []}]

theorem materialize_draft_fetched_exact (units : Array DraftUnit) (indices : List Nat)
    (fetched : Option Synapses.CanonicalSource.Delivery.Merged) :
    materializeDraftFetched units indices fetched = materializeFetched (units.map DraftUnit.realize) indices fetched := by
  cases fetched <;>
    simp only [materializeDraftFetched,materializeFetched,materialize_draft_exact,Array.getElem?_map,
      Option.map_map,Function.comp_def,DraftUnit.realize,← draft_shared_exact] <;> rfl

end Eggshell.Plugin.SharedRangeAdapter

#print axioms Eggshell.Plugin.SharedRangeAdapter.draft_pricing_exact
#print axioms Eggshell.Plugin.SharedRangeAdapter.outputs_reference_exact
#print axioms Eggshell.Plugin.SharedRangeAdapter.records_reference_exact
#print axioms Eggshell.Plugin.SharedRangeAdapter.outputs_map
#print axioms Eggshell.Plugin.SharedRangeAdapter.records_map
#print axioms Eggshell.Plugin.SharedRangeAdapter.prepare_draft_exact
#print axioms Eggshell.Plugin.SharedRangeAdapter.draft_prices_exact
#print axioms Eggshell.Plugin.SharedRangeAdapter.draft_generic_pieces_exact
#print axioms Eggshell.Plugin.SharedRangeAdapter.draft_merge_exact
#print axioms Eggshell.Plugin.SharedRangeAdapter.insert_draft_exact
#print axioms Eggshell.Plugin.SharedRangeAdapter.advance_draft_exact
#print axioms Eggshell.Plugin.SharedRangeAdapter.materialize_draft_exact
#print axioms Eggshell.Plugin.SharedRangeAdapter.materialize_draft_fetched_exact
