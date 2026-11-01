module
public import Eggshell.StoredReadEvidence
public import Eggshell.SynapseUsage
@[expose] public section

namespace Eggshell.Synapses.ReadCatalog
open Lean DB Persistence.Store _root_.Eggshell.Synapses.Extraction

/-- The input footprint includes negative points and complete ranges. Payload
references are expanded while their checked source is pinned. Reuse never
trusts a digest of a logical name or a later source's locator rows. -/
def expand (source : PageMap.Snapshot) (operations : List PageMap.ReadObservation) :
    IO (Array PageMap.ReadObservation) := do
  let mut result := #[]
  for operation in operations do
    match operation with
    | .payload key _ chunks =>
      result := result.push (.point key (← source.get key))
      for chunk in [:chunks] do
        let name := PageMap.payloadChunkKey key chunk
        let encoded ← source.get name
        result := result.push (.point name encoded)
        let some encoded := encoded | throw (IO.userError "catalog lost its checked payload descriptor")
        result := result.push (.blob (← IO.ofExcept (PageMap.decodeBlob encoded)))
    | _ => result := result.push operation
  return result

/-- This checker is private to one pinned file handle's history. Immutable
blob bytes were checked when compiled; their original references must still
fit the requested publication. Mutable pointers, absence and full intervals
are compared again. No arbitrary reopened file can enter this pool. -/
def agrees (source : PageMap.Snapshot) (operations : Array PageMap.ReadObservation) : IO Bool := do
  for operation in operations do
    match operation with
    | .blob ref => if (ref.pin? source.head).isNone then return false
    | .payload _ _ _ => return false
    | .point key (some encoded) =>
      -- These three inputs are population bounds in the original-owner
      -- loader, never catalog data or ranking statistics. Every actual frame,
      -- membership, inverse directory and metadata input stays exact below.
      if key == "nodes" || key == "roots" || key == "outcomes" then
        let previous ← IO.ofExcept (PageMap.payloadSize (some encoded))
        let current ← getNat source.get key
        if current < previous then return false
      else if (← source.checkObservation? source.head operation).isNone then return false
    | _ => if (← source.checkObservation? source.head operation).isNone then return false
  return true

/-- Increasing a directory population cannot invalidate an already checked
index bound. Exact forward/reverse rows are separate footprint dependencies. -/
theorem increasing_population_keeps_bound (index previous current : Nat)
    (checked : index < previous) (retained : previous ≤ current) : index < current := by omega

def evidenceReads (catalog : ObservationContext.Catalog) : Array Read :=
  catalog.reads ++ catalog.located.flatMap (·.originalRows)

structure Acknowledgment where
  whole : Bool
  spans : Presentation

/-- Compile once for this owner's ACK keys, rather than hashing its raw
response and parsing all ACKs again for every original row. -/
def acknowledgment (keys : List String) (doc : Document) : Acknowledgment :=
  let whole := keys.any fun value => match value.splitOn ":" with
    | ["h", owner] => owner == doc.owner
    | ["g", owner, result] => owner == doc.owner &&
        doc.source.any (fun text => Persistence.selectionKey (.text text) == result)
    | _ => false
  let spans := keys.filterMap fun value => match value.splitOn ":" with
    | ["e", owner, result, first, limit] =>
        if owner == doc.owner && doc.source.any (fun text => Persistence.selectionKey (.text text) == result) then do
          let a ← first.toNat?
          let b ← limit.toNat?
          if a < b then some (owner,a,b) else none
        else none
    | _ => none
  ⟨whole,{bindings := spans.toArray}⟩

def Acknowledgment.accepts (ack : Acknowledgment) (row : Read) : Bool :=
  ack.whole || ack.spans.coversBinding row.binding

def ownerAcknowledgments (owner : String) (keys : List String) : List String :=
  keys.filter fun key => match key.splitOn ":" with
    | ["h",id] | ["g",id,_] | ["e",id,_,_,_] => id == owner
    | _ => false

