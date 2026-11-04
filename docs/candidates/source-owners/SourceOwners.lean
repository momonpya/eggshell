module
public import Eggshell.SourceBitmap
public import Eggshell.LexicalAdvice

@[expose] public section
namespace Eggshell.SourceOwners
open Lean DB Persistence.Store PreparedOwners

def implementation : String := Sha256.hex ((include_str "SourceOwners.lean").toUTF8 ++
  (include_str "SourceBitmap.lean").toUTF8 ++ PreparedOwners.implementation.toUTF8 ++
  RetrievalResearch.Index.contract.toUTF8)

structure Binding where
  scope : String
  producer : String
  deriving ToJson, FromJson, BEq

/-- A retained immutable original byte witness, not a caller's source-array slot. -/
structure Witness where
  source : Source
  node : Nat
  deriving ToJson, FromJson

structure Identity where
  id : Nat
  witness : Witness
  originalTerms : List Nat
  lexicalTerms : List Nat
  deriving ToJson, FromJson

structure Member where
  node : Nat
  ordinal : Nat
  work : Nat
  candidate : Bool
  deriving ToJson, FromJson, BEq

structure Membership where
  id : Nat
  originals : List Member
  deriving ToJson, FromJson

structure State where
  binding : Binding
  source : Source
  dictionary : Source
  allOwners : Option SourceBitmap.Ref
  candidates : Option SourceBitmap.Ref
  deriving ToJson, FromJson

structure Captured where
  index : Source
  state : State
  deriving ToJson, FromJson

def restore (ref : Source) : IO PageMap.Snapshot := do
  let current ← PageMap.pin (.mk ref.directory)
  let some old ← PageMap.HistoryReader.make? current ref.head |
    throw (IO.userError "captured source-owner extent unavailable")
  return old.snapshot

def refOf (snapshot : PageMap.Snapshot) : Source := ⟨snapshot.directory.toString,snapshot.head⟩

def readIdentity (snapshot : PageMap.Snapshot) (read : String → IO (Option ByteArray))
    (id : Nat) : IO Identity := do
  let some entry ← readJson (α := Identity) snapshot read (key "identity" id) |
    throw (IO.userError "missing stable owner identity")
  unless entry.id == id do throw (IO.userError "stable owner identity changed")
  return entry

def originalAlias (source : PageMap.Snapshot) (node : Nat) : String :=
  key ("identityAlias/"++source.head.identity) node

def sourceTerms (dictionary : PageMap.Writer) (source : PageMap.Snapshot)
    (owner : Nat) (lexical : Option (RetrievalResearch.Index.Reader source)) : IO (List Nat × List Nat) := do
  let intern : Intern := ⟨dictionary,← IO.mkRef {}⟩
  let original ← (← readList source source.get "ownerTerms" owner).mapM fun term => do
    intern.term ("original/"++(← readTerm source source.get term))
  let modern ← match lexical with
    | none => pure []
    | some lexical => do
      if (← source.get (key "candidate" owner)).isNone then pure []
      else (← readList lexical.index lexical.index.get "ownerTerms" owner).mapM fun term => do
        intern.term ("lexical/"++(← readTerm lexical.index lexical.index.get term))
  return (original,modern)

