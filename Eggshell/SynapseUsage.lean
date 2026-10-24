module

public import Eggshell.SynapseSource

@[expose] public section

namespace Eggshell.Synapses.Extraction
open Lean

structure Presentation where
  ranges : Array Range := #[]
  uncertain : Std.HashSet File := {}
  bindings : Array (String × Nat × Nat) := #[]
  uncertainOwners : Std.HashSet String := {}
  addressed : Array (String × Nat × Nat × List JsonScalars.Segment) := #[]

def caption (text : String) : Option (Nat × Nat × Bool) := do
  if !text.startsWith "  ORIGINAL CHARS [" && !text.startsWith "  CHARS [" then none else do
    let parts := text.splitOn "CHARS ["
    let rest ← parts[1]?
    let bounds ← (rest.splitOn ")").head?
    let [first, limit] := bounds.splitOn "," | none
    let first ← first.toNat?
    let limit ← limit.toNat?
    if first < limit then some (first, limit, text.endsWith " decoded") else none

def scalarSlice (raw : String) (first limit : Nat) : Option String :=
  if first < limit && limit ≤ raw.length then
    some (String.ofList ((raw.toList.drop first).take (limit-first))) else none

/-- Verify actual packet bytes against immutable raw coordinates before labelling. -/
def presented (body : String) (docs : Array Document) (reads : Array Read) : Presentation := Id.run do
  let mut result : Presentation := {}
  for part in body.splitOn "\nWORK GRAPH " do
    let some owner := (part.splitOn "\n").head? | continue
    let some doc := docs.find? (·.owner == owner) | continue
    let some raw := doc.source | continue
    let blocks := part.splitOn "  GROUNDED OUTCOME\n"
    let some evidence := blocks[1]? | continue
    let evidence := (evidence.splitOn "  TRACE\n").head!
    let json := JsonScalars.prepare? raw
    let rawChars := match json with | some index => index.characters | none => raw.toList.toArray
    let evidenceChars := evidence.toList.toArray
    let mut spans := #[]
    let mut addressed := #[]
    let mut path : Option String := none
    let mut bad := false
    for line in textLines evidence do
      if line.text.startsWith "  JSON PATH " then
        path := some (String.ofList (line.text.toList.drop "  JSON PATH ".length))
        continue
      let some (first, limit, decoded) := caption line.text | continue
      let location := json.bind (·.cover? first limit)
      let declared := path
      path := none
      if declared.isSome && !location.any (fun address => declared == some address.label) then
        bad := true
        continue
      if !(first < limit && limit ≤ rawChars.size) then bad := true; continue
      let segment := String.ofList (rawChars.extract first limit).toList
      let marker := "  DECODED JSON STRING DATA\n"
      let marked := literal evidenceChars line.limit (line.limit+marker.length) marker
      let expected := if decoded || marked then
          (Json.parse ("\"" ++ segment ++ "\"") >>= Json.getStr?).toOption
        else some segment
      let some expected := expected | bad := true; continue
      let dataStart := line.limit + if marked then marker.length else 0
      if dataStart+expected.length > evidenceChars.size ||
          String.ofList (evidenceChars.extract dataStart (dataStart+expected.length)).toList != expected then
        bad := true
        continue
      spans := spans.push (first, limit)
      if let some address := location then
        if declared == some address.label then addressed := addressed.push (owner,first,limit,address.path)
    if spans.isEmpty then
      let decoded := (layout raw).toOption.map (·.text)
      if !raw.isEmpty && ((evidence.splitOn raw).length > 1 ||
          decoded.any (fun text => !text.isEmpty && (evidence.splitOn text).length > 1)) then
        spans := #[(0, raw.length)]
      else bad := true
    if bad then
      result := {result with uncertainOwners := result.uncertainOwners.insert owner}
      for file in doc.files do result := {result with uncertain := result.uncertain.insert file}
    else
      result := {result with
        bindings := result.bindings ++ spans.map (fun (a,b) => (owner,a,b))
        addressed := result.addressed ++ addressed}
    for row in reads do
      if row.binding.owner == owner && spans.any (fun (first, limit) =>
          first ≤ row.binding.first && row.binding.limit ≤ limit) then
        result := {result with ranges := result.ranges.push row.source}
  return result

