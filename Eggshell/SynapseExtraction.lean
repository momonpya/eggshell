module

public import Eggshell.Synapses
public import Eggshell.SearchUnicode
public import Eggshell.JsonScalars
public import tools.RetrievalCategories

@[expose] public section

namespace Eggshell.Synapses.Extraction
open Lean

structure Term where
  kind : WitnessKind
  text : String
  first : Nat
  limit : Nat
  deriving Repr, BEq

def termCharacter (char : Char) : Bool :=
  char.isAlphanum || char == '_' || char == '/' || char == '.' || char == '+' ||
    char == '-' || char == ':' || (128 ≤ char.toNat &&
      (RetrievalResearch.Unicode.letterNumber char || RetrievalResearch.Unicode.mark char))

def nameStart (char : Char) : Bool :=
  char == '_' || (RetrievalResearch.Unicode.letterNumber char && !SearchUnicode.isDigit char)

def namePart (char : Char) : Bool :=
  RetrievalResearch.Unicode.letterNumber char || RetrievalResearch.Unicode.mark char ||
    "_:.+-".contains char

/-- A named file component is required: separators and C++ comment delimiters
are not paths. Pure numbers, options and sed bounds are not identifiers.
This is a lexical witness policy, not a proof of tool data dependence. -/
def termKind? (value : String) : Option WitnessKind :=
  if value.isEmpty || value.toList.all SearchUnicode.isDigit then none
  else if value.contains '/' then
    if value.toList.any (fun char => RetrievalResearch.Unicode.letterNumber char || char == '_') then
      let suffix := value.splitOn ":" |>.getLast!
      some (if suffix.toNat?.isSome && value.contains ':' then .pathLine else .path)
    else none
  else if value.toList.head?.any nameStart && value.toList.all namePart then some .identifier
  else none

theorem numeric_not_a_witness (value : String)
    (numeric : value.toList.all SearchUnicode.isDigit = true) : termKind? value = none := by
  simp [termKind?, numeric]

theorem unnamed_path_not_a_witness (value : String) (slash : value.contains '/' = true)
    (unnamed : value.toList.any (fun char => RetrievalResearch.Unicode.letterNumber char || char == '_') = false) :
    termKind? value = none := by
  simp [termKind?, slash, unnamed]

/-- Preserve every source position. Repeating a token on another output row
is another possible witness, not a duplicate of the first row. -/
def termOccurrences (text : String) : Array Term := Id.run do
  let mut result := #[]
  let mut first := 0
  let mut position := 0
  let mut token : Array Char := #[]
  for char in text.toList ++ [' '] do
    if termCharacter char then
      if token.isEmpty then first := position
      token := token.push char
    else if !token.isEmpty then
      let value := String.ofList token.toList
      if let some kind := termKind? value then
        result := result.push ⟨kind, value, first, position⟩
        if kind == .pathLine then
          let path := ":".intercalate (value.splitOn ":" |>.dropLast)
          if termKind? path == some .path then
            result := result.push ⟨.path, path, first, first + path.length⟩
      token := #[]
    position := position + 1
  return result

/-- A consumer needs one literal argument witness per key. Deduplicating
arguments does not discard any position in a producer's output. -/
def terms (text : String) : Array Term := Id.run do
  let mut seen : Std.HashSet (WitnessKind × String) := {}
  let mut result := #[]
  for term in termOccurrences text do
    if seen.contains (term.kind, term.text) then continue
    seen := seen.insert (term.kind, term.text)
    result := result.push term
  return result

structure OutputRow where
  source : Range
  first : Nat
  limit : Nat
  deriving Repr, BEq, ToJson, FromJson

def OutputRow.covers (row : OutputRow) (first limit : Nat) : Bool :=
  row.first ≤ first && first < limit && limit ≤ row.limit && row.source.valid

/-- A verified file row takes precedence over its enclosing native member.
Otherwise keep the smallest covering span; adding context cannot expand a
located witness into every enclosing container. -/
def project (rows : Array OutputRow) (first limit : Nat) : Array Range :=
  let file := rows.any fun row => row.covers first limit && row.source.file?.isSome
  let candidates := rows.filter fun row => row.covers first limit && (!file || row.source.file?.isSome)
  let initial := (candidates[0]?).map (fun row => row.limit-row.first) |>.getD 0
  let width := candidates.foldl (fun n row => min n (row.limit-row.first)) initial
  (candidates.filter (fun row => row.limit-row.first == width)).map (·.source)

theorem project_has_witness {rows : Array OutputRow} {first limit : Nat} {source : Range}
    (present : source ∈ project rows first limit) :
    ∃ row ∈ rows, row.source = source ∧ row.covers first limit = true := by
  simp only [project, Array.mem_map, Array.mem_filter, Bool.and_eq_true] at present
  obtain ⟨row, ⟨⟨member, covers, _⟩, _⟩, equal⟩ := present
  exact ⟨row, member, equal, covers⟩

structure Produced where
  occurrence : Occurrence
  finished : Nat
  term : Term
  source : Array Char
  format : DataFormat := .text
  deriving Repr

