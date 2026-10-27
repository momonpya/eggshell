module

public import Eggshell.GraphCodec
public import Eggshell.AtomQuotient
public import Eggshell.DB.PageMap
public import Eggshell.DB.Sidecar
public import Eggshell.LogicalText
public import Eggshell.SearchRank
public import Eggshell.Sha256
public import Eggshell.HashDistinct
public import Eggshell.SourceEvidence
public import Std.Data.HashSet.Lemmas

@[expose] public section
namespace Eggshell.Persistence.Store
open Lean DB

abbrev Snapshot := PageMap.Snapshot
abbrev Writer := PageMap.Writer

def key (tag : String) (index : Nat) : String := tag ++ ":" ++ toString index

def getNat (read : String → IO (Option ByteArray)) (name : String) : IO Nat := do
  let some bytes ← read name | return 0
  let (value, tail) ← IO.ofExcept (Wire.natural.decode bytes.toList)
  unless tail.isEmpty do throw (IO.userError "trailing bytes in DB counter")
  pure value

def putNat (writer : Writer) (name : String) (value : Nat) : IO Unit :=
  writer.put name (some (Wire.natural.encode value).toByteArray)

def getIds (read : String → IO (Option ByteArray)) (name : String) : IO (List Nat) := do
  let some bytes ← read name | return []
  let (ids, tail) ← IO.ofExcept ((Wire.list Wire.natural).decode bytes.toList)
  unless tail.isEmpty do throw (IO.userError "trailing bytes in DB id bucket")
  pure ids

def putIds (writer : Writer) (name : String) (ids : List Nat) : IO Unit :=
  writer.put name (some ((Wire.list Wire.natural).encode ids).toByteArray)

/-- Semantic uses are a subset of all structural uses, including Exact-only
references. The executable add/retract transition preserves that invariant. -/
structure NodeMembership where
  total : Nat
  semantic : Nat
  within : semantic ≤ total

def NodeMembership.add (current : NodeMembership) (semantic : Bool) : NodeMembership :=
  ⟨current.total + 1, current.semantic + if semantic then 1 else 0, by
    have := current.within
    cases semantic <;> simp <;> omega⟩

def NodeMembership.retract? (current : NodeMembership) (semantic : Bool) : Option NodeMembership :=
  if present : (if semantic then 0 < current.semantic else current.semantic < current.total) then
    some ⟨current.total - 1, current.semantic - if semantic then 1 else 0, by
      have := current.within
      cases semantic <;> simp at present ⊢ <;> omega⟩
  else none

theorem NodeMembership.retract_add (current : NodeMembership) (semantic : Bool) :
    (current.add semantic).retract? semantic = some current := by
  have present : (if semantic then 0 < (current.add semantic).semantic
      else (current.add semantic).semantic < (current.add semantic).total) := by
    have := current.within
    cases semantic <;> simp [add] <;> omega
  rw [retract?, dif_pos present]
  cases current
  cases semantic <;> simp [add]

def NodeMembership.read (get : String → IO (Option ByteArray)) (node : Nat) : IO NodeMembership := do
  let total ← getNat get (key "nodeUses" node)
  let semantic ← getNat get (key "semanticUses" node)
  if within : semantic ≤ total then pure ⟨total, semantic, within⟩
  else throw (IO.userError "semantic membership exceeds structural membership")

def NodeMembership.write (writer : Writer) (node : Nat) (membership : NodeMembership) : IO Unit := do
  if membership.total == 0 then writer.put (key "nodeUses" node) none
  else putNat writer (key "nodeUses" node) membership.total
  if membership.semantic == 0 then writer.put (key "semanticUses" node) none
  else putNat writer (key "semanticUses" node) membership.semantic

/-- Positions and maximum payload size are checked by construction. The
writer cannot pass a larger body row through the chunk interface. -/
structure Chunk (source : ByteArray) where
  start : Nat
  stop : Nat
  ordered : start ≤ stop
  within : stop ≤ source.size
  bounded : stop - start ≤ 4096

def Chunk.atOffset (source : ByteArray) (offset : Nat) : Chunk source :=
  ⟨min offset source.size, min source.size (offset + 4096), by omega, by omega, by omega⟩

def Chunk.bytes (chunk : Chunk source) : ByteArray := source.extract chunk.start chunk.stop

theorem Chunk.payload_bounded (chunk : Chunk source) : chunk.bytes.size ≤ 4096 := by
  rw [Chunk.bytes, ByteArray.size_extract, Nat.min_eq_left chunk.within]
  exact chunk.bounded

theorem Chunk.adjacent_exact (source : ByteArray) (first middle last : Nat)
    (ordered : first ≤ middle) (within : middle ≤ last) :
    source.extract first middle ++ source.extract middle last = source.extract first last := by
  rw [ByteArray.extract_append_extract, Nat.min_eq_left ordered, Nat.max_eq_right within]

structure RetainedChunk (requested : ByteArray) where
  blob : PageMap.Blob
  observed : ByteArray
  exact : observed = requested

def retainChunk? (blob : PageMap.Blob) (observed requested : ByteArray) :
    Option (RetainedChunk requested) :=
  if exact : observed = requested then some ⟨blob, observed, exact⟩ else none

theorem different_chunk_rejected (blob : PageMap.Blob) (observed requested : ByteArray)
    (different : observed ≠ requested) : retainChunk? blob observed requested = none := by
  simp [retainChunk?, different]

/-- Opaque bodies and long reference lists are bounded rows. A shared
structural node has one payload; owner indexes only contain numeric ids. -/
def putPayload (writer : Writer) (payloadKey : String) (bytes : ByteArray) : IO Unit := do
  let previous ← writer.get payloadKey
  let oldChunks ← match previous with
    | none => pure 0
    | some _ => pure (((← IO.ofExcept (PageMap.payloadSize previous))+4095)/4096)
  putNat writer payloadKey bytes.size
  let chunks := (bytes.size+4095)/4096
  for chunk in [:chunks] do
    let part := Chunk.atOffset bytes (chunk * 4096)
    let name := PageMap.payloadChunkKey payloadKey chunk
    -- A stable extent may already contain this exact chunk. The digest only
    -- nominates it; compare all bytes before reusing its descriptor. A changed
    -- rank page or reverse index must not recopy every unchanged body chunk.
    if let some encoded ← writer.get name then
      let old ← IO.ofExcept (PageMap.decodeBlob encoded)
      if old.bytes == part.bytes.size && old.checksum == PageMap.digest part.bytes then
        let actual ← (← writer.snapshot).readBlob old
        if (retainChunk? old actual part.bytes).isSome then continue
    let blob ← if nonempty : 0 < part.bytes.size then
      writer.appendBlob part.bytes nonempty part.payload_bounded
      else throw (IO.userError "empty body chunk in a nonempty chunk range")
    writer.put name
      (some (PageMap.blobCodec.encode blob).toByteArray)
  for chunk in [chunks:oldChunks] do writer.put (PageMap.payloadChunkKey payloadKey chunk) none

def putChunks (writer : Writer) (tag : String) (index : Nat) (bytes : ByteArray) : IO Unit :=
  putPayload writer (key tag index) bytes

abbrev payloadSize := PageMap.payloadSize

theorem payloadSize_missing_rejected : payloadSize none = .error "missing node byte count" := rfl

theorem payloadSize_encoded (size : Nat) :
    payloadSize (some (Wire.natural.encode size).toByteArray) = .ok size := by
  have decoded := Wire.natural.roundtrip size []
  simp only [List.append_nil] at decoded
  simp [PageMap.payloadSize, decoded, bind, Except.bind, pure, Except.pure]

def readChunks (snapshot : Snapshot) (read : String → IO (Option ByteArray))
    (tag : String) (index : Nat) : IO ByteArray :=
  snapshot.readPayloadUsing read (key tag index)

/-- Exact comparison keeps only one persisted chunk in memory. A collision
probe never reconstructs an old, potentially huge, Atom merely to compare it
with bytes which are already available to the caller. -/
def chunksEqual (snapshot : Snapshot) (read : String → IO (Option ByteArray))
    (tag : String) (index : Nat) (requested : ByteArray) : IO Bool := do
  let size ← IO.ofExcept (payloadSize (← read (key tag index)))
  if size != requested.size then return false
  for chunk in [:((size + 4095) / 4096)] do
    let some descriptor ← read (key (key tag index) chunk) | throw (IO.userError "missing node chunk")
    let part ← snapshot.readBlob (← IO.ofExcept (PageMap.decodeBlob descriptor))
    unless part.size == min 4096 (size - chunk * 4096) do throw (IO.userError "invalid node chunk size")
    if part != (Chunk.atOffset requested (chunk * 4096)).bytes then return false
  pure true

/-- Structural frames contain only reference ids. Atom bytes live in separate
chunks and are not needed to decide which nodes or owners a query must read. -/
inductive NodeFrame where
  | atom
  | apply (operator : Operator) (arguments : List (Authority × Nat))
  deriving DecidableEq, BEq

def NodeFrame.arguments : NodeFrame → List (Authority × Nat)
  | .atom => []
  | .apply _ arguments => arguments

def NodeFrame.toJson : NodeFrame → Json
  | .atom => .arr #[.str "atom"]
  | .apply operator arguments =>
      .arr #[.str "apply", .str (operatorName operator),
        .arr (arguments.toArray.map storedRefToJson)]

def NodeFrame.fromJson (json : Json) : Except String NodeFrame := do
  match (← json.getArr?).toList with
  | [.str "atom"] => pure .atom
  | [.str "apply", .str operator, .arr arguments] =>
      pure (.apply (← operatorFromName operator)
        (← arguments.toList.mapM storedRefFromJson))
  | _ => throw "invalid DB node frame"

/-- The bound belongs to the same node whose frame was read. Both semantic
and Exact references must point backwards; authority does not waive safety. -/
structure NodeFrame.Checked (index : Nat) where
  frame : NodeFrame
  before : ∀ reference ∈ frame.arguments, reference.2 < index

def NodeFrame.check (index : Nat) (frame : NodeFrame) :
    Option (NodeFrame.Checked index) :=
  if valid : ∀ reference ∈ frame.arguments, reference.2 < index then
    some ⟨frame, valid⟩ else none

theorem NodeFrame.check_exact (index : Nat) (frame : NodeFrame) :
    (frame.check index).isSome = true ↔
      ∀ reference ∈ frame.arguments, reference.2 < index := by
  simp [check]

theorem NodeFrame.forward_rejected (index : Nat) (frame : NodeFrame)
    (reference : Authority × Nat) (present : reference ∈ frame.arguments)
    (forward : index ≤ reference.2) : frame.check index = none := by
  have invalid : ¬ ∀ ref ∈ frame.arguments, ref.2 < index := by
    intro valid
    have := valid reference present
    omega
  simp only [check, dif_neg invalid]

/-- A shallow read follows the very same chunk checks as hydration, but does
not touch an Atom body or any descendant. The dependent result is the only
frame accepted by recursive resolution. -/
def readFrame (snapshot : Snapshot) (read : String → IO (Option ByteArray))
    (index : Nat) : IO (NodeFrame.Checked index) := do
  let bytes ← readChunks snapshot read "node" index
  let some text := String.fromUTF8? bytes | throw (IO.userError "invalid node frame encoding")
  let frame ← IO.ofExcept (Json.parse text >>= NodeFrame.fromJson)
  unless frame.toJson.compress.toUTF8 == bytes do
    throw (IO.userError "noncanonical DB node frame")
  let some checked := frame.check index
    | throw (IO.userError "DB reference is not earlier than its node")
  pure checked

def putFrame (writer : Writer) (index : Nat) (checked : NodeFrame.Checked index) : IO Unit :=
  putChunks writer "node" index checked.frame.toJson.compress.toUTF8

def exactIds : List (Authority × Nat) → Option (List Nat)
  | [] => some []
  | (.exact, index) :: tail => (index :: ·) <$> exactIds tail
  | (.semantic, _) :: _ => none

theorem exactIds_sound {references ids} (decoded : exactIds references = some ids) :
    references = ids.map (Authority.exact, ·) := by
  induction references generalizing ids with
  | nil => simp [exactIds] at decoded; simp [decoded]
  | cons head tail ih =>
      rcases head with ⟨authority, index⟩
      cases authority with
      | semantic => simp [exactIds] at decoded
      | exact =>
          simp only [exactIds] at decoded
          cases decodedTail : exactIds tail with
          | none => simp [decodedTail] at decoded
          | some tailIds =>
              simp [decodedTail] at decoded
              subst ids
              simp [ih decodedTail]

def semanticIds : List (Authority × Nat) → Option (List Nat)
  | [] => some []
  | (.semantic, index) :: tail => (index :: ·) <$> semanticIds tail
  | (.exact, _) :: _ => none

theorem semanticIds_sound {references ids} (decoded : semanticIds references = some ids) :
    references = ids.map (Authority.semantic, ·) := by
  induction references generalizing ids with
  | nil => simp [semanticIds] at decoded; simp [decoded]
  | cons head tail ih =>
      rcases head with ⟨authority, index⟩
      cases authority with
      | exact => simp [semanticIds] at decoded
      | semantic =>
          simp only [semanticIds] at decoded
          cases decodedTail : semanticIds tail with
          | none => simp [decodedTail] at decoded
          | some tailIds =>
              simp [decodedTail] at decoded
              subst ids
              simp [ih decodedTail]

/-- A positional All directory entry supplies numeric references only. It
does not assert that arbitrary resolved Values form a valid All judgment. -/
structure AllHeader (index : Nat) where
  checked : NodeFrame.Checked index
  parent : Nat
  children : List Nat
  positional : checked.frame = .apply .all
    ((.semantic, parent) :: children.map (Authority.semantic, ·))
  nonempty : children ≠ []
  excludes : parent ∉ children

def AllHeader.fromFrame? (checked : NodeFrame.Checked index) : Option (AllHeader index) :=
  match shape : checked.frame with
  | .apply .all ((.semantic, parent) :: encoded) =>
      match decoded : semanticIds encoded with
      | some children =>
          if nonempty : children ≠ [] then
            if excludes : parent ∉ children then
              some ⟨checked, parent, children,
                by rw [shape, semanticIds_sound decoded], nonempty, excludes⟩
            else none
          else none
      | none => none
  | _ => none

theorem AllHeader.parent_before (header : AllHeader index) : header.parent < index := by
  apply header.checked.before (.semantic, header.parent)
  simp [header.positional, NodeFrame.arguments]

theorem AllHeader.child_before (header : AllHeader index) (child : Nat)
    (present : child ∈ header.children) : child < index := by
  apply header.checked.before (.semantic, child)
  simp [header.positional, NodeFrame.arguments, present]

/-- With the producer's canonical node interpretation, numeric references
are precisely the original All parent and children; no Atom bytes enter this
projection. The interpretation premise is explicit, not an OS axiom. -/
def AllHeader.interpret (header : AllHeader index) (resolve : Nat → Value)
    (canonical : Function.Injective resolve) : AllEdge :=
  AllEdge.make (resolve header.parent) (header.children.map resolve)
    (by simpa using header.nonempty)
    (by
      intro present
      obtain ⟨child, member, same⟩ := List.mem_map.mp present
      exact header.excludes (canonical same ▸ member))

