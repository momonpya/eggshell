module

public import Eggshell.SynapseSource

@[expose] public section

namespace Eggshell.Synapses.ObservationContext
open Lean Extraction

/-- Plain text keeps its actual row. Structured data uses checked scalar
members and ancestor paths, rather than copying the enclosing object. -/
def lineBounds (lines : Array TextLine) (first limit : Nat) : Nat × Nat := Id.run do
  let mut lower := 0
  let mut upper := lines.size
  while lower < upper do
    let middle := (lower+upper)/2
    let some line := lines[middle]? | return (first,limit)
    if line.limit < limit then lower := middle+1 else upper := middle
  match lines[lower]? with
  | some line => if line.first ≤ first && limit ≤ line.limit then (line.first,line.limit) else (first,limit)
  | none => (first,limit)

structure Prepared (doc : Document) where
  raw : String
  original : doc.source = some raw
  view : Layout
  mapped : layout raw = .ok view
  rawChars : Array Char
  rawCharsExact : rawChars = raw.toList.toArray
  viewChars : Array Char
  viewCharsExact : viewChars = view.text.toList.toArray
  lines : Array TextLine
  json : Option (JsonScalars.Index raw)

def prepare? (doc : Document) : Option (Prepared doc) := do
  let raw ← doc.source
  if original : doc.source = some raw then
    match mapped : layout raw with
    | .error _ => none
    | .ok view => some ⟨raw,original,view,mapped,raw.toList.toArray,rfl,
        view.text.toList.toArray,rfl,textLines view.text,JsonScalars.prepare? raw⟩
  else none

def Prepared.rawBounds (prepared : Prepared doc) (edge : Consumption) :
    Option (Nat × Nat × JsonScalars.Address prepared.raw) := do
  let index ← prepared.json
  let address ← index.witness? edge.outputFirst edge.outputLimit
  let scalar := address.leaf.scalar
  if edge.kind == .value then
    if edge.outputFirst != scalar.first || edge.outputLimit != scalar.limit then none
    else some (scalar.contextFirst,scalar.limit,address)
  else if let some text := scalar.text then
    if text.contains '\n' then do
      let first ← scalar.offsets.findIdx? (· == edge.outputFirst)
      let limit ← scalar.offsets.findIdx? (· == edge.outputLimit)
      let (first,limit) := lineBounds (textLines text) first limit
      let first ← scalar.offsets[first]?
      let limit ← scalar.offsets[limit]?
      some (first,limit,address)
    else some (scalar.contextFirst,scalar.limit,address)
  else some (scalar.contextFirst,scalar.limit,address)

structure Fragment (doc : Document) where
  occurrence : Occurrence
  binding : Binding
  raw : String
  payload : String
  address : Option (JsonScalars.Address raw)
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
        let view := if edge.outputFormat == .json then prepared.rawChars else prepared.viewChars
        if !(literal view edge.outputFirst edge.outputLimit edge.term) then none else do
          let (first,limit,address) ← if edge.outputFormat == .json then do
              let (first,limit,address) ← prepared.rawBounds edge
              if first ≤ edge.outputFirst && edge.outputLimit ≤ limit then some (first,limit,some address) else none
            else do
              let (first,limit) := lineBounds prepared.lines edge.outputFirst edge.outputLimit
              if !(first ≤ edge.outputFirst && edge.outputLimit ≤ limit) then none else do
                let first ← prepared.view.offsets[first]?
                let limit ← prepared.view.offsets[limit]?
                some (first,limit,prepared.json.bind (·.cover? first limit))
          do
            let binding : Binding := ⟨database,doc.owner,doc.work,first,limit⟩
            if valid : binding.valid = true then
              if bounded : binding.first < binding.limit ∧ binding.limit ≤ prepared.rawChars.size then
                have size : prepared.rawChars.size = raw.length := by
                  simp [prepared.rawCharsExact,raw,String.length_toList]
                have within : binding.first < binding.limit ∧ binding.limit ≤ raw.length := by
                  simpa only [size] using bounded
                let payload := String.ofList (prepared.rawChars.extract binding.first binding.limit).toList
                have exact : payload = String.ofList ((raw.toList.drop binding.first).take (binding.limit-binding.first)) := by
                  simp [payload,prepared.rawCharsExact,raw]
                some ⟨edge.producer,binding,raw,
                  payload,address,native,origin,prepared.original,rfl,rfl,valid,within,exact⟩
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
