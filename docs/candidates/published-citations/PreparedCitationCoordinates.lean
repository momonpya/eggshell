module
public import Eggshell.CitationCoordinates
@[expose] public section

namespace Eggshell.Research.PreparedCitationCoordinates
open Lean Plugin

abbrev Result := Nat × List Nat × List (Nat × Nat) × List (Nat × List (Nat × Nat))

/-- Only original coordinates and relative filenames survive preparation.
Decoded output strings and command parsers are absent from the query loop. -/
structure Data (source : String) where
  workChars : Nat
  files : List String
  numbered : List (Nat × ContextSpan source)

def numbered (rows : List (ContextSpan source × String)) : List (Nat × ContextSpan source) :=
  rows.filterMap fun (span,row) => do
    let (number,_) ← observedLineNumber? row
    return (number,span)

def inside (first last : Nat) (entry : Nat × ContextSpan source) : Bool :=
  first ≤ entry.1 && entry.1 ≤ last

theorem numbered_filter (rows : List (ContextSpan source × String)) (first last : Nat) :
    (numbered rows).filter (inside first last) =
      rows.filterMap (fun (span,row) => do
        let (number,_) ← observedLineNumber? row
        if first ≤ number && number ≤ last then some (number,span) else none) := by
  induction rows with
  | nil => rfl
  | cons row rows ih =>
    rcases row with ⟨span,text⟩
    cases found : observedLineNumber? text with
    | none => simpa [numbered,found] using ih
    | some value =>
      rcases value with ⟨number,delimiter⟩
      by_cases selected : first ≤ number ∧ number ≤ last
      · simp_all [numbered,inside]
      · simp_all [numbered,inside]

theorem all_numbered_filter (rows : List (ContextSpan source × String))
    (native : List (ContextSpan source × Nat)) (first last : Nat) :
    (numbered rows ++ native.map Prod.swap).filter (inside first last) =
      (rows.filterMap fun (span,row) => do
        let (number,_) ← observedLineNumber? row
        if first ≤ number && number ≤ last then some (number,span) else none) ++
      (native.filterMap fun (span,number) =>
        if first ≤ number && number ≤ last then some (number,span) else none) := by
  rw [List.filter_append,numbered_filter]
  congr 1
  induction native with
  | nil => rfl
  | cons entry rest ih =>
    rcases entry with ⟨span,number⟩
    by_cases selected : first ≤ number ∧ number ≤ last
    · simp_all [inside]
    · simp_all [inside]

def prepare (owner : OutcomeEdge) (records : List SourceEvidence.Record) :
    Option (Sigma Data) := do
  let source ← Matcher.atomText? owner.outcome
  let work ← Matcher.atomText? owner.work
  let layout := (decodedToolText? source).map DecodedLayout.make
  let text := layout.map (·.decoded.text) |>.getD source
  let rows := (contextRecordSpans source layout).zip (text.splitOn "\n")
  let native := nativeReadRows source layout work records
  return ⟨source,work.length+1,(records.flatMap (·.files)).map (·.relative),
    numbered rows ++ native.map Prod.swap⟩

def Data.queryUsing (data : Data source) (parse : Nat → String → String → List (Nat × Nat))
    (texts : List (Nat × String)) : Option Result := Id.run do
  let mut hints : List (Nat × Nat) := []
  let mut groups : List (Nat × List (Nat × Nat)) := []
  for (priority,parent) in texts do
    let intervals := (data.files.flatMap (parse priority parent)).eraseDups
    for (first,last) in intervals do
      let numbered := data.numbered.filter (inside first last)
      let spans := numbered.map Prod.snd
      if (numbered.map Prod.fst).eraseDups.length == last-first+1 && !spans.isEmpty then
        let original := (spans.map fun span => (span.start,span.stop)).eraseDups
        if !groups.contains (priority,original) then groups := groups ++ [(priority,original)]
      for position in (spans.flatMap (observedSpanWindows data.workChars)).eraseDups do
        match hints.find? (·.1 == position) with
        | none => hints := hints ++ [(position,priority)]
        | some (_,old) => if priority < old then
            hints := hints.map fun row => if row.1 == position then (position,priority) else row
  let some first := hints.head? | return none
  return some (first.2,hints.map Prod.fst,hints,groups)

def Data.query (data : Data source) (texts : List (Nat × String)) : Option Result :=
  data.queryUsing (fun _ => citedLineIntervals) texts

def query (data : Option (Sigma Data)) (texts : List (Nat × String)) : Option Result :=
  data.bind fun data => data.2.query texts

theorem query_prepare_exact (texts : List (Nat × String)) (owner : OutcomeEdge)
    (records : List SourceEvidence.Record) :
    query (prepare owner records) texts = rankedCitedObservationCoordinates texts owner records := by
  unfold prepare query rankedCitedObservationCoordinates
  cases Matcher.atomText? owner.outcome with
  | none => simp
  | some source =>
    cases Matcher.atomText? owner.work with
    | none => simp
    | some work =>
      simp only [Option.pure_def,bind,Option.bind]
      unfold Data.query Data.queryUsing
      simp only [List.flatMap_map,all_numbered_filter]
      rfl

end Eggshell.Research.PreparedCitationCoordinates
