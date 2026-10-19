module

public import Eggshell.DB.Wire
public import Eggshell.FileSystem
public import Eggshell.Blake3
public import Std.Data.HashMap.Lemmas
import all Init.Data.Ord.String
import all Init.System.ST

@[expose] public section
namespace Eggshell.DB.PageMap
open Lean Std

/-- Dense immutable leaves and a high-fanout ordered directory. A transaction
copies only affected leaf/directory pages; the head is a constant-size root.
Physical addresses are never semantic identities. -/
abbrev Row := String × Option ByteArray

def rowCodec : Wire.Codec Row := Wire.text.product (Wire.optional Wire.byteBlob)

structure Ref where
  offset : Nat
  bytes : Nat
  checksum : String
  first : String
  last : String
  height : Nat
  rows : Nat
  deriving ToJson, FromJson, BEq, DecidableEq

def refCodec : Wire.Codec Ref :=
  (Wire.natural.product (Wire.natural.product (Wire.text.product
    (Wire.text.product (Wire.text.product (Wire.natural.product Wire.natural)))))).iso
    (fun r => (r.offset, r.bytes, r.checksum, r.first, r.last, r.height, r.rows))
    (fun (offset, bytes, checksum, first, last, height, rows) =>
      ⟨offset, bytes, checksum, first, last, height, rows⟩)
    (by intro r; cases r; rfl)

inductive Page where
  | leaf (rows : List Row)
  | branch (children : List Ref)
  deriving DecidableEq

def pageCodec : Wire.Codec Page :=
  (Wire.sum (Wire.list rowCodec) (Wire.list refCodec)).iso
    (fun | .leaf rows => .inl rows | .branch children => .inr children)
    (fun | .inl rows => .leaf rows | .inr children => .branch children)
    (by intro page; cases page <;> rfl)

def encode (page : Page) : ByteArray := (pageCodec.encode page).toByteArray

def decode (bytes : ByteArray) : Except String Page := do
  let (page, tail) ← pageCodec.decode bytes.toList
  unless tail.isEmpty do throw "trailing bytes in index page"
  unless encode page == bytes do throw "noncanonical index page"
  pure page

theorem page_codec_roundtrip (page : Page) (tail : List UInt8) :
    pageCodec.decode (pageCodec.encode page ++ tail) = .ok (page, tail) :=
  pageCodec.roundtrip page tail

def ordered : List Row → Bool
  | [] | [_] => true
  | a :: b :: rest => compare a.1 b.1 == .lt && ordered (b :: rest)

theorem ordered_of_pairwise (rows : List Row)
    (sorted : rows.Pairwise (fun a b => compare a.1 b.1 = .lt)) : ordered rows = true := by
  induction rows with
  | nil => rfl
  | cons a rest ih =>
    cases rest with
    | nil => rfl
    | cons b rest =>
      have parts := List.pairwise_cons.mp sorted
      simp only [ordered, Bool.and_eq_true, beq_iff_eq]
      exact ⟨parts.1 b (by simp), ih parts.2⟩

/-- The linear check performed by the disk decoder establishes the complete
strict-order premise used by the merge proof; no quadratic runtime check is
needed to connect decoded pages to that specification. -/
theorem pairwise_of_ordered (rows : List Row) (accepted : ordered rows = true) :
    rows.Pairwise (fun a b => compare a.1 b.1 = .lt) := by
  induction rows with
  | nil => exact List.Pairwise.nil
  | cons a rest ih =>
    cases rest with
    | nil => simp
    | cons b rest =>
      simp only [ordered, Bool.and_eq_true, beq_iff_eq] at accepted
      have tail := ih accepted.2
      obtain ⟨afterB, _⟩ := List.pairwise_cons.mp tail
      apply List.pairwise_cons.mpr
      refine ⟨?_, tail⟩
      intro row member
      rcases List.mem_cons.mp member with equal | member
      · subst row; exact accepted.1
      · exact Std.TransCmp.lt_of_lt_of_isLE accepted.1 (by rw [afterB row member]; decide)

def childrenValid (refs : List Ref) : Bool :=
  !refs.isEmpty && refs.length ≤ 32 &&
  refs.all (fun r => 0 < r.rows && 0 < r.bytes && r.bytes ≤ 65536 && r.first ≤ r.last) &&
  (refs.zip refs.tail).all (fun (a, b) => a.last < b.first && a.height == b.height)

def agrees (ref : Ref) : Page → Bool
  | .leaf rows =>
      !rows.isEmpty && ordered rows && ref.height == 0 && ref.rows == rows.length &&
      rows.head?.map (·.1) == some ref.first && rows.getLast?.map (·.1) == some ref.last
  | .branch children =>
      childrenValid children &&
      children.head?.map (·.first) == some ref.first &&
      children.getLast?.map (·.last) == some ref.last &&
      children.head?.map (fun r => r.height + 1) == some ref.height &&
      ref.rows == (children.map (·.rows)).sum

def magic : ByteArray := "eggshell.pages\n".toUTF8

def digest (bytes : ByteArray) : String :=
  Blake3.hex (Blake3.digest "eggshell.page".toUTF8 [bytes])

structure Head where
  identity : String
  authority : String
  revision : Nat := 0
  bytes : Nat := magic.size
  root : Option Ref := none
  deriving ToJson, FromJson, BEq, DecidableEq

def headCodec : Wire.Codec Head :=
  (Wire.text.product (Wire.text.product (Wire.natural.product
    (Wire.natural.product (Wire.optional refCodec))))).iso
    (fun h => (h.identity, h.authority, h.revision, h.bytes, h.root))
    (fun (identity, authority, revision, bytes, root) =>
      ⟨identity, authority, revision, bytes, root⟩)
    (by intro h; cases h; rfl)

theorem head_codec_roundtrip (head : Head) (tail : List UInt8) :
    headCodec.decode (headCodec.encode head ++ tail) = .ok (head, tail) :=
  headCodec.roundtrip head tail

structure Loaded (ref : Ref) where
  page : Page
  valid : agrees ref page = true

structure CachedPage where
  ref : Ref
  loaded : Loaded ref

/-- Fixed-size LRU of certified pages from this pinned reader. A frequently
used directory must not be evicted merely because its first read was old. -/
structure PageCache where
  pages : List CachedPage := []
  bounded : pages.length ≤ 64 := by decide

def PageCache.touch (cache : PageCache) (page : CachedPage) : PageCache :=
  let pages := (page :: cache.pages.filter (fun old => old.ref != page.ref)).take 64
  ⟨pages, by dsimp only [pages]; simp only [List.length_take]; omega⟩

theorem PageCache.touch_bounded (cache : PageCache) (page : CachedPage) :
    (cache.touch page).pages.length ≤ 64 := (cache.touch page).bounded

theorem PageCache.touch_recent (cache : PageCache) (page : CachedPage) :
    (cache.touch page).pages.head? = some page := by
  simp [touch, List.take_succ_cons]

def validIdentity (identity : String) : Bool :=
  identity.length == 64 && identity.toList.all (fun c =>
    ('0' ≤ c && c ≤ '9') || ('a' ≤ c && c ≤ 'f'))

def dataPath (directory : System.FilePath) (head : Head) : System.FilePath :=
  directory / (head.identity ++ ".pages")

/-- A reference into an append-only file incarnation. A checksum detects
damage; reference identity, rather than checksum equality, preserves bytes. -/
structure Blob where
  offset : Nat
  bytes : Nat
  checksum : String
  deriving BEq, DecidableEq, Hashable

instance : LawfulBEq Blob where
  rfl := by
    intro blob
    change instBEqBlob.beq blob blob = true
    cases blob; simp [instBEqBlob.beq]
  eq_of_beq := by
    intro left right equal
    change instBEqBlob.beq left right = true at equal
    cases left; cases right; simp_all [instBEqBlob.beq]

