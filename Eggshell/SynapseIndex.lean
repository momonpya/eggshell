module

public import Eggshell.GraphStore
public import Eggshell.SynapseProvenance

@[expose] public section

namespace Eggshell.Synapses.Index
open Lean DB

inductive Scope where
  | shared | usage
  deriving Repr, BEq, ToJson, FromJson

def Scope.directory : Scope → String
  | .shared => "recommendations"
  | .usage => "usage"

def Scope.accepts (scope : Scope) : Fact → Bool
  | .used _ => scope == .usage
  | _ => scope == .shared

theorem shared_rejects_usage (usage : Usage) : Scope.shared.accepts (.used usage) = false := rfl

/-- The implementation key follows source bytes, never a hand-maintained version. -/
def implementation : String :=
  Blake3.hex (Blake3.digest "eggshell.synaptic-index".toUTF8 [
    (include_str "Synapses.lean").toUTF8, (include_str "SynapseExtraction.lean").toUTF8,
    (include_str "SynapseSource.lean").toUTF8, (include_str "SynapseUsage.lean").toUTF8,
    (include_str "SynapseIndex.lean").toUTF8, (include_str "SynapseBuild.lean").toUTF8,
    (include_str "SynapseProvenance.lean").toUTF8,
    (include_str "SourceEvidence.lean").toUTF8,
    (include_str "SearchUnicode.lean").toUTF8,
    (include_str "../tools/RetrievalCategories.lean").toUTF8])

inductive Key where
  | owner (database owner : String)
  | answer (database owner : String)
  | claim (claim : Claim)
  | consumer (occurrence : Occurrence)
  | group (group : Group)
  | quoted (source : Range)
  | source (source : Range)
  | file (file : File)
  | query (digest : String)
  | usage (source : Range)
  deriving Repr, DecidableEq, BEq, ReflBEq, LawfulBEq, ToJson, FromJson

def addresses : Fact → Array Key
  | .read recorded => #[.owner recorded.binding.database recorded.binding.owner, .source recorded.source, .file recorded.source.file]
  | .supports support => #[
      .answer support.claim.database support.claim.answer, .claim support.claim, .source support.source]
  | .consumed edge => #[.consumer edge.consumer]
  | .coquoted group source => #[.group group, .quoted source]
  | .used usage => #[.query usage.query, .usage usage.source]

def contentKey [ToJson α] (value : α) : String :=
  Blake3.hex (Blake3.digest "eggshell.synaptic-object".toUTF8 [(toJson value).compress.toUTF8])

def factName (fact : Fact) : String := "fact:" ++ contentKey fact

def postingPrefix (key : Key) : String := "lookup:" ++ contentKey key ++ ":"

structure Posting where
  key : Key
  fact : String
  deriving BEq, ToJson, FromJson

def postingName (key : Key) (fact : Fact) : String := postingPrefix key ++ contentKey fact

def eventName (event : Event) : String := "event:" ++ contentKey event

def belongs (database : String) : Fact → Bool
  | .read recorded => recorded.binding.database == database
  | .supports support => support.claim.database == database && support.read.binding.database == database
  | .coquoted (.answer owner _) _ => owner == database
  | .coquoted (.claim claim) _ => claim.database == database
  | .consumed _ | .used _ => true

def checkDestination (storage : Sidecar.Storage) (scope : Scope) : IO Unit :=
  if scope == .usage && storage != .user then
    throw (IO.userError "synaptic usage must stay in the private DB overlay")
  else pure ()

structure Manifest where
  source : PageMap.Head
  implementation : String
  scope : Scope
  facts : Nat
  deriving BEq, ToJson, FromJson

def payloadLimit : Nat := 262144

def decode [FromJson α] [ToJson α] (bytes : ByteArray) : IO α := do
  unless bytes.size ≤ payloadLimit do throw (IO.userError "synaptic record exceeds its byte bound")
  let some text := String.fromUTF8? bytes | throw (IO.userError "invalid synaptic UTF-8")
  let value ← IO.ofExcept (Json.parse text >>= fromJson? (α := α))
  unless (toJson value).compress.toUTF8 == bytes do
    throw (IO.userError "noncanonical synaptic record")
  return value

