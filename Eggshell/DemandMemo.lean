module

public import Eggshell.GraphStore

@[expose] public section
namespace Eggshell.Plugin.DemandMemo
open Lean Persistence DB

/-- Physical snapshot capabilities also cover negative membership, population,
frequencies, root order, topology and source authority. A digest nominates a
cache slot; complete request bytes and every source capability decide reuse. -/
abbrev Source := String × Option PageMap.Head

structure Record where
  request : String
  sources : List Source
  response : String
  /-- Captured by the production snapshot reader, never inferred from hits. -/
  reads : Option (List (List PageMap.ReadObservation)) := none
  /-- `none` means that no external nomination was used. `some []` is an
  actual, completed negative observation and must not be confused with it. -/
  nominations : Option (List Nat) := none
  deriving BEq, DecidableEq

def sourceCodec : Wire.Codec Source := Wire.text.product (Wire.optional PageMap.headCodec)
def codec : Wire.Codec Record :=
  (Wire.text.product ((Wire.list sourceCodec).product (Wire.text.product
    ((Wire.optional (Wire.list (Wire.list PageMap.readObservationCodec))).product
      (Wire.optional (Wire.list Wire.natural)))))).iso
    (fun r => (r.request, r.sources, r.response, r.reads, r.nominations))
    (fun (request, sources, response, reads, nominations) =>
      ⟨request, sources, response, reads, nominations⟩)
    (by intro r; cases r; rfl)

theorem codec_roundtrip (record : Record) (tail : List UInt8) :
    codec.decode (codec.encode record ++ tail) = .ok (record, tail) := codec.roundtrip record tail

def allowance : Nat := 65536
def slots : Nat := 8
def chainAllowance : Nat := 32
def publicationAllowance : Nat := 16384
def row (request : String) : String := "memo:handoff:" ++ toString (hash request % slots)

def requestMatches (record : Record) (request : String) : Bool := record.request == request

theorem changed_request_rejected (record : Record) (request : String)
    (different : record.request ≠ request) : requestMatches record request = false := by
  simp [requestMatches, different]

/-- Only the observation produced by this request can authorize its cache
record. This certificate does not predict or memoize an external provider. -/
structure ObservedRecord (nominations : Option (List Nat)) where
  record : Record
  agrees : record.nominations = nominations

def observedRecord? (record : Record) (nominations : Option (List Nat)) :
    Option (ObservedRecord nominations) :=
  if same : record.nominations = nominations then some ⟨record, same⟩ else none

theorem changed_nominations_rejected (record : Record) (nominations : Option (List Nat))
    (changed : record.nominations ≠ nominations) : observedRecord? record nominations = none := by
  simp [observedRecord?, changed]

theorem observed_record_has_current_nominations (checked : ObservedRecord nominations) :
    checked.record.nominations = nominations := checked.agrees

/-- Cache metadata is not a graph input. Give its reader a separate disabled
observer while retaining the exact immutable file/root and resource counters.
Otherwise a lookup performed after semantic retrieval records its own empty
memo slot and invalidates itself as soon as that slot is published. -/
structure MetadataReader (origin : Store.Snapshot) where
  snapshot : Store.Snapshot
  sameDirectory : snapshot.directory = origin.directory
  sameHead : snapshot.head = origin.head
  sameHandle : snapshot.handle = origin.handle
  sameReadCount : snapshot.reads = origin.reads
  sameByteCount : snapshot.readBytes = origin.readBytes

def MetadataReader.make (origin : Store.Snapshot) : IO (MetadataReader origin) := do
  let quiet ← PageMap.QuietReader.make origin
  pure ⟨quiet.snapshot, quiet.sameDirectory, quiet.sameHead, quiet.sameHandle,
    quiet.sameCounts.1, quiet.sameCounts.2⟩

theorem metadata_reader_uses_pinned_file {origin : Store.Snapshot} (reader : MetadataReader origin) :
    reader.snapshot.head = origin.head ∧ reader.snapshot.handle = origin.handle :=
  ⟨reader.sameHead, reader.sameHandle⟩

