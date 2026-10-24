import Eggshell.SynapseSource

open Lean Eggshell Eggshell.Synapses Eggshell.Synapses.Extraction

private def check (value : Bool) (message : String) : IO Unit :=
  unless value do throw (IO.userError message)

private def occurrence (name : String) : Occurrence := ⟨"structured","turn",name⟩

def main : IO Unit := do
  let raw := (Json.mkObj [("key_only",toJson "東京\n\"quote\"\\tail"),
    ("numbers",toJson #[toJson (42 : Nat),toJson "42",Json.null,toJson false])]).compress
  let scalars ← IO.ofExcept (JsonScalars.values raw)
  check (scalars.size == 5 && scalars.all (fun scalar =>
    literal raw.toList.toArray scalar.first scalar.limit scalar.literal))
    "scalar enumeration lost a type or its original UTF-8/escape coordinates"
  let observed ← IO.ofExcept (payloadOccurrences .json raw)
  check (observed.all (fun term => term.text != "key_only" && term.text != "numbers"))
    "JSON keys became observed values"
  let trace : Trace := {}
  let trace ← IO.ofExcept (trace.start (occurrence "producer") 1 "{}" .json)
  let trace ← IO.ofExcept (trace.finish (occurrence "producer") 2 raw .json)
  let inputs := (Json.mkObj [("parameters",toJson #[toJson (42 : Nat),toJson "42"])]).compress
  let trace ← IO.ofExcept (trace.start (occurrence "consumer") 3 inputs .json)
  let some pending := trace.starts[occurrence "consumer"]? | throw (IO.userError "missing structured start")
  check (pending.pending.size == 2 && pending.pending.all (fun row => row.edge.kind == .value) &&
    (pending.pending.map (·.edge.term)).contains "42" &&
    (pending.pending.map (·.edge.term)).contains "\"42\"")
    "typed numeric IDs were omitted or conflated with strings"
  let keyOnly := (Json.mkObj [("parameter",toJson "key_only")]).compress
  let trace ← IO.ofExcept (trace.start (occurrence "not-consumed") 4 keyOnly .json)
  check ((trace.starts[occurrence "not-consumed"]?).any (·.pending.isEmpty))
    "an object key falsely became consumption evidence"
  let exact := (Json.mkObj [("id",toJson "RECORD_42")]).compress
  let fresh : Trace := {}
  let fresh ← IO.ofExcept (fresh.start (occurrence "exact-producer") 1 "{}" .json)
  let fresh ← IO.ofExcept (fresh.finish (occurrence "exact-producer") 2 exact .json)
  let fresh ← IO.ofExcept (fresh.start (occurrence "exact-consumer") 3 exact .json)
  check ((fresh.starts[occurrence "exact-consumer"]?).any (fun row =>
    row.pending.size == 1 && row.pending.all (·.edge.kind == .value)))
    "one whole-value match also created duplicate lexical witnesses"
  let mixed := (Json.mkObj [("output",toJson "display text"),("cursor",toJson (73 : Nat))]).compress
  let complete : Trace := {}
  let complete ← IO.ofExcept (complete.start (occurrence "mixed-output") 1 "{}" .json)
  let complete ← IO.ofExcept (complete.finish (occurrence "mixed-output") 2 mixed .json)
  let cursor := (Json.mkObj [("cursor",toJson (73 : Nat))]).compress
  let complete ← IO.ofExcept (complete.start (occurrence "cursor-consumer") 3 cursor .json)
  check ((complete.starts[occurrence "cursor-consumer"]?).any (fun row =>
    row.pending.size == 1 && row.pending.all (fun value => value.edge.term == "73")))
    "choosing a display-text field hid another structured result value"
  for fixture in #[
      Json.mkObj [("before",Json.mkObj [("status",toJson "same")]),
        ("after",Json.mkObj [("status",toJson "same")])],
      toJson #[Json.mkObj [("a/~\"東京",toJson #[toJson "🙂",toJson (73 : Nat)])],
        Json.mkObj [("",toJson true),("0",Json.null)]],
      toJson ((List.range 2048).map fun n => Json.mkObj [("index",toJson n),("value",toJson s!"item-{n}")])
    ] do
    let raw := fixture.compress
    let some indexed := JsonScalars.prepare? raw | throw (IO.userError "valid JSON addresses were rejected")
    for leaf in indexed.leaves do
      let scalar := leaf.scalar
      let some address := indexed.witness? scalar.first scalar.limit |
        throw (IO.userError "binary lookup missed an original scalar")
      check (address.leaf.scalar.pathRev == scalar.pathRev &&
        address.leaf.scalar.contextFirst == scalar.contextFirst)
        "equal values in different objects lost their distinct original addresses"
      if scalar.contextFirst < scalar.first then
        check ((indexed.witness? scalar.contextFirst scalar.first).isNone)
          "a field name acquired a value witness"
      let altered := {scalar with pathRev := [.key "absent"]}
      check ((JsonScalars.Checked.check? indexed.root indexed.characters altered).isNone)
        "a fabricated ancestor path was accepted"
  IO.println "structured value checks passed: typed IDs, key exclusion, original Unicode coordinates, checked ancestor paths and 4096-leaf binary lookup"