/-- Append-only identity assignment. Hashes only choose collision buckets;
ordered authority positions and complete streamed original bytes decide identity. -/
def identify (writer : PageMap.Writer) (source : PageMap.Snapshot) (owner : Nat)
    (lexical : Option (RetrievalResearch.Index.Reader source)) : IO Identity := do
  let snapshot ← writer.snapshot
  if let some alias ← writer.get (originalAlias source owner) then
    let entry ← readIdentity snapshot writer.get (← IO.ofExcept (payloadSize (some alias)))
    let witness ← restore entry.witness.source
    unless ← nodesEqual witness entry.witness.node source owner do
      throw (IO.userError "original owner alias diverged; a fork requires a distinct source incarnation")
    return entry
  let digest ← nodeHash source owner
  let bucket ← readList snapshot writer.get "identityBucket" digest
  for id in bucket do
    let entry ← readIdentity snapshot writer.get id
    let witness ← restore entry.witness.source
    if ← nodesEqual witness entry.witness.node source owner then
      putNat writer (originalAlias source owner) id
      return entry
  let id ← getNat writer.get "ownerIdentities"
  let terms ← sourceTerms writer source owner lexical
  let entry : Identity := ⟨id,⟨refOf source,owner⟩,terms.1,terms.2⟩
  writeJson writer (key "identity" id) entry
  writeList writer "identityBucket" digest (bucket++[id])
  putNat writer (originalAlias source owner) id
  putNat writer "ownerIdentities" (id+1)
  return entry

def membership (snapshot : PageMap.Snapshot) (read : String → IO (Option ByteArray))
    (id : Nat) : IO Membership := do
  let entry ← readJson (α := Membership) snapshot read (key "membership" id)
  match entry with
  | none => return ⟨id,[]⟩
  | some entry =>
    unless entry.id == id &&
        entry.originals == entry.originals.mergeSort (fun a b => a.ordinal < b.ordinal) &&
        hashDistinct (entry.originals.map (·.node)) == entry.originals.map (·.node) do
      throw (IO.userError "invalid per-source original inventory")
    return entry

def root (snapshot : PageMap.Snapshot) (read : String → IO (Option ByteArray))
    (name : String) : IO (Option SourceBitmap.Ref) := do
  return (← readJson (α := Option SourceBitmap.Ref) snapshot read name).join

def changeRoot (dictionary index : PageMap.Writer) (name : String) (id : Nat) (present : Bool) : IO Unit := do
  let previous ← root (← index.snapshot) index.get name
  let next ← SourceBitmap.set dictionary previous id present
  writeJson index name next

def replace (dictionary index : PageMap.Writer) (entry : Identity)
    (before after : Membership) : IO Unit := do
  let wasLive := !before.originals.isEmpty
  let isLive := !after.originals.isEmpty
  if wasLive != isLive then
    changeRoot dictionary index "allOwners" entry.id isLive
    for term in entry.originalTerms do changeRoot dictionary index (key "postingRoot" term) entry.id isLive
  let wasCandidate := before.originals.any (·.candidate)
  let isCandidate := after.originals.any (·.candidate)
  if wasCandidate != isCandidate then
    changeRoot dictionary index "candidates" entry.id isCandidate
    for term in entry.lexicalTerms do changeRoot dictionary index (key "postingRoot" term) entry.id isCandidate
  writeJson index (key "membership" entry.id) after

structure Prepared where
  captured : Captured
  changedOwners : Nat
  publications : Nat
  mode : String
  deriving ToJson

