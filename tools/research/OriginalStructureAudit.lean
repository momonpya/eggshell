import Eggshell.Handoff
open Lean Eggshell Eggshell.Plugin Eggshell.Plugin.SharedRangeAdapter

private def referenceOriginalRecords (familyIndex : Nat) (family : Family) :
    List UnitPlan × List (Nat × Nat) := Id.run do
  let some source := Matcher.atomText? family.owner.outcome | return ([],[])
  let some envelope := family.template.context | return ([],[])
  let some wholeSpan := (if positive : 0 < source.length then
    some (⟨0,source.length,positive,Nat.le_refl _⟩ : ContextSpan source) else none) | return ([],[])
  let scalar := ScalarLayout.check? source
  let layout := scalar.map (·.layout)
  let original := layout.map (·.original) |>.getD (IndexedCharacters.make source)
  let boundaries := scalar.map ScalarLayout.boundaries |>.getD {}
  let records := contextRecordSpans source layout
  let heads := contextStructureHeads source layout
  let scopedHeads := contextStructureHeads source layout true
  let covered := records.map fun record =>
    (⟨record.start,record.stop,record.ordered⟩ : DeliveryInterval)
  let whole : DeliveryInterval := ⟨wholeSpan.start,wholeSpan.stop,wholeSpan.ordered⟩
  let gaps := (whole.subtractAll covered).attach.map fun gap =>
    (⟨gap.val.start,gap.val.stop,gap.val.ordered,by
      have inside : gap.val.covers (gap.val.stop-1) := by
        have := gap.val.ordered
        simp only [DeliveryInterval.covers]
        omega
      have contained := ((DeliveryInterval.subtractAll_covers whole covered (gap.val.stop-1)).mp
        ⟨gap.val,gap.property,inside⟩).1
      have bound := wholeSpan.within
      simp only [DeliveryInterval.covers,whole] at contained
      omega⟩ : ContextSpan source)
  let workChars := (Matcher.atomText? family.owner.work).getD "" |>.length
  let cues := ((rankedContextRanges source (workChars+1)
    (family.windows ++ family.references).eraseDups).map fun range => (range.start,range.stop)) ++
    (family.synapticRanges ++ family.outputCues).map (fun (_,a,b) => (a,b))
  let mut units := []
  let mut seen : Std.HashSet (Nat × Nat) := {}
  for record in records ++ gaps do
    for part in record.ranges do
      let required := recordPrerequisite records heads scopedHeads part
      if seen.contains (required.start,required.stop) then continue
      seen := seen.insert (required.start,required.stop)
      let fragment := originalRecordFragment original required
        (scalar.isSome && boundaries.contains required.start && boundaries.contains required.stop)
      let ranges := [(required.start,required.stop)]
      let selectedCues := cues.filterMap fun (a,b) =>
        let first := max a required.start
        let last := min b required.stop
        if first < last then some (first,last) else none
      let context := {envelope with fragments := [fragment],cues := selectedCues}
      let slice := {family.template with context := some context,keys := context.keys,text := context.render}
      units := units ++ [{family := familyIndex,slice,ranges}]
  return (units,cues)

#print axioms OriginalStructure.Span.range_roundtrip
#print axioms OriginalStructure.Span.range_using_exact
#print axioms OriginalStructure.Span.range_positions
#print axioms OriginalStructure.prepared_span_has_original_range
#print axioms OriginalStructure.complete_position
#print axioms original_record_fragment_exact
#print axioms Plan.keeps_control
#print axioms Plan.within_budget

private def check (condition : Bool) (message : String) : IO Unit :=
  unless condition do throw (IO.userError message)

private def unitValue (unit : UnitPlan) : Json :=
  toJson (unit.family,unit.ranges,unit.slice.text,unit.slice.keys,
    unit.slice.context.map fun context => (context.cues,context.fragments.map fun fragment =>
      (fragment.first,fragment.original,fragment.decoded)))

