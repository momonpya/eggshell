
namespace SharedRangeAdapter.ReferenceRecords

/-- Original bytes are referenced through the pinned owner, never copied
or rendered while this candidate competes in the selector. -/
structure Record where
  source : String
  range : EvidenceRange source
  stored : OriginalRecordPrice.Stored
  firstExact : range.start = stored.span.first
  lastExact : range.stop = stored.span.limit
  template : TransportSlice
  envelope : ContextDelivery

def Record.fragment (record : Record) : DeliveryFragment :=
  {first := record.range.start
   original := record.range.text
   decoded := record.stored.span.decoded}

theorem Record.fragment_exact (record : Record) (original : IndexedCharacters record.source) :
    record.fragment = originalRecordFragment original record.range record.stored.span.decoded := by
  simp only [Record.fragment,originalRecordFragment,IndexedCharacters.slice_exact,EvidenceRange.text]

theorem Record.price_exact (record : Record) (original : IndexedCharacters record.source)
    (prepared : record.stored = OriginalRecordPrice.prepare original record.stored.span)
    (compact : Bool) :
    record.stored.cost compact = OriginalRecordPrice.Cost.ofText (record.fragment.render compact) := by
  calc
    record.stored.cost compact = (OriginalRecordPrice.prepare original record.stored.span).cost compact :=
      congrArg (fun value : OriginalRecordPrice.Stored => value.cost compact) prepared
    _ = OriginalRecordPrice.Cost.ofText ((OriginalRecordPrice.fragment original record.stored.span).render compact) :=
      OriginalRecordPrice.prepared_cost_exact original record.stored.span compact
    _ = OriginalRecordPrice.Cost.ofText (record.fragment.render compact) := by
      rw [record.fragment_exact original]
      simp only [OriginalRecordPrice.fragment,originalRecordFragment,record.firstExact,record.lastExact]

inductive Payload where
  | eager (draft : DraftUnit)
  | original (record : Record)

structure Candidate where
  shape : UnitShape
  payload : Payload

def Candidate.toDraft (candidate : Candidate) : DraftUnit :=
  match candidate.payload with
  | .eager draft => draft
  | .original record =>
    {family := candidate.shape.family
     payload := .contextual record.template {record.envelope with fragments := [record.fragment]}
     ranges := candidate.shape.ranges
     coverage := candidate.shape.coverage}

def Candidate.contextual (candidate : Candidate) : Bool :=
  match candidate.payload with
  | .eager draft => draft.payload.context.isSome
  | .original _ => true

def eager (draft : DraftUnit) : Candidate := ⟨draft.pricing.shape,.eager draft⟩

/-- Keys retain every presentation discriminator. Original coordinates are
scoped to one family/source. Paths are compared exactly, never hashed JSON. -/
inductive Key where
  | whole (family : Nat) (text : String)
  | interval (family first last : Nat) (decoded compact : Bool)
      (path : Option (List JsonScalars.Segment))
  deriving DecidableEq

instance : BEq Key := ⟨fun a b => decide (a = b)⟩
instance : LawfulBEq Key where
  rfl := by intro key; simp [BEq.beq]
  eq_of_beq := by intro a b same; exact of_decide_eq_true same
instance : Hashable Key where
  hash
    | .whole family text => hash ((0 : Nat),family,text)
    | .interval family first last decoded compact _ => hash ((1 : Nat),family,first,last,decoded,compact)

def parts (candidate : Candidate) : Option (List (Key × (Nat × Nat))) := do
  let family := candidate.shape.family
  match candidate.payload with
  | .original record =>
    let span := record.stored.span
    let cost := record.stored.cost record.envelope.compactCaptions
    return [(.interval family span.first span.limit span.decoded record.envelope.compactCaptions none,
      (cost.characters,cost.bytes))]
  | .eager draft =>
    let slice := draft.payload.pricing
    if let some shared := slice.shared then
      unless shared.rows.isEmpty do none
      return []
    match slice.context with
    | none => return [(.whole family slice.text,(slice.text.length+1,slice.text.utf8ByteSize+1))]
    | some context =>
      return context.fragments.map fun fragment =>
        let text := fragment.render context.compactCaptions
        (.interval family fragment.first (fragment.first+fragment.original.length)
          fragment.decoded context.compactCaptions fragment.path,(text.length+1,text.utf8ByteSize+1))

abbrev State := Array (Nat × Nat) × Std.HashMap Key Nat

def step (state : State) (candidate : Candidate) : Option (State × List Nat) := do
  let entries ← parts candidate
  let mut costs := state.1
  let mut keys := state.2
  let mut closure := [candidate.shape.family]
  for (key,cost) in entries do
    let index := keys[key]?.getD costs.size
    if index == costs.size then
      costs := costs.push cost
      keys := keys.insert key index
    else
      unless costs[index]? == some cost do none
    closure := closure ++ [index]
  return ((costs,keys),closure)