/-- Explicit off-hook source preparation. Original publishers never acquire
these derived locks. This prototype serializes short dictionary updates; it
does not claim a lock-free or capacity-validated eighty-writer dictionary. -/
def prepare (dictionaryPath : System.FilePath) (index source : PageMap.Snapshot)
    (scope : String) : IO Prepared := do
  unless !scope.isEmpty && scope.toUTF8.size ≤ 1024 do throw (IO.userError "explicit authorized source-owner scope required")
  let binding : Binding := ⟨scope,implementation⟩
  let previous ← readJson (α := State) index index.get "sourceReady"
  if let some previous := previous then
    unless previous.binding == binding && previous.source.directory == source.directory.toString &&
        previous.dictionary.directory == dictionaryPath.toString &&
        previous.source.head.identity == source.head.identity && previous.source.head.authority == source.head.authority do
      throw (IO.userError "per-source owner preparation changed namespace or source")
    if previous.source.head == source.head then return ⟨⟨refOf index,previous⟩,0,0,"unchanged"⟩
  let (owners,publications) ← match previous with
    | none => do
      let rows ← directory source "outcome"
      unless rows.length == (← getNat source.get "liveOutcomes") do throw (IO.userError "incomplete original bootstrap inventory")
      pure (rows.map Prod.snd,0)
    | some before => do
      let some delta ← SourceDelta.read? source before.source.head |
        throw (IO.userError "per-source publication delta unavailable; explicit recovery required")
      pure (delta.owners,delta.records)
  let lexical ← RetrievalResearch.Index.open? source
  unless (← getNat source.get "candidates") == 0 || lexical.isSome do
    throw (IO.userError "individual lexical source is not prepared")
  let (state,indexHead,_) ← PageMap.withWriter index fun indexWriter => do
    let dictionary ← PageMap.pin dictionaryPath
    if let some previous := previous then
      unless (← PageMap.HistoryReader.make? dictionary previous.dictionary.head).isSome do
        throw (IO.userError "source membership refers to a different dictionary extent")
    let (_,dictionaryHead,_) ← PageMap.withWriter dictionary fun writer => do
      let saved ← readJson (α := Binding) dictionary writer.get "dictionaryBinding"
      if let some saved := saved then
        unless saved == binding do throw (IO.userError "foreign source-owner dictionary")
      else writeJson writer "dictionaryBinding" binding
      for owner in owners do
        if let some bytes ← indexWriter.get (key "liveAlias" owner) then
          let id ← IO.ofExcept (payloadSize (some bytes))
          let entry ← readIdentity (← writer.snapshot) writer.get id
          let before ← membership (← indexWriter.snapshot) indexWriter.get id
          unless before.originals.any (·.node == owner) do throw (IO.userError "live alias lost source membership")
          let after := {before with originals := before.originals.filter (·.node != owner)}
          replace writer indexWriter entry before after
          indexWriter.put (key "liveAlias" owner) none
        if let some original ← readOriginal? source 0 owner then
          let entry ← identify writer source owner lexical
          let before ← membership (← indexWriter.snapshot) indexWriter.get entry.id
          let member : Member := ⟨owner,original.ordinal,original.work,original.candidate⟩
          let after := {before with originals := (member::before.originals).mergeSort (fun a b => a.ordinal < b.ordinal)}
          replace writer indexWriter entry before after
          putNat indexWriter (key "liveAlias" owner) entry.id
    let state : State := {
      binding,source := refOf source,dictionary := ⟨dictionaryPath.toString,dictionaryHead⟩
      allOwners := ← root (← indexWriter.snapshot) indexWriter.get "allOwners"
      candidates := ← root (← indexWriter.snapshot) indexWriter.get "candidates"}
    unless (state.allOwners.map (·.count) |>.getD 0) == (← getNat source.get "liveOutcomes") &&
        (state.candidates.map (·.count) |>.getD 0) == (← getNat source.get "candidates") do
      throw (IO.userError "individual source membership population differs from its original")
    writeJson indexWriter "sourceReady" state
    return state
  return ⟨⟨⟨index.directory.toString,indexHead⟩,state⟩,owners.length,publications,
    if previous.isSome then "publication-delta" else "bootstrap"⟩

structure Input where
  original : PageMap.Snapshot
  index : PageMap.Snapshot
  captured : Captured

structure Reader where
  binding : Binding
  dictionary : PageMap.Snapshot
  inputs : Array Input
  bitmap : SourceBitmap.Reader
  allOwners : Option SourceBitmap.Ref
  candidates : Option SourceBitmap.Ref

