import Eggshell.Handoff
import tools.ExactMemo

open Lean Eggshell Plugin

private structure CollisionKey where
  value : Nat
  deriving DecidableEq
private instance : Hashable CollisionKey := ⟨fun _ => 0⟩

private def check (accepted : Bool) (message : String) : IO Unit :=
  unless accepted do throw (IO.userError message)

private def sequences (choices : List α) : Nat → List (List α)
  | 0 => [[]]
  | n + 1 => [] :: choices.flatMap (fun item => (sequences choices n).map (item :: ·))

/-- Independent unchanged loop bodies, avoiding compiler redirection of the
old public functions when comparing actual native list results. -/
private def referenceViews (records : List (ContextSpan source)) (heads : List (Nat × Option Nat))
    (decoded : Option (DecodedLayout source)) (ranges : List (EvidenceRange source)) : List (EvidenceView source) :=
  ranges.flatMap fun range =>
    let part := prerequisiteContextRange records heads range
    let coherent := coherentRecordContext records heads part
    let alternatives := if coherent.start == part.start && coherent.stop == part.stop then [part] else [coherent, part]
    alternatives.filterMap fun candidate => match decoded with
      | none => some (.original candidate)
      | some value => (decodedEvidenceUsing? value candidate).map EvidenceView.decoded

private def signature (views : List (EvidenceView source)) : Json :=
  toJson (views.map fun view => match view with
    | .original range => (false, range.start, range.stop, 0, 0, range.text)
    | .decoded evidence => (true, evidence.original.start, evidence.original.stop,
        evidence.content.start, evidence.content.stop, evidence.content.text))

private def range? (source : String) (first width : Nat) : Option (EvidenceRange source) :=
  let last := min source.length (first + width)
  if h : first < last ∧ last ≤ source.length ∧ last - first ≤ 2048 then
    some ⟨first, last, h.1, h.2.1, h.2.2⟩ else none

def main : IO UInt32 := do
  let mut checks := 0
  for items in sequences [0, 1, 2, 3] 5 do
    let f := fun n => if n % 2 == 0 then some (n * n) else none
    check (ExactMemo.filterMap f items == items.filterMap f) "memo changed order, duplicates or absent values"
    let colliding := items.map CollisionKey.mk
    let f := fun key : CollisionKey => if key.value % 2 == 0 then some (key.value * key.value) else none
    check (ExactMemo.filterMap f colliding == colliding.filterMap f) "collision changed a checked result"
    checks := checks + 2
  let text := String.intercalate "" (List.replicate 200 "record α日本語🐣 \\\"quoted\\\"\tvalue\n")
  let mut rangeChecks := 0
  let mut sliceChecks := 0
  for source in [text, (Json.str text).compress, r#""\u0061""#] do
    let indexed := IndexedCharacters.make source
    for first in [0, 1, 2, 3, 400, 1500, source.length - 1, source.length, source.length + 1] do
      for count in [0, 1, 2, 16, 2048, source.length + 3] do
        check (indexed.slice first count == ((source.drop first).take count).copy)
          "indexed characters changed Unicode, empty or clamped String coordinates"
        sliceChecks := sliceChecks + 1
    let layout := (decodedToolText? source).map DecodedLayout.make
    let records := contextRecordSpans source layout
    let heads := contextStructureHeads source layout
    let ranges := ([0, 1, 3, 10, 400, 1300, 2100, 4000, 5000] : List Nat).flatMap fun first =>
      ([1, 16, 128, 512, 2048] : List Nat).filterMap (range? source first)
    let ranges := ranges ++ ranges.reverse ++ ranges
    check (signature (prepareContextViewsFast records heads layout ranges) ==
        signature (referenceViews records heads layout ranges))
      "memoized views changed an original interval, occurrence, decode or duplicate"
    rangeChecks := rangeChecks + ranges.length
  IO.println (Json.mkObj [("passed", toJson true), ("mapChecks", toJson checks),
    ("rangeInputs", toJson rangeChecks), ("sliceChecks", toJson sliceChecks),
    ("generationModelCalls", toJson (0 : Nat)),
    ("productionAdoption", toJson false)]).compress
  pure 0
