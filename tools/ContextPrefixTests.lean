import Eggshell.Handoff
import tools.PairDecisions

open Lean Eggshell Plugin

private def check (accepted : Bool) (message : String) : IO Unit :=
  unless accepted do throw (IO.userError message)

-- The old decoder loop is copied unchanged under a fresh name. Compiler
-- equalities of the public decoder cannot redirect this independent oracle.
private def referenceDecode (layout : DecodedLayout source) (requested : EvidenceRange source) :
    Option (DecodedEvidence source) := do
  let decoded := layout.decoded
  let mut position := 1
  let mut first := none
  let mut last := 0
  let mut rawStart := 0
  let mut rawStop := 0
  for (index, width) in layout.widths do
    if position ≥ requested.stop then break
    let next := position + width
    if requested.start ≤ position && next ≤ requested.stop then
      if first.isNone then
        first := some index
        rawStart := position
      last := index + 1
      rawStop := next
    position := next
  let start ← first
  if bounds : start < last ∧ last ≤ decoded.text.length ∧ last - start ≤ 2048 then
    let content : EvidenceRange decoded.text := ⟨start, last, bounds.1, bounds.2.1, bounds.2.2⟩
    -- Accumulated positions nominate coordinates only. Bounded reencoding
    -- and the prefix certificate validate the exact original occurrence.
    if rawBounds : rawStart < rawStop ∧ rawStop ≤ source.length ∧ rawStop - rawStart ≤ 2048 ∧
        requested.start ≤ rawStart ∧ rawStop ≤ requested.stop then
      let original : EvidenceRange source := ⟨rawStart, rawStop, rawBounds.1,
        rawBounds.2.1, rawBounds.2.2.1⟩
      if reencoded : encodedTextBody content.text = original.text then
        if prefixExact : (source.take original.start).copy = "\"" ++
            encodedTextBody ((decoded.text.take content.start).copy) then
          some ⟨decoded, content, original, reencoded,
            by
              have samePrefix : (decoded.text.take content.start).copy =
                  String.ofList (decoded.text.toList.take content.start) := by
                apply String.ext
                simp
              simpa only [samePrefix] using prefixExact⟩
        else none
      else none
    else none
  else none

private def range? (source : String) (first count : Nat) : Option (EvidenceRange source) :=
  let last := min source.length (first + count)
  if h : first < last ∧ last ≤ source.length ∧ last - first ≤ 2048 then
    some ⟨first, last, h.1, h.2.1, h.2.2⟩ else none

private def signature (found : Option (DecodedEvidence source)) : Json :=
  match found with
  | none => Json.null
  | some found => toJson (found.original.start, found.original.stop,
      found.content.start, found.content.stop, found.original.text, found.content.text)

private def tracedPredicate (first second : Nat) : Prop := (first + second) % 3 = 0
private instance : DecidableRel tracedPredicate := fun first second =>
  dbg_trace s!"prefix-leaf {first} {second}"; Nat.decEq ((first + second) % 3) 0

def main : IO UInt32 := do
  let mut decisionChecks := 0
  for width in [0, 1, 7, 32] do
    let predicate := fun first second => (first + 2 * second) % 3 = 0
    let table := PairDecisions.make predicate width 8
    for first in [:8] do
      for second in [:12] do
        check (@decide _ (table.decision first second) == decide ((first + 2 * second) % 3 = 0))
          "pair decision changed a false, zero-stride or outside coordinate"
        decisionChecks := decisionChecks + 1
  let odd := PairDecisions.make (fun first second => (first + second) % 2 = 1) 8 6
  let even := PairDecisions.make (fun first second => (first + second) % 2 = 0) 8 6
  for first in [:8] do
    for second in [:8] do
      check (@decide _ (odd.decision first second) != @decide _ (even.decision first second))
        "different predicates shared a decision"
      decisionChecks := decisionChecks + 1
  let mut ranges := 0
  let mut rejected := 0
  let text := String.intercalate "" (List.replicate 160 "record 日本語🐣 α \"quote\"\tvalue\n")
  for source in [(Json.str text).compress, (Json.str "α\\\"\n🐣 duplicate duplicate\t日本語").compress,
      (Json.str "").compress, r#""\u0061""#] do
    match decodedToolText? source with
    | none => rejected := rejected + 1
    | some decoded =>
      let layout := DecodedLayout.make decoded
      let selected := ([0, 1, 2, 3, 7, 17, 63, 100, 511, 1024, 2047, 4096, source.length - 1] : List Nat).flatMap fun first =>
        ([1, 2, 3, 16, 128, 512, 2048] : List Nat).filterMap (range? source first)
      for range in selected ++ selected.reverse ++ selected do
        check (signature (decodedEvidenceUsing? layout range) == signature (referenceDecode layout range))
          "prefix sharing changed a decoded occurrence, rejection, boundary or original body"
        ranges := ranges + 1
  check (rejected == 1 && ranges > 300) "canonical/noncanonical scalar fixtures did not run"
  -- An observed computation trace verifies sharing in the compiled program.
  let table := PairDecisions.make tracedPredicate 16 12
  let addresses := [(0, 0), (0, 1), (2, 3), (7, 9), (20, 15), (100, 0)]
  let mut nativeDecisionChecks := 0
  for _ in [:3] do
    for (first, second) in addresses ++ addresses.reverse do
      check (@decide _ (table.decision first second) == @decide _ (Nat.decEq ((first + second) % 3) 0))
        "shared native decision changed truth"
      nativeDecisionChecks := nativeDecisionChecks + 1
  IO.println (Json.mkObj [("passed", toJson true), ("decisionChecks", toJson (decisionChecks + nativeDecisionChecks)),
    ("rangeChecks", toJson ranges), ("rejectedNoncanonical", toJson rejected),
    ("expectedNativePrefixEvaluations", toJson (6 : Nat)),
    ("generationModelCalls", toJson (0 : Nat)), ("productionAdoption", toJson false)]).compress
  pure 0