/-- Each input carries its own preparation. No whole-cut readiness key exists.
Selecting a newer captured append-only dictionary does not alter old memberships. -/
def open? (captured : Array Captured) (scope : String) : IO (Option Reader) := do
  if captured.isEmpty || scope.isEmpty then return none
  let binding : Binding := ⟨scope,implementation⟩
  let mut latest : Option Source := none
  let mut inputs : Array Input := #[]
  let mut identities : Std.HashSet String := {}
  for ref in captured do
    unless ref.state.binding == binding && !identities.contains ref.state.source.head.identity do return none
    identities := identities.insert ref.state.source.head.identity
    let original ← restore ref.state.source
    let index ← restore ref.index
    let some actual ← readJson (α := State) index index.get "sourceReady" | return none
    unless (toJson actual).compress == (toJson ref.state).compress do return none
    unless (actual.allOwners.map (·.count) |>.getD 0) == (← getNat original.get "liveOutcomes") &&
        (actual.candidates.map (·.count) |>.getD 0) == (← getNat original.get "candidates") do return none
    inputs := inputs.push ⟨original,index,ref⟩
    if let some previous := latest then
      unless previous.directory == actual.dictionary.directory &&
          previous.head.identity == actual.dictionary.head.identity && previous.head.authority == actual.dictionary.head.authority do return none
      if previous.head.revision < actual.dictionary.head.revision then latest := some actual.dictionary
    else latest := some actual.dictionary
  let some selectedDictionary := latest | return none
  let dictionary ← restore selectedDictionary
  unless (← readJson (α := Binding) dictionary dictionary.get "dictionaryBinding").any (· == binding) do return none
  -- Under the checked builder's immutable-row invariant, each captured extent
  -- remains addressable in this dictionary. This is not an IO lineage proof.
  for input in inputs do
    unless (← PageMap.HistoryReader.make? dictionary input.captured.state.dictionary.head).isSome do return none
  let bitmap ← SourceBitmap.Reader.new dictionary
  let mut allOwners := none
  let mut candidates := none
  for input in inputs do
    for ref in [input.captured.state.allOwners,input.captured.state.candidates] do
      if let some ref := ref then
        let _ ← bitmap.read ref
    allOwners ← bitmap.union allOwners input.captured.state.allOwners
    candidates ← bitmap.union candidates input.captured.state.candidates
  return some ⟨binding,dictionary,inputs,bitmap,allOwners,candidates⟩

def Reader.counts (reader : Reader) : Nat × Nat :=
  (reader.allOwners.map (·.count) |>.getD 0,reader.candidates.map (·.count) |>.getD 0)

def Reader.postingRoot (reader : Reader) (unit : String) (modern : Bool) : IO (Option SourceBitmap.Ref) := do
  let some term ← findTerm? reader.dictionary reader.dictionary.get
      ((if modern then "lexical/" else "original/")++unit) | return none
  let mut result := none
  for input in reader.inputs do
    result ← reader.bitmap.union result (← root input.index input.index.get (key "postingRoot" term.id))
  return result

def Reader.postings (reader : Reader) (unit : String) (modern : Bool := false) : IO (List Nat) := do
  let some root ← reader.postingRoot unit modern | return []
  reader.bitmap.members root.height root

def Reader.frequency (reader : Reader) (unit : String) (modern : Bool := false) : IO Nat := do
  return (← reader.postingRoot unit modern).map (·.count) |>.getD 0

def Reader.originals (reader : Reader) (id : Nat) : IO (List PreparedOwners.Original) := do
  let mut result := []
  for slot in [:reader.inputs.size] do
    let some input := reader.inputs[slot]? | throw (IO.userError "source inventory changed")
    let entry ← membership input.index input.index.get id
    result := result++entry.originals.map fun member =>
      ⟨slot,member.node,member.ordinal,member.work,member.candidate⟩
  return result

def Reader.owner? (reader : Reader) (slot owner : Nat) : IO (Option Nat) := do
  let some input := reader.inputs[slot]? | return none
  let some bytes ← input.index.get (key "liveAlias" owner) | return none
  let id ← IO.ofExcept (payloadSize (some bytes))
  let entry ← membership input.index input.index.get id
  unless entry.originals.any (·.node == owner) do throw (IO.userError "source owner alias lost membership")
  return some id

end Eggshell.SourceOwners