theorem metadata_reader_counts_actual_io {origin : Store.Snapshot} (reader : MetadataReader origin) :
    reader.snapshot.reads = origin.reads ∧ reader.snapshot.readBytes = origin.readBytes :=
  ⟨reader.sameReadCount, reader.sameByteCount⟩

/-- A chain cannot jump over a changed record or accept another branch having
the same revision counter. Each edge checks the complete predecessor head. -/
inductive NeutralChain : PageMap.Head → PageMap.Head → Prop
  | refl (head) : NeutralChain head head
  | step {first parent last} (earlier : NeutralChain first parent)
      (publication : Store.Publication) (linked : publication.parent = parent)
      (neutral : publication.change.neutral = true)
      (successor : last.revision = parent.revision + 1)
      (identity : last.identity = parent.identity)
      (authority : last.authority = parent.authority) : NeutralChain first last

/-- Refinement boundary: a graph-store producer must publish an empty delta
only for a graph-neutral operation. Under that invariant, the entire source
meaning, rather than just its previously selected positive roots, is preserved.
This is a theorem about the actual checked chain, not a filesystem axiom. -/
theorem NeutralChain.preserves {first last : PageMap.Head}
    (chain : NeutralChain first last) (meaning : PageMap.Head → α)
    (producer : ∀ parent child (publication : Store.Publication),
      publication.parent = parent → publication.change.neutral = true →
      child.revision = parent.revision + 1 → child.identity = parent.identity →
      child.authority = parent.authority → meaning parent = meaning child) :
    meaning first = meaning last := by
  induction chain with
  | refl => rfl
  | step earlier publication linked neutral successor identity authority ih =>
      exact ih.trans (producer _ _ publication linked neutral successor identity authority)

/-- The semantic effect replayed by the graph store. Both removed and newly
matching roots are included; a nonempty delta is never a cache hit. -/
def replay (change : Store.Change) (roots : List Value) (unions : List UnionEdge)
    (resolve : Nat → Value) (newUnions : List UnionEdge) : List Value × List UnionEdge :=
  (Store.reviseValues roots (change.removed.map resolve) (change.added.map resolve),
    if change.unionsChanged then newUnions else unions)

theorem neutral_replay (change : Store.Change) (neutral : change.neutral = true)
    (roots : List Value) (unions : List UnionEdge) (resolve : Nat → Value)
    (newUnions : List UnionEdge) : replay change roots unions resolve newUnions = (roots, unions) := by
  obtain ⟨added, removed, unionsSame⟩ := (Store.Change.neutral_exact change).mp neutral
  simp [replay, added, removed, unionsSame, Store.reviseValues]

structure Agreed (old current : PageMap.Head) : Type where
  chain : NeutralChain old current

def agreement (snapshot : Store.Snapshot) (old : PageMap.Head) :
    (fuel : Nat) → (current : PageMap.Head) → IO (Option (Agreed old current))
  | 0, current =>
      if same : old = current then pure (some ⟨same ▸ NeutralChain.refl old⟩) else pure none
  | fuel + 1, current => do
      if same : old = current then return some ⟨same ▸ NeutralChain.refl old⟩
      unless current.identity == old.identity && current.authority == old.authority &&
          old.revision < current.revision do return none
      -- Check sizes before following any chunk counter from an optional memo.
      let size ← Store.getNat snapshot.get (Store.key "change" current.revision)
      if size == 0 || size > publicationAllowance then return none
      let publication ← Store.readPublication snapshot current.revision
      if neutral : publication.change.neutral = true then
        if successor : current.revision = publication.parent.revision + 1 then
          if identity : current.identity = publication.parent.identity then
            if authority : current.authority = publication.parent.authority then
              let some earlier ← agreement snapshot old fuel publication.parent | return none
              return some ⟨.step earlier.chain publication rfl neutral successor identity authority⟩
      return none

def agree (snapshot : Store.Snapshot) (old : PageMap.Head) : IO Bool := do
  if snapshot.head.revision - old.revision > chainAllowance then return false
  pure (← agreement snapshot old chainAllowance snapshot.head).isSome

