module
public import Eggshell.OriginalStructure
public import Eggshell.Matcher
public import Eggshell.SourceEvidence
@[expose] public section
namespace Eggshell.Plugin
open Lean

/-- A locator in historical prose is only a hint into an already loaded
observation with the same recorded dependency. It is never followed as a path. -/
def citedLineNumbers (texts : List String) (relative : String) : List Nat :=
  if !SourceEvidence.safeRelative relative then [] else
    (texts.flatMap fun text => [relative ++ ":", relative ++ "#L"].flatMap fun marker =>
      ((text.splitOn marker).drop 1).filterMap fun rest =>
        (String.ofList (rest.toList.takeWhile Char.isDigit)).toNat?).eraseDups

/-- A closed line interval in a stored citation. Unsupported or conflicting
Markdown locators are ignored; this parser never opens a path. -/
def citationBounds? (text : String) : Option (Nat × Nat) := do
  let chars := text.toList
  let digits := chars.takeWhile Char.isDigit
  let first ← (String.ofList digits).toNat?
  if first == 0 then none else do
    let rest := chars.drop digits.length
    if rest.isEmpty then some (first,first) else do
      let dash ← rest.head?
      if dash != '-' && dash != '–' && dash != '—' then none else do
        let tail := rest.drop 1
        let tail := if tail.head? == some 'L' then tail.drop 1 else tail
        let last ← (String.ofList tail).toNat?
        if first ≤ last then some (first,last) else none

def citationTarget? (text relative : String) : Option (Nat × Nat) :=
  [relative ++ ":",relative ++ "#L"].findSome? fun marker =>
    match text.splitOn marker with
    | [leading,bounds] =>
        if leading.isEmpty || leading.endsWith "/" then citationBounds? bounds else none
    | _ => none

def citedLineIntervals (text relative : String) : List (Nat × Nat) :=
  if !SourceEvidence.safeRelative relative then [] else
    ((text.splitOn "](").drop 1).zipIdx.filterMap fun (tail,index) => do
      let before ← (text.splitOn "](")[index]?
      let label ← (before.splitOn "[").getLast?
      let target ← (tail.splitOn ")").head?
      let destination ← citationTarget? target relative
      let explicitRange := [relative ++ ":",relative ++ "#L"].any fun marker =>
        ((target.splitOn marker).drop 1).any fun bounds =>
          !(bounds.toList.dropWhile Char.isDigit).isEmpty
      let basename := (relative.splitOn "/").getLast?.getD relative
      let displayed := (label.splitOn (basename ++ ":")).drop 1
      match displayed with
      | [] => some destination
      | [bounds] => do
          let shown ← citationBounds? bounds
          if shown.1 == destination.1 &&
              (!explicitRange || shown.2 == destination.2) then
            some shown else none
      | _ => none

def observedLineNumber? (text : String) : Option (Nat × Char) := do
  let chars := text.toList.dropWhile (· == ' ')
  let digits := chars.takeWhile Char.isDigit
  if digits.isEmpty then none else do
    let number ← (String.ofList digits).toNat?
    let delimiter ← (chars.drop digits.length).head?
    if delimiter == '\t' || delimiter == ':' then some (number, delimiter) else none

/-- Independent numbered read ranges have explicit discontinuities. Keep a
short complete companion range when the same original observation supports
a citation; this also handles multi-file reads without guessing source syntax.
All offsets remain in the canonical saved scalar, including JSON escapes. -/
def observedNumberedSegments (source : String) (layout : Option (DecodedLayout source)) :
    List (ContextSpan source × List Nat) := Id.run do
  let text := layout.map (·.decoded.text) |>.getD source
  let rows := (contextRecordSpans source layout).zip (text.splitOn "\n")
  let mut groups : List (ContextSpan source × List Nat) := []
  let mut previous : Option (Nat × Char) := none
  for (span, text) in rows do
    match observedLineNumber? text with
    | none => previous := none
    | some (number, delimiter) =>
        if previous == some (number - 1, delimiter) && number > 0 then
          match groups with
          | (first, numbers) :: rest =>
              if valid : first.start < span.stop then
                groups := (⟨first.start, span.stop, valid, span.within⟩, number :: numbers) :: rest
              else groups := (span, [number]) :: groups
          | [] => groups := [(span, [number])]
        else groups := (span, [number]) :: groups
        previous := some (number, delimiter)
  return groups.reverse.map fun (span, numbers) => (span,numbers.reverse)

