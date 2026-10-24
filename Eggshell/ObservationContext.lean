module

public import Eggshell.SynapseSource
public import Eggshell.Sha256
public import Eggshell.SynapseQuotes

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

def originalSubject (work raw : String) : Original := ⟨work,Sha256.hex raw.toUTF8,raw.length⟩

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
  identity : Original
  identityExact : identity = originalSubject doc.work raw
  json : Option (JsonScalars.Index raw)

def prepare? (doc : Document) : Option (Prepared doc) := do
  let raw ← doc.source
  if original : doc.source = some raw then
    match mapped : layout raw with
    | .error _ => none
    | .ok view => some ⟨raw,original,view,mapped,raw.toList.toArray,rfl,
        view.text.toList.toArray,rfl,textLines view.text,originalSubject doc.work raw,rfl,JsonScalars.prepare? raw⟩
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

/-- Canonical data is independent of the occurrence that observed it. The
actual origin remains in the binding and can never certify another Work. -/
def Fragment.read? (fragment : Fragment doc) : Option {read : Read // read.valid = true} :=
  let source := Range.original (originalSubject fragment.binding.work fragment.raw)
    fragment.binding.first fragment.binding.limit
  let read : Read := {occurrence := fragment.occurrence,source,binding := fragment.binding}
  if valid : read.valid = true then some ⟨read,valid⟩ else none

/-- Resolve a stored canonical interval only against the same complete
Work/output snapshot, then attach this observation's own native origin. -/
def Prepared.bindSource? (prepared : Prepared doc) (database : String) (source : Range) : Option Read := do
  let .original original := source.subject | none
  if !doc.native || original != prepared.identity || !source.valid then none else do
    let occurrence ← doc.occurrences[0]?
    let read : Read := {occurrence,source,binding := ⟨database,doc.owner,doc.work,source.first-1,source.last⟩}
    if read.valid then some read else none

def bindSource? (database : String) (doc : Document) (source : Range) : Option Read := do
  let prepared ← prepare? doc
  prepared.bindSource? database source

/-- Transient spellings are hydrated from the original owner. Only their
digests travel with a persisted Read; hash lookup alone never creates support. -/
structure Quotation where
  read : Read
  text : String

structure Catalog where
  located : Array LocatedRead := #[]
  quotations : Array Quotation := #[]

def Catalog.reads (catalog : Catalog) : Array Read := catalog.located.map (·.read)

/-- Certified source rows have disjoint original intervals. Search their
sorted limits once, instead of scanning the growing native catalog per row. -/
def fileCovers (rows : Array Read) (first limit : Nat) : Bool := Id.run do
  let mut lower := 0
  let mut upper := rows.size
  while lower < upper do
    let middle := (lower+upper)/2
    let some row := rows[middle]? | return false
    if row.binding.limit < limit then lower := middle+1 else upper := middle
  return (rows[lower]?).any (fun row => row.binding.first ≤ first && limit ≤ row.binding.limit)

def Catalog.add (catalog : Catalog) (prepared : Prepared doc) (database : String)
    (files : Array Read) (first limit : Nat) (spellings : Array String) : Catalog := Id.run do
  if !doc.native || first ≥ limit || limit > prepared.rawChars.size then return catalog
  -- Preserve an existing certified file row instead of giving it a second,
  -- larger native identity. General data never requires such certification.
  if fileCovers files first limit then return catalog
  let some occurrence := doc.occurrences[0]? | return catalog
  let spellings := spellings.filter (!·.isEmpty) |>.toList.eraseDups.toArray
  let read : Read := {
    occurrence,source := Range.original prepared.identity first limit
    binding := ⟨database,doc.owner,doc.work,first,limit⟩
    quotations := spellings.map Quotes.digest |>.toList.eraseDups.toArray}
  if !read.valid then return catalog
  let payload := String.ofList (prepared.rawChars.extract first limit).toList
  return {
    located := catalog.located.push ⟨read,#[⟨read.source,first,limit⟩],#[read],payload⟩
    quotations := catalog.quotations ++ spellings.map (fun text => ⟨read,text⟩)}

/-- Enumerate source members/rows once during indexing, independently of tool
names, command syntax and the presence of files. The immutable subject hash,
JSON scan and character arrays are shared across all these spans. -/
def Prepared.catalog (prepared : Prepared doc) (database : String) : Catalog := Id.run do
  let mut catalog : Catalog := {located := (recordedReads database doc).toOption.getD #[]}
  let files := (catalog.located.flatMap (·.originalRows)).qsort (fun a b => a.binding.limit < b.binding.limit)
  if let some index := prepared.json then
    for leaf in index.leaves do
      let scalar := leaf.scalar
      let member := String.ofList (prepared.rawChars.extract scalar.contextFirst scalar.limit).toList
      let aliases := #[scalar.literal,member] ++ scalar.text.toArray
      catalog := catalog.add prepared database files scalar.contextFirst scalar.limit aliases
      if let some text := scalar.text then
        if text.contains '\n' then
          for line in textLines text do
            let some first := scalar.offsets[line.first]? | continue
            let some limit := scalar.offsets[line.limit]? | continue
            let raw := String.ofList (prepared.rawChars.extract first limit).toList
            catalog := catalog.add prepared database files first limit #[line.text,raw]
    if index.leaves.isEmpty then
      catalog := catalog.add prepared database files 0 prepared.rawChars.size #[prepared.raw]
  else
    for line in textLines prepared.raw do
      let payload := String.ofList (prepared.rawChars.extract line.first line.limit).toList
      catalog := catalog.add prepared database files line.first line.limit #[line.text,payload]
  return catalog

def recorded (database : String) (doc : Document) : Option Catalog := do
  return (← prepare? doc).catalog database

/-- File certification remains optional. General rows are located only when
the actual completed call has the complete saved invocation and output. -/
def locate (database : String) (doc : Document) (trace : Trace) : Array LocatedRead := Id.run do
  let mut result := (locateReads database doc trace).toOption.getD #[]
  let some prepared := prepare? doc | return result
  let .ok (input,format) := invocationData (doc.workText.getD "") | return result
  let native := (prepared.catalog database).located.filter (·.read.source.file?.isNone)
  for occurrence in doc.occurrences do
    let some started := trace.starts[occurrence]? | continue
    if started.command != input || started.format != format || trace.finished[occurrence]? != some prepared.raw then continue
    for located in native do
      let read := {located.read with occurrence}
      result := result.push {located with read,originalRows := #[read]}
  return result

/-- Exact quoted spellings provide advisory support/coquotation. The caller
restricts the catalog to the answer's actual All-reachable source owners.
This records an observed citation, not the truth or causality of a claim. -/
def addQuotedAnswer (database : String) (doc : Document) (spellings : Array Quotation)
    (graph : Graph) : Except String Graph := do
  let decoded ← layout (doc.source.getD "")
  let byText := spellings.foldl (fun (map : Std.HashMap String (Array Read)) item =>
    map.insert item.text (map[item.text]?.getD #[] |>.push item.read)) {}
  let mut graph := graph
  let mut position := 0
  for paragraph in decoded.text.splitOn "\n\n" do
    let limit := position+paragraph.length
    if position < limit then
      let claim : Claim := ⟨database,doc.owner,decoded.offsets[position]!,decoded.offsets[limit]!⟩
      for quote in Quotes.extract paragraph do
        for read in byText[quote.text]?.getD #[] do
          let support ← Support.checked read read.source claim
          graph ← graph.insert (.supports support)
          graph ← graph.insert (.coquoted (.claim claim) read.source)
          graph ← graph.insert (.coquoted (.answer database doc.owner) read.source)
    position := limit+2
  return graph

end Eggshell.Synapses.ObservationContext