private def compare (edge : OutcomeEdge) (spans : Array OriginalStructure.Span) : IO Nat := do
  let some source := Matcher.atomText? edge.outcome | throw (IO.userError "non-text fixture")
  let envelope : ContextDelivery := {
    owner := Persistence.selectionKey edge.relation,outcome := Persistence.selectionKey edge.outcome,
    sourceChars := source.length,leading := "FRAME\n",trailing := "\nEND\n",cues := [],fragments := []}
  let family : Family := {
    owner := edge,template := {keys := [],text := envelope.render,context := some envelope,members := [],visibleKeys := []}
    windows := [0,1,3,source.length/384],references := [2],referenceRanks := [(2,0)]
    synapticRanges := [(0,0,min source.length 17),(4,source.length/2,source.length)]
    original := some spans}
  let previous := referenceOriginalRecords 3 family
  let current := prepareOriginalRecords 3 family
  check (previous.2 == current.2 && previous.1.map unitValue == current.1.map unitValue)
    "published geometry changed range/order/payload/cues/rendered candidate"
  return current.1.length

def main (args : List String) : IO Unit := do
  let [output] := args | throw (IO.userError "new output directory required")
  let root := System.FilePath.mk output
  unless !(← root.pathExists) do throw (IO.userError "preserve original structure audit")
  IO.FS.createDir root
  let snapshot ← DB.PageMap.pin (.mk "/Users/ovm/.codex/experiments/eggshell/packet-delivery-ledger-20261027/one-prepared-hook/work.egg")
  let before := snapshot.head
  let reader ← Persistence.Store.NodeReader.new snapshot
  let mut checked := #[]
  let mut kinds := #[]
  let mut nativeOwners := 0
  let mut total := 0
  for entry in ← Synapses.Build.entries snapshot do
    let edge ← reader.outcome (← Persistence.Store.locateOutcome snapshot entry.id)
    let some source := Matcher.atomText? edge.outcome | continue
    let native := Matcher.nativeOutcome edge
    if native then nativeOwners := nativeOwners+1
    let spans := OriginalStructure.prepare source
    let restored ← IO.ofExcept (fromJson? (α := Array OriginalStructure.Span) (toJson spans))
    check (restored == spans) "serialized recipes changed original intervals"
    total := total+(← compare edge restored)
    checked := checked.push (Persistence.selectionKey edge.relation,spans)
    kinds := kinds.push (Persistence.selectionKey edge.relation,native,spans.size)
  for raw in ["", "plain opaque value", "a\n\nb\n",(toJson "x\n日本語\t\\end").compress,
      "{\"resource\":\"mcp://server/item\",\"items\":[1,2,3]}"] do
    let edge := OutcomeEdge.make (.text "opaque-mcp-read") (.text raw) [] (by simp) (by simp)
    total := total+(← compare edge (OriginalStructure.prepare raw))
  let warmStarted ← IO.monoMsNow
  let rebuilt ← Synapses.Build.refresh snapshot .database
  let warmElapsed := (← IO.monoMsNow)-warmStarted
  IO.FS.writeFile (root / "changed-view.json") (toJson rebuilt).pretty
  let some index ← Synapses.Index.openShared? snapshot | throw (IO.userError "published recipes not ready")
  let cache ← Synapses.ObservedRecordView.Cache.new
  let deadline := (← IO.monoMsNow)+30000
  for (owner,expected) in checked do
    let some found ← cache.acquire index.index snapshot.head.identity owner deadline |
      throw (IO.userError "native owner has no published recipe")
    check (found.spans == expected) "published original recipe changed after page verification"
    let some reused ← cache.acquire index.index snapshot.head.identity owner deadline |
      throw (IO.userError "prepared recipe cache lost a native owner")
    check (reused.spans == expected) "shared cache changed a prepared recipe"
  let stats ← cache.stats
  check (stats.getObjValD "loads" == toJson checked.size && stats.getObjValD "hits" == toJson checked.size)
    "unchanged prepared recipes were decoded twice"
  check ((← DB.PageMap.pin snapshot.directory).head == before) "prepared publication changed original source facts"
  IO.FS.writeFile (root / "result.json") (Json.mkObj [
    ("textOwners",toJson checked.size),("nativeOwners",toJson nativeOwners),("ownerKinds",toJson kinds),
    ("candidateUnitsCompared",toJson total),
    ("sameOriginalRangesPayloadOrderCues",toJson true),("syntheticOpaqueShapes",toJson (5 : Nat)),
    ("publishedRecipeMetadataMatches",toJson true),("cache",stats),("changedViewMs",toJson warmElapsed),
    ("fullWarmCalls",toJson (0 : Nat)),("modelCalls",toJson (0 : Nat)),("adopted",toJson false)]).pretty