/-- Existing directory positions covering an original observed scalar span. -/
def observedSpanWindows (workChars : Nat) (span : ContextSpan source) : List Nat :=
  let first := (workChars + span.start) / 384
  let last := (workChars + span.stop - 1) / 384
  (List.range (last + 1 - first)).map (· + first)

/-- Literal native read metadata can locate an unnumbered observation too.
Only a single fixed numeric print range is understood. Existing shell parsing
rejects expansions and operators; unsupported output ends the projected prefix.
This is a data-selection hint, never an equation for external shell behavior. -/
def literalReadRange? (segment : String) : Option (String × Nat × Nat) := do
  let words ← SourceEvidence.literalWords? segment
  match words with
  | ["sed", "-n", program, file] =>
      if !program.endsWith "p" then none else do
        let bounds := (program.dropEnd 1).copy.splitOn ","
        let (first, last) ← match bounds with
          | [first, last] => do pure (← first.toNat?, ← last.toNat?)
          | [line] => do let value ← line.toNat?; pure (value,value)
          | _ => none
        if first > 0 && first ≤ last then some (file,first,last) else none
  | _ => none

def nativeReadPrefix (work : String) : List (String × Nat × Nat) := Id.run do
  let input := Json.parse ("\n".intercalate ((work.splitOn "\n").drop 1)) |>.toOption
  let command := input.bind fun input =>
    (input.getObjValAs? String "command").toOption.orElse
      (fun _ => (input.getObjValAs? String "cmd").toOption)
  let segments := command.bind SourceEvidence.sequenceSegments? |>.getD []
  let mut result := []
  for segment in segments do
    let some range := literalReadRange? segment | return result
    result := result ++ [range]
  return result

/-- Project the recorded read prefix into existing original scalar rows.
No file is opened. Every returned range is an actual bounded observation;
the external command/OS relation remains advisory and freshness is separate. -/
def nativeReadRowsUsing (rows : Array (ContextSpan source))
    (plans : List (String × Nat × Nat)) (records : List SourceEvidence.Record) :
    List (ContextSpan source × Nat) := Id.run do
  let files := (records.flatMap (·.files)).map (·.relative)
  let mut offset := 0
  let mut result := []
  for (file, first, last) in plans do
    let count := last + 1 - first
    if count > rows.size - offset then return result.reverse
    if files.any (fun relative => file == relative || file.endsWith ("/" ++ relative)) then
      for i in List.range count do
        if let some span := rows[offset + i]? then
          result := (span,first+i) :: result
    offset := offset + count
  return result.reverse

def nativeReadRows (source : String) (layout : Option (DecodedLayout source))
    (work : String) (records : List SourceEvidence.Record) :
    List (ContextSpan source × Nat) :=
  nativeReadRowsUsing (contextRecordSpans source layout).toArray (nativeReadPrefix work) records

theorem native_read_rows_factored (source : String) (layout : Option (DecodedLayout source))
    (work : String) (records : List SourceEvidence.Record) :
    nativeReadRows source layout work records = (Id.run do
      let rows := (contextRecordSpans source layout).toArray
      let files := (records.flatMap (·.files)).map (·.relative)
      let mut offset := 0
      let mut result := []
      for (file, first, last) in nativeReadPrefix work do
        let count := last + 1 - first
        if count > rows.size - offset then return result.reverse
        if files.any (fun relative => file == relative || file.endsWith ("/" ++ relative)) then
          for i in List.range count do
            if let some span := rows[offset + i]? then
              result := (span,first+i) :: result
        offset := offset + count
      return result.reverse) := rfl

/-- A long interpretation cannot hide another admitted interpretation's
references behind all of its own. No history timestamp or source language is
needed: visit each original list once per depth. -/
def balancedReferenceNumbers (rows : List (List Nat)) : List Nat :=
  let depths := rows.foldl (fun n row => max n row.length) 0
  ((List.range depths).flatMap fun depth => rows.filterMap (·[depth]?)).eraseDups