structure Projection where
  doc : Document
  evidence : Option StoredReadEvidence.Owner
  shown : Array Read
  charge : Nat

/-- The original-row membership witness is retained in memory, rather than
reconstructed from untrusted serialized witnesses. -/
def owner? (doc : Document) (catalog : ObservationContext.Catalog) : Option StoredReadEvidence.Owner := do
  let some raw := doc.source | none
  if original : doc.source = some raw then
    if native : doc.native = true then
      let reads := evidenceReads catalog
      let byCore := reads.attach.foldl
        (fun found row => found.insert (StoredReadEvidence.core row.val) row) {}
      some {doc,raw,original,native,reads,byCore}
    else none
  else none

theorem compiled_membership (doc : Document) (catalog : ObservationContext.Catalog)
    (owner : StoredReadEvidence.Owner) (compiled : owner? doc catalog = some owner) :
    owner.reads = evidenceReads catalog := by
  unfold owner? at compiled
  split at compiled <;> simp_all
  rcases compiled with ⟨_,rfl⟩
  rfl

def compile (source : PageMap.Snapshot) (prepared : Option PageMap.Snapshot) (id : Nat) : IO Projection := do
  let reader ← NodeReader.new source
  let documents : Build.Documents source := {
    reader,cache := ← IO.mkRef {},catalogs := ← IO.mkRef {},prepared}
  let doc ← documents.get id
  let evidence ← documents.catalog id
  let original := (ObservationContext.recorded source.head.identity doc).getD {}
  let shown ← ContentMetadata.addFileCoordinates source id doc original prepared
  let rows := evidenceReads evidence
  let shown := shown.located.flatMap (·.originalRows)
  -- Read/ACK consumers retain projections only. Located text and lazy quote
  -- maps belong to extraction and are discarded here. One shared allowance
  -- includes the document, Read arrays, membership map and input footprint.
  let textBytes := (doc.source.map String.utf8ByteSize).getD 0 +
    (doc.workText.map String.utf8ByteSize).getD 0
  let charge := 8192 + 4*textBytes + 2*(toJson (rows,shown)).compress.utf8ByteSize +
    128*(rows.size+shown.size)
  return ⟨doc,owner? doc evidence,shown,charge⟩

structure Entry where
  sourceReads : Array PageMap.ReadObservation
  indexReads : Array PageMap.ReadObservation
  indexed : Bool
  projection : Projection
  sourceHead : PageMap.Head
  indexHead : Option PageMap.Head

/-- Only the final ACK's original ranges and their input footprint survive.
No original body, quote map or stored-read membership table is retained. -/
structure Acknowledged where
  owner : String
  keys : List String
  ranges : Array Range
  sourceReads : Array PageMap.ReadObservation
  indexReads : Array PageMap.ReadObservation
  indexed : Bool
  sourceHead : PageMap.Head
  indexHead : Option PageMap.Head
  charge : Nat

structure State where
  entries : Std.HashMap Nat Entry := {}
  acknowledgments : Std.HashMap Nat Acknowledged := {}
  bytes : Nat := 0
  ackBytes : Nat := 0
  compiled : Nat := 0
  reused : Nat := 0
  sameHead : Nat := 0
  invalidated : Nat := 0
  uncached : Nat := 0
  evictions : Nat := 0
  ackProjections : Nat := 0
  ackReused : Nat := 0

/-- One project service owns one source pin and an optional prepared-index
pin. Clients request historical heads, never supply a foreign typed reader.
The allowance is shared by clients, not multiplied by their count. -/
structure Pool where
  source : PageMap.Snapshot
  prepared : Option PageMap.Snapshot
  state : IO.Ref State
  gate : Std.Mutex Unit
  maxBytes : Nat := 67108864
  maxOwners : Nat := 1024

def create (source : PageMap.Snapshot) (prepared : Option PageMap.Snapshot) : IO Pool := do
  return ⟨source,prepared,← IO.mkRef {},← Std.Mutex.new (),67108864,1024⟩