theorem AllHeader.interpret_parent (header : AllHeader index) (resolve : Nat → Value)
    (canonical : Function.Injective resolve) :
    (header.interpret resolve canonical).parent = resolve header.parent := rfl

theorem AllHeader.interpret_children (header : AllHeader index) (resolve : Nat → Value)
    (canonical : Function.Injective resolve) :
    (header.interpret resolve canonical).children = header.children.map resolve := rfl

/-- The save-time parent posting comes from the checked source frame. It
contains no child list or body; the same record names its reverse directory. -/
structure AllParentPosting where
  parent : Nat
  ordinal : Nat
  root : Nat
  deriving DecidableEq

def AllParentPosting.fromHeader (ordinal : Nat) (header : AllHeader index) : AllParentPosting :=
  ⟨header.parent, ordinal, index⟩

def AllParentPosting.name (posting : AllParentPosting) : String :=
  key (key "allParent" posting.parent) posting.ordinal

def AllParentPosting.matches (posting : AllParentPosting) (query : Nat) : Bool :=
  decide (posting.parent = query)

/-- Numeric parent lookup is exactly literal decomposition under the
producer's injective interpretation. No approximation of a Work is used. -/
theorem AllParentPosting.matches_exact (header : AllHeader index) (ordinal query : Nat)
    (resolve : Nat → Value) (canonical : Function.Injective resolve) :
    (fromHeader ordinal header).matches query =
      decide ((header.interpret resolve canonical).parent = resolve query) := by
  simp only [AllParentPosting.matches, fromHeader, AllHeader.interpret_parent]
  congr 1
  exact propext ⟨fun same => congrArg resolve same, fun same => canonical same⟩

def AllParentPosting.write (posting : AllParentPosting) (writer : Writer) : IO Unit := do
  putNat writer posting.name posting.root
  putNat writer (key "allParentOf" posting.root) posting.parent

/-- Both reference roles are published from this one checked frame. Child
membership cannot be inferred from generic semantic reachability: an Outcome
may mention a Work without putting it in an All child position. -/
def AllHeader.writeIndex (header : AllHeader index) (ordinal : Nat) (writer : Writer) : IO Unit := do
  (AllParentPosting.fromHeader ordinal header).write writer
  for child in header.children.eraseDups do
    putNat writer (key (key "allChild" child) ordinal) index

theorem AllHeader.child_membership_exact (header : AllHeader index) (query : Nat)
    (resolve : Nat → Value) (canonical : Function.Injective resolve) :
    query ∈ header.children.eraseDups ↔
      resolve query ∈ (header.interpret resolve canonical).children := by
  rw [List.mem_eraseDups, interpret_children, List.mem_map]
  constructor
  · intro member
    exact ⟨query, member, rfl⟩
  · rintro ⟨child, member, same⟩
    exact canonical same ▸ member

/-- An owner header is a positional directory entry, not an Outcome judgment.
Only hydration and OutcomeEdge.fromValue? can provide that authority. Exact
observation positions cannot be treated as substitutable Work references. -/
structure OutcomeHeader (index : Nat) where
  checked : NodeFrame.Checked index
  work : Nat
  outcome : Nat
  observations : List Nat
  positional : checked.frame = .apply .outcome
    ((.semantic, work) :: (.semantic, outcome) :: observations.map (Authority.exact, ·))
  distinct : observations.Nodup
  bounded : observations.length ≤ maxOutcomeObservations

def OutcomeHeader.fromFrame? (checked : NodeFrame.Checked index) :
    Option (OutcomeHeader index) :=
  match shape : checked.frame with
  | .apply .outcome ((.semantic, work) :: (.semantic, outcome) :: encoded) =>
      match decoded : exactIds encoded with
      | some observations =>
          if distinct : observations.Nodup then
            if bounded : observations.length ≤ maxOutcomeObservations then
              some ⟨checked, work, outcome, observations,
                by rw [shape, exactIds_sound decoded], distinct, bounded⟩
            else none
          else none
      | none => none
  | _ => none

theorem OutcomeHeader.work_before (header : OutcomeHeader index) : header.work < index := by
  apply header.checked.before (.semantic, header.work)
  simp [header.positional, NodeFrame.arguments]

theorem OutcomeHeader.outcome_before (header : OutcomeHeader index) : header.outcome < index := by
  apply header.checked.before (.semantic, header.outcome)
  simp [header.positional, NodeFrame.arguments]

theorem OutcomeHeader.observation_before (header : OutcomeHeader index)
    (observation : Nat) (present : observation ∈ header.observations) : observation < index := by
  apply header.checked.before (.exact, observation)
  simp [header.positional, NodeFrame.arguments, present]

/-- The save-time Work directory is derived from the original positional
Outcome frame. It is an association index, not a relevance or equality gate.
The payload and its root insertion ordinal are identical on both sides. -/
structure WorkOwnerPosting where
  work : Nat
  ordinal : Nat
  owner : Nat
  deriving DecidableEq, BEq

def WorkOwnerPosting.fromHeader (ordinal : Nat) (header : OutcomeHeader index) :
    WorkOwnerPosting := ⟨header.work, ordinal, index⟩

def WorkOwnerPosting.name (posting : WorkOwnerPosting) : String :=
  key (key "searchWork" posting.work) posting.ordinal

def WorkOwnerPosting.matches (posting : WorkOwnerPosting) (work : Nat) : Bool :=
  decide (posting.work = work)

theorem WorkOwnerPosting.matches_original (ordinal query : Nat) (header : OutcomeHeader index)
    (resolve : Nat → Value) (canonical : Function.Injective resolve) :
    (fromHeader ordinal header).matches query = decide (resolve header.work = resolve query) := by
  simp only [WorkOwnerPosting.fromHeader, WorkOwnerPosting.matches]
  congr 1
  exact propext ⟨fun same => congrArg resolve same, fun same => canonical same⟩

def WorkOwnerPosting.write (posting : WorkOwnerPosting) (writer : Writer) : IO Unit :=
  putNat writer posting.name posting.owner

def WorkOwnerPosting.retract (posting : WorkOwnerPosting) (writer : Writer) : IO Unit := do
  unless (← IO.ofExcept (payloadSize (← writer.get posting.name))) == posting.owner do
    throw (IO.userError "Work owner retraction disagrees with its original posting")
  writer.put posting.name none

/-- A decoded directory row acquires its Work binding only after checking
the same immutable live Outcome frame used by the producer. -/
structure CheckedWorkOwner (work ordinal owner : Nat) where
  header : OutcomeHeader owner
  originalWork : header.work = work

def checkedWorkOwner? (work ordinal : Nat) (header : OutcomeHeader owner) :
    Option (CheckedWorkOwner work ordinal owner) :=
  if same : header.work = work then some ⟨header, same⟩ else none

theorem checked_work_owner_original (checked : CheckedWorkOwner work ordinal owner) :
    WorkOwnerPosting.fromHeader ordinal checked.header = ⟨work, ordinal, owner⟩ := by
  simp [WorkOwnerPosting.fromHeader, checked.originalWork]

theorem foreign_work_owner_rejected (work ordinal : Nat) (header : OutcomeHeader owner)
    (different : header.work ≠ work) : checkedWorkOwner? work ordinal header = none := by
  simp [checkedWorkOwner?, different]

/-- Reference projection of this same producer. The runtime directory lookup
reads the demanded buckets instead of filtering every source window list. -/
def workOwnerBucket (rows : List WorkOwnerPosting) (work : Nat) : List WorkOwnerPosting :=
  rows.filter (·.matches work)

theorem work_owner_bucket_complete (rows : List WorkOwnerPosting) (work : Nat)
    (posting : WorkOwnerPosting) :
    posting ∈ workOwnerBucket rows work ↔ posting ∈ rows ∧ posting.work = work := by
  simp [workOwnerBucket, WorkOwnerPosting.matches]

theorem work_owner_retraction_exact (rows : List WorkOwnerPosting) (owner work : Nat) :
    workOwnerBucket (rows.filter fun row => row.owner != owner) work =
      (workOwnerBucket rows work).filter (fun row => row.owner != owner) := by
  simp only [workOwnerBucket, List.filter_filter]
  congr 1
  funext row
  simp only [Bool.and_comm]

def readOutcomeHeader (snapshot : Snapshot) (index : Nat) : IO (OutcomeHeader index) := do
  -- Immutability of a node does not mean its owner remains live. Check both
  -- inverse directories before following the frame; old bytes left after a
  -- retraction are not a candidate in this publication.
  unless index < (← getNat snapshot.get "nodes") do
    throw (IO.userError "Outcome id is outside its pinned node population")
  let rootOrdinal ← IO.ofExcept (payloadSize (← snapshot.get (key "member" index)))
  unless rootOrdinal < (← getNat snapshot.get "roots") do
    throw (IO.userError "Outcome membership is outside its root directory")
  let rootId ← IO.ofExcept (payloadSize (← snapshot.get (key "root" rootOrdinal)))
  unless rootId == index do throw (IO.userError "Outcome membership disagrees with its root")
  let outcomeOrdinal ← IO.ofExcept (payloadSize (← snapshot.get (key "outcomeOrdinal" index)))
  unless outcomeOrdinal < (← getNat snapshot.get "outcomes") do
    throw (IO.userError "Outcome ordinal is outside its live directory")
  let outcomeId ← IO.ofExcept (payloadSize (← snapshot.get (key "outcome" outcomeOrdinal)))
  unless outcomeId == index do throw (IO.userError "Outcome directory disagrees with its owner")
  let checked ← readFrame snapshot snapshot.get index
  let some header := OutcomeHeader.fromFrame? checked
    | throw (IO.userError "invalid Outcome directory frame")
  pure header

/-- The node number is local to one complete immutable publication. Keeping
it with the Head prevents a nomination from another DB or an older live set
from reaching hydration through the same numeric id. The directory checks
are performed by locateOutcome, not inferred from the frame's shape. -/
structure LocatedOutcome (index : Nat) where
  head : PageMap.Head
  header : OutcomeHeader index

def LocatedOutcome.atHead? (entry : LocatedOutcome index) (head : PageMap.Head) :
    Option { checked : LocatedOutcome index // checked.head = head } :=
  if same : entry.head = head then some ⟨entry, same⟩ else none

theorem LocatedOutcome.foreign_head_rejected (entry : LocatedOutcome index) (head : PageMap.Head)
    (different : entry.head ≠ head) : entry.atHead? head = none := by
  simp [atHead?, different]

def locateOutcome (snapshot : Snapshot) (index : Nat) : IO (LocatedOutcome index) := do
  pure ⟨snapshot.head, ← readOutcomeHeader snapshot index⟩

/-- Resolution recurses on a strictly smaller certified node id. No guessed
recursion fuel, body length, or historical allocation count controls safety. -/
def resolveUsing (snapshot : Snapshot) (read : String → IO (Option ByteArray))
    (payload : String → Nat → IO ByteArray)
    (known : IO.Ref (Std.HashMap Nat Value)) (index : Nat) : IO Value := do
  if let some value := (← known.get)[index]? then return value
  let checked ← readFrame snapshot read index
  let value ← match shape : checked.frame with
    | .atom => pure (.atom (← payload "body" index))
    | .apply operator arguments => do
        let refs ← arguments.attach.mapM fun reference => do
          pure (reference.val.1, ← resolveUsing snapshot read payload known reference.val.2)
        pure (.applyList operator refs)
  known.modify (·.insert index value)
  pure value
termination_by index
decreasing_by
  exact checked.before reference.val (by simpa [shape, NodeFrame.arguments] using reference.property)

def resolve (snapshot : Snapshot) (read : String → IO (Option ByteArray))
    (known : IO.Ref (Std.HashMap Nat Value)) (index : Nat) : IO Value :=
  resolveUsing snapshot read (readChunks snapshot read) known index

def readNode (snapshot : Snapshot) (read : String → IO (Option ByteArray)) (index : Nat) : IO Value := do
  resolve snapshot read (← IO.mkRef {}) index

structure WorkOrigin where
  work : Value
  native : Bool

private structure NodeMemo where
  values : IO.Ref (Std.HashMap Nat Value)
  owners : IO.Ref (Std.HashMap Nat (Sigma LocatedOutcome))
  origins : IO.Ref (Std.HashMap Nat WorkOrigin)

private def NodeMemo.new : IO NodeMemo :=
  return ⟨← IO.mkRef {}, ← IO.mkRef {}, ← IO.mkRef {}⟩

/-- A request-local DAG reader belongs to one complete immutable snapshot.
Its constructor and mutable tables are private: callers cannot seed it with a
foreign Value, change the publication or reuse it with a writer snapshot.
Decoded nodes share their original children and Atom buffers across owners. -/
structure NodeReader (snapshot : Snapshot) where
  private mk ::
  private memo : NodeMemo

@[no_expose] def NodeReader.new (snapshot : Snapshot) : IO (NodeReader snapshot) :=
  return NodeReader.mk (← NodeMemo.new)

@[no_expose] def NodeReader.read (reader : NodeReader snapshot) (index : Nat) : IO Value :=
  resolveUsing snapshot snapshot.get (fun tag index => snapshot.readPayload (key tag index))
    (NodeReader.memo reader).values index

/-- Live membership and the complete positional frame are validated once per
immutable request. The private table cannot be seeded by a nomination or
shared with another source/publication. -/
@[no_expose] def NodeReader.locateOutcome (reader : NodeReader snapshot) (index : Nat) :
    IO (LocatedOutcome index) := do
  let memo := NodeReader.memo reader
  if let some cached := (← memo.owners.get)[index]? then
    if same : cached.1 = index then return same ▸ cached.2
  let entry ← Eggshell.Persistence.Store.locateOutcome snapshot index
  memo.owners.modify (·.insert index ⟨index, entry⟩)
  pure entry

/-- A source certificate nominates exactly this Outcome id. Exact authority
and positional binding are checked before reading any certificate payload;
the referenced Outcome body is never hydrated a second time. -/
def sourceHeaderReferences (fields : SourceEvidence.ReceiptFields Nat) : List (Authority × Nat) :=
  [.exact, .exact, .exact, .exact, .exact, .exact, .exact].zip
    [fields.marker, fields.session, fields.turn, fields.tag, fields.owner, fields.data, fields.purpose]

structure SourceHeader (owner index : Nat) where
  checked : NodeFrame.Checked index
  fields : SourceEvidence.ReceiptFields Nat
  parsed : checked.frame = .apply .receipt (sourceHeaderReferences fields)
  bound : fields.owner = owner

def sourceHeader? (owner index : Nat) (checked : NodeFrame.Checked index) :
    Option (SourceHeader owner index) := do
  match checked.frame with
  | .apply .receipt references =>
      match SourceEvidence.receiptFields? references with
      | none => none
      | some fields =>
          if bound : fields.owner = owner then
            if parsed : checked.frame = .apply .receipt (sourceHeaderReferences fields) then
              some ⟨checked, fields, parsed, bound⟩ else none
          else none
  | _ => none

theorem source_header_bound (header : SourceHeader owner index) : header.fields.owner = owner :=
  header.bound

def sourceRange (owner : Nat) : PageMap.KeyRange :=
  ⟨key "sourceReceipt" owner ++ ":", key "sourceReceipt" owner ++ ";"⟩

def NodeReader.sources (reader : NodeReader snapshot) (owner : Nat) :
    IO (List SourceEvidence.Record) := do
  let _ ← readOutcomeHeader snapshot owner
  snapshot.foldRange (sourceRange owner) (fun records (name, value) => do
    let some encoded := value | return records
    let index ← IO.ofExcept (payloadSize (some encoded))
    unless name == key (key "sourceReceipt" owner) index do
      throw (IO.userError "source directory key disagrees with receipt")
    let reverse ← IO.ofExcept (payloadSize (← snapshot.get (key "sourceOwner" index)))
    unless reverse == owner do throw (IO.userError "source directory has another owner")
    let ordinal ← IO.ofExcept (payloadSize (← snapshot.get (key "member" index)))
    let root ← IO.ofExcept (payloadSize (← snapshot.get (key "root" ordinal)))
    unless ordinal < (← getNat snapshot.get "roots") && root == index do
      throw (IO.userError "source receipt is not a live root")
    let some header := sourceHeader? owner index (← readFrame snapshot snapshot.get index) |
      throw (IO.userError "source receipt frame has another owner or authority")
    unless (← reader.read header.fields.marker) == .text SourceEvidence.receiptMarker &&
        (← reader.read header.fields.purpose) == .text SourceEvidence.receiptPurpose do
      throw (IO.userError "source receipt marker is invalid")
    let .atom bytes ← reader.read header.fields.data |
      throw (IO.userError "source record is not an Atom")
    let some record := String.fromUTF8? bytes >>= SourceEvidence.decode? |
      throw (IO.userError "source certificate is malformed")
    pure (records ++ [record])) []

/-- A positional family has one table per source, including sources with
equal local node numbers. Lookup is constant time and the dependent result
cannot be passed to a different source's node interpreter. -/
structure NodeReaders (snapshots : Array Snapshot) where
  private mk ::
  private tables : Array NodeMemo
  private complete : tables.size = snapshots.size

@[no_expose] def NodeReaders.new (snapshots : Array Snapshot) : IO (NodeReaders snapshots) := do
  let tables ← snapshots.mapM fun _ => NodeMemo.new
  if complete : tables.size = snapshots.size then pure (NodeReaders.mk tables complete)
  else throw (IO.userError "source reader table is incomplete")

@[no_expose] def NodeReaders.at (readers : NodeReaders snapshots) (source : Fin snapshots.size) :
    NodeReader snapshots[source] :=
  NodeReader.mk ((NodeReaders.tables readers)[source.val]'(by
    simpa only [NodeReaders.complete readers] using source.isLt))