def sourcesAgree (sources : List Source) (paths : List System.FilePath)
    (snapshots : List (Option Store.Snapshot)) : IO Bool := do
  if sources.length != paths.length || snapshots.length != paths.length then return false
  for ((path, snapshot), source) in (paths.zip snapshots).zip sources do
    if source.1 != path.normalize.toString then return false
    match source.2, snapshot with
    | none, none => pure ()
    | some old, some current =>
        let reader ← MetadataReader.make current
        if !(← agree reader.snapshot old) then return false
    | _, _ => return false
  return true

/-- A changed publication need not repair an unused request. Recheck the
actual read domain, including absent keys, complete candidate intervals,
population/frequency rows, topology, origins and selected payloads. The pinned
incarnation and authority still belong to the same readable source. -/
def dependenciesAgree (record : Record) (paths : List System.FilePath)
    (snapshots : List (Option Store.Snapshot)) : IO Bool := do
  -- An unchanged source, or a certified graph-neutral append chain, preserves
  -- its committed prefix. Do not read every immutable body just to reuse a
  -- completed demand. Actual body reads still perform their checksum checks.
  if ← sourcesAgree record.sources paths snapshots then return true
  let some reads := record.reads | return false
  if record.sources.length != paths.length || snapshots.length != paths.length ||
      reads.length != paths.length then return false
  for (((path, snapshot), source), observations) in ((paths.zip snapshots).zip record.sources).zip reads do
    if source.1 != path.normalize.toString then return false
    match source.2, snapshot with
    | none, none => if !observations.isEmpty then return false
    | some old, some current =>
        unless old.identity == current.head.identity && old.authority == current.head.authority &&
            old.revision ≤ current.head.revision do return false
        let reader ← MetadataReader.make current
        if (← reader.snapshot.verifyReads? old observations).isNone then return false
    | _, _ => return false
  return true

def read (snapshot : Store.Snapshot) (request : String) : IO (Option Record) := do
  let snapshot := (← MetadataReader.make snapshot).snapshot
  let tag := row request
  if (← snapshot.get tag).isNone then return none
  let size ← Store.getNat snapshot.get tag
  if size > allowance then return none
  let payloadSize ← Store.getNat snapshot.get (Store.key tag 0)
  if payloadSize != size then return none
  let bytes ← Store.readChunks snapshot snapshot.get tag 0
  let (record, tail) ← IO.ofExcept (codec.decode bytes.toList)
  unless tail.isEmpty && (codec.encode record).toByteArray == bytes do
    throw (IO.userError "noncanonical demand memo")
  return if requestMatches record request then some record else none

def readObserved (snapshot : Store.Snapshot) (request : String)
    (nominations : Option (List Nat)) : IO (Option (ObservedRecord nominations)) := do
  pure ((← read snapshot request).bind fun record => observedRecord? record nominations)

/-- A cache write never waits for the authoritative writer. Cache slots and
encoded records bound live optional data; they do not cap source data or users.
Neither an error nor a pending-search notice may be published by the caller. -/
def publish (snapshot : Store.Snapshot) (record : Record) : IO Unit := do
  if codec.encodedSize record > allowance then return
  let tag := row record.request
  let bytes := (codec.encode record).toByteArray
  -- Computing may itself have published graph-neutral rank metadata. Use the
  -- current writer capability; the record still names the pinned search heads.
  -- A concurrently changed source makes this record a future cache miss.
  let current ← PageMap.pin snapshot.directory
  let _ ← PageMap.withWriter current fun writer => do
    if let some _ ← writer.get tag then
      let size ← Store.getNat writer.get tag
      let payloadSize ← Store.getNat writer.get (Store.key tag 0)
      if size ≤ allowance && size == payloadSize then
        let previous ← Store.readChunks (← writer.snapshot) writer.get tag 0
        if previous == bytes then return
    Store.putChunks writer tag 0 bytes
    Store.putNat writer tag bytes.size
    Store.writeChange writer ⟨[], [], false⟩
  pure ()

end Eggshell.Plugin.DemandMemo