def literal (source : Array Char) (first limit : Nat) (term : String) : Bool :=
  first < limit && limit ≤ source.size &&
    String.ofList (source.extract first limit).toList == term

/-- Structured values retain their JSON type and raw literal coordinates.
Lexical hints are extracted only inside string values, never object keys. -/
def payloadOccurrences (format : DataFormat) (text : String) : Except String (Array Term) := do
  if format == .text then return termOccurrences text
  let raw := text.toList.toArray
  let mut terms := #[]
  for scalar in ← JsonScalars.values text do
    terms := terms.push ⟨.value,scalar.literal,scalar.first,scalar.limit⟩
    if let some value := scalar.text then
      for term in termOccurrences value do
        let some first := scalar.offsets[term.first]? | continue
        let some limit := scalar.offsets[term.limit]? | continue
        if literal raw first limit term.text then
          terms := terms.push {term with first,limit}
  return terms

def witnessTerm (edge : Consumption) : Bool :=
  if edge.kind == .value then edge.inputFormat == .json && edge.outputFormat == .json &&
    JsonScalars.scalarLiteral edge.term
  else termKind? edge.term == some edge.kind

/-- A pending link carries checked literal positions in both actual texts.
The output array is shared by all witnesses from one immutable completion. -/
structure Pending where
  edge : Consumption
  input : Array Char
  output : Array Char
  valid : edge.valid = true
  classified : witnessTerm edge = true
  inputExact : literal input edge.inputFirst edge.inputLimit edge.term = true
  outputExact : literal output edge.outputFirst edge.outputLimit edge.term = true

def Pending.check? (edge : Consumption) (input output : Array Char) : Option Pending :=
  if valid : edge.valid = true then
    if classified : witnessTerm edge = true then
      if inputExact : literal input edge.inputFirst edge.inputLimit edge.term = true then
        if outputExact : literal output edge.outputFirst edge.outputLimit edge.term = true then
          some ⟨edge, input, output, valid, classified, inputExact, outputExact⟩ else none
      else none
    else none
  else none

theorem Pending.input_literal (pending : Pending) :
    String.ofList (pending.input.extract pending.edge.inputFirst pending.edge.inputLimit).toList =
      pending.edge.term := by
  have witness := pending.inputExact
  simp only [literal, Bool.and_eq_true, beq_iff_eq] at witness
  exact witness.2

theorem Pending.output_literal (pending : Pending) :
    String.ofList (pending.output.extract pending.edge.outputFirst pending.edge.outputLimit).toList =
      pending.edge.term := by
  have witness := pending.outputExact
  simp only [literal, Bool.and_eq_true, beq_iff_eq] at witness
  exact witness.2

theorem Pending.output_within (pending : Pending) :
    pending.edge.outputFirst < pending.edge.outputLimit ∧ pending.edge.outputLimit ≤ pending.output.size := by
  have witness := pending.outputExact
  simp only [literal, Bool.and_eq_true, decide_eq_true_eq] at witness
  exact witness.1

theorem Pending.before (pending : Pending) : pending.edge.producerFinish < pending.edge.consumerStart :=
  Consumption.checked_before (edge := pending.edge) (accepted := pending.edge)
    (by simp [Consumption.checked, pending.valid])

theorem Pending.non_numeric (pending : Pending) (unstructured : pending.edge.kind ≠ .value) :
    pending.edge.term.toList.all SearchUnicode.isDigit = false := by
  cases numeric : pending.edge.term.toList.all SearchUnicode.isDigit with
  | false => rfl
  | true =>
    have rejected := numeric_not_a_witness pending.edge.term numeric
    have accepted := pending.classified
    simp [witnessTerm,unstructured,beq_iff_eq,rejected] at accepted

structure Started where
  command : String
  ordinal : Nat
  pending : Array Pending
  format : DataFormat := .text

structure Trace where
  graph : Graph := .empty
  outputs : Std.HashMap (WitnessKind × String) (Std.HashMap Occurrence (Array Produced)) := {}
  starts : Std.HashMap Occurrence Started := {}
  finished : Std.HashMap Occurrence String := {}
  finishedFormats : Std.HashMap Occurrence DataFormat := {}
  rows : Std.HashMap Occurrence (Array OutputRow) := {}
  lastOrdinal : Option Nat := none

def Trace.advance (trace : Trace) (ordinal : Nat) : Except String Trace := do
  if trace.lastOrdinal.any (ordinal < ·) then throw "RPC trace is not in observed order"
  return {trace with lastOrdinal := some ordinal}