/-- The publication is supplied by the reader's type, never a new current
head or a locator-only lookup. This is source binding, not a complete IO
refinement theorem for the external filesystem. -/
def NodeReader.scope (_reader : NodeReader snapshot) : System.FilePath × PageMap.Head :=
  (snapshot.directory, snapshot.head)

theorem NodeReader.scope_exact (reader : NodeReader snapshot) :
    reader.scope = (snapshot.directory, snapshot.head) := rfl

theorem NodeReaders.at_scope (readers : NodeReaders snapshots) (source : Fin snapshots.size) :
    (readers.at source).scope = (snapshots[source].directory, snapshots[source].head) := rfl

theorem NodeReader.different_scope (reader : NodeReader snapshot)
    (directory : System.FilePath) (head : PageMap.Head)
    (different : (snapshot.directory, snapshot.head) ≠ (directory, head)) :
    reader.scope ≠ (directory, head) := different

/-- Nomination does not establish evidence. Resolve the original owner from
the same pinned publication, then let the relation parser check its complete
semantic and Exact positions before returning it as an Outcome. -/
def NodeReader.outcome (reader : NodeReader snapshot) (entry : LocatedOutcome index) : IO OutcomeEdge := do
  let some checked := entry.atHead? snapshot.head
    | throw (IO.userError "Outcome nomination belongs to another pinned publication")
  let observed := (← reader.locateOutcome index).header
  unless observed.checked.frame == checked.val.header.checked.frame do
    throw (IO.userError "Outcome nomination disagrees with its published frame")
  let value ← reader.read index
  let some edge := OutcomeEdge.fromValue? value
    | throw (IO.userError "selected Outcome is not a well-formed relation")
  pure edge

def readLocatedOutcome (snapshot : Snapshot) (entry : LocatedOutcome index) : IO OutcomeEdge := do
  (← NodeReader.new snapshot).outcome entry

/-- Read the nominated Work lane before deciding whether its Outcome is
needed. The complete immutable Head and live inverse directories are checked
just as for owner hydration; this never follows the Outcome reference. -/
def NodeReader.work (reader : NodeReader snapshot) (entry : LocatedOutcome index) : IO Value := do
  let some checked := entry.atHead? snapshot.head
    | throw (IO.userError "Work nomination belongs to another pinned publication")
  let observed := (← reader.locateOutcome index).header
  unless observed.checked.frame == checked.val.header.checked.frame do
    throw (IO.userError "Work nomination disagrees with its published frame")
  reader.read observed.work

def readLocatedWork (snapshot : Snapshot) (entry : LocatedOutcome index) : IO Value := do
  (← NodeReader.new snapshot).work entry

structure Intern where
  writer : Writer
  known : IO.Ref (Std.HashMap Value Nat)

/-- A hash nominates a small collision bucket. Complete structural equality
of decoded candidates decides identity, including Exact reference positions. -/
def Intern.valueBound (intern : Intern) : Nat → Value → IO Nat
  | 0, _ => throw (IO.userError "node allocation exceeded structural bound")
  | fuel + 1, value => do
    if let some id := (← intern.known.get)[value]? then return id
    let frame ← match value with
      | .atom _ => pure NodeFrame.atom
      | .apply operator arguments =>
          let refs ← arguments.toList.mapM fun (authority, child) => do
            pure (authority, ← intern.valueBound fuel child)
          pure (NodeFrame.apply operator refs)
    let bucket := "hash:" ++ toString (hash value)
    let ids ← getIds intern.writer.get bucket
    for id in ids do
      let snapshot ← intern.writer.snapshot
      -- Child ids were individually interned above. Comparing this exact
      -- frame therefore does not recursively hydrate an old Outcome body.
      if (← readFrame snapshot intern.writer.get id).frame != frame then continue
      let same ← match value with
        | .atom bytes => chunksEqual snapshot intern.writer.get "body" id bytes
        | .apply .. => pure true
      if same then
        intern.known.modify (·.insert value id)
        return id
    let id ← getNat intern.writer.get "nodes"
    let some checked := frame.check id
      | throw (IO.userError "node allocation does not follow its dependencies")
    putNat intern.writer "nodes" (id + 1)
    putFrame intern.writer id checked
    if let .atom bytes := value then putChunks intern.writer "body" id bytes
    putNat intern.writer (key "nodeHash" id) (hash value).toNat
    putIds intern.writer bucket (ids ++ [id])
    intern.known.modify (·.insert value id)
    pure id


def Intern.value (intern : Intern) (value : Value) : IO Nat :=
  intern.valueBound value.structuralSize value

/-- Read-only structural identity lookup. Hashes nominate a bucket; complete
child positions and streamed Atom bytes decide identity. Exact and Semantic
references remain different, and a missing node is never allocated by search. -/
def findNodeBound? (snapshot : Snapshot) : Nat → Value → IO (Option Nat)
  | 0, _ => throw (IO.userError "node lookup exceeded structural bound")
  | fuel + 1, value => do
    let frame ← match value with
      | .atom _ => pure NodeFrame.atom
      | .apply operator arguments =>
          let mut refs := []
          for (authority, child) in arguments.toList do
            let some id ← findNodeBound? snapshot fuel child | return none
            refs := (authority, id) :: refs
          pure (.apply operator refs.reverse)
    for id in (← getIds snapshot.get ("hash:" ++ toString (hash value))) do
      unless id < (← getNat snapshot.get "nodes") do
        throw (IO.userError "hash bucket exceeds its published node population")
      if (← readFrame snapshot snapshot.get id).frame != frame then continue
      let same ← match value with
        | .atom bytes => chunksEqual snapshot snapshot.get "body" id bytes
        | .apply .. => pure true
      if same then return some id
    pure none

def findNode? (snapshot : Snapshot) (value : Value) : IO (Option Nat) :=
  findNodeBound? snapshot value.structuralSize value

/-- Portable nomination metadata, checked against the same collision bucket
used by interning. This is not equality or source authority. -/
def nodeHash (snapshot : Snapshot) (index : Nat) : IO Nat := do
  unless index < (← getNat snapshot.get "nodes") do
    throw (IO.userError "portable node nomination exceeds allocation")
  let hash ← IO.ofExcept (payloadSize (← snapshot.get (key "nodeHash" index)))
  unless (← getIds snapshot.get ("hash:" ++ toString hash)).contains index do
    throw (IO.userError "portable node nomination disagrees with its bucket")
  pure hash

/-- Cross-source comparison holds at most one checked payload chunk from each
source. Neither a digest nor an equal byte count decides Atom identity. -/
structure BodyChunk (size chunk : Nat) where
  bytes : ByteArray
  exactSize : bytes.size = min 4096 (size - chunk * 4096)

theorem BodyChunk.bounded (part : BodyChunk size chunk) : part.bytes.size ≤ 4096 := by
  rw [part.exactSize]
  exact Nat.min_le_left _ _

def bodyChunk (snapshot : Snapshot) (index size chunk : Nat) : IO (BodyChunk size chunk) := do
  let some encoded ← snapshot.get (key (key "body" index) chunk) |
    throw (IO.userError "missing source comparison chunk")
  let blob ← IO.ofExcept (PageMap.decodeBlob encoded)
  unless blob.bytes == min 4096 (size - chunk * 4096) do
    throw (IO.userError "source comparison chunk exceeds original body")
  let bytes ← snapshot.readBlob blob
  if valid : bytes.size = min 4096 (size - chunk * 4096) then pure ⟨bytes, valid⟩
  else throw (IO.userError "incomplete source comparison chunk")

def bodiesEqual (left : Snapshot) (leftId : Nat) (right : Snapshot) (rightId : Nat) : IO Bool := do
  let leftSize ← IO.ofExcept (payloadSize (← left.get (key "body" leftId)))
  let rightSize ← IO.ofExcept (payloadSize (← right.get (key "body" rightId)))
  if leftSize != rightSize then return false
  let first ← PageMap.QuietReader.make left
  let second ← PageMap.QuietReader.make right
  let comparison ← PageMap.checkPrefix (fun chunk => do
    pure ((← bodyChunk first.snapshot leftId leftSize chunk).bytes ==
      (← bodyChunk second.snapshot rightId rightSize chunk).bytes)) 0 ((leftSize + 4095) / 4096)
  left.observe (.payload (key "body" leftId) leftSize comparison.checked)
  right.observe (.payload (key "body" rightId) rightSize comparison.checked)
  pure comparison.accepted

/-- Equal arity is required before any zip traversal. A shorter reference list
must never be accepted because its common prefix happens to agree. -/
structure ReferencePairs (left right : List (Authority × Nat)) where
  pairs : List ((Authority × Nat) × (Authority × Nat))
  leftExact : pairs.map Prod.fst = left
  rightExact : pairs.map Prod.snd = right
  authority : ∀ pair ∈ pairs, pair.1.1 = pair.2.1

def ReferencePairs.check? (left right : List (Authority × Nat)) : Option (ReferencePairs left right) :=
  if same : left.length = right.length then
    if tags : (left.zip right).all (fun pair => decide (pair.1.1 = pair.2.1)) = true then
      some { pairs := left.zip right
             leftExact := by simp [List.map_fst_zip, same]
             rightExact := by simp [List.map_snd_zip, same]
             authority := fun pair present => of_decide_eq_true ((List.all_eq_true.mp tags) pair present) }
    else none
  else none

theorem ReferencePairs.positions (pairs : ReferencePairs left right) :
    pairs.pairs.length = left.length ∧ pairs.pairs.length = right.length := by
  constructor
  · simpa only [List.length_map] using congrArg List.length pairs.leftExact
  · simpa only [List.length_map] using congrArg List.length pairs.rightExact

theorem ReferencePairs.unequal_arity (left right : List (Authority × Nat))
    (different : left.length ≠ right.length) : ReferencePairs.check? left right = none := by
  simp [check?, different]

/-- The executable pairing certificate preserves the complete decoded
application, including Exact positions. Child comparison must establish
complete equality; matching hashes or semantic footprints are insufficient. -/
theorem ReferencePairs.resolved (paired : ReferencePairs left right)
    (first second : Nat → Value)
    (children : ∀ pair ∈ paired.pairs, first pair.1.2 = second pair.2.2) :
    left.map (fun ref => (ref.1, first ref.2)) =
      right.map (fun ref => (ref.1, second ref.2)) := by
  calc
    _ = paired.pairs.map (fun pair => (pair.1.1, first pair.1.2)) := by
      simpa only [List.map_map, Function.comp_def] using
        (congrArg (List.map (fun ref : Authority × Nat => (ref.1, first ref.2))) paired.leftExact).symm
    _ = paired.pairs.map (fun pair => (pair.2.1, second pair.2.2)) := by
      apply List.map_congr_left
      intro pair member
      exact Prod.ext (paired.authority pair member) (children pair member)
    _ = _ := by
      simpa only [List.map_map, Function.comp_def] using
        congrArg (List.map (fun ref : Authority × Nat => (ref.1, second ref.2))) paired.rightExact

theorem ReferencePairs.application_exact (paired : ReferencePairs left right)
    (operator : Operator) (first second : Nat → Value)
    (children : ∀ pair ∈ paired.pairs, first pair.1.2 = second pair.2.2) :
    Value.applyList operator (left.map (fun ref => (ref.1, first ref.2))) =
      Value.applyList operator (right.map (fun ref => (ref.1, second ref.2))) := by
  rw [paired.resolved first second children]

/-- This interpreter compares two persisted DAGs without constructing either
structural Value. Checked frames preserve every Exact/Semantic position. -/
def nodesEqualBound (left : Snapshot) (right : Snapshot) : Nat → Nat → Nat → IO Bool
  | 0, _, _ => throw (IO.userError "source identity exceeds its backward-reference bound")
  | fuel + 1, leftId, rightId => do
      if (← nodeHash left leftId) != (← nodeHash right rightId) then return false
      if left.directory == right.directory && left.head == right.head && leftId == rightId then
        return true
      let first ← readFrame left left.get leftId
      let second ← readFrame right right.get rightId
      match first.frame, second.frame with
      | .atom, .atom => bodiesEqual left leftId right rightId
      | .apply firstOp firstRefs, .apply secondOp secondRefs =>
          if firstOp != secondOp then return false
          let some paired := ReferencePairs.check? firstRefs secondRefs | return false
          for ((_, firstId), (_, secondId)) in paired.pairs do
            unless ← nodesEqualBound left right fuel firstId secondId do return false
          pure true
      | _, _ => pure false

def nodesEqual (left : Snapshot) (leftId : Nat) (right : Snapshot) (rightId : Nat) : IO Bool :=
  nodesEqualBound left right (leftId + 1) leftId rightId