def Presentation.coversBinding (shown : Presentation) (binding : Binding) : Bool := Id.run do
  if shown.uncertainOwners.contains binding.owner then return false
  let spans := shown.bindings.filterMap fun (owner,first,limit) =>
    if owner == binding.owner then some (first,limit) else none
  let spans := spans.qsort fun a b => a.1 < b.1
  let covered := spans.foldl (fun position (first,limit) =>
    if first ≤ position then max position limit else position) binding.first
  return binding.first < binding.limit && binding.limit ≤ covered

def Presentation.coversAddress (shown : Presentation) (binding : Binding) (path : List JsonScalars.Segment) : Bool :=
  let bindings := shown.addressed.filterMap fun (owner,first,limit,actual) =>
    if actual == path then some (owner,first,limit) else none
  {shown with bindings}.coversBinding binding

def compactRanges (ranges : Array Range) : Array Range := Id.run do
  let mut files : Std.HashMap Subject (Array Range) := {}
  for range in ranges do files := files.insert range.subject (files[range.subject]?.getD #[] |>.push range)
  let mut result := #[]
  for (_, spans) in files do
    let mut merged : Array Range := #[]
    for span in spans.qsort (fun a b => a.first < b.first || (a.first == b.first && a.last < b.last)) do
      if let some previous := merged.back? then
        if span.first ≤ previous.last+1 then
          merged := merged.pop.push {previous with last := max previous.last span.last}
          continue
      merged := merged.push span
    result := result ++ merged
  return result

/-- Stored overlap minus verified delivery; does not expand a citation's line count. -/
def omittedRanges (requested : Range) (stored delivered : Array Range) : Array Range := Id.run do
  let mut result : Std.HashSet Range := {}
  for saved in compactRanges stored do
    if saved.subject != requested.subject then continue
    let first := max saved.first requested.first
    let last := min saved.last requested.last
    if last < first then continue
    let relevant := (delivered.filter (·.subject == requested.subject)).toList.mergeSort
      (fun a b => a.first ≤ b.first)
    let mut position := first
    for shown in relevant do
      if position > last then break
      if shown.last < position then continue
      if position < shown.first then
        result := result.insert {requested with first := position, last := min last (shown.first-1)}
      position := max position (shown.last+1)
    if position ≤ last then result := result.insert {requested with first := position, last}
  return result.toArray

structure Feedback where
  graph : Graph := .empty
  delivered : Presentation := {}
  atStart : Std.HashMap Occurrence Presentation := {}

def Feedback.present (feedback : Feedback) (packet : Presentation) : Feedback :=
  {feedback with delivered := {
    ranges := feedback.delivered.ranges ++ packet.ranges
    uncertain := feedback.delivered.uncertain.union packet.uncertain
    bindings := feedback.delivered.bindings ++ packet.bindings
    addressed := feedback.delivered.addressed ++ packet.addressed
    uncertainOwners := feedback.delivered.uncertainOwners.union packet.uncertainOwners }}

/-- A PreToolUse packet arriving after proposal cannot rewrite what was known. -/
def Feedback.start (feedback : Feedback) (occurrence : Occurrence) : Feedback :=
  if feedback.atStart.contains occurrence then feedback else
    {feedback with atStart := feedback.atStart.insert occurrence feedback.delivered}

def Feedback.completedRead (feedback : Feedback) (occurrence : Occurrence) (query : String)
    (requested stored : Array Range) : Except String Feedback := do
  let some earlier := feedback.atStart[occurrence]? | throw "read has no observed start"
  let mut graph := feedback.graph
  let mut ordinal := 0
  for source in compactRanges requested do
    let checked := match source.subject with
      | .file file => !earlier.uncertain.contains file
      | .original _ => earlier.uncertainOwners.isEmpty
    let gaps := if checked then omittedRanges source stored earlier.ranges else #[]
    for gap in if gaps.isEmpty then #[source] else gaps do
      graph ← graph.recordRead ⟨occurrence, ordinal⟩ query gap stored earlier.ranges checked
      ordinal := ordinal+1
  return {feedback with graph}

def Feedback.answer (feedback : Feedback) (occurrence : Occurrence) (query text : String) :
    Except String Feedback := do
  let files := feedback.delivered.ranges.foldl (fun files range =>
    (range.file?.map files.insert).getD files) ({} : Std.HashSet File)
  let cited := paragraphCitations text files.toArray
  let mut graph := feedback.graph
  for index in [:cited.size] do
    graph ← graph.recordCitation ⟨occurrence, index⟩ query cited[index]! feedback.delivered.ranges
  return {feedback with graph}

end Eggshell.Synapses.Extraction