def manifest? (snapshot : PageMap.Snapshot) : IO (Option Manifest) := do
  (← snapshot.get "manifest").mapM (decode (α := Manifest))

/-- An old index is usable across derived-only commits, through exact parent heads.
The lookup path examines at most the supplied number of journal entries. -/
def sameSources (snapshot : PageMap.Snapshot) (saved : PageMap.Head) (limit : Nat := 16) : IO Bool := do
  if saved.identity != snapshot.head.identity || saved.authority != snapshot.head.authority then return false
  let mut current := snapshot.head
  for _ in [:limit] do
    if current == saved then return true
    if current.revision ≤ saved.revision then return false
    let publication ← Persistence.Store.readPublication snapshot current.revision
    if !publication.change.neutral then return false
    current := publication.parent
  return current == saved

def directory (snapshot : PageMap.Snapshot) (storage : Sidecar.Storage) (scope : Scope) :
    IO System.FilePath := do
  return (← Sidecar.locate snapshot storage).directory / "synapses" / scope.directory

def prepare (snapshot : PageMap.Snapshot) (storage : Sidecar.Storage) (scope : Scope) :
    IO PageMap.Snapshot := do
  if scope == .usage && storage != .user then
    throw (IO.userError "synaptic usage must stay in the private DB overlay")
  let sidecar ← Sidecar.prepare (Sidecar.Owner.ofSnapshot snapshot) storage
  let parent ← Sidecar.childDirectory sidecar.directory "synapses"
  let path := parent / scope.directory
  match ← PageMap.open? path with
  | some snapshot => return snapshot
  | none => PageMap.create path ("advisory:" ++ snapshot.head.identity ++ ":" ++ scope.directory)

structure Reader where
  index : PageMap.Snapshot
  manifest : Manifest

/-- Opening never creates an index or prepares a directory inside a shared DB. -/
def open? (source : PageMap.Snapshot) (storage : Sidecar.Storage) (scope : Scope) : IO (Option Reader) := do
  if scope == .usage && storage != .user then return none
  let path ← directory source storage scope
  let some index ← PageMap.open? path | return none
  let some metadata ← manifest? index | return none
  unless metadata.implementation == implementation && metadata.scope == scope do return none
  if scope == .shared then
    unless (← index.get "provenance") == some (toJson (← Provenance.stamp source)).compress.toUTF8 do return none
    unless ← sameSources source metadata.source do return none
  else
    unless metadata.source.identity == source.head.identity &&
        metadata.source.authority == source.head.authority do return none
  return some ⟨index, metadata⟩

def openShared? (source : PageMap.Snapshot) : IO (Option Reader) := do
  if let some reader ← open? source .database .shared then return some reader
  open? source .user .shared

def checkedBytes [ToJson α] (value : α) : IO ByteArray := do
  let bytes := (toJson value).compress.toUTF8
  unless bytes.size ≤ payloadLimit do throw (IO.userError "synaptic record exceeds its byte bound")
  return bytes

def putImmutable (writer : PageMap.Writer) (name : String) (bytes : ByteArray) : IO Bool := do
  if let some previous ← writer.get name then
    unless previous == bytes do throw (IO.userError "conflicting synaptic content address")
    return false
  writer.put name (some bytes)
  return true

def insert (writer : PageMap.Writer) (database : String) (scope : Scope) (fact : Fact) : IO Bool := do
  unless scope.accepts fact && belongs database fact && fact.valid do
    throw (IO.userError "invalid fact or wrong synaptic privacy/DB scope")
  if let .used usage := fact then
    let _ ← putImmutable writer (eventName usage.event) (← checkedBytes usage)
  let inserted ← putImmutable writer (factName fact) (← checkedBytes fact)
  for key in addresses fact do
    let posting : Posting := ⟨key, contentKey fact⟩
    let _ ← putImmutable writer (postingName key fact) (← checkedBytes posting)
  return inserted