/-- Observation orientation is derived from the same authority-position
parser used on Values. Atom bodies and Exact receipt payloads are not read. -/
def NodeFrame.nativeEndpoints? : NodeFrame → Option (Nat × Nat)
  | .apply .occurrence arguments =>
      match Relation.splitOccurrence arguments with
      | some ([observed, invoked], _) => some (observed, invoked)
      | _ => none
  | _ => none

/-- A frame's interpretation preserves every original authority position.
The Atom payload is explicit; classifying an observation never consults it. -/
def NodeFrame.resolveWith (resolve : Nat → Value) (body : ByteArray) : NodeFrame → Value
  | .atom => .atom body
  | .apply operator arguments =>
      .applyList operator (arguments.map fun ref => (ref.1, resolve ref.2))

theorem AllHeader.interpret_frame (header : AllHeader index) (resolve : Nat → Value)
    (canonical : Function.Injective resolve) (body : ByteArray) :
    (header.interpret resolve canonical).relation = header.checked.frame.resolveWith resolve body := by
  simp [AllHeader.interpret, AllEdge.make, header.positional, NodeFrame.resolveWith,
    List.map_map, Function.comp_def, Ref.semantic]

def NodeFrame.nativeResolved (frame : NodeFrame) (resolve : Nat → Value)
    (outcome work : Nat) : Bool :=
  match frame.nativeEndpoints? with
  | some (observed, invoked) => resolve observed == resolve outcome && resolve invoked == resolve work
  | none => false

/-- Shallow positional classification is exactly the original Value parser
for any consistent interpretation of the referenced nodes, including aliases
with different ids but equal Values. This is not a claim about arbitrary IO. -/
theorem NodeFrame.nativeResolved_exact (frame : NodeFrame) (resolve : Nat → Value)
    (body : ByteArray) (outcome work : Nat) :
    frame.nativeResolved resolve outcome work =
      Relation.observesOutcomeWork (resolve outcome) (resolve work) (frame.resolveWith resolve body) := by
  cases frame with
  | atom => rfl
  | apply operator arguments =>
      cases operator <;> try rfl
      simp only [nativeResolved, nativeEndpoints?, resolveWith, Value.applyList,
        Relation.observesOutcomeWork, Refs.toList_ofList, Relation.splitOccurrence_map]
      cases parsed : Relation.splitOccurrence arguments with
      | none => simp
      | some pair =>
          rcases pair with ⟨meanings, receipts⟩
          cases meanings with
          | nil => simp
          | cons observed tail =>
              cases tail with
              | nil => simp
              | cons invoked tail =>
                  cases tail <;> simp

/-- Work and native occurrence orientation from one live pinned owner.
This is nomination metadata, never a substitute Outcome or evidence payload.
Distinct but equal endpoint ids use bounded structural comparison. -/
@[no_expose] def NodeReader.workOrigin (reader : NodeReader snapshot) (entry : LocatedOutcome index) : IO WorkOrigin := do
  let some checked := entry.atHead? snapshot.head |
    throw (IO.userError "Work origin belongs to another pinned publication")
  let header := (← reader.locateOutcome index).header
  unless header.checked.frame == checked.val.header.checked.frame do
    throw (IO.userError "Work origin disagrees with its published frame")
  let memo := reader.memo
  if let some origin := (← memo.origins.get)[index]? then return origin
  let work ← reader.read header.work
  let mut native := false
  for observation in header.observations do
    let frame ← readFrame snapshot snapshot.get observation
    if let some (observed, invoked) := frame.frame.nativeEndpoints? then
      -- Equal ids in this same checked frame name the same original node.
      -- Distinct aliases still require the complete structural interpreter.
      let sameOutcome ← if observed == header.outcome then pure true
        else nodesEqual snapshot observed snapshot header.outcome
      let sameWork ← if invoked == header.work then pure true
        else nodesEqual snapshot invoked snapshot header.work
      if sameOutcome && sameWork then
        native := true
        break
  let origin : WorkOrigin := {work, native}
  memo.origins.modify (·.insert index origin)
  pure origin

def readLocatedWorkOrigin (snapshot : Snapshot) (entry : LocatedOutcome index) : IO WorkOrigin := do
  (← NodeReader.new snapshot).workOrigin entry

/-- Only a structurally live node can be nominated for manual selection.
The digest is checked against the existing allocation bucket; it establishes
neither equality nor uniqueness, which the caller must check separately. -/
structure LiveSelectionNode where
  id : Nat
  uses : Nat
  active : 0 < uses

def selectionNodes (snapshot : Snapshot) (selected : SelectionKey spelling) :
    IO (List LiveSelectionNode) := do
  let mut found := []
  for id in (← getIds snapshot.get ("hash:" ++ toString selected.digest)) do
    unless (← nodeHash snapshot id) == selected.digest do
      throw (IO.userError "selection nomination disagrees with its allocation")
    let membership ← NodeMembership.read snapshot.get id
    let uses := membership.total
    if active : 0 < uses then found := ⟨id, uses, active⟩ :: found
  pure found.reverse

def liveRoot? (snapshot : Snapshot) (value : Value) : IO (Option (Nat × Nat)) := do
  let some id ← findNode? snapshot value | return none
  let some member ← snapshot.get (key "member" id) | return none
  let ordinal ← IO.ofExcept (payloadSize (some member))
  unless ordinal < (← getNat snapshot.get "roots") &&
      (← IO.ofExcept (payloadSize (← snapshot.get (key "root" ordinal)))) == id do
    throw (IO.userError "root identity disagrees with live membership")
  pure (some (ordinal, id))

/-- These are exactly the owner-level document-frequency terms, rather than
occurrence counts. Only text Work creates a compiled candidate. -/
def text? : Value → Option String
  | .atom bytes => String.fromUTF8? bytes
  | .apply .. => none

def ownerTermsFor (owner : OutcomeEdge) : List String :=
  match text? owner.work with
  | none => []
  | some work => hashDistinct
      ((LogicalText.logical work).units.map (·.text) ++
       ((text? owner.outcome).toList.flatMap fun text =>
          (LogicalText.logical text).units.map (·.text)))

def ownerTerms (value : Value) : List String :=
  (OutcomeEdge.fromValue? value).toList.flatMap ownerTermsFor

def ownerWorkSurfaces (owner : OutcomeEdge) : List String :=
  (text? owner.work).toList.flatMap LogicalText.surfaceNames

/-- Search-only metadata is compiled while original bytes are available.
Window digests locate optional numerical hints; they never authorize a graph
identity, a completed Work, or an erased operation. -/
def searchText (owner : OutcomeEdge) : String :=
  (text? owner.work |>.getD "") ++ "\n" ++ (text? owner.outcome |>.getD "")

def windowKey (text : String) : String := Sha256.hex text.toUTF8

def searchWindows (owner : OutcomeEdge) : List String :=
  (SearchRank.windows (searchText owner)).map windowKey

def windowCodec : Wire.Codec (List String) := Wire.list Wire.text

theorem window_codec_roundtrip (windows : List String) (tail : List UInt8) :
    windowCodec.decode (windowCodec.encode windows ++ tail) = .ok (windows, tail) :=
  windowCodec.roundtrip windows tail

/-- Checked positions refer to original immutable bytes, not a second copy
of the source. The source bounds and the extraction bound survive decoding. -/
structure WindowRange (size : Nat) where
  start : Nat
  stop : Nat
  ordered : start ≤ stop
  within : stop ≤ size
  bounded : stop - start ≤ 2048

def WindowRange.make? (size start stop : Nat) : Option (WindowRange size) :=
  if valid : start ≤ stop ∧ stop ≤ size ∧ stop - start ≤ 2048 then
    some ⟨start, stop, valid.1, valid.2.1, valid.2.2⟩ else none

structure SourceWindow (source : ByteArray) (text : String) where
  range : WindowRange source.size
  exact : source.extract range.start range.stop = text.toUTF8

def SourceWindow.make? (source : ByteArray) (start : Nat) (text : String) :
    Option (SourceWindow source text) := do
  let range ← WindowRange.make? source.size start (start + text.utf8ByteSize)
  if exact : source.extract range.start range.stop = text.toUTF8 then
    some ⟨range, exact⟩ else none

theorem SourceWindow.source_exact (window : SourceWindow source text) :
    source.extract window.range.start window.range.stop = text.toUTF8 := window.exact

theorem WindowRange.extraction_bounded {source : ByteArray} (range : WindowRange source.size) :
    (source.extract range.start range.stop).size ≤ 2048 := by
  rw [ByteArray.size_extract, Nat.min_eq_left range.within]
  exact range.bounded

theorem WindowRange.chunks_bounded (range : WindowRange size) :
    (range.stop + 4095) / 4096 - range.start / 4096 ≤ 2 := by
  have := range.ordered
  have := range.bounded
  omega

def spanCodec : Wire.Codec (Nat × Nat) := Wire.natural.product Wire.natural
def searchBodyCodec : Wire.Codec (Nat × Option Nat) := Wire.natural.product (Wire.optional Wire.natural)

theorem span_codec_roundtrip (span : Nat × Nat) (tail : List UInt8) :
    spanCodec.decode (spanCodec.encode span ++ tail) = .ok (span, tail) := spanCodec.roundtrip span tail

/-- At most two 4KiB chunks intersect a window; source size does not control
this loop. The caller supplies the bounds checked for this exact node. -/
def readBodyRange (snapshot : Snapshot) (node size start stop : Nat)
    (_ordered : start ≤ stop) (_within : stop ≤ size) (_bounded : stop - start ≤ 2048) : IO ByteArray := do
  unless (← IO.ofExcept (payloadSize (← snapshot.get (key "body" node)))) == size do
    throw (IO.userError "window body length disagrees with its pinned source")
  let mut result := ByteArray.empty
  if start == stop then return result
  for chunk in [start / 4096 : (stop + 4095) / 4096] do
    let some encoded ← snapshot.get (key (key "body" node) chunk) |
      throw (IO.userError "missing source window chunk")
    let part ← snapshot.readBlob (← IO.ofExcept (PageMap.decodeBlob encoded))
    unless part.size == min 4096 (size - chunk * 4096) do
      throw (IO.userError "invalid source window chunk length")
    result := result ++ part.extract (start - chunk * 4096) (stop - chunk * 4096)
  unless result.size == stop - start do throw (IO.userError "incomplete source window")
  pure result

def termKey (space unit : String) : String := space ++ ":" ++ (Json.str unit).compress

/-- Search terms have their own dense dictionary. They are not graph nodes:
allocating an Atom frame, body descriptor, and graph hash row for every word
multiplies metadata writes without adding graph information. -/
def termPayloadCodec : Wire.Codec (Sum ByteArray Nat) := Wire.sum Wire.byteBlob Wire.natural

theorem term_payload_roundtrip (payload : Sum ByteArray Nat) (tail : List UInt8) :
    termPayloadCodec.decode (termPayloadCodec.encode payload ++ tail) = .ok (payload, tail) :=
  termPayloadCodec.roundtrip payload tail

def termBucket (unit : String) : String := "termHash:" ++ toString (hash unit)

structure Term (unit : String) where
  id : Nat
  spelling : String
  exact : spelling = unit

def term? (id : Nat) (spelling unit : String) : Option (Term unit) :=
  if exact : spelling = unit then some ⟨id, spelling, exact⟩ else none

theorem different_term_rejected (id : Nat) (spelling unit : String)
    (different : spelling ≠ unit) : term? id spelling unit = none := by
  simp [term?, different]

def readTerm (snapshot : Snapshot) (read : String → IO (Option ByteArray)) (id : Nat) : IO String := do
  let some bytes ← read (key "term" id) | throw (IO.userError "missing term dictionary entry")
  let (payload, tail) ← IO.ofExcept (termPayloadCodec.decode bytes.toList)
  unless tail.isEmpty && (termPayloadCodec.encode payload).toByteArray == bytes do
    throw (IO.userError "invalid term dictionary entry")
  let bytes ← match payload with
    | .inl bytes =>
        unless bytes.size ≤ 128 do throw (IO.userError "oversized inline term")
        pure bytes
    | .inr size =>
        unless size > 128 do throw (IO.userError "noncanonical chunked term")
        let bytes ← readChunks snapshot read "termText" id
        unless bytes.size == size do throw (IO.userError "term dictionary size differs from its body")
        pure bytes
  let some text := String.fromUTF8? bytes | throw (IO.userError "invalid term encoding")
  pure text

/-- A hash only nominates entries. The dependent result carries full spelling
equality, so a collision cannot combine frequencies for different words. -/
def findTerm? (snapshot : Snapshot) (read : String → IO (Option ByteArray))
    (unit : String) : IO (Option (Term unit)) := do
  for id in (← getIds read (termBucket unit)) do
    if let some term := term? id (← readTerm snapshot read id) unit then return some term
  pure none

def Intern.term (intern : Intern) (unit : String) : IO Nat := do
  if let some term ← findTerm? (← intern.writer.snapshot) intern.writer.get unit then return term.id
  let id ← getNat intern.writer.get "terms"
  putNat intern.writer "terms" (id + 1)
  let bytes := unit.toUTF8
  let payload ← if bytes.size ≤ 128 then pure (.inl bytes) else do
    putChunks intern.writer "termText" id bytes
    pure (.inr bytes.size)
  intern.writer.put (key "term" id) (some (termPayloadCodec.encode payload).toByteArray)
  let bucket := termBucket unit
  putIds intern.writer bucket ((← getIds intern.writer.get bucket) ++ [id])
  pure id

namespace RootReach

/-- One reverse directory contains every structural node exactly once.
Semantic membership is a separate role; an Exact-only observation is still
manually selectable, but cannot enlarge the semantic discovery population. -/
def compile (root : Value) : List (Value × Bool) :=
  let semantic := root.foldSemanticNodes
    (fun (known : Std.HashMap Value Unit) node => known.insert node ()) {}
  let structural := root.foldNodes HashDistinct.step
    (({} : Std.HashMap Value Unit), [])
  structural.2.reverse.map fun node => (node, semantic.contains node)

/-- The actual save-time compiler preserves every node, its first-occurrence
order and its Semantic/Exact role. It does not build either flattened input
list merely to discard duplicates afterwards. -/
theorem compile_reference (root : Value) : compile root =
    (hashDistinct root.nodes).map (fun node =>
      (node, (Std.HashSet.ofList root.semanticNodes).contains node)) := by
  simp only [compile, Value.foldNodes_exact, Value.foldSemanticNodes_exact]
  change (hashDistinct root.nodes).map _ = _
  apply List.map_congr_left
  intro node _
  congr 1
  rw [HashDistinct.fold_contains]
  simp [Std.HashSet.contains_ofList]

theorem compile_nodes (root : Value) : (compile root).map Prod.fst = hashDistinct root.nodes := by
  simp [compile_reference, List.map_map, Function.comp_def]

theorem compile_unique (root : Value) : ((compile root).map Prod.fst).Nodup := by
  rw [compile_nodes]
  exact HashDistinct.nodup _

theorem compile_member (root node : Value) :
    node ∈ (compile root).map Prod.fst ↔ node ∈ root.nodes := by
  rw [compile_nodes, HashDistinct.mem]

theorem compile_role (root : Value) (row : Value × Bool) (member : row ∈ compile root) :
    row.2 = true ↔ row.1 ∈ root.semanticNodes := by
  rw [compile_reference] at member
  obtain ⟨node, _member, same⟩ := List.mem_map.mp member
  subst row
  simp [Std.HashSet.contains_ofList]