def blobCodec : Wire.Codec Blob :=
  (Wire.natural.product (Wire.natural.product Wire.text)).iso
    (fun blob => (blob.offset, blob.bytes, blob.checksum))
    (fun (offset, bytes, checksum) => ⟨offset, bytes, checksum⟩)
    (by intro blob; cases blob; rfl)

theorem blob_codec_roundtrip (blob : Blob) (tail : List UInt8) :
    blobCodec.decode (blobCodec.encode blob ++ tail) = .ok (blob, tail) :=
  blobCodec.roundtrip blob tail

/-- The read reference must belong to the committed prefix of this pinned
head. Each OS read is bounded independently of the size of the whole body. -/
structure PinnedBlob (head : Head) where
  ref : Blob
  nonempty : 0 < ref.bytes
  bounded : ref.bytes ≤ 4096
  afterMagic : magic.size ≤ ref.offset
  committed : ref.offset + ref.bytes ≤ head.bytes

def Blob.pin? (blob : Blob) (head : Head) : Option (PinnedBlob head) :=
  if valid : 0 < blob.bytes ∧ blob.bytes ≤ 4096 ∧ magic.size ≤ blob.offset ∧
      blob.offset + blob.bytes ≤ head.bytes then
    some ⟨blob, valid.1, valid.2.1, valid.2.2.1, valid.2.2.2⟩
  else none

/-- This is a byte equality under the append-only storage contract. No
injectivity or collision-resistance assumption about a digest is used. -/
theorem blob_bytes_preserved_by_append (before appended : ByteArray) (blob : Blob)
    (committed : blob.offset + blob.bytes ≤ before.size) :
    (before ++ appended).extract blob.offset (blob.offset + blob.bytes) =
      before.extract blob.offset (blob.offset + blob.bytes) := by
  rw [ByteArray.extract_append]
  have start : blob.offset - before.size = 0 := by omega
  have finish : blob.offset + blob.bytes - before.size = 0 := by omega
  simp [start, finish]

/-- Discarding an uncommitted tail also preserves every committed reference.
The native recovery adapter checks EOF and the writer supplies the durable
head boundary; recovery never truncates inside that boundary. -/
theorem blob_bytes_preserved_by_recovery (before : ByteArray) (retained : Nat) (blob : Blob)
    (committed : blob.offset + blob.bytes ≤ retained) :
    (before.extract 0 retained).extract blob.offset (blob.offset + blob.bytes) =
      before.extract blob.offset (blob.offset + blob.bytes) := by
  rw [ByteArray.extract_extract]
  simp only [Nat.zero_add, Nat.min_eq_left committed]

/-- Actual search reads, including empty ranges and absent keys. A new
matching owner cannot hide behind a cache which recorded only positive hits.
Payload dependencies retain immutable references, never another body copy.
The source head records the file incarnation once for the complete read set;
validation checks that identity before checking references and body integrity. -/
inductive ReadObservation where
  | point (key : String) (value : Option ByteArray)
  | range (lower upper : String) (rows : List Row)
  | blob (ref : Blob)
  /-- The complete observed prefix is expanded from the source's saved root.
  A full read uses all chunks; a short-circuit comparison names only the
  prefix it actually consumed, never a duplicate descriptor/body list. -/
  | payload (payloadKey : String) (bytes chunks : Nat)
  deriving BEq, DecidableEq, Hashable

local instance : LawfulBEq ByteArray where
  rfl := by
    intro bytes
    change ByteArray.beq bytes bytes = true
    simp [ByteArray.beq]
  eq_of_beq := by
    intro left right equal
    apply ByteArray.ext
    change (left.data == right.data) = true at equal
    exact beq_iff_eq.mp equal

instance : LawfulBEq ReadObservation where
  rfl := by
    intro observation
    change instBEqReadObservation.beq observation observation = true
    cases observation <;> simp [instBEqReadObservation.beq]
  eq_of_beq := by
    intro left right equal
    change instBEqReadObservation.beq left right = true at equal
    cases left <;> cases right <;> simp_all [instBEqReadObservation.beq]

def readObservationCodec : Wire.Codec ReadObservation :=
  (Wire.sum rowCodec (Wire.sum
    (Wire.text.product (Wire.text.product (Wire.list rowCodec)))
    (Wire.sum blobCodec (Wire.text.product (Wire.natural.product Wire.natural))))).iso
    (fun | .point key value => .inl (key, value)
         | .range lower upper rows => .inr (.inl (lower, upper, rows))
         | .blob ref => .inr (.inr (.inl ref))
         | .payload payloadKey bytes chunks => .inr (.inr (.inr (payloadKey, bytes, chunks))))
    (fun | .inl (key, value) => .point key value
         | .inr (.inl (lower, upper, rows)) => .range lower upper rows
         | .inr (.inr (.inl ref)) => .blob ref
         | .inr (.inr (.inr (payloadKey, bytes, chunks))) => .payload payloadKey bytes chunks)
    (by intro observation; cases observation <;> rfl)

theorem read_observation_roundtrip (observation : ReadObservation) (tail : List UInt8) :
    readObservationCodec.decode (readObservationCodec.encode observation ++ tail) =
      .ok (observation, tail) := readObservationCodec.roundtrip observation tail