def erase (writer : PageMap.Writer) (fact : Fact) : IO Bool := do
  let name := factName fact
  let some previous ← writer.get name | return false
  unless previous == (toJson fact).compress.toUTF8 do
    throw (IO.userError "retired synaptic object differs from its content address")
  writer.put name none
  for key in addresses fact do writer.put (postingName key fact) none
  -- Retiring a recommendation does not permit relabelling an observed event.
  -- The small immutable witness remains until its owning DB cache is retired.
  return true

structure Delta where
  removed : Array Fact := #[]
  added : Array Fact := #[]

def checkFacts (database : String) (scope : Scope) (facts : Array Fact) : IO Unit :=
  unless facts.all (fun fact => scope.accepts fact && belongs database fact && fact.valid) do
    throw (IO.userError "invalid fact or wrong synaptic privacy/DB scope")

/-- One metadata publication commits facts and all inverse postings together.
An incompatible prior implementation needs a full replacement, never reuse. -/
def publishDelta (source : PageMap.Snapshot) (storage : Sidecar.Storage) (scope : Scope)
    (expected : Option PageMap.Head) (delta : Delta) : IO PageMap.Head := do
  checkDestination storage scope
  checkFacts source.head.identity scope delta.added
  checkFacts source.head.identity scope delta.removed
  Sidecar.withIndexClaim (Sidecar.Owner.ofSnapshot source) (fun _ => do
    let index ← prepare source storage scope
    let previous ← manifest? index
    if let some previous := previous then
      if scope == .shared && previous.source.revision > source.head.revision then
        throw (IO.userError "older source cannot replace a later synaptic publication")
      unless previous.source == expected.getD source.head && previous.implementation == implementation &&
          previous.scope == scope do throw (IO.userError "stale synaptic index update")
    else if expected.isSome then throw (IO.userError "missing synaptic index update base")
    let (_, head, _) ← PageMap.withWriter index fun writer => do
      let mut count := previous.map (·.facts) |>.getD 0
      for fact in delta.removed do
        if ← erase writer fact then count := count-1
      for fact in delta.added do
        if ← insert writer source.head.identity scope fact then count := count+1
      let next : Manifest := ⟨source.head, implementation, scope, count⟩
      let bytes ← checkedBytes next
      if (← writer.get "manifest") != some bytes then writer.put "manifest" (some bytes)
      let provenance := (toJson (← Provenance.stamp source)).compress.toUTF8
      if (← writer.get "provenance") != some provenance then writer.put "provenance" (some provenance)
    return head) storage

def allFacts (index : PageMap.Snapshot) : IO (Array Fact) :=
  index.foldRange ⟨"fact:", "fact;"⟩ (fun facts row => do
    let some bytes := row.2 | return facts
    let fact ← decode (α := Fact) bytes
    unless row.1 == factName fact && fact.valid do throw (IO.userError "foreign synaptic fact row")
    return facts.push fact) #[]

/-- Explicit warm/background replacement; it never runs in a search hook. -/
def replace (source : PageMap.Snapshot) (storage : Sidecar.Storage) (scope : Scope)
    (facts : Array Fact) : IO PageMap.Head := do
  checkDestination storage scope
  checkFacts source.head.identity scope facts
  Sidecar.withIndexClaim (Sidecar.Owner.ofSnapshot source) (fun _ => do
    let index ← prepare source storage scope
    if let some previous ← manifest? index then
      if scope == .shared && previous.source.revision > source.head.revision then
        throw (IO.userError "older source cannot replace a later synaptic publication")
    let wanted := facts.foldl (fun wanted fact => wanted.insert (factName fact)) ({} : Std.HashSet String)
    let old ← allFacts index
    let (_, head, _) ← PageMap.withWriter index fun writer => do
      for fact in old do
        if !wanted.contains (factName fact) then let _ ← erase writer fact; pure ()
      for fact in facts do let _ ← insert writer source.head.identity scope fact; pure ()
      let next : Manifest := ⟨source.head, implementation, scope, wanted.size⟩
      let bytes ← checkedBytes next
      if (← writer.get "manifest") != some bytes then writer.put "manifest" (some bytes)
      let provenance := (toJson (← Provenance.stamp source)).compress.toUTF8
      if (← writer.get "provenance") != some provenance then writer.put "provenance" (some provenance)
    return head) storage