theorem compile_semantic_complete (root node : Value) (member : node ∈ root.semanticNodes) :
    (node, true) ∈ compile root := by
  rw [compile_reference]
  apply List.mem_map.mpr
  refine ⟨node, (HashDistinct.mem _ _).mpr (Value.semanticNodes_subset_nodes root member), ?_⟩
  simp [Std.HashSet.contains_ofList, member]

abbrev Row := Sum Nat Nat
def node : Row → Nat := Sum.elim id id
def semantic : Row → Bool | .inl _ => true | .inr _ => false
def codec : Wire.Codec (List Row) := Wire.list (Wire.sum Wire.natural Wire.natural)

theorem codec_roundtrip (rows : List Row) (tail : List UInt8) :
    codec.decode (codec.encode rows ++ tail) = .ok (rows, tail) := codec.roundtrip rows tail

structure Checked where
  rows : List Row
  unique : (rows.map node).Nodup

def check? (rows : List Row) : Option Checked :=
  if unique : HashDistinct.unique (rows.map node) = true then
    some ⟨rows, HashDistinct.unique_exact _ |>.mp unique⟩ else none

theorem check_exact (rows : List Row) :
    (check? rows).isSome = true ↔ (rows.map node).Nodup := by
  simp [check?, HashDistinct.unique_exact]

def read (snapshot : Snapshot) (get : String → IO (Option ByteArray)) (id : Nat) : IO Checked := do
  let bytes ← readChunks snapshot get "rootReach" id
  let (rows, tail) ← IO.ofExcept (codec.decode bytes.toList)
  unless tail.isEmpty && (codec.encode rows).toByteArray == bytes do
    throw (IO.userError "noncanonical root reach directory")
  let some checked := check? rows | throw (IO.userError "duplicate root reach node")
  let allocated ← getNat get "nodes"
  unless checked.rows.all (fun row => decide (node row < allocated)) do
    throw (IO.userError "root reach node exceeds allocation")
  pure checked

end RootReach

/-- Membership, stable insertion order, terms and frequency counters are in
one batch/root. Replaying a root cannot increment any of these indexes twice. -/
def Intern.root (intern : Intern) (value : Value) : IO Nat := do
  let id ← intern.value value
  if (← intern.writer.get (key "member" id)).isSome then return id
  let ordinal ← getNat intern.writer.get "roots"
  putNat intern.writer "roots" (ordinal + 1)
  putNat intern.writer (key "root" ordinal) id
  putNat intern.writer (key "member" id) ordinal
  let rows ← (RootReach.compile value).mapM fun (node, semantic) => do
    let id ← intern.value node
    pure (if semantic then Sum.inl id else Sum.inr id)
  let some reached := RootReach.check? rows |
    throw (IO.userError "interned root reach contains duplicate node identities")
  putChunks intern.writer "rootReach" id (RootReach.codec.encode reached.rows).toByteArray
  for row in reached.rows do
    let node := RootReach.node row
    let before ← NodeMembership.read intern.writer.get node
    NodeMembership.write intern.writer node (before.add (RootReach.semantic row))
    if RootReach.semantic row && before.semantic == 0 then
      putNat intern.writer "semanticPopulation" ((← getNat intern.writer.get "semanticPopulation") + 1)
  let owners := "owner:" ++ toString (hash value)
  let ownerIds ← getIds intern.writer.get owners
  unless ownerIds.contains id do putIds intern.writer owners (ownerIds ++ [id])
  let terms := ownerTerms value
  let mut termIds := []
  for unit in terms do
    let term ← intern.term unit
    termIds := term :: termIds
    let name := key "frequency" term
    putNat intern.writer name ((← getNat intern.writer.get name) + 1)
    putNat intern.writer (key (key "posting" term) ordinal) id
  putChunks intern.writer "ownerTerms" id
    ((Wire.list Wire.natural).encode termIds.reverse).toByteArray
  if let some owner := OutcomeEdge.fromValue? value then
    putNat intern.writer "liveOutcomes" ((← getNat intern.writer.get "liveOutcomes") + 1)
    if (text? owner.work).isSome then
      let some header := OutcomeHeader.fromFrame?
          (← readFrame (← intern.writer.snapshot) intern.writer.get id) |
        throw (IO.userError "Work index producer disagrees with its original Outcome frame")
      (WorkOwnerPosting.fromHeader ordinal header).write intern.writer
      putNat intern.writer "indexedSearchWorks"
        ((← getNat intern.writer.get "indexedSearchWorks") + 1)
      let surfaces ← (ownerWorkSurfaces owner).mapM intern.term
      putChunks intern.writer "workSurfaces" id
        ((Wire.list Wire.natural).encode surfaces).toByteArray
      for surface in surfaces do
        putNat intern.writer (key (key "workSurface" surface) ordinal) id
      putNat intern.writer "indexedWorks" ((← getNat intern.writer.get "indexedWorks") + 1)
      putNat intern.writer "candidates" ((← getNat intern.writer.get "candidates") + 1)
      putNat intern.writer (key "candidate" id) 1
      putNat intern.writer (key "searchCandidate" ordinal) id
      putChunks intern.writer "searchWindows" id
        (windowCodec.encode (searchWindows owner)).toByteArray
      let source := (searchText owner).toUTF8
      let shape := ((text? owner.work |>.getD "").utf8ByteSize,
        (text? owner.outcome).map String.utf8ByteSize)
      intern.writer.put (key "searchBody" id) (some (searchBodyCodec.encode shape).toByteArray)
      for ((offset, text), window) in (SearchRank.locatedWindows (searchText owner)).zipIdx do
        let some checked := SourceWindow.make? source offset text |
          throw (IO.userError "window compiler disagrees with original source bytes")
        intern.writer.put (key (key "searchSpan" id) window)
          (some (spanCodec.encode (checked.range.start, checked.range.stop)).toByteArray)
      let lexical ← (SearchRank.terms (searchText owner)).mapM intern.term
      putChunks intern.writer "searchTerms" id
        ((Wire.list Wire.natural).encode lexical).toByteArray
      for term in lexical do
        putNat intern.writer (key "searchFrequency" term)
          ((← getNat intern.writer.get (key "searchFrequency" term)) + 1)
        putNat intern.writer (key (key "searchPosting" term) ordinal) id
    let count ← getNat intern.writer.get "outcomes"
    putNat intern.writer (key "outcome" count) id
    putNat intern.writer (key "outcomeOrdinal" id) count
    putNat intern.writer "outcomes" (count + 1)
  if (AllEdge.fromValue? value).isSome then
    let count ← getNat intern.writer.get "alls"
    let some header := AllHeader.fromFrame?
        (← readFrame (← intern.writer.snapshot) intern.writer.get id) |
      throw (IO.userError "All producer disagrees with its interned reference frame")
    header.writeIndex count intern.writer
    putNat intern.writer "indexedAllReferences"
      ((← getNat intern.writer.get "indexedAllReferences") + 1)
    putNat intern.writer (key "all" count) id
    putNat intern.writer (key "allOrdinal" id) count
    putNat intern.writer "alls" (count + 1)
  if let .apply .receipt references := value then
    if let some fields := SourceEvidence.receiptFields? references.toList then
      if fields.marker == .text SourceEvidence.receiptMarker &&
          fields.purpose == .text SourceEvidence.receiptPurpose &&
          (OutcomeEdge.fromValue? fields.owner).isSome then
        let owner ← intern.value fields.owner
        putNat intern.writer (key "sourceOwner" id) owner
        putNat intern.writer (key (key "sourceReceipt" owner) id) id
  pure id

/-- Retractions use the owner's reverse term index. Old bodies are immutable;
only live membership, postings and exact document frequencies change. -/
def removeRoot (writer : Writer) (id : Nat) : IO Unit := do
  if (← writer.get (key "member" id)).isNone then return
  let ordinal ← getNat writer.get (key "member" id)
  writer.put (key "member" id) none
  writer.put (key "root" ordinal) none
  if let some encoded ← writer.get (key "sourceOwner" id) then
    let owner ← IO.ofExcept (payloadSize (some encoded))
    writer.put (key (key "sourceReceipt" owner) id) none
    writer.put (key "sourceOwner" id) none
  let reached ← RootReach.read (← writer.snapshot) writer.get id
  for row in reached.rows do
    let node := RootReach.node row
    let before ← NodeMembership.read writer.get node
    let some after := before.retract? (RootReach.semantic row) |
      throw (IO.userError "root reach membership role underflow")
    NodeMembership.write writer node after
    if RootReach.semantic row && after.semantic == 0 then
      let population ← getNat writer.get "semanticPopulation"
      if population == 0 then throw (IO.userError "semantic population underflow")
      putNat writer "semanticPopulation" (population - 1)
  let termBytes ← readChunks (← writer.snapshot) writer.get "ownerTerms" id
  let (terms, tail) ← IO.ofExcept ((Wire.list Wire.natural).decode termBytes.toList)
  unless tail.isEmpty do throw (IO.userError "trailing owner reverse-index bytes")
  for term in terms do
    let count ← getNat writer.get (key "frequency" term)
    if count == 0 then throw (IO.userError "frequency underflow during owner retraction")
    putNat writer (key "frequency" term) (count - 1)
    writer.put (key (key "posting" term) ordinal) none
  if (← writer.get (key "candidate" id)).isSome then
    let some header := OutcomeHeader.fromFrame? (← readFrame (← writer.snapshot) writer.get id) |
      throw (IO.userError "invalid retired Work owner frame")
    (WorkOwnerPosting.fromHeader ordinal header).retract writer
    let indexed ← getNat writer.get "indexedSearchWorks"
    if indexed == 0 then throw (IO.userError "Work owner index population underflow")
    putNat writer "indexedSearchWorks" (indexed - 1)
    let lexicalBytes ← readChunks (← writer.snapshot) writer.get "searchTerms" id
    let (lexical, tail) ← IO.ofExcept ((Wire.list Wire.natural).decode lexicalBytes.toList)
    unless tail.isEmpty && lexical.eraseDups == lexical do
      throw (IO.userError "invalid search term reverse directory")
    for term in lexical do
      let count ← getNat writer.get (key "searchFrequency" term)
      if count == 0 then throw (IO.userError "search frequency underflow")
      putNat writer (key "searchFrequency" term) (count - 1)
      writer.put (key (key "searchPosting" term) ordinal) none
    writer.put (key "searchCandidate" ordinal) none
    let surfaceBytes ← readChunks (← writer.snapshot) writer.get "workSurfaces" id
    let (surfaces, tail) ← IO.ofExcept ((Wire.list Wire.natural).decode surfaceBytes.toList)
    unless tail.isEmpty do throw (IO.userError "trailing Work surface reverse-index bytes")
    for surface in surfaces do writer.put (key (key "workSurface" surface) ordinal) none
    let indexed ← getNat writer.get "indexedWorks"
    if indexed == 0 then throw (IO.userError "Work surface population underflow")
    putNat writer "indexedWorks" (indexed - 1)
    let count ← getNat writer.get "candidates"
    if count == 0 then throw (IO.userError "candidate population underflow")
    putNat writer "candidates" (count - 1)
    writer.put (key "candidate" id) none
  if (← writer.get (key "outcomeOrdinal" id)).isSome then
    let count ← getNat writer.get "liveOutcomes"
    if count == 0 then throw (IO.userError "live Outcome population underflow")
    putNat writer "liveOutcomes" (count - 1)
    let some _ := OutcomeHeader.fromFrame? (← readFrame (← writer.snapshot) writer.get id) |
      throw (IO.userError "invalid retired Outcome header")
    let ordinal ← getNat writer.get (key "outcomeOrdinal" id)
    writer.put (key "outcome" ordinal) none
    writer.put (key "outcomeOrdinal" id) none
  if (← writer.get (key "allOrdinal" id)).isSome then
    let ordinal ← getNat writer.get (key "allOrdinal" id)
    let parent ← IO.ofExcept (payloadSize (← writer.get (key "allParentOf" id)))
    let posting : AllParentPosting := ⟨parent, ordinal, id⟩
    unless (← IO.ofExcept (payloadSize (← writer.get posting.name))) == id do
      throw (IO.userError "All retraction disagrees with its parent posting")
    let some header := AllHeader.fromFrame? (← readFrame (← writer.snapshot) writer.get id) |
      throw (IO.userError "invalid retired All header")
    unless header.parent == parent do
      throw (IO.userError "retired All header disagrees with its parent posting")
    for child in header.children.eraseDups do
      let name := key (key "allChild" child) ordinal
      unless (← IO.ofExcept (payloadSize (← writer.get name))) == id do
        throw (IO.userError "All retraction disagrees with its child posting")
      writer.put name none
    writer.put posting.name none
    writer.put (key "allParentOf" id) none
    writer.put (key "all" ordinal) none
    writer.put (key "allOrdinal" id) none

structure MetadataChange where
  changed : Bool := false
  affected : List Nat := []

structure Change where
  added : List Nat
  removed : List Nat
  unionsChanged : Bool
  affected : List Nat := []
  deriving BEq, DecidableEq

def changeCodec : Wire.Codec Change :=
  ((Wire.list Wire.natural).product ((Wire.list Wire.natural).product
    ((Wire.natural.iso (fun b : Bool => if b then 1 else 0) (fun n => n != 0)
      (by intro b; cases b <;> rfl)).product (Wire.list Wire.natural)))).iso
    (fun c => (c.added, c.removed, c.unionsChanged,c.affected))
    (fun (added, removed, unionsChanged,affected) => ⟨added, removed, unionsChanged,affected⟩)
    (by intro c; cases c; rfl)

theorem change_codec_roundtrip (change : Change) (tail : List UInt8) :
    changeCodec.decode (changeCodec.encode change ++ tail) = .ok (change, tail) :=
  changeCodec.roundtrip change tail

structure Publication where
  parent : PageMap.Head
  change : Change
  deriving DecidableEq

def publicationCodec : Wire.Codec Publication :=
  (PageMap.headCodec.product changeCodec).iso
    (fun p => (p.parent, p.change)) (fun (parent, change) => ⟨parent, change⟩)
    (by intro p; cases p; rfl)

theorem publication_codec_roundtrip (publication : Publication) (tail : List UInt8) :
    publicationCodec.decode (publicationCodec.encode publication ++ tail) = .ok (publication, tail) :=
  publicationCodec.roundtrip publication tail

def Change.neutral (change : Change) : Bool :=
  change.added.isEmpty && change.removed.isEmpty && !change.unionsChanged && change.affected.isEmpty

theorem Change.neutral_exact (change : Change) : change.neutral = true ↔
    change.added = [] ∧ change.removed = [] ∧ change.unionsChanged = false ∧ change.affected = [] := by
  simp [neutral, Bool.and_eq_true, and_assoc]

structure CheckedChange (onlyDerived : Bool) where
  change : Change
  exact : change.neutral = true → onlyDerived = true

def Change.check? (change : Change) (onlyDerived : Bool) : Option (CheckedChange onlyDerived) :=
  if safe : change.neutral = true → onlyDerived = true then some ⟨change, safe⟩ else none