def Trace.start (trace : Trace) (occurrence : Occurrence) (ordinal : Nat) (command : String)
    (format : DataFormat := .text) :
    Except String Trace := do
  let trace ← trace.advance ordinal
  unless occurrence.valid do throw "missing exact session/turn/tool-use identity"
  if let some previous := trace.starts[occurrence]? then
    unless previous.command == command && previous.format == format do throw "one occurrence changed its input"
    return trace
  let mut pending := #[]
  let input := command.toList.toArray
  let candidates ← payloadOccurrences format command
  let strong := candidates.filter fun term => term.kind == .value &&
    (trace.outputs[(term.kind,term.text)]?.getD {}).any (fun _ producers =>
      producers.any (fun producer => producer.finished < ordinal))
  let mut seen : Std.HashSet (WitnessKind × String) := {}
  for term in candidates do
    if term.kind != .value && strong.any (fun value => value.first ≤ term.first && term.limit ≤ value.limit) then continue
    if seen.contains (term.kind,term.text) then continue
    seen := seen.insert (term.kind,term.text)
    for (_, producers) in trace.outputs[(term.kind, term.text)]?.getD {} do
      for producer in producers do
        if ordinal ≤ producer.finished then continue
        let edge : Consumption := {
          producer := producer.occurrence, consumer := occurrence
          producerFinish := producer.finished, consumerStart := ordinal
          kind := term.kind, term := term.text
          inputFirst := term.first, inputLimit := term.limit
          outputFirst := producer.term.first, outputLimit := producer.term.limit
          inputFormat := format,outputFormat := producer.format
          rows := project (trace.rows[producer.occurrence]?.getD {}) producer.term.first producer.term.limit }
        if let some checked := Pending.check? edge input producer.source then
          pending := pending.push checked
  return {trace with starts := trace.starts.insert occurrence ⟨command, ordinal, pending,format⟩}

def Trace.finish (trace : Trace) (occurrence : Occurrence) (ordinal : Nat) (output : String)
    (format : DataFormat := .text) :
    Except String Trace := do
  let trace ← trace.advance ordinal
  let some started := trace.starts[occurrence]? | throw "output has no observed start"
  if let some previous := trace.finished[occurrence]? then
    unless previous == output && trace.finishedFormats[occurrence]? == some format do throw "one occurrence changed its output"
    return trace
  unless started.ordinal < ordinal do throw "output predates call start"
  let mut graph := trace.graph
  for pending in started.pending do graph ← graph.insert (.consumed pending.edge)
  let mut outputs := trace.outputs
  let source := output.toList.toArray
  for term in ← payloadOccurrences format output do
    let previous := outputs[(term.kind, term.text)]?.getD {}
    let positions := previous[occurrence]?.getD #[]
    outputs := outputs.insert (term.kind, term.text)
      (previous.insert occurrence (positions.push ⟨occurrence, ordinal, term, source,format⟩))
  return {trace with
    graph, outputs
    finished := trace.finished.insert occurrence output
    finishedFormats := trace.finishedFormats.insert occurrence format}

/-- Attach verified row locations after exact native occurrence binding. -/
def Trace.locate (trace : Trace) (rows : Std.HashMap Occurrence (Array OutputRow)) :
    Except String Trace := do
  let mut facts := #[]
  for fact in trace.graph.snapshot do
    match fact with
    | .consumed edge =>
      let projected := project (rows[edge.producer]?.getD {}) edge.outputFirst edge.outputLimit
      facts := facts.push (.consumed {edge with rows := projected})
    | other => facts := facts.push other
  return {trace with rows, graph := ← Graph.ofFacts facts}

def supportCitations (graph : Graph) (claim : Claim) (cited : Array Range) (reads : Array Read)
    (original : Array Read := #[]) :
    Except String Graph := do
  let mut graph := graph
  for source in cited do
    for recorded in reads do
      if recorded.source.contains source then
        let rows := original.filter (fun row => row.occurrence == recorded.occurrence &&
          row.binding.database == recorded.binding.database &&
          row.binding.owner == recorded.binding.owner && row.binding.work == recorded.binding.work &&
          source.contains row.source)
        let binding ← if source == recorded.source then pure recorded.binding else do
          unless covered source (rows.map (·.source)) do continue
          let first := rows.foldl (fun first row => min first row.binding.first) recorded.binding.limit
          let limit := rows.foldl (fun limit row => max limit row.binding.limit) recorded.binding.first
          pure {recorded.binding with first, limit}
        let support ← Support.checked recorded source claim binding
        graph ← graph.insert (.supports support)
        graph ← graph.insert (.coquoted (.answer claim.database claim.answer) source)
        graph ← graph.insert (.coquoted (.claim claim) source)
  return graph

/-- Actual notifications only. Missing starts/finishes remain explicit errors. -/
def Trace.notification (trace : Trace) (ordinal : Nat) (record : Json) : Except String Trace := do
  if (← record.getObjValAs? String "direction") != "server" then return trace
  let message ← record.getObjVal? "message"
  let method := (message.getObjValAs? String "method").toOption.getD ""
  if method != "item/started" && method != "item/completed" then return trace
  let params ← message.getObjVal? "params"
  let item ← params.getObjVal? "item"
  if (← item.getObjValAs? String "type") != "commandExecution" then return trace
  let occurrence : Occurrence := ⟨← params.getObjValAs? String "threadId",
    ← params.getObjValAs? String "turnId", ← item.getObjValAs? String "id"⟩
  if method == "item/started" then
    trace.start occurrence ordinal (← item.getObjValAs? String "command")
  else
    trace.finish occurrence ordinal ((item.getObjValAs? String "aggregatedOutput").toOption.getD "")

end Eggshell.Synapses.Extraction
