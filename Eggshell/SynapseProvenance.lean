module

public import Eggshell.GraphStore
public import Eggshell.SynapseSource

@[expose] public section

namespace Eggshell.Synapses.Provenance
open Lean DB Persistence.Store _root_.Eggshell.Synapses.Extraction

/-- Native observation identity, with semantic positions checked independently
of the Exact session/turn/tool identifiers. -/
def identities (edge : OutcomeEdge) : Array Occurrence :=
  edge.observations.toArray.filterMap fun observation => do
    let .apply .occurrence references := observation | none
    let [(.semantic, result), (.semantic, work), (.exact, session),
        (.exact, turn), (.exact, useId)] := references.toList | none
    if result != edge.outcome || work != edge.work then none else
      some ⟨← text? session, ← text? turn, ← text? useId⟩

def document (reader : NodeReader snapshot) (id : Nat) : IO Document := do
  let edge ← reader.outcome (← reader.locateOutcome id)
  let owner := Persistence.selectionKey edge.relation
  let candidates ← getIds snapshot.get ("owner:" ++ toString (hash edge.relation).toNat)
  let live ← candidates.filterM fun id => return (← snapshot.get (key "member" id)).isSome
  unless live == [id] do throw (IO.userError "ambiguous synaptic source owner")
  return {
    owner, work := Persistence.selectionKey edge.work
    workText := text? edge.work, source := text? edge.outcome
    native := edge.observations.any (Relation.observesOutcomeWork edge.outcome edge.work)
    occurrences := identities edge
    files := ← IO.ofExcept (fileMap ((← reader.sources id).toArray.map toJson)) }

/-- Query-free provenance. The body stays in its original native Outcome. -/
structure Origin where
  owner : Nat
  occurrence : Occurrence
  domain : String
  started : Nat
  finished : Nat
  deriving BEq, ToJson, FromJson

def Origin.valid (origin : Origin) : Bool :=
  origin.occurrence.valid && digest origin.domain && origin.started < origin.finished

structure Checked where
  origin : Origin
  valid : origin.valid = true

def Origin.check? (origin : Origin) : Option Checked :=
  if valid : origin.valid = true then some ⟨origin, valid⟩ else none

theorem Checked.time_order (checked : Checked) : checked.origin.started < checked.origin.finished := by
  have := checked.valid
  simp only [Origin.valid, Bool.and_eq_true, decide_eq_true_eq] at this
  exact this.2

def originPrefix : String := "memo:synaptic-origin:"
def stateKey : String := "memo:synaptic-state"

def contentKey [ToJson α] (value : α) : String :=
  Blake3.hex (Blake3.digest "eggshell.synaptic-provenance".toUTF8 [(toJson value).compress.toUTF8])

def name (occurrence : Occurrence) : String := originPrefix ++ contentKey occurrence

def originRow (occurrence : Occurrence) (encoded : ByteArray) : PageMap.Row :=
  (name occurrence, some encoded)

def stateRow (encoded : ByteArray) : PageMap.Row := (stateKey, some encoded)

/-- The actual metadata row constructors preserve all graph and authority
keys. The publication journal is managed separately by the checked writer. -/
theorem metadata_preserves_authority (occurrence : Occurrence) (encoded root : ByteArray)
    (before : String → Option ByteArray) (key : String) (outside : PageMap.derivedKey key = false) :
    PageMap.applyRows [originRow occurrence encoded, stateRow root] before key = before key := by
  apply PageMap.derived_rows_preserve _ _ _ key outside
  simp [originRow, stateRow, name, originPrefix, stateKey, PageMap.derivedKey]

structure State where
  count : Nat := 0
  digest : String := contentKey ("empty" : String)
  deriving BEq, ToJson, FromJson

structure Stored where
  ordinal : Nat
  previous : String
  origin : Origin
  deriving BEq, ToJson, FromJson

def bytes [ToJson α] (value : α) : IO ByteArray := do
  let encoded := (toJson value).compress.toUTF8
  unless encoded.size ≤ 65536 do throw (IO.userError "synaptic provenance exceeds its metadata bound")
  return encoded

def decode [ToJson α] [FromJson α] (encoded : ByteArray) : IO α := do
  unless encoded.size ≤ 65536 do throw (IO.userError "synaptic provenance exceeds its metadata bound")
  let some text := String.fromUTF8? encoded | throw (IO.userError "invalid provenance UTF-8")
  let value ← IO.ofExcept (Json.parse text >>= fromJson? (α := α))
  unless (toJson value).compress.toUTF8 == encoded do throw (IO.userError "noncanonical synaptic provenance")
  return value

def state (source : PageMap.Snapshot) : IO State := do
  let result ← match ← source.get stateKey with
    | none => pure ({} : State)
    | some encoded => decode encoded
  unless Synapses.digest result.digest do throw (IO.userError "invalid synaptic provenance root")
  return result

def stamp (source : PageMap.Snapshot) : IO String := do
  return contentKey (← state source)