/-- Resolve prose citations only against recorded source dependencies and
original numbered rows. Ambiguous multi-file row numbers can offer multiple
original ranges, but cannot assert file identity or completion. -/
def citedObservationCoordinates (texts : List String) (owner : OutcomeEdge)
    (records : List SourceEvidence.Record) : Option (Nat × List Nat) := Id.run do
  let numbers := balancedReferenceNumbers (texts.map fun text =>
    ((records.flatMap (·.files)).flatMap fun file => citedLineNumbers [text] file.relative).eraseDups)
  if numbers.isEmpty then return none
  let some source := Matcher.atomText? owner.outcome | return none
  let some work := Matcher.atomText? owner.work | return none
  let layout := (decodedToolText? source).map DecodedLayout.make
  let text := layout.map (·.decoded.text) |>.getD source
  let rows := (contextRecordSpans source layout).zip (text.splitOn "\n")
  let native := nativeReadRows source layout work records
  let indexed := numbers.zipIdx.filterMap fun (number, priority) =>
    let spans := (rows.filterMap fun (span, row) =>
      if (observedLineNumber? row).any (·.1 == number) then some span else none) ++
      (native.filterMap fun (span, line) => if line == number then some span else none)
    if spans.isEmpty then none else some (priority,spans)
  let some first := indexed.head? | return none
  let cited := indexed.flatMap Prod.snd
  let compact := (observedNumberedSegments source layout).filterMap fun (span, rows) =>
    if rows.length > 1 && span.stop - span.start ≤ 2048 then some span else none
  return some (first.1,((cited ++ compact).flatMap (observedSpanWindows (work.length + 1))).eraseDups)

/-- Preserve the producer's actual nomination rank for each projected
window. Only already admitted, graph-reachable observations are supplied.
Neither a citation nor its rank adds equality or completion authority. -/
def rankedCitedObservationCoordinates (texts : List (Nat × String)) (owner : OutcomeEdge)
    (records : List SourceEvidence.Record) : Option
      (Nat × List Nat × List (Nat × Nat) × List (Nat × List (Nat × Nat))) := Id.run do
  let some source := Matcher.atomText? owner.outcome | return none
  let some work := Matcher.atomText? owner.work | return none
  let layout := (decodedToolText? source).map DecodedLayout.make
  let text := layout.map (·.decoded.text) |>.getD source
  let rows := (contextRecordSpans source layout).zip (text.splitOn "\n")
  let native := nativeReadRows source layout work records
  let mut hints : List (Nat × Nat) := []
  let mut groups : List (Nat × List (Nat × Nat)) := []
  for (priority,parent) in texts do
    let intervals := ((records.flatMap (·.files)).flatMap fun file =>
      citedLineIntervals parent file.relative).eraseDups
    for (first,last) in intervals do
      -- Filter finite saved rows, never enumerate an untrusted interval.
      let numbered := (rows.filterMap fun (span,row) => do
        let (number,_) ← observedLineNumber? row
        if first ≤ number && number ≤ last then some (number,span) else none) ++
        (native.filterMap fun (span,number) =>
          if first ≤ number && number ≤ last then some (number,span) else none)
      let spans := numbered.map Prod.snd
      -- Completeness counts the finite stored row domain; it never expands
      -- citation-controlled line bounds into a new allocation or file read.
      if (numbered.map Prod.fst).eraseDups.length == last-first+1 && !spans.isEmpty then
        let original := (spans.map fun span => (span.start,span.stop)).eraseDups
        if !groups.contains (priority,original) then groups := groups ++ [(priority,original)]
      for position in (spans.flatMap (observedSpanWindows (work.length+1))).eraseDups do
        match hints.find? (·.1 == position) with
        | none => hints := hints ++ [(position,priority)]
        | some (_,old) => if priority < old then
            hints := hints.map fun row => if row.1 == position then (position,priority) else row
  let some first := hints.head? | return none
  return some (first.2,hints.map Prod.fst,hints,groups)

def citedObservationWindows (texts : List String) (owner : OutcomeEdge)
    (records : List SourceEvidence.Record) : List Nat :=
  (citedObservationCoordinates texts owner records).map Prod.snd |>.getD []


#print axioms native_read_rows_factored
end Eggshell.Plugin