def historical? (origin : PageMap.Snapshot) (head : PageMap.Head) : IO (Option PageMap.Snapshot) := do
  return (← PageMap.HistoryReader.make? origin head).map (·.snapshot)

def getLocked? (pool : Pool) (head : PageMap.Head) (indexHead : Option PageMap.Head)
    (id : Nat) : IO (Option Projection) := do
  let some source ← historical? pool.source head | return none
  let available : Option (Option PageMap.Snapshot) ← match indexHead,pool.prepared with
    | none,_ => pure (some none)
    | some wanted,some origin => do
      let found ← historical? origin wanted
      pure (found.map (fun snapshot => (some snapshot : Option PageMap.Snapshot)))
    | _,_ => pure none
  let some prepared := available | return none
  if let some entry := (← pool.state.get).entries[id]? then
    let same := entry.sourceHead == head && entry.indexHead == indexHead
    if same || (entry.indexed == prepared.isSome && (← agrees source entry.sourceReads) &&
        (← match prepared with
          | some index => agrees index entry.indexReads
          | none => pure entry.indexReads.isEmpty)) then
      pool.state.modify fun state => {state with
        reused := state.reused+1,sameHead := state.sameHead+(if same then 1 else 0)
        entries := state.entries.insert id {entry with sourceHead := head,indexHead}}
      return some entry.projection
    pool.state.modify fun state => {state with invalidated := state.invalidated+1}
  let source := {source with trace := ← IO.mkRef (some {operations := []})}
  let prepared ← prepared.mapM fun index => do
    return {index with trace := ← IO.mkRef (some {operations := []})}
  let projection ← compile source prepared id
  let sourceTrace ← source.trace.get
  let indexTrace ← prepared.mapM (fun index => index.trace.get)
  let complete := sourceTrace.any (·.complete) && (indexTrace.getD (some {operations := []})).any (·.complete)
  let sourceReads ← expand source ((sourceTrace.map (·.operations)).getD [])
  let indexReads ← match prepared,indexTrace.join with
    | some index,some trace => expand index trace.operations
    | _,_ => pure #[]
  let charge := projection.charge + (sourceReads ++ indexReads).foldl
    (fun bytes operation => bytes+PageMap.readObservationCodec.encodedSize operation) 0
  pool.state.modify fun state =>
    let state := {state with compiled := state.compiled+1}
    let allowance := pool.maxBytes*3/4
    if !complete || charge > allowance then {state with uncached := state.uncached+1}
    else
      let oldCharge := (state.entries[id]?.map (·.projection.charge)).getD 0
      let state := {state with bytes := state.bytes-oldCharge,entries := state.entries.erase id}
      let state := if state.bytes+charge > allowance || state.entries.size ≥ pool.maxOwners then
          {state with entries := {},bytes := 0,evictions := state.evictions+1}
        else state
      {state with bytes := state.bytes+charge,entries := state.entries.insert id {
        sourceReads,indexReads,indexed := prepared.isSome
        projection := {projection with charge},sourceHead := head,indexHead}}
  return some projection

/-- Coalesce concurrent misses in the shared service. Publication preparation
and readers cannot compile the same owner eighty times. -/
def Pool.get? (pool : Pool) (head : PageMap.Head) (indexHead : Option PageMap.Head)
    (id : Nat) : IO (Option Projection) :=
  pool.gate.atomically (getLocked? pool head indexHead id)

