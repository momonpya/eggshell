module

public import Eggshell.Synapses

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
    char == '-' || char == ':' || (128 ≤ char.toNat && !char.isWhitespace)

def terms (text : String) : Array Term := Id.run do
  let mut result := #[]
  let mut first := 0
  let mut position := 0
  let mut token : Array Char := #[]
  let mut seen : Std.HashSet (WitnessKind × String) := {}
  for char in text.toList ++ [' '] do
    if termCharacter char then
      if token.isEmpty then first := position
      token := token.push char
    else if !token.isEmpty then
      let value := String.ofList token.toList
      let suffix := value.splitOn ":" |>.getLast!
      let kind := if value.contains '/' then
          if suffix.toNat?.isSome && value.contains ':' then WitnessKind.pathLine else .path
        else WitnessKind.identifier
      if !seen.contains (kind, value) then
        result := result.push ⟨kind, value, first, position⟩
        seen := seen.insert (kind, value)
      if kind == .pathLine then
        let path := ":".intercalate (value.splitOn ":" |>.dropLast)
        if !seen.contains (.path, path) then
          result := result.push ⟨.path, path, first, first + path.length⟩
          seen := seen.insert (.path, path)
      token := #[]
    position := position + 1
  return result

structure OutputRow where
  source : Range
  first : Nat
  limit : Nat
  deriving Repr, BEq, ToJson, FromJson

def OutputRow.covers (row : OutputRow) (first limit : Nat) : Bool :=
  row.first ≤ first && first < limit && limit ≤ row.limit && row.source.valid

/-- No whole-reader fallback when a witness cannot be located in original rows. -/
def project (rows : Array OutputRow) (first limit : Nat) : Array Range :=
  (rows.filter (·.covers first limit)).map (·.source)

theorem project_has_witness {rows : Array OutputRow} {first limit : Nat} {source : Range}
    (present : source ∈ project rows first limit) :
    ∃ row ∈ rows, row.source = source ∧ row.covers first limit = true := by
  simp only [project, Array.mem_map, Array.mem_filter] at present
  obtain ⟨row, ⟨member, covers⟩, equal⟩ := present
  exact ⟨row, member, equal, covers⟩

structure Produced where
  occurrence : Occurrence
  finished : Nat
  term : Term
  deriving Repr

structure Started where
  command : String
  ordinal : Nat
  pending : Array Consumption

structure Trace where
  graph : Graph := .empty
  outputs : Std.HashMap (WitnessKind × String) (Std.HashMap Occurrence Produced) := {}
  starts : Std.HashMap Occurrence Started := {}
  finished : Std.HashMap Occurrence String := {}
  rows : Std.HashMap Occurrence (Array OutputRow) := {}
  lastOrdinal : Option Nat := none

def Trace.advance (trace : Trace) (ordinal : Nat) : Except String Trace := do
  if trace.lastOrdinal.any (ordinal < ·) then throw "RPC trace is not in observed order"
  return {trace with lastOrdinal := some ordinal}

def Trace.start (trace : Trace) (occurrence : Occurrence) (ordinal : Nat) (command : String) :
    Except String Trace := do
  let trace ← trace.advance ordinal
  unless occurrence.valid do throw "missing exact session/turn/tool-use identity"
  if let some previous := trace.starts[occurrence]? then
    unless previous.command == command do throw "one occurrence changed its input"
    return trace
  let mut pending := #[]
  for term in terms command do
    for (_, producer) in trace.outputs[(term.kind, term.text)]?.getD {} do
      if ordinal ≤ producer.finished then continue
      pending := pending.push {
        producer := producer.occurrence, consumer := occurrence
        producerFinish := producer.finished, consumerStart := ordinal
        kind := term.kind, term := term.text
        inputFirst := term.first, inputLimit := term.limit
        outputFirst := producer.term.first, outputLimit := producer.term.limit
        rows := project (trace.rows[producer.occurrence]?.getD {}) producer.term.first producer.term.limit }
  return {trace with starts := trace.starts.insert occurrence ⟨command, ordinal, pending⟩}

def Trace.finish (trace : Trace) (occurrence : Occurrence) (ordinal : Nat) (output : String) :
    Except String Trace := do
  let trace ← trace.advance ordinal
  let some started := trace.starts[occurrence]? | throw "output has no observed start"
  if let some previous := trace.finished[occurrence]? then
    unless previous == output do throw "one occurrence changed its output"
    return trace
  unless started.ordinal < ordinal do throw "output predates call start"
  let mut graph := trace.graph
  for edge in started.pending do graph ← graph.insert (.consumed edge)
  let mut outputs := trace.outputs
  for term in terms output do
    let previous := outputs[(term.kind, term.text)]?.getD {}
    outputs := outputs.insert (term.kind, term.text) (previous.insert occurrence ⟨occurrence, ordinal, term⟩)
  return {trace with graph, outputs, finished := trace.finished.insert occurrence output}

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
