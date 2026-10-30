/-- Complete original outcomes are a bounded Work-level transport alternative.
No source fragment is rescored inside an accepted complete packet. -/
def completeSlice (family : Family) (context : ContextDelivery) : TransportSlice :=
  {family.template with
    owner := some family.owner.relation,keys := context.keys,
    text := context.render,context := some context,shared := none}

theorem complete_slice_keeps_members (family : Family) (context : ContextDelivery) :
    (completeSlice family context).members = family.template.members := rfl

def completeSourceSlice? (family : Family) : Option TransportSlice := do
  let true := family.template.members.all (fun member => !member.blocks) | none
  let source ← Matcher.atomText? family.owner.outcome
  let work ← Matcher.atomText? family.owner.work
  let spans ← family.completeOriginal
  let _ ← Eggshell.Research.CompleteOriginal.check? source.length spans
  let characters := source.toList.toArray
  let mut fragments : List DeliveryFragment := []
  for span in spans do
    fragments := fragments ++ [{
      first := span.first,
      original := String.ofList (characters.extract span.first span.limit).toList,decoded := span.decoded}]
  let owner := relationKey family.owner.relation
  let outcome := relationKey family.owner.outcome
  let provenance := "\n".intercalate (family.provenance.map fun record =>
    "    workspace=" ++ record.workspace ++ " relative=" ++
      ", ".intercalate (record.files.map (·.relative) ++ record.uris))
  let context : ContextDelivery := {
    owner,outcome,sourceChars := source.length,cues := [(0,source.length)]
    envelopeKey := "f:outcome:" ++ owner ++ ":" ++ outcome
    leading := "WORK GRAPH " ++ owner ++ "\n  WORK\n" ++ work ++
      "\n  GROUNDED OUTCOME\n  EVIDENCE " ++ displayKey family.owner.outcome ++
      "\n  [Complete recorded original result; advisory unless separately certified.]\n"
    trailing := "\n  TRACE\n" ++ "\n".intercalate (family.owner.observations.map renderObservation) ++
      "\n  OBSERVED SOURCES\n" ++ provenance ++ "\nEND WORK GRAPH\n"
    fragments,compactCaptions := true}
  return completeSlice family context

def completeWorkFit (ceiling : Nat × Nat) (cost : List TransportSlice → Nat × Nat)
    (families : List Family) (mandatory : List TransportSlice) : Option (Fitted ceiling cost mandatory) := do
  let mut inputBytes := 0
  for family in families do
    let source ← Matcher.atomText? family.owner.outcome
    let work ← Matcher.atomText? family.owner.work
    inputBytes := inputBytes+source.utf8ByteSize+work.utf8ByteSize
    if ceiling.2 < inputBytes then none
  let complete ← families.mapM completeSourceSlice?
  let result := mandatory ++ complete
  if fits : (cost result).1 ≤ ceiling.1 ∧ (cost result).2 ≤ ceiling.2 then
    some ⟨result,fits.1,fits.2,⟨complete,rfl⟩⟩
  else none