def outputs (index : Nat) (family : Family) : List Candidate :=
  if family.outputRanges.isEmpty then [] else
    (prepareOutputsWith emitDraft index family).1.map eager

def prepare (index : Nat) (family : Family) : Option (List Candidate) := do
  let rest := outputs index family
  if family.isFile then return rest
  let some source := Matcher.atomText? family.owner.outcome | return []
  let some envelope := family.template.context |
    return [eager (readyDraft (atomicUnit index source.length family))]
  -- Shared packets retain their existing typed materializer. This is a
  -- presentation case, not a fallback for missing original metadata.
  if family.template.shared.isSome then
    return (prepareDraft index family).1.map eager
  let spans ← family.original
  let stored ← family.prices
  unless stored.map (·.span) == spans do none
  if source.isEmpty then return rest
  let characters := source.length
  let workChars := (Matcher.atomText? family.owner.work).getD "" |>.length
  let cues := ((rankedContextRanges source (workChars+1)
    (family.windows ++ family.references).eraseDups).map fun range => (range.start,range.stop)) ++
    (family.synapticRanges ++ family.outputCues).map (fun (_,a,b) => (a,b))
  let template := {family.template with text := "",keys := [],context := none}
  let mut records := #[]
  for row in stored do
    let span := row.span
    if valid : span.first < span.limit ∧ span.limit ≤ characters ∧ span.limit-span.first ≤ 2048 then
      let range : EvidenceRange source := ⟨span.first,span.limit,valid.1,valid.2.1,valid.2.2⟩
      let selectedCues := cues.filterMap fun (a,b) =>
        let first := max a span.first
        let last := min b span.limit
        if first < last then some (first,last) else none
      let record : Record := {
        source,range,stored := row,firstExact := rfl,lastExact := rfl,template
        envelope := {envelope with cues := selectedCues,fragments := []}}
      records := records.push ⟨{family := index,ranges := [(span.first,span.limit)]},.original record⟩
    else none
  return records.toList ++ rest

def wire (closures : Array (List Nat)) (index : Nat) (candidate : Candidate) : Option GenericUnit := do
  let closure ← closures[index]?
  unless closure.head? == some candidate.shape.family do none
  return {
    family := candidate.shape.family
    ranges := candidate.shape.ranges
    payloads := closure.drop 1
    contextual := candidate.contextual}

def selectedDrafts (candidates : Array Candidate) (indices : Array Nat) : Option (Array DraftUnit) :=
  indices.mapM fun index => do return (← candidates[index]?).toDraft

end SharedRangeAdapter.ReferenceRecords

def PendingRendering.queryReferences? (pending : PendingRendering) :
    Option (SharedRangeAdapter.ServiceQuery × Array SharedRangeAdapter.ReferenceRecords.Candidate) := do
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
    let groups ← families.zipIdx.mapM fun (family,index) => SharedRangeAdapter.ReferenceRecords.prepare index family
    let candidates := groups.flatten
    let packed ← LinearOutput.pairLoop SharedRangeAdapter.ReferenceRecords.step candidates #[] {} []
    let closures := packed.2.2.toArray
    let genericWire ← candidates.toArray.mapIdxM (SharedRangeAdapter.ReferenceRecords.wire closures)
    let depth := max families.length (families.foldl (fun n family =>
      max n (max family.windows.length family.references.length)) 0)
    let scale := (List.range depth).foldl (fun value rank => Nat.lcm value (61+rank)) 1
    let shapes := candidates.map (·.shape)
    let pieces := families.zipIdx.flatMap fun (family,index) =>
      if family.isFile then [] else SharedRangeAdapter.genericPiecesFromShapes scale index family shapes
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
    return ({
      owners := (families.map (fun family => relationKey family.owner.relation)).toArray
      works := (families.map (fun family => (relationKey family.owner.work,
        ((Matcher.atomText? family.owner.work).getD "").length))).toArray
      frameCosts := frames.toArray,scale,genericCosts := packed.1,generic := genericWire,pieces,files := files.toArray
      bundles := pending.bundles,fixed,ceiling := pending.ceiling,
      captureRanges := pending.captureRanges,captureInput := pending.captureInput},candidates.toArray)

def PendingRendering.materializeReferences (pending : PendingRendering) (choice : SharedRangeAdapter.ServiceChoice)
    (candidates : Array SharedRangeAdapter.ReferenceRecords.Candidate)
    (rows : Option Synapses.CanonicalSource.Delivery.Merged) : Except String SharedRangeAdapter.RenderChoice := do
  let some selected := SharedRangeAdapter.ReferenceRecords.selectedDrafts candidates choice.generic |
    throw "selected original reference escaped its finite domain"
  let compactChoice := {choice with generic := (Array.range selected.size)}
  let result ← pending.materializeDraftReport compactChoice selected rows
  return {result with receipt := choice.receipt}