theorem Change.authoritative_neutral_rejected (change : Change)
    (neutral : change.neutral = true) : change.check? false = none := by
  simp [check?, neutral]

theorem CheckedChange.neutral_derived (checked : CheckedChange onlyDerived)
    (neutral : checked.change.neutral = true) : onlyDerived = true := checked.exact neutral

/-- Source changes invalidate prepared nomination data; memo-only commits keep
the existing source marker. This is a publication counter, not authority. -/
def Change.sourceMarker (change : Change) (revision previous : Nat) : Nat :=
  if change.neutral then previous else revision + 1

theorem Change.neutral_keeps_marker (change : Change) (revision previous : Nat)
    (neutral : change.neutral = true) : change.sourceMarker revision previous = previous := by
  simp [sourceMarker, neutral]

theorem Change.changed_advances_marker (change : Change) (revision previous : Nat)
    (changed : change.neutral = false) (within : previous ≤ revision) :
    previous < change.sourceMarker revision previous := by
  simp [sourceMarker, changed]
  omega

def writeChange (writer : Writer) (change : Change) : IO Unit := do
  if ← writer.journalSealed.get then throw (IO.userError "change journal was already sealed")
  let some checked := change.check? (← writer.onlyDerived.get) |
    throw (IO.userError "authoritative writes cannot publish an empty graph delta")
  unless checked.change.neutral do
    putNat writer "sourceChange" (checked.change.sourceMarker writer.base.head.revision
      (← getNat writer.get "sourceChange"))
  putChunks writer "change" (writer.base.head.revision + 1)
    (publicationCodec.encode ⟨writer.base.head, checked.change⟩).toByteArray
  writer.journalSealed.set true

def readPublication (snapshot : Snapshot) (revision : Nat) : IO Publication := do
  if (← snapshot.get (key "change" revision)).isNone then
    throw (IO.userError "published revision is missing its change record")
  let bytes ← readChunks snapshot snapshot.get "change" revision
  let (publication, tail) ← IO.ofExcept (publicationCodec.decode bytes.toList)
  unless tail.isEmpty do throw (IO.userError "trailing change record bytes")
  unless (publicationCodec.encode publication).toByteArray == bytes do
    throw (IO.userError "noncanonical change record")
  unless publication.parent.identity == snapshot.head.identity &&
      publication.parent.authority == snapshot.head.authority &&
      publication.parent.revision + 1 == revision &&
      publication.parent.bytes < snapshot.head.bytes do
    throw (IO.userError "change record does not follow its pinned publication")
  pure publication

def readChange (snapshot : Snapshot) (revision : Nat) : IO Change :=
  (·.change) <$> readPublication snapshot revision

def authority (snapshot : Snapshot) : IO Value :=
  IO.ofExcept (Json.parse snapshot.head.authority >>= valueFromJson (snapshot.head.authority.length + 1))

def header (snapshot : Snapshot) : IO Graph := do
  pure { Graph.empty (← authority snapshot) with revision := snapshot.head.revision }

/-- A selective published view resolves only requested owner ids. -/
def owners (snapshot : Snapshot) (keys : List String) : IO Graph := do
  let values ← keys.mapM fun key => do
    let ids ← getIds snapshot.get key
    let live ← ids.filterM fun id => (snapshot.get (Store.key "member" id)).map Option.isSome
    match live with
    | [id] => do
        let entry ← locateOutcome snapshot id
        pure (← readLocatedOutcome snapshot entry).relation
    | [] => throw (IO.userError "published owner is missing")
    | _ => throw (IO.userError "ambiguous published owner digest")
  if valid : values.all Relation.wellFormed then
    let owner ← authority snapshot
    pure {
      authority := owner
      revision := snapshot.head.revision
      values := values
      unions := []
      values_wellFormed := fun value member => (List.all_eq_true.mp valid) value member }
  else throw (IO.userError "invalid published owner")

/-- Read one numeric directory without probing every historical ordinal.
The B-tree orders textual keys; numeric order is restored explicitly so a
different page layout cannot change the Matcher's stable candidate order. -/
def directory (snapshot : Snapshot) (tag : String) : IO (List (Nat × Nat)) := do
  let keyPrefix := tag ++ ":"
  let entries ← snapshot.foldRange ⟨keyPrefix, tag ++ ";"⟩ (fun entries row => do
    let some bytes := row.2 | return entries
    let some ordinal := (row.1.drop keyPrefix.length).toString.toNat? |
      throw (IO.userError "invalid numeric directory key")
    unless row.1 == key tag ordinal do
      throw (IO.userError "noncanonical numeric directory key")
    let (id, tail) ← IO.ofExcept (Wire.natural.decode bytes.toList)
    unless tail.isEmpty && (Wire.natural.encode id).toByteArray == bytes do
      throw (IO.userError "invalid numeric directory value")
    pure ((ordinal, id) :: entries)) []
  pure (entries.mergeSort fun a b => a.1 ≤ b.1)

def rootDirectory (snapshot : Snapshot) : IO (List (Nat × Nat)) := do
  let entries ← directory snapshot "root"
  let population ← getNat snapshot.get "roots"
  unless entries.all (fun entry => entry.1 < population) do
    throw (IO.userError "root directory exceeds its published population")
  pure entries

def rootsBetween (snapshot : Snapshot) (start stop : Nat) : IO (List Value) := do
  let known ← IO.mkRef {}
  let entries ← rootDirectory snapshot
  let mut values := []
  for (ordinal, id) in entries do
    if start ≤ ordinal && ordinal < stop then
      values := (← resolve snapshot snapshot.get known id) :: values
  pure values.reverse

def rootIds (snapshot : Snapshot) : IO (List Nat) :=
  (List.map Prod.snd) <$> rootDirectory snapshot

/-- Demand reads use the persisted spelling-checked term dictionary and
counter, never decode Outcome bodies to rediscover document frequency. -/
def frequency (snapshot : Snapshot) (unit : String) : IO Nat := do
  let some term ← findTerm? snapshot snapshot.get unit | return 0
  getNat snapshot.get (key "frequency" term.id)

/-- Read each dictionary layer in key order. Interleaving bucket, spelling and
counter point reads for thousands of requested units thrashes a small page
cache even on a small corpus. These are the same checked point reads, from one
pinned root, including absent buckets; no dictionary-wide scan is performed. -/
def frequencies (snapshot : Snapshot) (units : List String) : IO (Std.HashMap String Nat) := do
  let units := hashDistinct units
  let mut buckets : Std.HashMap String (List Nat) := {}
  for bucket in (hashDistinct (units.map termBucket)).mergeSort (· ≤ ·) do
    buckets := buckets.insert bucket (← getIds snapshot.get bucket)
  let ids := hashDistinct (units.flatMap (fun unit => buckets.getD (termBucket unit) []))
  let mut spellings : Std.HashMap Nat String := {}
  for id in ids.mergeSort (fun left right => key "term" left ≤ key "term" right) do
    spellings := spellings.insert id (← readTerm snapshot snapshot.get id)
  let mut requested : List (String × Nat) := []
  let mut result : Std.HashMap String Nat := {}
  for unit in units do
    result := result.insert unit 0
    for id in buckets.getD (termBucket unit) [] do
      let some spelling := spellings[id]? | throw (IO.userError "incomplete demanded term dictionary")
      if let some term := term? id spelling unit then
        requested := (unit, term.id) :: requested
        break
  for (unit, id) in requested.mergeSort (fun left right =>
      key "frequency" left.2 ≤ key "frequency" right.2) do
    result := result.insert unit (← getNat snapshot.get (key "frequency" id))
  pure result

/-- A term posting directory yields existing owner ids in root order. Missing
terms are a real index miss, not a scan through every root/body. -/
def postings (snapshot : Snapshot) (unit : String) : IO (List Nat) := do
  let some term ← findTerm? snapshot snapshot.get unit | return []
  (List.map Prod.snd) <$> directory snapshot (key "posting" term.id)

structure SearchDocument where
  owner : Nat
  work : Nat
  windows : List String
  /-- Numerical hints for this pinned DB; unpublished documents use scratch. -/
  cache : Option DB.Sidecar.Owner := none

/-- Repair an optional numerical hint by fetching its original bounded byte
range from the requesting snapshot. No current head is reopened, and no
whole Outcome body is decoded. Digest checks do not establish graph facts. -/
def readSearchWindow (snapshot : Snapshot) (document : SearchDocument) (index : Nat) : IO String := do
  let some digest := document.windows[index]? | throw (IO.userError "unknown source window")
  let located ← locateOutcome snapshot document.owner
  unless located.header.work == document.work do throw (IO.userError "foreign source window Work")
  let workFrame ← readFrame snapshot snapshot.get document.work
  unless workFrame.frame == .atom do throw (IO.userError "source window Work is not textual")
  let some encoded ← snapshot.get (key "searchBody" document.owner) |
    throw (IO.userError "missing source window body directory")
  let ((workBytes, outcomeBytes), tail) ← IO.ofExcept (searchBodyCodec.decode encoded.toList)
  unless tail.isEmpty do throw (IO.userError "invalid source window body directory")
  let some span ← snapshot.get (key (key "searchSpan" document.owner) index) |
    throw (IO.userError "missing source window position")
  let ((start, stop), tail) ← IO.ofExcept (spanCodec.decode span.toList)
  unless tail.isEmpty do throw (IO.userError "invalid source window position")
  let total := workBytes + 1 + outcomeBytes.getD 0
  let some range := WindowRange.make? total start stop |
    throw (IO.userError "source window exceeds original bytes or extraction budget")
  let workStart := min range.start workBytes
  let workStop := min range.stop workBytes
  let work ← readBodyRange snapshot document.work workBytes workStart workStop
    (by have := range.ordered; omega) (by omega) (by have := range.bounded; omega)
  let separator := if range.start ≤ workBytes && workBytes < range.stop then
    ByteArray.mk #[10] else ByteArray.empty
  let mut outcome := ByteArray.empty
  if let some size := outcomeBytes then
    let frame ← readFrame snapshot snapshot.get located.header.outcome
    unless frame.frame == .atom do throw (IO.userError "source window Outcome is not textual")
    let base := workBytes + 1
    let first := min (range.start - base) size
    let last := min (range.stop - base) size
    outcome ← readBodyRange snapshot located.header.outcome size first last
      (by have := range.ordered; omega) (by omega) (by have := range.bounded; omega)
  let bytes := work ++ separator ++ outcome
  unless bytes.size == range.stop - range.start do throw (IO.userError "source window is incomplete")
  let some text := String.fromUTF8? bytes | throw (IO.userError "source window splits UTF-8")
  unless text.length ≤ 512 && windowKey text == digest do
    throw (IO.userError "source window disagrees with its indexed locator")
  pure text

/-- Only immutable numeric headers and bounded search metadata are read.
An incomplete live directory is pending/error, never a completed empty corpus. -/
def searchDocuments (snapshot : Snapshot) : IO (List SearchDocument) := do
  let entries ← directory snapshot "searchCandidate"
  unless entries.length == (← getNat snapshot.get "candidates") do
    throw (IO.userError "search candidate directory is incomplete")
  entries.mapM fun (ordinal, id) => do
    let located ← locateOutcome snapshot id
    unless (← getNat snapshot.get (key "member" id)) == ordinal &&
        (← getNat snapshot.get (key "candidate" id)) == 1 do
      throw (IO.userError "search document disagrees with live membership")
    let encoded ← readChunks snapshot snapshot.get "searchWindows" id
    let (windows, tail) ← IO.ofExcept (windowCodec.decode encoded.toList)
    unless tail.isEmpty && !windows.isEmpty &&
        windows.all (fun value => value.length == 64 && value.toList.all (fun c =>
          ('0' ≤ c && c ≤ '9') || ('a' ≤ c && c ≤ 'f'))) do
      throw (IO.userError "invalid search window directory")
    pure ⟨id, located.header.work, windows, some (DB.Sidecar.Owner.ofSnapshot snapshot)⟩

/-- No search-window directory or source body belongs to this read domain.
Original root order is restored before stable family/meaning ranking, so
unranked siblings retain the same order as the complete candidate oracle. -/
def supportDocuments (snapshot : Snapshot) (works : List Nat) : IO (List SearchDocument) := do
  unless (← getNat snapshot.get "indexedSearchWorks") == (← getNat snapshot.get "candidates") do
    throw (IO.userError "Work owner index is incomplete")
  let mut rows : List (Nat × SearchDocument) := []
  for work in works.eraseDups do
    for (ordinal, id) in (← directory snapshot (key "searchWork" work)) do
      let located ← locateOutcome snapshot id
      let some checked := checkedWorkOwner? work ordinal located.header |
        throw (IO.userError "Work owner directory points to a different original Work")
      unless (← getNat snapshot.get (key "member" id)) == ordinal &&
          (← getNat snapshot.get (key "candidate" id)) == 1 &&
          (← getNat snapshot.get (key "searchCandidate" ordinal)) == id do
        throw (IO.userError "Work owner directory disagrees with live candidate order")
      rows := (ordinal, ⟨id, checked.header.work, [], some (DB.Sidecar.Owner.ofSnapshot snapshot)⟩) :: rows
  pure ((rows.mergeSort fun a b => a.1 ≤ b.1).map Prod.snd)

/-- Source ranking reads bounded locator directories, not neighboring
Outcome bodies. Each document still belongs to the same pinned Work index. -/
def supportWindowDocuments (snapshot : Snapshot) (works : List Value) :
    IO (List SearchDocument) := do
  let ids ← (hashDistinct works).filterMapM fun work => findNode? snapshot work
  (← supportDocuments snapshot ids).mapM fun document => do
    let encoded ← readChunks snapshot snapshot.get "searchWindows" document.owner
    let (windows, tail) ← IO.ofExcept (windowCodec.decode encoded.toList)
    unless tail.isEmpty && !windows.isEmpty &&
        windows.all (fun value => value.length == 64 && value.toList.all (fun c =>
          ('0' ≤ c && c ≤ '9') || ('a' ≤ c && c ≤ 'f'))) do
      throw (IO.userError "invalid neighboring source window directory")
    pure {document with windows}

/-- Meaning rank orders hydration. Original family is a stable tie-break,
not permission for an earlier investigation to consume another source's
budget before its more relevant evidence can be considered. -/
def supportRankBefore (leftRank rightRank leftFamily rightFamily : Nat) : Bool :=
  if leftRank == rightRank then decide (leftFamily ≤ rightFamily)
  else decide (leftRank < rightRank)

theorem source_rank_precedes_family (leftRank rightRank leftFamily rightFamily : Nat)
    (better : leftRank < rightRank) :
    supportRankBefore leftRank rightRank leftFamily rightFamily = true := by
  simp [supportRankBefore, Nat.ne_of_lt better, better]

def rankSupportDocuments (documents : List SearchDocument) (ranking : List Nat)
    (families : Std.HashMap Nat Nat := {}) : List SearchDocument :=
  let priorities : Std.HashMap Nat Nat := Std.HashMap.ofList (ranking.zipIdx)
  documents.mergeSort fun left right => supportRankBefore
    (priorities.getD left.owner ranking.length) (priorities.getD right.owner ranking.length)
    (families.getD left.work families.size) (families.getD right.work families.size)