structure Scan where
  postings : Array Posting := #[]
  inspected : Nat := 0
  pages : Nat := 0
  complete : Bool := true

/-- Stop in the tree, rather than materializing or traversing all postings. -/
def scanAt (index : PageMap.Snapshot) (ref : PageMap.Ref) (range : PageMap.KeyRange)
    (limit deadline : Nat) (initial : Scan) : IO Scan := do
  if !initial.complete then return initial
  if initial.inspected ≥ limit || (← IO.monoMsNow) ≥ deadline then return {initial with complete := false}
  let loaded ← index.load ref
  let mut result := {initial with pages := initial.pages+1}
  match loaded.page with
  | .leaf rows =>
    for row in range.select rows do
      if result.inspected ≥ limit || (← IO.monoMsNow) ≥ deadline then return {result with complete := false}
      let some bytes := row.2 | continue
      let posting ← decode (α := Posting) bytes
      unless row.1 == postingPrefix posting.key ++ posting.fact do throw (IO.userError "foreign synaptic posting")
      result := {result with postings := result.postings.push posting, inspected := result.inspected+1}
    return result
  | .branch children =>
    for child in children do
      if range.overlaps child then
        if _smaller : child.height < ref.height then
          result ← scanAt index child range limit deadline result
        else throw (IO.userError "synaptic index height did not decrease")
        if !result.complete then return result
    return result
termination_by ref.height

/-- This certifies the advisory inverse relation, not Work or completion authority. -/
structure CheckedFact (key : Key) where
  fact : Fact
  valid : fact.valid = true
  bound : key ∈ addresses fact

def CheckedFact.check? (key : Key) (fact : Fact) : Option (CheckedFact key) :=
  if valid : fact.valid = true then
    if bound : (addresses fact).contains key = true then
      some ⟨fact, valid, Array.mem_of_contains_eq_true bound⟩
    else none
  else none

structure Lookup (key : Key) where
  checked : Array (CheckedFact key)
  complete : Bool
  postingPages : Nat
  index : PageMap.Head
  payloadBytes : Nat := 0

def Lookup.facts (lookup : Lookup key) : Array Fact := lookup.checked.map (·.fact)

theorem Lookup.returned_bound (lookup : Lookup key) (fact : Fact)
    (present : fact ∈ lookup.facts) :
    fact.valid = true ∧ key ∈ addresses fact := by
  simp only [Lookup.facts, Array.mem_map] at present
  obtain ⟨checked, _, equal⟩ := present
  subst fact
  exact ⟨checked.valid, checked.bound⟩

def Reader.lookup (reader : Reader) (key : Key) (limit deadline : Nat)
    (byteLimit : Option Nat := none) : IO (Lookup key) := do
  let name := postingPrefix key
  let scanned ← match reader.index.head.root with
    | none => pure ({} : Scan)
    | some root => scanAt reader.index root ⟨name, "lookup:" ++ contentKey key ++ ";"⟩ limit deadline {}
  let mut facts := #[]
  let mut complete := scanned.complete
  let mut payloadBytes := 0
  for posting in scanned.postings do
    if (← IO.monoMsNow) ≥ deadline then
      complete := false
      break
    unless posting.key == key do throw (IO.userError "ambiguous synaptic key digest")
    let some bytes ← reader.index.get ("fact:" ++ posting.fact) |
      throw (IO.userError "dangling synaptic posting")
    if byteLimit.any (payloadBytes+bytes.size > ·) then
      complete := false
      break
    let fact ← decode (α := Fact) bytes
    unless fact.valid && reader.manifest.scope.accepts fact && belongs reader.manifest.source.identity fact &&
        contentKey fact == posting.fact && (addresses fact).contains key do
      throw (IO.userError "synaptic posting does not bind its original fact")
    let some checked := CheckedFact.check? key fact |
      throw (IO.userError "unbound advisory index result")
    facts := facts.push checked
    payloadBytes := payloadBytes+bytes.size
  return ⟨facts, complete, scanned.pages, reader.index.head, payloadBytes⟩

end Eggshell.Synapses.Index
