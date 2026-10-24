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

structure SharedSpelling where
  file : File
  number : Nat
  code : String
  origins : Array (String × String × String × Occurrence)

/-- Decode only complete shared frames. This grants no original-byte status;
callers must bind each spelling to their saved original rows. -/
def sharedSpellings (body : String) : Array SharedSpelling := Id.run do
  let wrapper := "EGGSHELL SHARED SOURCE DATA\nOriginal recorded file data; advisory, not a completed operation.\n"
  let mut found : Array SharedSpelling := #[]
  for packet in (body.splitOn wrapper).tail do
    let parts := packet.splitOn "END EGGSHELL SHARED SOURCE DATA\n"
    if parts.length < 2 then continue
    for block in (("\n" ++ parts.head!).splitOn "\nSOURCE ").tail do
      let parts := block.splitOn "\nEND SOURCE"
      if parts.length < 2 then continue
      let suffix := parts[1]!
      if !suffix.isEmpty && !suffix.startsWith "\n" then continue
      let fileLine :: originsLine :: "CODE" :: codeLines := parts.head!.splitOn "\n" | continue
      let some file := (Json.parse fileLine >>= fromJson? (α := File)).toOption | continue
      if !file.valid || !originsLine.startsWith "ORIGINAL READS " then continue
      let encoded := String.ofList (originsLine.toList.drop "ORIGINAL READS ".length)
      let some origins := (Json.parse encoded >>= fromJson? (α := Array String)).toOption | continue
      let origins := origins.filterMap fun origin =>
        (Json.parse origin >>= fromJson? (α := String × String × String × Occurrence)).toOption
      for line in codeLines do
        let some (number,code) := numbered line | continue
        found := found.push ⟨file,number,code,origins⟩
  return found

/-- A shared spelling can report only a range belonging to an original saved
row. Sharing the payload never manufactures another execution witness. -/
structure SharedWitness (reads : Array Read) where
  row : Read
  original : row ∈ reads
  file : File
  number : Nat
  code : String
  sourceExact : row.source = ⟨file,number,number⟩

theorem SharedWitness.original_range (witness : SharedWitness reads) :
    ∃ row ∈ reads, row.source = ⟨witness.file,witness.number,witness.number⟩ :=
  ⟨witness.row,witness.original,witness.sourceExact⟩

/-- Recognize the producer's shared file frame, then compare every displayed
code row with its raw scalar coordinates and declared DB/owner/Work/occurrence.
Location-only notices and arbitrary matching prose cannot label delivery. -/
def sharedPresented (body : String) (docs : Array Document) (reads : Array Read) :
    Array (SharedWitness reads) := Id.run do
  let displayed := sharedSpellings body
  if displayed.isEmpty || reads.isEmpty then return #[]
  let mut index : Std.HashMap (File × Nat × String) (Array (SharedWitness reads)) := {}
  let byOwner := reads.attach.foldl (fun found saved =>
    found.insert saved.val.binding.owner
      ((found.getD saved.val.binding.owner #[]).push saved))
    ({} : Std.HashMap String (Array {row // row ∈ reads}))
  for doc in docs do
    if !doc.native then continue
    let some raw := doc.source | continue
    let .ok decoded := layout raw | continue
    for line in textLines decoded.text do
      let some (number,code) := numbered line.text | continue
      for saved in byOwner.getD doc.owner #[] do
        let row := saved.val
        if !row.valid || row.binding.work != doc.work ||
            row.binding.first != decoded.offsets[line.first]! ||
            row.binding.limit != decoded.offsets[line.limit]! then continue
        let .file file := row.source.subject | continue
        if same : row.source = ⟨file,number,number⟩ then
          let witness : SharedWitness reads := ⟨row,saved.property,file,number,code,same⟩
          let key := (file,number,code)
          index := index.insert key ((index.getD key #[]).push witness)
  let mut found := #[]
  for spelling in displayed do
    for witness in index.getD (spelling.file,spelling.number,spelling.code) #[] do
      let row := witness.row
      if spelling.origins.contains (row.binding.database,row.binding.owner,row.binding.work,row.occurrence) then
        found := found.push witness
  return found

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
  for witness in sharedPresented body docs reads do
    result := {result with
      ranges := result.ranges.push witness.row.source
      bindings := result.bindings.push
        (witness.row.binding.owner,witness.row.binding.first,witness.row.binding.limit)}
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
      graph ← graph.recordRead ⟨occurrence, ordinal, none⟩ query gap stored earlier.ranges checked
      ordinal := ordinal+1
  return {feedback with graph}

def Feedback.answer (feedback : Feedback) (occurrence : Occurrence) (query text : String) :
    Except String Feedback := do
  let files := feedback.delivered.ranges.foldl (fun files range =>
    (range.file?.map files.insert).getD files) ({} : Std.HashSet File)
  let cited := paragraphCitations text files.toArray
  let mut graph := feedback.graph
  for index in [:cited.size] do
    graph ← graph.recordCitation ⟨occurrence, index, none⟩ query cited[index]! feedback.delivered.ranges
  return {feedback with graph}

/-- A native usage label may cover only an actual located consumption witness.
The native row remains tied to its original Work and response digest. -/
structure ConsumedSource (edge : Consumption) where
  source : Range
  valid : edge.valid = true
  native : source.file?.isNone = true
  consumed : edge.rows.any (·.contains source) = true

def consumedSource? (edge : Consumption) (source : Range) : Option (ConsumedSource edge) :=
  if valid : edge.valid = true then
    if native : source.file?.isNone = true then
      if consumed : edge.rows.any (·.contains source) = true then
        some ⟨source,valid,native,consumed⟩ else none
    else none
  else none

theorem consumed_source_has_witness (checked : ConsumedSource edge) :
    ∃ row ∈ edge.rows, row.contains checked.source = true := by
  obtain ⟨index,bound,present⟩ := Array.any_eq_true.mp checked.consumed
  exact ⟨edge.rows[index],by simp,present⟩

theorem consumed_source_is_later (checked : ConsumedSource edge) :
    edge.producerFinish < edge.consumerStart := by
  exact Consumption.checked_before (edge := edge) (accepted := edge)
    (by simp [Consumption.checked,checked.valid])

/-- Literal reuse is advisory evidence, not proof of semantic necessity. The
caller supplies immutable pre-read stored and ACK ranges; no returned sibling
field is labelled merely because it was present in the tool's response. -/
def consumedUsage? (checked : ConsumedSource edge) (query : String)
    (stored delivered : Array Range) : Option Usage :=
  if covered checked.source stored && !covered checked.source delivered then some {
    event := {occurrence := edge.producer,ordinal := 0,consumption := some ⟨edge.consumer,checked.source⟩}
    query,source := checked.source,kind := .omittedThenConsumed}
  else none

theorem consumed_omission_requires_stored (checked : ConsumedSource edge)
    (observed : consumedUsage? checked query stored delivered = some usage) :
    covered checked.source stored = true ∧ covered checked.source delivered = false := by
  unfold consumedUsage? at observed
  split at observed
  next present => simpa only [Bool.and_eq_true,Bool.not_eq_true'] using present
  next => contradiction

def recordConsumed (graph : Graph) (checked : ConsumedSource edge) (query : String)
    (stored delivered : Array Range) : Except String Graph :=
  match consumedUsage? checked query stored delivered with
  | some usage => graph.insert (.used usage)
  | none => .ok graph

end Eggshell.Synapses.Extraction