theorem ranked_support_is_original (documents : List SearchDocument) (ranking : List Nat)
    (document : SearchDocument) (families : Std.HashMap Nat Nat := {}) :
    document ∈ rankSupportDocuments documents ranking families ↔ document ∈ documents := by
  simp [rankSupportDocuments]

def NodeReader.supportOwners (reader : NodeReader snapshot) (works : List Value)
    (excluded : List Value) (allowance : Nat) (ranking : List Nat := [])
    (priorities : List (Value × Nat) := []) : IO (List OutcomeEdge) := do
  let mut wanted : Std.HashSet Nat := {}
  let mut families : Std.HashMap Nat Nat := {}
  let priorityMap := Std.HashMap.ofList priorities
  for work in hashDistinct works do
    if let some id ← findNode? snapshot work then
      wanted := wanted.insert id
      families := families.insert id (priorityMap.getD work priorities.length)
  let documents := rankSupportDocuments (← supportDocuments snapshot wanted.toList) ranking families
  let mut remaining := allowance
  let mut owners := []
  for document in documents do
    unless wanted.contains document.work do continue
    let some encoded ← snapshot.get (key "searchBody" document.owner) |
      throw (IO.userError "missing neighboring Outcome size directory")
    let ((workBytes, outcomeBytes), tail) ← IO.ofExcept (searchBodyCodec.decode encoded.toList)
    unless tail.isEmpty do throw (IO.userError "invalid neighboring Outcome size directory")
    let some outcomeBytes := outcomeBytes | continue
    let size := workBytes + outcomeBytes
    if size > remaining then continue
    let owner ← reader.outcome (← reader.locateOutcome document.owner)
    unless owner.work ∈ works do throw (IO.userError "neighbor Work identity disagrees with its source node")
    let some work := text? owner.work | throw (IO.userError "neighbor Work is not indexed text")
    let some body := text? owner.outcome | throw (IO.userError "neighbor Outcome is not indexed text")
    unless work.utf8ByteSize == workBytes && body.utf8ByteSize == outcomeBytes do
      throw (IO.userError "neighbor body disagrees with its pre-hydration size")
    unless excluded.contains owner.relation do
      remaining := remaining - size
      owners := owners ++ [owner]
  pure owners

def searchPosting (snapshot : Snapshot) (unit : String) : IO (List Nat × Nat) := do
  let some term ← findTerm? snapshot snapshot.get unit | return ([], 0)
  let entries ← directory snapshot (key "searchPosting" term.id)
  let count ← getNat snapshot.get (key "searchFrequency" term.id)
  unless entries.length == count do throw (IO.userError "search posting frequency disagrees")
  for (ordinal, id) in entries do
    unless (← IO.ofExcept (payloadSize (← snapshot.get (key "searchCandidate" ordinal)))) == id do
      throw (IO.userError "search posting names a retired candidate")
  pure (entries.map Prod.snd, count)

/-- Complete spelling-checked Work gram postings, in authoritative root
order. Neither Outcome text nor model scores are read during nomination.
An incomplete index is an error, not a completed negative search. -/
def workSurfaceCandidates (snapshot : Snapshot) (surfaces : List String) : IO (List Nat) := do
  unless (← getNat snapshot.get "indexedWorks") == (← getNat snapshot.get "candidates") do
    throw (IO.userError "Work surface index is incomplete")
  let mut found : Std.HashMap Nat Nat := {}
  for surface in surfaces do
    if let some term ← findTerm? snapshot snapshot.get surface then
      for (ordinal, id) in (← directory snapshot (key "workSurface" term.id)) do
        -- One owner can occur in many demanded gram postings. Its live
        -- membership is immutable in this pinned publication: validate the
        -- complete pair once, and reject any conflicting later nomination.
        if let some checked := found[ordinal]? then
          unless checked == id do
            throw (IO.userError "Work postings disagree on their live root owner")
          continue
        let live ← IO.ofExcept (payloadSize (← snapshot.get (key "member" id)))
        let member ← IO.ofExcept (payloadSize (← snapshot.get (key "root" ordinal)))
        let candidate ← IO.ofExcept (payloadSize (← snapshot.get (key "candidate" id)))
        unless id < (← getNat snapshot.get "nodes") &&
            ordinal < (← getNat snapshot.get "roots") &&
            live == ordinal && member == id && candidate == 1 do
          throw (IO.userError "Work posting disagrees with live root membership")
        found := found.insert ordinal id
  pure ((found.toList.mergeSort fun a b => a.1 ≤ b.1).map Prod.snd)

/-- Enumerate only published All relations, retaining their original order.
The Atom-only probe may reject before hydration; the general reader resolves
the same checked topology without visiting unrelated Outcome roots. -/
structure LocatedAll (index : Nat) where
  head : PageMap.Head
  header : AllHeader index