def ReadObservation.check? (expected actual : ReadObservation) :
    Option { observed : ReadObservation // observed = expected } :=
  if same : actual = expected then some ⟨actual, same⟩ else none

theorem changed_observation_rejected (expected actual : ReadObservation)
    (changed : actual ≠ expected) : expected.check? actual = none := by
  simp [ReadObservation.check?, changed]

def readTraceAllowance : Nat := 65536

/-- An address nominates a collision bucket; complete observation equality
decides membership. The erased invariant covers misses, empty ranges and
payload bytes as well as positive rows. Arbitrary address functions, including
a constant function, preserve the exact observed domain. -/
structure ObservationIndex (address : ReadObservation → UInt64)
    (operations : List ReadObservation) where
  buckets : Std.HashMap UInt64 (List ReadObservation)
  exact : ∀ operation,
    operation ∈ buckets.getD (address operation) [] ↔ operation ∈ operations

def ObservationIndex.empty (address : ReadObservation → UInt64) :
    ObservationIndex address [] := ObservationIndex.mk {} (by intro operation; simp)

def ObservationIndex.contains (index : ObservationIndex address operations)
    (operation : ReadObservation) : Bool :=
  ((ObservationIndex.buckets index).getD (address operation) []).contains operation

theorem ObservationIndex.contains_exact (index : ObservationIndex address operations)
    (operation : ReadObservation) : index.contains operation = operations.contains operation := by
  apply Bool.eq_iff_iff.mpr
  simpa only [contains, List.contains_iff_mem] using index.exact operation

def ObservationIndex.insert (index : ObservationIndex address operations)
    (operation : ReadObservation) : ObservationIndex address (operation :: operations) :=
  ObservationIndex.mk ((ObservationIndex.buckets index).insert (address operation)
      (operation :: (ObservationIndex.buckets index).getD (address operation) [])) (by
    intro wanted
    rw [Std.HashMap.getD_insert]
    by_cases same : address operation = address wanted
    · simp only [same, BEq.rfl, ↓reduceIte, List.mem_cons]
      rw [index.exact]
    · have different : operation ≠ wanted := by
        intro equal; exact same (congrArg address equal)
      simp only [beq_iff_eq, same, ↓reduceIte, List.mem_cons,
        eq_comm (a := wanted) (b := operation), different, false_or]
      exact index.exact wanted)

def ObservationIndex.make (address : ReadObservation → UInt64) :
    (operations : List ReadObservation) → ObservationIndex address operations
  | [] => .empty address
  | operation :: rest => (make address rest).insert operation

structure ReadTrace where
  operations : List ReadObservation := []
  encodedBytes : Nat := 0
  complete : Bool := true
  index : ObservationIndex hash operations := ObservationIndex.make hash operations

abbrev ReadSummary := List ReadObservation × Nat × Bool

/-- Full-list interpreter used only as the capture specification. -/
def ReadSummary.step (state : ReadSummary) (operation : ReadObservation) : ReadSummary :=
  if !state.2.2 || state.1.contains operation then state else
    let next := state.2.1 + readObservationCodec.encodedSize operation
    if next ≤ readTraceAllowance then (operation :: state.1, next, true) else ([], 0, false)

def ReadTrace.summary (trace : ReadTrace) : ReadSummary :=
  (trace.operations, trace.encodedBytes, trace.complete)

def ReadTrace.add (trace : ReadTrace) (operation : ReadObservation) : ReadTrace :=
  if !trace.complete || trace.index.contains operation then trace else
    let next := trace.encodedBytes + readObservationCodec.encodedSize operation
    if next ≤ readTraceAllowance then
      { operations := operation :: trace.operations, encodedBytes := next, complete := true,
        index := trace.index.insert operation }
    else { complete := false }

/-- The complete externally observable trace, including order, charged bytes
and permanent overflow, is identical to the former full-list interpreter.
Only collision-bucket members are traversed by the actual capture path. -/
theorem ReadTrace.add_exact (trace : ReadTrace) (operation : ReadObservation) :
    (trace.add operation).summary = ReadSummary.step trace.summary operation := by
  simp only [add, ObservationIndex.contains_exact, summary, ReadSummary.step]
  split
  · simp_all
  · split
    · simp_all
    · simp_all
      exact (if_neg (show ¬ trace.encodedBytes + readObservationCodec.encodedSize operation ≤
        readTraceAllowance from by omega)).symm

theorem ReadTrace.fold_exact (trace : ReadTrace) (operations : List ReadObservation) :
    (operations.foldl ReadTrace.add trace).summary =
      operations.foldl ReadSummary.step trace.summary :=
  (List.foldl_hom ReadTrace.summary (g₁ := ReadTrace.add) (g₂ := ReadSummary.step)
    (l := operations) (init := trace)
    (fun state operation => (state.add_exact operation).symm)).symm

theorem ReadTrace.add_bounded (trace : ReadTrace) (operation : ReadObservation)
    (bounded : trace.encodedBytes ≤ readTraceAllowance) :
    (trace.add operation).encodedBytes ≤ readTraceAllowance := by
  unfold add
  split
  · exact bounded
  · dsimp only
    split
    · assumption
    · exact Nat.zero_le _

theorem ReadTrace.incomplete_stays_incomplete (trace : ReadTrace)
    (incomplete : trace.complete = false) (operation : ReadObservation) :
    (trace.add operation).complete = false := by
  simp [add, incomplete]

structure Snapshot where
  directory : System.FilePath
  head : Head
  handle : FileSystem.ReadHandle
  reads : IO.Ref Nat
  readBytes : IO.Ref Nat
  cache : IO.Ref PageCache
  trace : IO.Ref (Option ReadTrace)

def Snapshot.observe (snapshot : Snapshot) (operation : ReadObservation) : IO Unit :=
  snapshot.trace.modify (·.map (·.add operation))

def absolute (path : System.FilePath) : IO System.FilePath := do
  let cwd ← IO.currentDir
  pure ((if path.isAbsolute then path else cwd / path).normalize)

def open? (directory : System.FilePath) : IO (Option Snapshot) := do
  let directory ← absolute directory
  FileSystem.rejectSymlinkAncestors directory
  match ← FileSystem.symlinkMetadata? directory with
  | none => pure none
  | some metadata =>
      unless metadata.type == .dir do throw (IO.userError "memory DB must be a directory")
      let bytes ← FileSystem.boundedBytes (directory / "head") 16384
      let some text := String.fromUTF8? bytes | throw (IO.userError "invalid DB head encoding")
      let head : Head ← IO.ofExcept (Json.parse text >>= fromJson?)
      unless validIdentity head.identity do throw (IO.userError "invalid DB file incarnation")
      unless head.bytes ≥ magic.size && head.bytes < 2 ^ 63 do
        throw (IO.userError "invalid committed DB extent")
      if head.root.isNone then
        unless head.bytes == magic.size && head.revision == 0 do
          throw (IO.userError "a published nonempty DB lost its root")
      let handle ← FileSystem.openRead (dataPath directory head).toString
      let signature : FileSystem.ReadSize ← if small : magic.size ≤ 4096 then
          pure ⟨magic.size, small⟩ else throw (IO.userError "DB signature exceeds one page")
      unless (← FileSystem.readVersion handle).bytes ≥ head.bytes &&
          (← FileSystem.readPage handle 0 signature) == magic do
        throw (IO.userError "truncated or foreign DB pages")
      -- Opening a shared or filesystem-read-only publication never changes
      -- its permissions. Creation owns access-mode initialization.
      pure (some ⟨directory, head, handle, ← IO.mkRef 0, ← IO.mkRef 0, ← IO.mkRef {}, ← IO.mkRef none⟩)

def pin (directory : System.FilePath) : IO Snapshot := do
  let some snapshot ← open? directory | throw (IO.userError "memory DB does not exist")
  pure snapshot

def Snapshot.load (snapshot : Snapshot) (ref : Ref) : IO (Loaded ref) := do
  unless 0 < ref.bytes && ref.bytes ≤ 65536 && magic.size ≤ ref.offset &&
      ref.offset + ref.bytes ≤ snapshot.head.bytes do
    throw (IO.userError "index page is outside its pinned committed extent")
  for cached in (← snapshot.cache.get).pages do
    if same : cached.ref = ref then
      snapshot.cache.modify (·.touch cached)
      return same ▸ cached.loaded
  let mut bytes := ByteArray.empty
  while bytes.size < ref.bytes do
    let count := min 4096 (ref.bytes - bytes.size)
    let part ← FileSystem.readPage snapshot.handle (ref.offset + bytes.size).toUInt64
      ⟨count, Nat.min_le_left _ _⟩
    unless part.size == count do throw (IO.userError "truncated DB page")
    bytes := bytes ++ part
  snapshot.reads.modify (· + 1)
  snapshot.readBytes.modify (· + bytes.size)
  unless digest bytes == ref.checksum do throw (IO.userError "corrupted DB page")
  let page ← IO.ofExcept (decode bytes)
  if valid : agrees ref page = true then
    let loaded : Loaded ref := ⟨page, valid⟩
    snapshot.cache.modify (·.touch ⟨ref, loaded⟩)
    pure loaded
  else throw (IO.userError "DB page differs from its directory descriptor")

/-- The last fence not greater than the key also handles insertions beyond
current outer fences. Point reads never enumerate the remaining children. -/
def route (refs : List Ref) (key : String) : Option (Nat × Ref) :=
  refs.zipIdx |>.foldl (fun chosen (ref, index) =>
    if chosen.isNone || ref.first ≤ key then some (index, ref) else chosen) none

structure Lookup (height : Nat) where
  value : Option ByteArray
  visits : Nat
  bounded : visits ≤ height + 1

/-- The bound counts executed page visits, including directory nodes. Cache
hits can reduce physical reads; they cannot weaken the fixed-snapshot bound. -/
def Snapshot.getAt (snapshot : Snapshot) (ref : Ref) (key : String) : IO (Lookup ref.height) := do
  -- A miss is certified by the decoded page's fences. Checking an unchecked
  -- head/directory descriptor first can silently turn corruption into emptiness.
  let loaded ← snapshot.load ref
  if key < ref.first || ref.last < key then return ⟨none, 1, by omega⟩
  match loaded.page with
  | .leaf rows => pure ⟨(rows.find? (fun row => row.1 == key)).bind (·.2), 1, by omega⟩
  | .branch children =>
      let some (_, child) := route children key | throw (IO.userError "empty branch")
      if smaller : child.height < ref.height then
        let next ← snapshot.getAt child key
        pure ⟨next.value, next.visits + 1, by have := next.bounded; omega⟩
      else throw (IO.userError "index height did not decrease")
termination_by ref.height

theorem Lookup.pages_bounded (result : Lookup height) : result.visits ≤ height + 1 := result.bounded

def Snapshot.get (snapshot : Snapshot) (key : String) : IO (Option ByteArray) := do
  let result ← match snapshot.head.root with
  | none => pure none
  | some ref => pure (← snapshot.getAt ref key).value
  snapshot.observe (.point key result)
  pure result

/-- Half-open key intervals. Range readers use the same checked pages and
immutable root as point readers; they never enumerate unrelated namespaces. -/
structure KeyRange where
  lower : String
  upper : String
  deriving DecidableEq

def KeyRange.contains (range : KeyRange) (key : String) : Bool :=
  decide (range.lower ≤ key ∧ key < range.upper)

def KeyRange.overlaps (range : KeyRange) (ref : Ref) : Bool :=
  decide (range.lower ≤ ref.last ∧ ref.first < range.upper)

def KeyRange.select (range : KeyRange) (rows : List Row) : List Row :=
  rows.filter fun row => range.contains row.1

theorem KeyRange.select_exact (range : KeyRange) (rows : List Row) (row : Row) :
    row ∈ range.select rows ↔ row ∈ rows ∧ range.lower ≤ row.1 ∧ row.1 < range.upper := by
  simp [select, contains]

theorem ordered_bounds (rows : List Row) (sorted : ordered rows = true)
    (first last : String) (head : rows.head?.map Prod.fst = some first)
    (ending : rows.getLast?.map Prod.fst = some last) :
    ∀ row ∈ rows, first ≤ row.1 ∧ row.1 ≤ last := by
  induction rows generalizing first last with
  | nil => simp at head
  | cons a rest ih =>
      simp only [List.head?_cons, Option.map_some, Option.some.injEq] at head
      subst first
      cases rest with
      | nil =>
          simp only [List.getLast?_singleton, Option.map_some, Option.some.injEq] at ending
          subst last
          intro row member
          simp only [List.mem_singleton] at member
          subst row
          exact ⟨Std.le_refl _, Std.le_refl _⟩
      | cons b tail =>
          simp only [ordered, Bool.and_eq_true, beq_iff_eq] at sorted
          have later := ih sorted.2 b.1 last rfl (by simpa using ending)
          have before : a.1 ≤ b.1 := Std.le_of_lt (compareOfLessAndEq_eq_lt.mp sorted.1)
          intro row member
          rcases List.mem_cons.mp member with same | member
          · subst row
            exact ⟨Std.le_refl _, Std.le_trans before (later b (by simp)).2⟩
          · obtain ⟨lower, upper⟩ := later row member
            exact ⟨Std.le_trans before lower, upper⟩

/-- The actual page-decoder predicate establishes the fences used by pruning;
they are not an additional assumption supplied by a range caller. -/
theorem leaf_bounds (ref : Ref) (rows : List Row) (checked : agrees ref (.leaf rows) = true) :
    ∀ row ∈ rows, ref.first ≤ row.1 ∧ row.1 ≤ ref.last := by
  simp only [agrees, Bool.and_eq_true, beq_iff_eq] at checked
  exact ordered_bounds rows checked.1.1.1.1.2 ref.first ref.last checked.1.2 checked.2

/-- Directory fences can discard a subtree only when no key in its checked
interval belongs to the request. This includes both ends of the interval. -/
theorem KeyRange.prune_exact (range : KeyRange) (ref : Ref) (rows : List Row)
    (bounded : ∀ row ∈ rows, ref.first ≤ row.1 ∧ row.1 ≤ ref.last)
    (outside : range.overlaps ref = false) : range.select rows = [] := by
  apply List.eq_nil_iff_forall_not_mem.mpr
  intro row present
  obtain ⟨member, lower, upper⟩ := (range.select_exact rows row).mp present
  obtain ⟨first, last⟩ := bounded row member
  have overlapping : range.overlaps ref = true := by
    simp only [overlaps, decide_eq_true_eq]
    exact ⟨Std.le_trans lower last, Std.lt_of_le_of_lt first upper⟩
  simp [outside] at overlapping

theorem KeyRange.select_append (range : KeyRange) (left right : List Row) :
    range.select (left ++ right) = range.select left ++ range.select right :=
  List.filter_append left right

def KeyRange.prunedRows (range : KeyRange) (subtrees : List (Ref × List Row)) : List Row :=
  subtrees.flatMap fun (ref, rows) => if range.overlaps ref then range.select rows else []

/-- Pruning any number of checked subtrees gives the same ordered rows as a
full traversal. No matching row can disappear at a skipped directory. -/
theorem KeyRange.prunedRows_exact (range : KeyRange) (subtrees : List (Ref × List Row))
    (bounded : ∀ subtree ∈ subtrees, ∀ row ∈ subtree.2,
      subtree.1.first ≤ row.1 ∧ row.1 ≤ subtree.1.last) :
    range.prunedRows subtrees = range.select (subtrees.flatMap Prod.snd) := by
  induction subtrees with
  | nil => rfl
  | cons subtree rest ih =>
      obtain ⟨ref, rows⟩ := subtree
      simp only [prunedRows, List.flatMap_cons, select_append]
      have tail := ih (fun subtree member => bounded subtree (by simp [member]))
      change _ ++ range.prunedRows rest = _
      rw [tail]
      by_cases overlap : range.overlaps ref = true
      · simp [overlap]
      · have outside : range.overlaps ref = false := Bool.eq_false_iff.mpr overlap
        rw [if_neg overlap, range.prune_exact ref rows (bounded (ref, rows) (by simp)) outside]

/-- Stream the selected rows to the consumer. Only one decoded leaf and the
directory path are needed; bodies are not read by this traversal. Tombstones
are retained here so callers can choose their own live-row projection. -/
def Snapshot.foldRangeAt (snapshot : Snapshot) (ref : Ref) (range : KeyRange)
    (consume : α → Row → IO α) (initial : α) : IO α := do
  -- As in point lookup, an unchecked head cannot certify an empty result.
  let loaded ← snapshot.load ref
  unless range.overlaps ref do return initial
  match loaded.page with
  | .leaf rows => (range.select rows).foldlM consume initial
  | .branch children =>
      let mut result := initial
      for child in children do
        -- Child fences come from this checksum-checked directory page.
        if range.overlaps child then
          if _smaller : child.height < ref.height then
            result ← snapshot.foldRangeAt child range consume result
          else throw (IO.userError "range index height did not decrease")
      pure result
termination_by ref.height

def Snapshot.foldRange (snapshot : Snapshot) (range : KeyRange)
    (consume : α → Row → IO α) (initial : α) : IO α := do
  let tracing := (← snapshot.trace.get).any (·.complete)
  if !tracing then
    match snapshot.head.root with
    | none => pure initial
    | some ref => snapshot.foldRangeAt ref range consume initial
  else
    let captured ← IO.mkRef (some ([], 0) : Option (List Row × Nat))
    let collect := fun (state : α) (row : Row) => do
      captured.modify fun previous => previous.bind fun (rows, size) =>
        let size := size + rowCodec.encodedSize row
        if size ≤ readTraceAllowance then some (row :: rows, size) else none
      consume state row
    let result ← match snapshot.head.root with
      | none => pure initial
      | some ref => snapshot.foldRangeAt ref range collect initial
    match ← captured.get with
    | some (rows, _) => snapshot.observe (.range range.lower range.upper rows.reverse)
    | none => snapshot.trace.modify (·.map fun _ => { complete := false })
    pure result

def decodeBlob (bytes : ByteArray) : Except String Blob := do
  let (blob, tail) ← blobCodec.decode bytes.toList
  unless tail.isEmpty do throw "trailing bytes in body descriptor"
  unless (blobCodec.encode blob).toByteArray == bytes do throw "noncanonical body descriptor"
  pure blob

def Snapshot.readPinnedBlob (snapshot : Snapshot) (pinned : PinnedBlob snapshot.head) :
    IO ByteArray := do
  let blob := pinned.ref
  let count : FileSystem.ReadSize := ⟨blob.bytes, pinned.bounded⟩
  let bytes ← FileSystem.readPage snapshot.handle blob.offset.toUInt64 count
  unless bytes.size == blob.bytes && digest bytes == blob.checksum do
    throw (IO.userError "corrupted or truncated body chunk")
  snapshot.reads.modify (· + 1)
  snapshot.readBytes.modify (· + bytes.size)
  snapshot.observe (.blob blob)
  pure bytes

def Snapshot.readBlob (snapshot : Snapshot) (blob : Blob) : IO ByteArray := do
  let some pinned := blob.pin? snapshot.head |
    throw (IO.userError "body chunk is outside its pinned extent or exceeds its budget")
  snapshot.readPinnedBlob pinned

/-- Disabling capture uses a separate observer, never a mutable toggle on a
reader shared with another calculation. Physical IO counters remain shared. -/
structure QuietReader (origin : Snapshot) where
  snapshot : Snapshot
  sameDirectory : snapshot.directory = origin.directory
  sameHead : snapshot.head = origin.head
  sameHandle : snapshot.handle = origin.handle
  sameCounts : snapshot.reads = origin.reads ∧ snapshot.readBytes = origin.readBytes

def QuietReader.make (origin : Snapshot) : IO (QuietReader origin) := do
  let trace ← IO.mkRef (none : Option ReadTrace)
  pure ⟨{origin with trace}, rfl, rfl, rfl, rfl, rfl⟩

structure HistoryReader (origin : Snapshot) (basis : Head) where
  snapshot : Snapshot
  pinned : snapshot.head = basis
  sameHandle : snapshot.handle = origin.handle
  sameIdentity : origin.head.identity = basis.identity
  retained : basis.bytes ≤ origin.head.bytes

def HistoryReader.make? (origin : Snapshot) (basis : Head) :
    IO (Option (HistoryReader origin basis)) := do
  if valid : origin.head.identity = basis.identity ∧ origin.head.authority = basis.authority ∧
      basis.revision ≤ origin.head.revision ∧ magic.size ≤ basis.bytes ∧
      basis.bytes ≤ origin.head.bytes then
    let trace ← IO.mkRef (none : Option ReadTrace)
    pure (some ⟨{origin with head := basis, trace}, rfl, rfl, valid.1, valid.2.2.2.2⟩)
  else pure none

def HistoryReader.retainBlob {origin : Snapshot} {basis : Head} (reader : HistoryReader origin basis)
    (pinned : PinnedBlob basis) : PinnedBlob origin.head :=
  ⟨pinned.ref, pinned.nonempty, pinned.bounded, pinned.afterMagic,
    Nat.le_trans pinned.committed reader.retained⟩

theorem HistoryReader.retains_exact_reference {origin : Snapshot} {basis : Head}
    (reader : HistoryReader origin basis)
    (pinned : PinnedBlob basis) : (reader.retainBlob pinned).ref = pinned.ref := rfl

def payloadChunkKey (payloadKey : String) (chunk : Nat) : String := payloadKey ++ ":" ++ toString chunk

def payloadSize (row : Option ByteArray) : Except String Nat := do
  let some bytes := row | throw "missing node byte count"
  let (size, tail) ← Wire.natural.decode bytes.data.toList
  if tail = [] ∧ (Wire.natural.encode size).toByteArray = bytes then pure size
  else throw "trailing or noncanonical node byte count"

/-- A constant-size dependency names its complete ordered read program. The
old root keeps the original descriptors, including all chunk checksums. -/
def Snapshot.readPayloadUsing (snapshot : Snapshot) (read : String → IO (Option ByteArray))
    (payloadKey : String) : IO ByteArray := do
  let size ← IO.ofExcept (payloadSize (← read payloadKey))
  let mut bytes := ByteArray.empty
  for chunk in [:((size + 4095) / 4096)] do
    let some encoded ← read (payloadChunkKey payloadKey chunk) |
      throw (IO.userError "missing node chunk")
    let part ← snapshot.readBlob (← IO.ofExcept (decodeBlob encoded))
    unless part.size == min 4096 (size - chunk * 4096) do
      throw (IO.userError "invalid node chunk size")
    bytes := bytes ++ part
  pure bytes

def Snapshot.readPayload (snapshot : Snapshot) (payloadKey : String) : IO ByteArray := do
  let quiet ← QuietReader.make snapshot
  let bytes ← quiet.snapshot.readPayloadUsing quiet.snapshot.get payloadKey
  snapshot.observe (.payload payloadKey bytes.size ((bytes.size + 4095) / 4096))
  pure bytes

/-- Short-circuit validation is the complete ordered chunk domain. The
runtime recursion keeps no list of chunk positions or descriptors. -/
def checkPayloadChunks (check : Nat → IO Bool) (first : Nat) : Nat → IO Bool
  | 0 => pure true
  | count + 1 => do
      if ← check first then checkPayloadChunks check (first + 1) count else pure false

theorem checkPayloadChunks_full_domain (check : Nat → IO Bool) (first count : Nat) :
    checkPayloadChunks check first count = (List.range' first count).allM check := by
  induction count generalizing first with
  | zero => simp [checkPayloadChunks]
  | succ count ih => simp [checkPayloadChunks, List.range'_succ, ih]

/-- The observer cannot invent a completed comparison or an empty failing
prefix. Only the actual ordered checker constructs this consumption result. -/
structure CheckedPrefix (count : Nat) where
  checked : Nat
  accepted : Bool
  bounded : checked ≤ count
  complete : accepted = true → checked = count
  stopped : accepted = false → 0 < checked

/-- Tail recursion retains one position counter, never a chunk/position list
or one return frame per consumed chunk. The erased equality ties the counter
to the remaining domain in every executed recursive call. -/
def checkPrefixLoop (check : Nat → IO Bool) (first total checked : Nat) :
    (remaining : Nat) → (exact : checked + remaining = total) → IO (CheckedPrefix total)
  | 0, exact => pure ⟨checked, true, by omega, fun _ => by omega, by simp⟩
  | remaining + 1, exact => do
      if ← check (first + checked) then
        checkPrefixLoop check first total (checked + 1) remaining (by omega)
      else pure ⟨checked + 1, false, by omega, by simp, fun _ => by omega⟩

def checkPrefix (check : Nat → IO Bool) (first count : Nat) : IO (CheckedPrefix count) :=
  checkPrefixLoop check first count 0 count (by omega)

/- IO's EST representation has no library LawfulMonad instance. Establish
these laws from its actual state/error operations, locally to this refinement;
no callback is assumed pure and no effect or exception is erased. -/
private theorem lawfulIO : LawfulMonad IO := .mk'
  (id_map := fun x => funext fun s => by
    change EST.bind x (fun a => EST.pure (id a)) s = x s
    simp only [EST.bind]
    cases x s <;> rfl)
  (pure_bind := fun _ _ => rfl)
  (bind_assoc := fun x f g => funext fun s => by
    change EST.bind (EST.bind x f) g s = EST.bind x (fun a => EST.bind (f a) g) s
    simp only [EST.bind]
    cases x s <;> rfl)
  (map_const := fun _ _ => rfl)

theorem checkPrefixLoop_exact (check : Nat → IO Bool) (first total checked remaining : Nat)
    (exact : checked + remaining = total) :
    (fun result => result.accepted) <$> checkPrefixLoop check first total checked remaining exact =
      checkPayloadChunks check (first + checked) remaining := by
  letI := lawfulIO
  induction remaining generalizing checked with
  | zero => simp [checkPrefixLoop, checkPayloadChunks]
  | succ remaining ih =>
      simp only [checkPrefixLoop, checkPayloadChunks, map_bind]
      congr 1
      funext accepted
      cases accepted <;> simp [ih, Nat.add_assoc]

theorem checkPrefix_exact (check : Nat → IO Bool) (first count : Nat) :
    (fun result => result.accepted) <$> checkPrefix check first count =
      (List.range' first count).allM check := by
  rw [checkPrefix, checkPrefixLoop_exact]
  simpa using checkPayloadChunks_full_domain check first count

structure PayloadPrefix (bytes : Nat) where
  chunks : Nat
  bounded : chunks ≤ (bytes + 4095) / 4096

def PayloadPrefix.check? (bytes chunks : Nat) : Option (PayloadPrefix bytes) :=
  if bounded : chunks ≤ (bytes + 4095) / 4096 then some ⟨chunks, bounded⟩ else none

theorem PayloadPrefix.outside_rejected (bytes chunks : Nat)
    (outside : (bytes + 4095) / 4096 < chunks) : PayloadPrefix.check? bytes chunks = none := by
  simp [check?, show ¬chunks ≤ (bytes + 4095) / 4096 by omega]

def Snapshot.checkPayload? (snapshot : Snapshot) (basis : Head)
    (payloadKey : String) (size chunks : Nat) : IO Bool := do
  let some domain := PayloadPrefix.check? size chunks | return false
  let some history ← HistoryReader.make? snapshot basis | return false
  let quiet ← QuietReader.make snapshot
  let old := history.snapshot
  let now := quiet.snapshot
  let expected := some (Wire.natural.encode size).toByteArray
  if (← old.get payloadKey) != expected || (← now.get payloadKey) != expected then return false
  checkPayloadChunks (fun chunk => do
    let before ← old.get (payloadChunkKey payloadKey chunk)
    let after ← now.get (payloadChunkKey payloadKey chunk)
    unless before == after do return false
    let some encoded := before | return false
    let ref ← IO.ofExcept (decodeBlob encoded)
    let some pinned := ref.pin? basis |
      throw (IO.userError "body chunk is outside its pinned extent or exceeds its budget")
    let retained : PinnedBlob now.head := quiet.sameHead.symm ▸ history.retainBlob pinned
    let part ← now.readPinnedBlob retained
    pure (part.size == min 4096 (size - chunk * 4096))) 0 domain.chunks

structure RangeProgress (expected : List Row) where
  seen : List Row
  remaining : List Row
  exact : seen.reverse ++ remaining = expected

def RangeProgress.start (expected : List Row) : RangeProgress expected := ⟨[], expected, rfl⟩

/-- A streaming range certificate cannot skip, duplicate or reorder a row.
An extra row, including the first new row in a previously empty interval,
is rejected before the rest of that interval can be loaded. -/
def RangeProgress.step? (progress : RangeProgress expected) (row : Row) :
    Option (RangeProgress expected) :=
  match rest : progress.remaining with
  | [] => none
  | head :: tail =>
      if same : head = row then
        some ⟨row :: progress.seen, tail, by
          simpa only [List.reverse_cons, List.append_assoc, List.singleton_append, ← same, ← rest]
            using progress.exact⟩
      else none

def RangeProgress.finish? (progress : RangeProgress expected) :
    Option { rows : List Row // rows = expected } :=
  if done : progress.remaining = [] then
    some ⟨progress.seen.reverse, by simpa only [done, List.append_nil] using progress.exact⟩
  else none

theorem RangeProgress.unexpected_rejected (progress : RangeProgress expected) (row : Row)
    (unexpected : progress.remaining.head? ≠ some row) : progress.step? row = none := by
  unfold step?
  split
  · rfl
  · rename_i head tail rest
    have different : head ≠ row := by
      intro same
      simp [rest, same] at unexpected
    simp only [dif_neg different]

/-- Demand validation short-circuits at the first changed row. A normal new
match is a typed miss, not an IO failure. Invalid pages still fail through
the same checked immutable reader used by the complete range traversal. -/
def Snapshot.checkRangeAt? (snapshot : Snapshot) (ref : Ref) (range : KeyRange)
    (progress : RangeProgress expected) : IO (Option (RangeProgress expected)) := do
  let loaded ← snapshot.load ref
  unless range.overlaps ref do return some progress
  match loaded.page with
  | .leaf rows =>
      let mut progress := progress
      for row in range.select rows do
        let some next := progress.step? row | return none
        progress := next
      pure (some progress)
  | .branch children =>
      let mut progress := progress
      for child in children do
        if range.overlaps child then
          if _smaller : child.height < ref.height then
            let some next ← snapshot.checkRangeAt? child range progress | return none
            progress := next
          else throw (IO.userError "range index height did not decrease")
      pure (some progress)
termination_by ref.height

/-- Every observed point, complete key interval and payload is rechecked on
one immutable current snapshot. Checking a range includes new matches and
absence; checking a blob validates its full bytes and checksum. -/
def Snapshot.checkObservation? (snapshot : Snapshot) (basis : Head) (expected : ReadObservation) :
    IO (Option { observed : ReadObservation // observed = expected }) := do
  let actual ← match expected with
    | .point key _ => pure (.point key (← snapshot.get key))
    | .range lower upper rows =>
        let progress ← match snapshot.head.root with
          | none => pure (some (RangeProgress.start rows))
          | some ref => snapshot.checkRangeAt? ref ⟨lower, upper⟩ (RangeProgress.start rows)
        let some progress := progress | return none
        let some actual := progress.finish? | return none
        pure (.range lower upper actual.val)
    | .blob ref =>
        let _ ← snapshot.readBlob ref
        pure (.blob ref)
    | .payload payloadKey size chunks =>
        unless ← snapshot.checkPayload? basis payloadKey size chunks do return none
        pure (.payload payloadKey size chunks)
  pure (expected.check? actual)

structure VerifiedReads (head basis : Head) (expected : List ReadObservation) where
  sameIdentity : head.identity = basis.identity
  actual : List ReadObservation
  exact : actual = expected

def Snapshot.verifyReadOperations? (snapshot : Snapshot) (basis : Head)
    (sameIdentity : snapshot.head.identity = basis.identity) :
    (expected : List ReadObservation) → IO (Option (VerifiedReads snapshot.head basis expected))
  | [] => pure (some ⟨sameIdentity, [], rfl⟩)
  | expected :: rest => do
      let some head ← snapshot.checkObservation? basis expected | return none
      let some tail ← snapshot.verifyReadOperations? basis sameIdentity rest | return none
      pure (some ⟨sameIdentity, head.val :: tail.actual, by rw [head.property, tail.exact]⟩)

/-- Physical references have meaning only in their original file incarnation.
Store the identity once per source; a foreign DB must be rejected even if an
offset, length, checksum and all body bytes happen to be identical. -/
def Snapshot.verifyReads? (snapshot : Snapshot) (basis : Head)
    (expected : List ReadObservation) : IO (Option (VerifiedReads snapshot.head basis expected)) :=
  if sameIdentity : snapshot.head.identity = basis.identity then
    snapshot.verifyReadOperations? basis sameIdentity expected
  else pure none

theorem foreign_read_identity_rejected (snapshot : Snapshot) (basis : Head)
    (expected : List ReadObservation) (different : snapshot.head.identity ≠ basis.identity) :
    snapshot.verifyReads? basis expected = pure none := by
  simp [Snapshot.verifyReads?, different]

/-- Derived query rows have one reserved namespace. The graph publisher's
empty-delta claim is checked against actual writes, including already-flushed
pages. It cannot infer neutrality from an empty remaining pending buffer. -/
def derivedKey (key : String) : Bool := key.startsWith "memo:"

def derivedStep (onlyDerived : Bool) (key : String) : Bool :=
  onlyDerived && derivedKey key

@[simp] theorem derivedStep_false (key : String) : derivedStep false key = false := rfl

/-- The writer only retains this monotone bit; flush does not reset it. The
equivalence covers the complete edit sequence without retaining that sequence
or searching already-written pages at publication time. -/
theorem derived_trace_exact (rows : List Row) (before : Bool) :
    rows.foldl (fun flag row => derivedStep flag row.1) before = true ↔
      before = true ∧ rows.all (fun row => derivedKey row.1) = true := by
  induction rows generalizing before with
  | nil => simp
  | cons head tail ih =>
    rw [List.foldl_cons, ih]
    simp only [derivedStep, Bool.and_eq_true, List.all_cons, and_assoc]

def applyRows (rows : List Row) (before : String → Option ByteArray) : String → Option ByteArray :=
  rows.foldl (fun state row query => if query = row.1 then row.2 else state query) before

/-- The actual row-update algebra, including overwrite and deletion. A
derived-only trace preserves every other key, not just positive graph hits. -/
theorem derived_rows_preserve (rows : List Row) (before : String → Option ByteArray)
    (onlyDerived : rows.all (fun row => derivedKey row.1) = true)
    (key : String) (outside : derivedKey key = false) :
    applyRows rows before key = before key := by
  induction rows generalizing before with
  | nil => rfl
  | cons head tail ih =>
    have parts : derivedKey head.1 = true ∧
        tail.all (fun row => derivedKey row.1) = true := by simpa using onlyDerived
    have permitted := parts.1
    have different : key ≠ head.1 := by
      intro same
      rw [same, permitted] at outside
      cases outside
    simpa only [applyRows, List.foldl_cons, different, ↓reduceIte] using
      ih (fun query => if query = head.1 then head.2 else before query)
        parts.2

theorem derived_trace_preserve (rows : List Row) (before : String → Option ByteArray)
    (accepted : rows.foldl (fun flag row => derivedStep flag row.1) true = true)
    (key : String) (outside : derivedKey key = false) :
    applyRows rows before key = before key :=
  derived_rows_preserve rows before ((derived_trace_exact rows true).mp accepted).2 key outside

structure Writer where
  base : Snapshot
  handle : FileSystem.AppendHandle
  extent : IO.Ref Nat
  written : IO.Ref Nat
  root : IO.Ref (Option Ref)
  failed : IO.Ref Bool
  pending : IO.Ref (Std.TreeMap String (Option ByteArray))
  onlyDerived : IO.Ref Bool
  journalSealed : IO.Ref Bool

/-- Newly appended pages may be read through the same opened file object;
only this writer owns their uncommitted extent. Readers retain the old head. -/
def Writer.snapshot (writer : Writer) : IO Snapshot := do
  pure { writer.base with head := { writer.base.head with bytes := ← writer.extent.get } }

def Writer.appendBlob (writer : Writer) (bytes : ByteArray)
    (_nonempty : 0 < bytes.size) (_bounded : bytes.size ≤ 4096) : IO Blob := do
  if ← writer.failed.get then throw (IO.userError "DB writer requires recovery")
  let blob : Blob := ⟨← writer.extent.get, bytes.size, digest bytes⟩
  try
    FileSystem.appendAt writer.handle blob.offset.toUInt64 bytes
    writer.extent.modify (· + bytes.size)
    writer.written.modify (· + bytes.size)
    pure blob
  catch error => writer.failed.set true; throw error

def Writer.appendPage (writer : Writer) (page : Page) : IO Ref := do
  if ← writer.failed.get then throw (IO.userError "DB writer requires recovery")
  let bytes := encode page
  unless 0 < bytes.size && bytes.size ≤ 65536 do throw (IO.userError "DB page exceeds budget")
  let (first, last, height, rows) ← match page with
    | .leaf rows =>
        let some first := rows.head? | throw (IO.userError "empty leaf")
        let some last := rows.getLast? | throw (IO.userError "empty leaf")
        pure (first.1, last.1, 0, rows.length)
    | .branch refs =>
        let some first := refs.head? | throw (IO.userError "empty branch")
        let some last := refs.getLast? | throw (IO.userError "empty branch")
        pure (first.first, last.last, first.height + 1, (refs.map (·.rows)).sum)
  let ref : Ref := ⟨← writer.extent.get, bytes.size, digest bytes, first, last, height, rows⟩
  unless agrees ref page do throw (IO.userError "invalid page ordering or child heights")
  try
    FileSystem.appendAt writer.handle ref.offset.toUInt64 bytes
    writer.extent.modify (· + bytes.size)
    writer.written.modify (· + bytes.size)
    pure ref
  catch error => writer.failed.set true; throw error

def Writer.leaves (writer : Writer) (rows : List Row) : IO (List Ref) := do
  let page := Page.leaf rows
  if (encode page).size ≤ 8192 then pure [← writer.appendPage page]
  else
    if _splittable : rows.length > 1 then
      let middle := rows.length / 2
      let left ← writer.leaves (rows.take middle)
      let right ← writer.leaves (rows.drop middle)
      pure (left ++ right)
    else throw (IO.userError "one indexed row exceeds page budget; chunk its payload")
termination_by rows.length

/-- Directory fanout is bounded regardless of the number of rows in a batch. -/
def Writer.branches (writer : Writer) (children : List Ref) : IO (List Ref) := do
  if _bounded : children.length ≤ 32 then pure [← writer.appendPage (.branch children)]
  else
    let first ← writer.appendPage (.branch (children.take 32))
    pure (first :: (← writer.branches (children.drop 32)))
termination_by children.length

/-- Linear merge of two unique ordered row lists. Pending edits never
serialize a partially filled leaf once per term or chunk. -/
def lookup (rows : List Row) (key : String) : Option (Option ByteArray) :=
  (rows.find? fun row => row.1 == key).map (·.2)

def mergeRows (newer older : List Row) : List Row :=
  match newer, older with
  | [], rows | rows, [] => rows
  | n :: ns, o :: os =>
      match compare n.1 o.1 with
      | .lt => n :: mergeRows ns (o :: os)
      | .eq => n :: mergeRows ns os
      | .gt => o :: mergeRows (n :: ns) os
termination_by newer.length + older.length

private theorem lookup_cons (row : Row) (rest : List Row) (key : String) :
    lookup (row :: rest) key = if row.1 == key then some row.2 else lookup rest key := by
  by_cases hit : row.1 == key <;> simp [lookup, hit]

private theorem absent_before (rows : List Row) (key : String)
    (before : ∀ row ∈ rows, compare key row.1 = .lt) : lookup rows key = none := by
  unfold lookup
  have absent : rows.find? (fun row => row.1 == key) = none := by
    apply List.find?_eq_none.mpr
    intro row member hit
    have same : row.1 = key := by simpa using hit
    have impossible := before row member
    simp [same] at impossible
  rw [absent]; rfl

/-- Pending edits replace the current row even when the edit removes it.
The nested Option distinguishes a deletion from an absent pending edit. -/
theorem merge_lookup (newer older : List Row)
    (sorted : newer.Pairwise (fun a b => compare a.1 b.1 = .lt)) (key : String) :
    lookup (mergeRows newer older) key = (lookup newer key).or (lookup older key) := by
  induction newer generalizing older with
  | nil => simp [mergeRows, lookup]
  | cons n ns ih =>
    obtain ⟨afterHead, sortedTail⟩ := List.pairwise_cons.mp sorted
    induction older with
    | nil => simp [mergeRows, lookup]
    | cons o os io =>
      rw [mergeRows]
      split
      · rw [lookup_cons, ih _ sortedTail]
        simp only [lookup_cons]
        by_cases hit : n.1 == key <;> simp [hit]
      · rename_i same
        have equal : n.1 = o.1 := compare_eq_iff_eq.mp same
        rw [lookup_cons, ih _ sortedTail]
        simp only [lookup_cons, equal]
        by_cases hit : o.1 == key <;> simp [hit]
      · rename_i before
        have less : compare o.1 n.1 = .lt := Std.OrientedCmp.lt_of_gt before
        have absent : lookup (n :: ns) o.1 = none := absent_before _ _ (by
          intro row member
          rcases List.mem_cons.mp member with equal | member
          · subst row; exact less
          · exact Std.TransCmp.lt_of_lt_of_isLE less (by rw [afterHead row member]; decide))
        rw [lookup_cons, io, lookup_cons o]
        by_cases hit : o.1 == key
        · have equal : o.1 = key := by simpa using hit
          rw [equal] at absent
          simp [hit, absent]
        · simp [hit]

def Writer.putManyAt (writer : Writer) (ref : Ref) (edits : List Row) : IO (List Ref) := do
  if edits.isEmpty then return [ref]
  let snapshot ← writer.snapshot
  match (← snapshot.load ref).page with
  | .leaf rows =>
      unless ordered edits do throw (IO.userError "unordered edit batch")
      let updated := mergeRows edits rows
      if updated == rows then return [ref]
      writer.leaves updated
  | .branch children =>
      let mut updated : List Ref := []
      for (child, index) in children.zipIdx do
        let selected := edits.filter fun edit => (route children edit.1).map (·.1) == some index
        if _smaller : child.height < ref.height then
          updated := updated ++ (← writer.putManyAt child selected)
        else throw (IO.userError "index height did not decrease")
      if updated == children then return [ref]
      writer.branches updated
termination_by ref.height

/-- All roots at this boundary have the same height. Grouping increases the
height while reducing the number of roots, until there is exactly one. -/
def Writer.finishRoots (writer : Writer) (roots : List Ref) : IO Ref := do
  if roots.length ≤ 1 then
    let some root := roots.head? | throw (IO.userError "empty update roots")
    pure root
  else
    let next ← writer.branches roots
    if _decreases : next.length < roots.length then writer.finishRoots next
    else throw (IO.userError "directory grouping did not progress")
termination_by roots.length

def Writer.flush (writer : Writer) : IO Unit := do
  let edits := (← writer.pending.get).toList
  if edits.isEmpty then return
  let roots ← match ← writer.root.get with
    | none => writer.leaves edits
    | some root => writer.putManyAt root edits
  writer.root.set (some (← writer.finishRoots roots))
  writer.pending.set {}

def Writer.put (writer : Writer) (key : String) (value : Option ByteArray) : IO Unit := do
  unless key.toUTF8.size ≤ 1024 do throw (IO.userError "index key exceeds its page budget")
  if ← writer.journalSealed.get then
    throw (IO.userError "index write after the change journal was sealed")
  writer.onlyDerived.modify (derivedStep · key)
  writer.pending.modify (·.insert key value)

def Writer.get (writer : Writer) (key : String) : IO (Option ByteArray) := do
  match (← writer.pending.get)[key]? with
  | some value => pure value
  | none =>
      let snapshot ← writer.snapshot
      ({ snapshot with head := { snapshot.head with root := ← writer.root.get } }).get key

/-- Caller holds the authority's writer guard. Recovery discards only bytes
beyond the currently published extent, never any pinned-reader interval. -/
private def withWriterLocked (snapshot : Snapshot) (action : Writer → IO α) : IO (α × Head × Nat) := do
  let current ← pin snapshot.directory
  unless current.head == snapshot.head do throw (IO.userError "stale DB writer snapshot")
  let handle ← FileSystem.openAppend (dataPath snapshot.directory snapshot.head).toString
  try
    let actual ← FileSystem.readVersion snapshot.handle
    if actual.bytes > snapshot.head.bytes then
      FileSystem.truncateAppend handle actual.bytes.toUInt64 snapshot.head.bytes.toUInt64
    let writer : Writer := ⟨snapshot, handle, ← IO.mkRef snapshot.head.bytes,
      ← IO.mkRef 0, ← IO.mkRef snapshot.head.root, ← IO.mkRef false, ← IO.mkRef {},
      ← IO.mkRef true, ← IO.mkRef false⟩
    let result ← action writer
    writer.flush
    if ← writer.failed.get then throw (IO.userError "failed DB update cannot publish")
    let root ← writer.root.get
    if root == snapshot.head.root then return (result, snapshot.head, 0)
    let bytes ← writer.extent.get
    let head : Head := { snapshot.head with
      root := root
      bytes := bytes
      revision := snapshot.head.revision + 1 }
    let header := (toJson head).compress.toUTF8
    unless header.size ≤ 16384 do throw (IO.userError "DB head exceeds metadata budget")
    FileSystem.syncAppend handle
    FileSystem.atomicBytes (snapshot.directory / "head") header
    pure (result, head, ← writer.written.get)
  finally FileSystem.closeAppend handle

/-- Ownership is acquired before reading the recovery extent. A raw caller
cannot race another writer's publication and then truncate its committed tail.
Readers hold no writer lock. OS descriptor/lock semantics are native premises. -/
opaque withWriter (snapshot : Snapshot) (action : Writer → IO α) : IO (α × Head × Nat) := do
  let guard ← FileSystem.openRead (snapshot.directory / "writer").toString
  unless ← FileSystem.tryReadLock guard true do throw (IO.userError "DB writer is busy")
  try withWriterLocked snapshot action
  finally FileSystem.unlockRead guard

/-- Creation uses stable random authority identity, independent of placement.
There is no regular-file compatibility fallback. -/
def create (directory : System.FilePath) (authority : String) : IO Snapshot := do
  let directory ← absolute directory
  if (← FileSystem.symlinkMetadata? directory).isSome then
    throw (IO.userError "memory DB already exists")
  let parent := directory.parent.getD "/"
  FileSystem.durableDirectory parent
  let temporary := parent / s!".eggshell-create-{← IO.Process.getPID}-{← IO.monoNanosNow}"
  if (← FileSystem.symlinkMetadata? temporary).isSome then throw (IO.userError "DB creation temporary exists")
  FileSystem.durableDirectory temporary
  try
    let head : Head := ⟨Blake3.hex (← IO.getRandomBytes 32), authority, 0, magic.size, none⟩
    FileSystem.immutableBytes (dataPath temporary head) magic
    FileSystem.immutableBytes (temporary / "writer") ByteArray.empty
    let header := (toJson head).compress.toUTF8
    unless header.size ≤ 16384 do throw (IO.userError "DB head exceeds metadata budget")
    FileSystem.immutableBytes (temporary / "head") header
    FileSystem.publishDirectory temporary.toString directory.toString
  finally
    if (← FileSystem.symlinkMetadata? temporary).isSome then IO.FS.removeDirAll temporary
  pin directory

end Eggshell.DB.PageMap