def records (source : PageMap.Snapshot) : IO (Array Stored) := do
  let values ← source.foldRange ⟨originPrefix, "memo:synaptic-origin;"⟩ (fun values row => do
    let some encoded := row.2 | return values
    let value ← decode (α := Stored) encoded
    unless row.1 == name value.origin.occurrence && value.origin.valid do
      throw (IO.userError "provenance record is not bound to its original identity")
    return values.push value) #[]
  let values := values.qsort (fun a b => a.ordinal < b.ordinal)
  let mut previous : State := {}
  for value in values do
    unless value.ordinal == previous.count && value.previous == previous.digest do
      throw (IO.userError "incomplete or reordered provenance chain")
    previous := ⟨previous.count+1, contentKey value⟩
  unless previous == (← state source) do throw (IO.userError "provenance records disagree with their published root")
  return values

def checkedDocument (reader : NodeReader source) (origin : Origin) : IO Document := do
  unless origin.valid do throw (IO.userError "invalid native provenance interval")
  let doc ← document reader origin.owner
  unless doc.native && doc.occurrences.contains origin.occurrence do
    throw (IO.userError "provenance does not belong to its original native observation")
  return doc

/-- Only an explicitly writable native source may call this publisher. It
writes the existing non-authoritative namespace, never roots or Union rows. -/
def publish (source : PageMap.Snapshot) (origins : Array Origin) : IO PageMap.Snapshot := do
  if origins.isEmpty then return source
  let reader ← NodeReader.new source
  for origin in origins do
    let _ ← checkedDocument reader origin
    pure ()
  let initial ← state source
  let (_, head, _) ← PageMap.withWriter source fun writer => do
    let mut current := initial
    for origin in origins do
      let key := name origin.occurrence
      unless PageMap.derivedKey key do throw (IO.userError "provenance key escaped the non-authoritative namespace")
      if let some encoded ← writer.get key then
        let old ← decode (α := Stored) encoded
        unless old.origin == origin && old.ordinal < current.count do
          throw (IO.userError "conflicting immutable native provenance")
      else
        let value : Stored := ⟨current.count, current.digest, origin⟩
        let row := originRow origin.occurrence (← bytes value)
        writer.put row.1 row.2
        current := ⟨current.count+1, contentKey value⟩
    if current != initial then
      let row := stateRow (← bytes current)
      writer.put row.1 row.2
      writeChange writer ⟨[], [], false⟩
  if head == source.head then return source
  return {source with head}

structure Event where
  origin : Origin
  start : Bool

def Event.time (event : Event) : Nat := if event.start then event.origin.started else event.origin.finished

def Event.group (event : Event) : String :=
  (toJson (event.origin.domain, event.origin.occurrence.session, event.origin.occurrence.turn)).compress

structure Derived where
  graph : Graph := .empty
  originals : Nat := 0
  ignored : Nat := 0

/-- Reconstruct only from DB-owned original bodies and observed intervals.
Allocation ordinals validate storage; only actual times determine consumption. -/
def derive (source : PageMap.Snapshot) : IO Derived := do
  let stored ← records source
  if stored.isEmpty then return {}
  let reader ← NodeReader.new source
  let mut docs : Std.HashMap Nat Document := {}
  let mut events : Array Event := #[]
  let mut ignored := 0
  for value in stored do
    let origin := value.origin
    if (← source.get (key "member" origin.owner)).isNone then ignored := ignored+1; continue
    let doc ← checkedDocument reader origin
    let some work := doc.workText | ignored := ignored+1; continue
    let some raw := doc.source | ignored := ignored+1; continue
    if (workCommand work).toOption.isNone || (layout raw).toOption.isNone then ignored := ignored+1; continue
    docs := docs.insert origin.owner doc
    events := events.push ⟨origin, true⟩ |>.push ⟨origin, false⟩
  events := events.qsort fun a b =>
    if a.group == b.group then
      if a.time == b.time then name a.origin.occurrence < name b.origin.occurrence else a.time < b.time
    else a.group < b.group
  let mut result : Derived := {ignored, originals := events.size/2}
  let mut trace : Trace := {}
  let mut group := ""
  let mut locations : Std.HashMap Occurrence (Array OutputRow) := {}
  for event in events do
    if group != event.group then
      let located ← IO.ofExcept (trace.locate locations)
      result := {result with graph := ← IO.ofExcept (result.graph.merge located.graph)}
      trace := {}; locations := {}; group := event.group
    let some doc := docs[event.origin.owner]? | throw (IO.userError "missing original provenance body")
    if event.start then
      let command ← IO.ofExcept (workCommand (doc.workText.getD ""))
      trace ← IO.ofExcept (trace.start event.origin.occurrence event.time command)
    else
      let output ← IO.ofExcept (layout (doc.source.getD ""))
      trace ← IO.ofExcept (trace.finish event.origin.occurrence event.time output.text)
      if let .ok reads := locateReads source.head.identity doc trace then
        let rows := reads.filter (·.read.occurrence == event.origin.occurrence) |>.flatMap (·.rows)
        locations := locations.insert event.origin.occurrence rows
  let located ← IO.ofExcept (trace.locate locations)
  return {result with graph := ← IO.ofExcept (result.graph.merge located.graph)}

end Eggshell.Synapses.Provenance