def LocatedAll.atHead? (entry : LocatedAll index) (head : PageMap.Head) :
    Option { checked : LocatedAll index // checked.head = head } :=
  if same : entry.head = head then some ⟨entry, same⟩ else none

theorem LocatedAll.foreign_head_rejected (entry : LocatedAll index) (head : PageMap.Head)
    (different : entry.head ≠ head) : entry.atHead? head = none := by
  simp [atHead?, different]

/-- Read the complete live All directory and its checked reference frames.
No descendant is restored merely to order semantic search documents. -/
def allHeaders (snapshot : Snapshot) : IO (List (Sigma LocatedAll)) := do
  let entries ← directory snapshot "all"
  let mut headers : List (Sigma LocatedAll) := []
  for (ordinal, id) in entries do
    let member ← IO.ofExcept (payloadSize (← snapshot.get (key "member" id)))
    let root ← IO.ofExcept (payloadSize (← snapshot.get (key "root" member)))
    let inverse ← IO.ofExcept (payloadSize (← snapshot.get (key "allOrdinal" id)))
    unless id < (← getNat snapshot.get "nodes") &&
        member < (← getNat snapshot.get "roots") &&
        ordinal < (← getNat snapshot.get "alls") && root == id && inverse == ordinal do
      throw (IO.userError "All topology disagrees with live root membership")
    let frame ← readFrame snapshot snapshot.get id
    let some header := AllHeader.fromFrame? frame |
      throw (IO.userError "invalid All topology frame")
    headers := ⟨id, ⟨snapshot.head, header⟩⟩ :: headers
  pure headers.reverse

/-- Lookup just one literal parent in the save-time relation index. Missing
or incomplete indexing is an error, never a completed negative result. The
allocation counters advance together; retiring a relation removes its exact
parent row without scanning children or rewriting the remaining directory. -/
def literalAllParents (snapshot : Snapshot) (query : Value) : IO (List Nat) := do
  let population ← getNat snapshot.get "alls"
  unless (← getNat snapshot.get "indexedAllReferences") == population do
    throw (IO.userError "All parent index is incomplete")
  let some parent ← findNode? snapshot query | return []
  let rows ← directory snapshot (key "allParent" parent)
  let mut found := []
  for (ordinal, id) in rows do
    let member ← IO.ofExcept (payloadSize (← snapshot.get (key "member" id)))
    let root ← IO.ofExcept (payloadSize (← snapshot.get (key "root" member)))
    let inverse ← IO.ofExcept (payloadSize (← snapshot.get (key "allOrdinal" id)))
    let indexed ← IO.ofExcept (payloadSize (← snapshot.get (key "all" ordinal)))
    let actualParent ← IO.ofExcept (payloadSize (← snapshot.get (key "allParentOf" id)))
    unless id < (← getNat snapshot.get "nodes") &&
        member < (← getNat snapshot.get "roots") && ordinal < population &&
        root == id && inverse == ordinal && indexed == id && actualParent == parent do
      throw (IO.userError "All parent posting disagrees with its pinned live directories")
    found := id :: found
  pure found.reverse

/-- The source IO boundary has checked the live directories, the literal
node binding and the original All frame. No sibling payload is hydrated. -/
structure ChildObservation where
  requested : Value
  original : Value
  directory : String
  head : PageMap.Head
  child : Nat
  owner : Nat
  header : AllHeader owner
  position : child ∈ header.children

theorem ChildObservation.child_before (observation : ChildObservation) :
    observation.child < observation.owner :=
  observation.header.child_before observation.child observation.position

def ChildObservation.encode (observation : ChildObservation) : Json := Json.mkObj [
  ("kind", toJson "indexed"), ("requested", valueToJson observation.requested),
  ("original", valueToJson observation.original), ("directory", toJson observation.directory),
  ("head", toJson observation.head), ("child", toJson observation.child),
  ("owner", toJson observation.owner), ("frame", observation.header.checked.frame.toJson)]

/-- Read only All reference frames in which the literal Work occupies a
child position. Even a structured sibling is never hydrated by this lookup.
Retired references and frames from another publication are rejected. -/
def literalAllChildren (snapshot : Snapshot) (query : Value)
    (observe : Option (ChildObservation → IO Unit) := none) : IO (List Nat) := do
  let population ← getNat snapshot.get "alls"
  unless (← getNat snapshot.get "indexedAllReferences") == population do
    throw (IO.userError "All reference index is incomplete")
  let some child ← findNode? snapshot query | return []
  let rows ← directory snapshot (key "allChild" child)
  let mut found := []
  for (ordinal, id) in rows do
    let member ← IO.ofExcept (payloadSize (← snapshot.get (key "member" id)))
    let root ← IO.ofExcept (payloadSize (← snapshot.get (key "root" member)))
    let inverse ← IO.ofExcept (payloadSize (← snapshot.get (key "allOrdinal" id)))
    let indexed ← IO.ofExcept (payloadSize (← snapshot.get (key "all" ordinal)))
    unless id < (← getNat snapshot.get "nodes") &&
        member < (← getNat snapshot.get "roots") && ordinal < population &&
        root == id && inverse == ordinal && indexed == id do
      throw (IO.userError "All child posting disagrees with its pinned live directories")
    let some header := AllHeader.fromFrame? (← readFrame snapshot snapshot.get id) |
      throw (IO.userError "invalid indexed All child frame")
    if position : child ∈ header.children then
      if found.isEmpty then
        if let some observe := observe then
          try observe ⟨query, query, snapshot.directory.toString, snapshot.head,
            child, id, header, position⟩
          catch error => IO.eprintln s!"Eggshell could not record original All-child evidence: {error}"
    else throw (IO.userError "All child posting disagrees with its checked frame")
    found := id :: found
  pure found.reverse

def NodeReader.readTopology (reader : NodeReader snapshot) (atomsOnly : Bool) : IO (Option (List AllEdge)) := do
  let headers ← allHeaders snapshot
  -- Decide the complete fast-lane domain before any descendant hydration.
  for entry in headers do
    if atomsOnly then
      for child in entry.2.header.parent :: entry.2.header.children do
        match (← readFrame snapshot snapshot.get child).frame with
        | .atom => pure ()
        | .apply .. => return none
  let mut edges := []
  for entry in headers do
    let some _ := entry.2.atHead? snapshot.head |
      throw (IO.userError "All nomination belongs to another pinned publication")
    let value ← reader.read entry.1
    let some edge := AllEdge.fromValue? value |
      throw (IO.userError "invalid published All relation")
    edges := edge :: edges
  pure (some edges.reverse)

def readTopology (snapshot : Snapshot) (atomsOnly : Bool) : IO (Option (List AllEdge)) := do
  (← NodeReader.new snapshot).readTopology atomsOnly

def NodeReader.atomTopology? (reader : NodeReader snapshot) : IO (Option (List AllEdge)) :=
  reader.readTopology true

def atomTopology? (snapshot : Snapshot) : IO (Option (List AllEdge)) := do
  (← NodeReader.new snapshot).atomTopology?

/-- Structured Work is a topology dependency, not permission to materialize
every Outcome in the DB. The general kernel consumes these original edges. -/
def NodeReader.topology (reader : NodeReader snapshot) : IO (List AllEdge) := do
  let some edges ← reader.readTopology false |
    throw (IO.userError "general topology read unexpectedly rejected its domain")
  pure edges

def topology (snapshot : Snapshot) : IO (List AllEdge) := do
  (← NodeReader.new snapshot).topology

/-- A request owns a pinned parent cache, not a second graph. Every pass
revisits the demand closure under its current Union classes; new aliases can
therefore expose a previously absent parent. Unrelated children stay on disk.
Structured equality still uses the complete reference kernel. -/
structure DemandTopology (snapshot : Snapshot) where
  reader : NodeReader snapshot
  parents : IO.Ref (Std.HashMap Value (List Nat))
  loaded : IO.Ref (Std.HashMap Nat (Nat × AllEdge))

def DemandTopology.new (reader : NodeReader snapshot) : IO (DemandTopology snapshot) :=
  return ⟨reader, ← IO.mkRef {}, ← IO.mkRef {}⟩

def DemandTopology.parentIds (demand : DemandTopology snapshot) (work : Value) : IO (List Nat) := do
  if let some ids := (← demand.parents.get)[work]? then return ids
  let ids ← literalAllParents snapshot work
  demand.parents.modify (·.insert work ids)
  pure ids

def DemandTopology.edge (demand : DemandTopology snapshot) (id : Nat) : IO AllEdge := do
  if let some row := (← demand.loaded.get)[id]? then return row.2
  let ordinal ← IO.ofExcept (payloadSize (← snapshot.get (key "allOrdinal" id)))
  let value ← demand.reader.read id
  let some edge := AllEdge.fromValue? value |
    throw (IO.userError "demanded All posting is not an original All relation")
  demand.loaded.modify (·.insert id (ordinal, edge))
  pure edge

/-- An indexed source hop must be an actual parent/child reference. The
checked frame, rather than lexical matching or congruence, supplies the hop. -/
structure IncidentAll (origin : Value) where
  edge : AllEdge
  touches : origin = edge.parent ∨ origin ∈ edge.children

def IncidentAll.check? (origin : Value) (edge : AllEdge) : Option (IncidentAll origin) :=
  if parent : origin = edge.parent then some ⟨edge, Or.inl parent⟩
  else if child : origin ∈ edge.children then some ⟨edge, Or.inr child⟩ else none

def IncidentAll.neighbors {origin : Value} (incident : IncidentAll origin) : List Value :=
  if origin = incident.edge.parent then incident.edge.children else [incident.edge.parent]

theorem IncidentAll.neighbor_is_original {origin : Value} (incident : IncidentAll origin) (work : Value)
    (present : work ∈ incident.neighbors) :
    (origin = incident.edge.parent ∧ work ∈ incident.edge.children) ∨
    (origin ∈ incident.edge.children ∧ work = incident.edge.parent) := by
  unfold neighbors at present
  split at present
  · exact Or.inl ⟨‹origin = incident.edge.parent›, present⟩
  · exact Or.inr ⟨incident.touches.resolve_left ‹origin ≠ incident.edge.parent›,
      List.mem_singleton.mp present⟩

theorem IncidentAll.disconnected_rejected (origin : Value) (edge : AllEdge)
    (notParent : origin ≠ edge.parent) (notChild : origin ∉ edge.children) :
    IncidentAll.check? origin edge = none := by
  simp [check?, notParent, notChild]

/-- Traverse the saved source component from the requested entry points.
Both parent/child postings and original Union endpoints extend the queue;
each Work is scheduled once. This is association traversal, independent of
semantic equality, lexical admission and completion. Outcome bodies are
hydrated separately under the aggregate delivery budget. -/
def DemandTopology.neighborhood (demand : DemandTopology snapshot) (edges : List UnionEdge)
    (requested : List Value) : IO (List AllEdge) := do
  let initial := hashDistinct requested
  let rec visit : Nat → Nat → Array Value → Std.HashSet Value → Std.HashMap Nat Unit →
      IO (Std.HashMap Nat Unit)
    | fuel, cursor, queue, scheduled, chosen => do
        let some work := queue[cursor]? | return chosen
        let remaining + 1 := fuel |
          throw (IO.userError "source component exceeded its finite node domain")
        let mut neighbors := edges.flatMap fun edge =>
          (if edge.left == work then [edge.right] else []) ++
          (if edge.right == work then [edge.left] else [])
        let mut chosen := chosen
        for id in (← demand.parentIds work) ++ (← literalAllChildren snapshot work) do
          let edge ← demand.edge id
          let some incident := IncidentAll.check? work edge |
            throw (IO.userError "source posting does not reference its requested Work")
          neighbors := incident.neighbors ++ neighbors
          chosen := chosen.insert id ()
        let mut queue := queue
        let mut scheduled := scheduled
        for neighbor in neighbors do
          unless scheduled.contains neighbor do
            scheduled := scheduled.insert neighbor
            queue := queue.push neighbor
        visit remaining (cursor + 1) queue scheduled chosen
  let chosen ← visit ((← getNat snapshot.get "nodes") + initial.length + edges.length * 2 + 1)
    0 initial.toArray (Std.HashSet.ofList initial) {}
  let loaded ← demand.loaded.get
  let rows ← chosen.toList.mapM fun (id, _) => do
    let some row := loaded[id]? | throw (IO.userError "source neighborhood lost its original All")
    pure row
  pure ((rows.mergeSort fun a b => a.1 ≤ b.1).map (·.2))

def DemandTopology.read (demand : DemandTopology snapshot) (edges : List UnionEdge)
    (requested : List Value) : IO (List AllEdge) := do
  let some classes := QuotientBuilder.AtomQuotient.prepare edges |
    return ← demand.reader.topology
  let rec visit : Nat → List Value → Std.HashMap Value Unit → Std.HashMap Nat Unit →
      IO (Option (Std.HashMap Nat Unit))
    | _, [], _, chosen => pure (some chosen)
    | 0, _ :: _, _, _ => throw (IO.userError "All demand closure exceeded its finite node domain")
    | fuel + 1, work :: pending, seen, chosen => do
        if seen.contains work then return ← visit fuel pending seen chosen
        let .atom bytes := work | return none
        let seen := seen.insert work ()
        let mut pending := pending
        let mut chosen := chosen
        for alias in classes.aliases bytes do
          for id in ← demand.parentIds alias do
            unless chosen.contains id do
              let edge ← demand.edge id
              chosen := chosen.insert id ()
              pending := hashDistinct (edge.children ++ pending) |>.filter (!seen.contains ·)
        visit fuel pending seen chosen
  let some chosen ← visit ((← getNat snapshot.get "nodes") + requested.length + 1)
      (hashDistinct requested) {} {} | return ← demand.reader.topology
  let loaded ← demand.loaded.get
  let rows ← chosen.toList.mapM fun (id, _) => do
    let some row := loaded[id]? | throw (IO.userError "demanded All lost its original owner")
    pure row
  pure ((rows.mergeSort fun a b => a.1 ≤ b.1).map (·.2))

/-- Completion authority is global child membership, independent of which
parents the current demand happens to traverse. Build one certified inverse
quotient per pass, then read just the original child postings of its aliases.
The pinned source and quotient are captured together by the returned reader;
positive and negative answers cannot survive into a later discovery pass. -/
def DemandTopology.childLookup (_demand : DemandTopology snapshot) (view : RunView)
    (observe : Option (ChildObservation → IO Unit) := none) :
    IO (Value → IO Bool) := do
  let index := Quotient.AliasIndex.prepare view.quotient
  let known ← IO.mkRef ({} : Std.HashMap Value Bool)
  pure fun work => do
    if let some found := (← known.get)[work]? then return found
    let mut found := false
    for alias in index.aliases work do
      let owners ← literalAllChildren snapshot alias (observe.map fun observe observation =>
        observe {observation with requested := work})
      unless owners.isEmpty do
        found := true
        break
    known.modify (·.insert work found)
    pure found

def unionPairCodec : Wire.Codec (Nat × Nat) := Wire.natural.product Wire.natural

def decodeUnionPair (bytes : ByteArray) : IO (Nat × Nat) := do
  let (pair, tail) ← IO.ofExcept (unionPairCodec.decode bytes.toList)
  unless tail.isEmpty && (unionPairCodec.encode pair).toByteArray == bytes do
    throw (IO.userError "noncanonical Union pair")
  pure pair

/-- A display digest locates a bucket, never establishes graph equality. -/
def unionDisplayKey (left right : Value) : String :=
  let first := (valueToJson left).compress
  let second := (valueToJson right).compress
  let ordered := if first ≤ second then [first.toUTF8, second.toUTF8]
    else [second.toUTF8, first.toUTF8]
  "u" ++ Blake3.hex (Blake3.digest "eggshell.union.ui".toUTF8 ordered)

def unionPairKey (left right : Nat) : String :=
  key (key "pair" (min left right)) (max left right)

theorem union_pair_key_symmetric (left right : Nat) :
    unionPairKey left right = unionPairKey right left := by
  simp [unionPairKey, Nat.min_comm, Nat.max_comm]

/-- Only live relation rows are read, in their original numeric order. A
history of retractions does not introduce missing ordinal point probes. -/
def unionDirectory (snapshot : Snapshot) : IO (List (Nat × (Nat × Nat))) := do
  let population ← getNat snapshot.get "unions"
  let rows ← snapshot.foldRange ⟨"union:", "union;"⟩ (fun rows row => do
    let some bytes := row.2 | return rows
    let some ordinal := (row.1.drop 6).toString.toNat? |
      throw (IO.userError "invalid Union directory key")
    unless row.1 == key "union" ordinal && ordinal < population do
      throw (IO.userError "Union directory exceeds its published population")
    pure ((ordinal, ← decodeUnionPair bytes) :: rows)) []
  pure (rows.mergeSort fun a b => a.1 ≤ b.1)

def unionPairs (snapshot : Snapshot) : IO (List (Nat × Nat)) :=
  (List.map Prod.snd) <$> unionDirectory snapshot

/-- The locator carries native node ids as well as the certified relation.
All ids are checked against the pinned allocation and pair directory. -/
structure LocatedUnion where
  head : PageMap.Head
  ordinal : Nat
  leftId : Nat
  rightId : Nat
  edge : UnionEdge

def LocatedUnion.atHead? (entry : LocatedUnion) (head : PageMap.Head) :
    Option { checked : LocatedUnion // checked.head = head } :=
  if same : entry.head = head then some ⟨entry, same⟩ else none

theorem LocatedUnion.foreign_head_rejected (entry : LocatedUnion) (head : PageMap.Head)
    (different : entry.head ≠ head) : entry.atHead? head = none := by
  simp [atHead?, different]

def locateUnion? (snapshot : Snapshot) (displayKey : String) : IO (Option LocatedUnion) := do
  let ordinals ← getIds snapshot.get ("unionKey:" ++ displayKey)
  let mut found := []
  let population ← getNat snapshot.get "unions"
  let nodePopulation ← getNat snapshot.get "nodes"
  let owner ← authority snapshot
  let known ← IO.mkRef {}
  for ordinal in ordinals do
    unless ordinal < population do throw (IO.userError "Union locator exceeds its allocation")
    let some bytes ← snapshot.get (key "union" ordinal) |
      throw (IO.userError "Union locator points to a retired relation")
    let (leftId, rightId) ← decodeUnionPair bytes
    unless leftId < nodePopulation && rightId < nodePopulation do
      throw (IO.userError "Union locator points outside node allocation")
    let some _ ← snapshot.get (unionPairKey leftId rightId) |
      throw (IO.userError "Union locator is missing its pair directory")
    unless (← getNat snapshot.get (unionPairKey leftId rightId)) == ordinal do
      throw (IO.userError "Union locator disagrees with its pair directory")
    let left ← resolve snapshot snapshot.get known leftId
    let right ← resolve snapshot snapshot.get known rightId
    unless unionDisplayKey left right == displayKey do
      throw (IO.userError "Union locator disagrees with its native endpoints")
    if safe : Value.sameExactFootprint left right then
      let edge : UnionEdge := ⟨left, right, .workspace owner,
        Value.sameExactFootprint_sound safe⟩
      found := ⟨snapshot.head, ordinal, leftId, rightId, edge⟩ :: found
    else throw (IO.userError "stored Union changes Exact authority")
  match found with
  | [] => pure none
  | [entry] => pure (some entry)
  | _ => throw (IO.userError "ambiguous Union display key")

/-- Remove just the located relation and its two indexes. Root membership,
body extents, postings and document frequencies are never rewritten. -/
def removeUnion (writer : Writer) (entry : LocatedUnion) : IO Unit := do
  let some checked := entry.atHead? writer.base.head |
    throw (IO.userError "Union retraction belongs to another pinned publication")
  let entry := checked.val
  let pairKey := unionPairKey entry.leftId entry.rightId
  let some _ ← writer.get pairKey | throw (IO.userError "Union was already retired")
  unless (← getNat writer.get pairKey) == entry.ordinal do
    throw (IO.userError "Union pair changed before retraction")
  let some bytes ← writer.get (key "union" entry.ordinal) |
    throw (IO.userError "Union pair has no relation row")
  unless (← decodeUnionPair bytes) == (entry.leftId, entry.rightId) do
    throw (IO.userError "Union relation changed before retraction")
  let locator := "unionKey:" ++ unionDisplayKey entry.edge.left entry.edge.right
  let previous ← getIds writer.get locator
  unless previous.contains entry.ordinal do
    throw (IO.userError "Union retraction is missing its display locator")
  let remaining := previous.filter (· != entry.ordinal)
  writer.put pairKey none
  writer.put (key "union" entry.ordinal) none
  if remaining.isEmpty then writer.put locator none else putIds writer locator remaining

def NodeReader.unions (reader : NodeReader snapshot) (authority : Value) : IO (List (PersistentUnion authority)) := do
  unless (← Store.authority snapshot) == authority do throw (IO.userError "foreign Union authority")
  let mut unions : List (PersistentUnion authority) := []
  for (left, right) in (← unionPairs snapshot) do
    let left ← reader.read left
    let right ← reader.read right
    if same : Value.sameExactFootprint left right then
      unions := unions ++ [.make authority left right (Value.sameExactFootprint_sound same)]
    else throw (IO.userError "stored Union changes Exact authority")
  pure unions

def readUnions (snapshot : Snapshot) (authority : Value) : IO (List (PersistentUnion authority)) := do
  (← NodeReader.new snapshot).unions authority

/-- Detect the general congruence lane from headers before resolving any
structured Union endpoint. A rejected fast probe must not hydrate its large
Outcome descendants merely to learn that the atom index does not apply. -/
def NodeReader.atomUnions? (reader : NodeReader snapshot) (authority : Value) :
    IO (Option (List (PersistentUnion authority))) := do
  for (left, right) in (← unionPairs snapshot) do
    for id in [left, right] do
      unless id < (← getNat snapshot.get "nodes") do
        throw (IO.userError "Union endpoint exceeds its pinned node population")
      match (← readFrame snapshot snapshot.get id).frame with
      | .atom => pure ()
      | .apply .. => return none
  some <$> reader.unions authority

def atomUnions? (snapshot : Snapshot) (authority : Value) :
    IO (Option (List (PersistentUnion authority))) := do
  (← NodeReader.new snapshot).atomUnions? authority

/-- Explicit whole-graph inspection/oracle. Normal promotion/indexing uses
header and selected-owner reads instead. Search replacement is separate. -/
def materialize (snapshot : Snapshot) : IO Graph := do
  let values ← rootsBetween snapshot 0 (← getNat snapshot.get "roots")
  let authority ← authority snapshot
  let unions ← readUnions snapshot authority
  if valid : values.all Relation.wellFormed then
    pure {
      authority := authority
      revision := snapshot.head.revision
      values := values
      unions := unions
      values_wellFormed := fun value member => (List.all_eq_true.mp valid) value member }
  else throw (IO.userError "invalid DB relation root")

def reviseValues (previous removed added : List Value) : List Value :=
  previous.filter (!removed.contains ·) ++ added

theorem reviseValues_retired (previous removed added : List Value) (value : Value)
    (retired : value ∈ removed) (notAdded : value ∉ added) :
    value ∉ reviseValues previous removed added := by
  simp [reviseValues, retired, notAdded]

theorem reviseValues_new (previous removed added : List Value) (value : Value)
    (fresh : value ∈ added) : value ∈ reviseValues previous removed added := by
  simp [reviseValues, fresh]

/-- Replay only publications after the previous view. The input revision is
checked, and the returned view consumes exactly the pinned target revision.
Retractions are replayed before additions; changed equality is read separately.
No unchanged root body is read by this path. -/
def revise (snapshot : Snapshot) (previousHead : PageMap.Head) (previous : Graph) : IO Graph := do
  unless previousHead.identity == snapshot.head.identity &&
      previous.revision == previousHead.revision && previousHead.revision ≤ snapshot.head.revision &&
      previousHead.authority == snapshot.head.authority do
    throw (IO.userError "change replay does not follow the same published DB")
  if previousHead.revision == snapshot.head.revision && previousHead != snapshot.head then
    throw (IO.userError "DB root changed without a new publication revision")
  let mut values := previous.values
  let mut unionsChanged := false
  let known ← IO.mkRef {}
  for revision in [previousHead.revision + 1 : snapshot.head.revision + 1] do
    let change ← readChange snapshot revision
    let removed ← change.removed.mapM fun id => resolve snapshot snapshot.get known id
    let added ← change.added.mapM fun id => resolve snapshot snapshot.get known id
    values := reviseValues values removed added
    unionsChanged := unionsChanged || change.unionsChanged
  let unions ← if unionsChanged then readUnions snapshot previous.authority else pure previous.unions
  if valid : values.all Relation.wellFormed then
    pure {
      authority := previous.authority
      revision := snapshot.head.revision
      values := values
      unions := unions
      values_wellFormed := fun value member => (List.all_eq_true.mp valid) value member }
  else throw (IO.userError "invalid root in a published change record")

def addUnions (intern : Intern) (edges : List UnionEdge) : IO Unit := do
  for edge in edges do
    let left ← intern.value edge.left
    let right ← intern.value edge.right
    let name := unionPairKey left right
    if (← intern.writer.get name).isSome then continue
    let ordinal ← getNat intern.writer.get "unions"
    putNat intern.writer "unions" (ordinal + 1)
    putNat intern.writer name ordinal
    intern.writer.put (key "union" ordinal)
      (some (unionPairCodec.encode (left, right)).toByteArray)
    let locator := "unionKey:" ++ unionDisplayKey edge.left edge.right
    putIds intern.writer locator ((← getIds intern.writer.get locator) ++ [ordinal])

end Eggshell.Persistence.Store
