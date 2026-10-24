module

public import Eggshell.SynapseSource

@[expose] public section

namespace Eggshell.Synapses.ObservationContext
open Lean Extraction

/-- Container coordinates in the actual serialized value. Quoted braces and
escaped quotes never introduce a container. No tool names are interpreted. -/
def containers (text : String) : Array (Nat × Nat) := Id.run do
  match Json.parse text with
  | .ok (.obj _) | .ok (.arr _) => pure ()
  | _ => return #[]
  let mut stack : Array (Nat × Char) := #[]
  let mut found := #[]
  let mut quoted := false
  let mut escaped := false
  let mut position := 0
  for char in text.toList do
    if escaped then escaped := false
    else if quoted then
      if char == '\\' then escaped := true
      else if char == '"' then quoted := false
    else if char == '"' then quoted := true
    else if char == '{' || char == '[' then stack := stack.push (position,char)
    else if char == '}' || char == ']' then
      let some (first,opening) := stack.back? | return #[]
      if (opening == '{' && char != '}') || (opening == '[' && char != ']') then return #[]
      found := found.push (first,position+1)
      stack := stack.pop
    position := position+1
  return found

/-- A complete smallest JSON container, or the original text row containing
the witness. This is display context, never a claim about tool semantics. -/
def bounds (structured : Array (Nat × Nat)) (lines : Array TextLine) (first limit : Nat) : Nat × Nat :=
  let containing := structured.filter fun (a,b) => a ≤ first && limit ≤ b
  match (containing.qsort fun a b => a.2-a.1 < b.2-b.1)[0]? with
  | some result => result
  | none =>
    match lines.find? (fun line => line.first ≤ first && limit ≤ line.limit) with
    | some line => (line.first,line.limit)
    | none => (first,limit)

structure Prepared (doc : Document) where
  raw : String
  original : doc.source = some raw
  view : Layout
  mapped : layout raw = .ok view
  structured : Array (Nat × Nat)
  lines : Array TextLine
  rawStructured : Array (Nat × Nat)
  rawLines : Array TextLine
  scalars : Array JsonScalars.Scalar

def prepare? (doc : Document) : Option (Prepared doc) := do
  let raw ← doc.source
  if original : doc.source = some raw then
    match mapped : layout raw with
    | .error _ => none
    | .ok view => some ⟨raw,original,view,mapped,containers view.text,textLines view.text,
        containers raw,textLines raw,(JsonScalars.values raw).toOption.getD #[]⟩
  else none

def Prepared.rawBounds (prepared : Prepared doc) (edge : Consumption) : Nat × Nat := Id.run do
  if edge.kind != .value then
    for scalar in prepared.scalars do
      let some text := scalar.text | continue
      if !text.contains '\n' then continue
      let some first := scalar.offsets.findIdx? (· == edge.outputFirst) | continue
      let some limit := scalar.offsets.findIdx? (· == edge.outputLimit) | continue
      let (first,limit) := bounds #[] (textLines text) first limit
      let some first := scalar.offsets[first]? | continue
      let some limit := scalar.offsets[limit]? | continue
      return (first,limit)
  return bounds prepared.rawStructured prepared.rawLines edge.outputFirst edge.outputLimit

structure Fragment (doc : Document) where
  occurrence : Occurrence
  binding : Binding
  raw : String
  payload : String
  native : doc.native = true
  origin : doc.occurrences.contains occurrence = true
  original : doc.source = some raw
  owner : binding.owner = doc.owner
  work : binding.work = doc.work
  valid : binding.valid = true
  within : binding.first < binding.limit ∧ binding.limit ≤ raw.length
  exact : payload = String.ofList ((raw.toList.drop binding.first).take (binding.limit-binding.first))

/-- Resolve only an actual producer and a literal saved output witness. Source
files, shell syntax and line numbers are not prerequisites. -/
def Prepared.locate? (prepared : Prepared doc) (database : String) (edge : Consumption) : Option (Fragment doc) := do
  if native : doc.native = true then
    if origin : doc.occurrences.contains edge.producer = true then
        let raw := prepared.raw
        let view := if edge.outputFormat == .json then raw else prepared.view.text
        if !(literal view.toList.toArray edge.outputFirst edge.outputLimit edge.term) then none else do
          let (first,limit) := if edge.outputFormat == .json then prepared.rawBounds edge
            else bounds prepared.structured prepared.lines edge.outputFirst edge.outputLimit
          if !(first ≤ edge.outputFirst && edge.outputLimit ≤ limit) then none else do
            let first ← if edge.outputFormat == .json then some first else prepared.view.offsets[first]?
            let limit ← if edge.outputFormat == .json then some limit else prepared.view.offsets[limit]?
            let binding : Binding := ⟨database,doc.owner,doc.work,first,limit⟩
            if valid : binding.valid = true then
              if within : binding.first < binding.limit ∧ binding.limit ≤ raw.length then
                some ⟨edge.producer,binding,raw,
                  String.ofList ((raw.toList.drop binding.first).take (binding.limit-binding.first)),
                  native,origin,prepared.original,rfl,rfl,valid,within,rfl⟩
              else none
            else none
    else none
  else none

def locate? (database : String) (doc : Document) (edge : Consumption) : Option (Fragment doc) := do
  let prepared ← prepare? doc
  prepared.locate? database edge

theorem fragment_is_original (fragment : Fragment doc) :
    doc.source = some fragment.raw ∧
    fragment.payload = String.ofList ((fragment.raw.toList.drop fragment.binding.first).take
      (fragment.binding.limit-fragment.binding.first)) := ⟨fragment.original,fragment.exact⟩

theorem fragment_has_native_origin (fragment : Fragment doc) :
    doc.native = true ∧ doc.occurrences.contains fragment.occurrence = true :=
  ⟨fragment.native,fragment.origin⟩

end Eggshell.Synapses.ObservationContext