def acknowledgedLocked? (pool : Pool) (head : PageMap.Head) (indexHead : Option PageMap.Head)
    (id : Nat) (keys : List String) : IO (Option (Array Range)) := do
  let some source ← historical? pool.source head | return none
  let available : Option (Option PageMap.Snapshot) ← match indexHead,pool.prepared with
    | none,_ => pure (some none)
    | some wanted,some origin => do
      let found ← historical? origin wanted
      pure (found.map (fun snapshot => (some snapshot : Option PageMap.Snapshot)))
    | _,_ => pure none
  let some prepared := available | return none
  if let some ack := (← pool.state.get).acknowledgments[id]? then
    let same := ack.sourceHead == head && ack.indexHead == indexHead
    if ack.keys == ownerAcknowledgments ack.owner keys &&
        (same || (ack.indexed == prepared.isSome && (← agrees source ack.sourceReads) &&
          (← match prepared with
            | some index => agrees index ack.indexReads
            | none => pure ack.indexReads.isEmpty))) then
      pool.state.modify fun state => {state with
        ackReused := state.ackReused+1
        acknowledgments := state.acknowledgments.insert id {ack with sourceHead := head,indexHead}}
      return some ack.ranges
  let some projected ← getLocked? pool head indexHead id | return none
  let ack := acknowledgment keys projected.doc
  let ranges := projected.shown.filter ack.accepts |>.map (·.source)
  -- An uncacheable original must not acquire a reusable ACK through this
  -- path: the complete checked input footprint is mandatory for both.
  if let some entry := (← pool.state.get).entries[id]?.filter (fun entry =>
      entry.sourceHead == head && entry.indexHead == indexHead) then
    let localKeys := ownerAcknowledgments projected.doc.owner keys
    let charge := 4096 + 2*(toJson (localKeys,ranges)).compress.utf8ByteSize +
      2*(entry.sourceReads ++ entry.indexReads).foldl
        (fun size operation => size+PageMap.readObservationCodec.encodedSize operation) 0
    pool.state.modify fun state =>
      let state := {state with ackProjections := state.ackProjections+1}
      let allowance := pool.maxBytes/4
      if charge > allowance then state else
        let previous := (state.acknowledgments[id]?.map (·.charge)).getD 0
        let state := {state with ackBytes := state.ackBytes-previous,acknowledgments := state.acknowledgments.erase id}
        let state := if state.ackBytes+charge > allowance || state.acknowledgments.size ≥ pool.maxOwners then
            {state with ackBytes := 0,acknowledgments := {}}
          else state
        {state with ackBytes := state.ackBytes+charge,acknowledgments := state.acknowledgments.insert id {
          owner := projected.doc.owner,keys := localKeys,ranges,sourceReads := entry.sourceReads,
          indexReads := entry.indexReads,indexed := entry.indexed,sourceHead := head,indexHead,charge}}
  return some ranges

def Pool.acknowledged? (pool : Pool) (head : PageMap.Head) (indexHead : Option PageMap.Head)
    (id : Nat) (keys : List String) : IO (Option (Array Range)) :=
  pool.gate.atomically (acknowledgedLocked? pool head indexHead id keys)

/-- Publication preparation is explicit and can receive only the changed
owner IDs. No question, ranking score or answer model enters the compiler. -/
def Pool.preparePublication (pool : Pool) (head : PageMap.Head) (indexHead : Option PageMap.Head)
    (changedOwners : Array Nat) : IO Unit := do
  for id in changedOwners do
    unless (← pool.get? head indexHead id).isSome do
      throw (IO.userError "read catalog publication is outside its pinned service scope")

def check? (database : String) (projection : Projection) (candidate : Read) :
    Option (StoredReadEvidence.Witness candidate) := do
  unless candidate.valid && candidate.binding.database == database &&
      (Persistence.SelectionKey.check? candidate.binding.owner).isSome do none
  let owner ← projection.evidence
  unless owner.doc.owner == candidate.binding.owner && owner.doc.work == candidate.binding.work &&
      owner.doc.occurrences.contains candidate.occurrence do none
  let saved ← owner.byCore[StoredReadEvidence.core candidate]?
  if same : StoredReadEvidence.core candidate = StoredReadEvidence.core saved.val then some ⟨owner,saved,same⟩
  else none

theorem checked_keeps_original (candidate : Read)
    (witness : StoredReadEvidence.Witness candidate) :
    candidate.source = witness.saved.val.source ∧ candidate.binding = witness.saved.val.binding ∧
      candidate.occurrence = witness.saved.val.occurrence :=
  ⟨witness.same_source,witness.same_binding,witness.same_occurrence⟩

end Eggshell.Synapses.ReadCatalog
