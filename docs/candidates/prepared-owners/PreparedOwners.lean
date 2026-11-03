module

public import Eggshell.SourceDelta

@[expose] public section
namespace Eggshell.PreparedOwners
open Lean DB Persistence.Store

def implementation : String := Sha256.hex ((include_str "PreparedOwners.lean").toUTF8 ++
  (include_str "SourceDelta.lean").toUTF8 ++ (include_str "GraphStore.lean").toUTF8)

/-- A local original location. These integers never assert Work equivalence. -/
structure Original where
  source : Nat
  node : Nat
  ordinal : Nat
  work : Nat
  candidate : Bool
  deriving ToJson, FromJson, BEq, DecidableEq

def Original.before (left right : Original) : Bool :=
  decide (left.source < right.source ∨
    (left.source = right.source ∧ left.ordinal ≤ right.ordinal))

/-- Gaps in source ordinals do not change tie order. The stride belongs to
the captured cut, and is never used as a population or a stable owner id. -/
def Original.rank (original : Original) (stride : Nat) : Nat :=
  original.source*stride+original.ordinal

theorem Original.rank_source_lt (left right : Original) (stride : Nat)
    (bound : left.ordinal < stride) (before : left.source < right.source) :
    left.rank stride < right.rank stride := by
  unfold rank
  calc left.source*stride+left.ordinal < left.source*stride+stride := Nat.add_lt_add_left bound _
       _ = (left.source+1)*stride := by rw [Nat.add_mul]; simp
       _ ≤ right.source*stride := Nat.mul_le_mul_right stride (by omega)
       _ ≤ right.source*stride+right.ordinal := Nat.le_add_right _ _

theorem Original.rank_order (left right : Original) (stride : Nat)
    (leftBound : left.ordinal < stride) (rightBound : right.ordinal < stride) :
    left.rank stride < right.rank stride ↔
      left.source < right.source ∨ (left.source = right.source ∧ left.ordinal < right.ordinal) := by
  constructor
  · intro before
    by_cases less : left.source < right.source
    · exact Or.inl less
    · by_cases same : left.source = right.source
      · exact Or.inr ⟨same, by simpa [rank, same] using before⟩
      · have reversed := rank_source_lt right left stride rightBound (by omega)
        omega
  · rintro (before | ⟨same,before⟩)
    · exact rank_source_lt left right stride leftBound before
    · simpa [rank, same] using Nat.add_lt_add_left before (right.source*stride)

structure Source where
  directory : String
  head : PageMap.Head
  deriving ToJson, FromJson, BEq, DecidableEq

structure Manifest where
  scope : String
  producer : String
  sources : Array Source
  stride : Nat
  deriving ToJson, FromJson, BEq, DecidableEq

/-- The representative remains an immutable byte witness even while dead.
Live originals and their first-source order are maintained separately. -/
structure Entry where
  id : Nat
  representative : Original
  originals : List Original
  terms : List Nat
  deriving ToJson, FromJson, BEq, DecidableEq

def Entry.candidate (entry : Entry) : Bool := entry.originals.any (·.candidate)

def Entry.without (entry : Entry) (source node : Nat) : Entry :=
  {entry with originals := entry.originals.filter fun original =>
    !(original.source == source && original.node == node)}

theorem Entry.without_other (entry : Entry) (source node : Nat) (original : Original)
    (member : original ∈ entry.originals)
    (other : original.source ≠ source ∨ original.node ≠ node) :
    original ∈ (entry.without source node).originals := by
  apply List.mem_filter.mpr
  refine ⟨member,?_⟩
  rcases other with different | different <;> simp [different]

def readJson (snapshot : PageMap.Snapshot) (read : String → IO (Option ByteArray)) (name : String)
    [FromJson α] : IO (Option α) := do
  let some size ← read (key name 0) | return none
  unless (← IO.ofExcept (payloadSize (some size))) ≤ 16*1024*1024 do
    throw (IO.userError "oversized owner-view header")
  let bytes ← readChunks snapshot read name 0
  let some text := String.fromUTF8? bytes | throw (IO.userError "invalid owner-view header encoding")
  some <$> IO.ofExcept (Json.parse text >>= fromJson?)

def writeJson [ToJson α] (writer : PageMap.Writer) (name : String) (value : α) : IO Unit :=
  putChunks writer name 0 (toJson value).compress.toUTF8

def readList (snapshot : PageMap.Snapshot) (read : String → IO (Option ByteArray))
    (tag : String) (id : Nat) : IO (List Nat) := do
  if (← read (key tag id)).isNone then return []
  let bytes ← readChunks snapshot read tag id
  let (ids,tail) ← IO.ofExcept ((Wire.list Wire.natural).decode bytes.toList)
  unless tail.isEmpty && hashDistinct ids == ids do throw (IO.userError "invalid owner-view id list")
  return ids

def writeList (writer : PageMap.Writer) (tag : String) (id : Nat) (ids : List Nat) : IO Unit :=
  putChunks writer tag id ((Wire.list Wire.natural).encode ids).toByteArray

def readEntry (snapshot : PageMap.Snapshot) (read : String → IO (Option ByteArray))
    (id : Nat) : IO Entry := do
  let bytes ← readChunks snapshot read "ownerEntry" id
  let some text := String.fromUTF8? bytes | throw (IO.userError "invalid owner-view entry encoding")
  let entry ← IO.ofExcept (Json.parse text >>= fromJson? (α := Entry))
  unless entry.id == id && entry.originals == entry.originals.mergeSort Original.before &&
      hashDistinct (entry.originals.map fun original => (original.source,original.node)) ==
        entry.originals.map (fun original => (original.source,original.node)) do
    throw (IO.userError "invalid owner-view entry order or original inventory")
  return entry

def writeEntry (writer : PageMap.Writer) (entry : Entry) : IO Unit :=
  putChunks writer "ownerEntry" entry.id (toJson entry).compress.toUTF8

def alias (source node : Nat) : String := key (key "originalOwner" source) node

def readOriginal? (snapshot : PageMap.Snapshot) (slot node : Nat) : IO (Option Original) := do
  if (← snapshot.get (key "outcomeOrdinal" node)).isNone then return none
  let header ← readOutcomeHeader snapshot node
  let ordinal ← getNat snapshot.get (key "member" node)
  let candidate ← snapshot.get (key "candidate" node)
  if let some candidate := candidate then
    unless (← IO.ofExcept (payloadSize (some candidate))) == 1 &&
        (← getNat snapshot.get (key "searchCandidate" ordinal)) == node do
      throw (IO.userError "owner-view candidate lost its original membership")
  return some ⟨slot,node,ordinal,header.work,candidate.isSome⟩

def sourceAt (sources : Array PageMap.Snapshot) (original : Original) : IO PageMap.Snapshot :=
  match sources[original.source]? with
  | some source => pure source
  | none => throw (IO.userError "owner-view original is outside its complete source inventory")

def adjust (writer : PageMap.Writer) (name : String) (before after : Bool) : IO Unit := do
  if before == after then return
  let count ← getNat writer.get name
  if before then
    if count == 0 then throw (IO.userError "owner-view reference count underflow")
    putNat writer name (count-1)
  else putNat writer name (count+1)

/-- Only liveness transitions alter global document frequencies. Removing one
copy of a shared original leaves the other copies and their postings alive. -/
def replace (writer : PageMap.Writer) (before after : Entry) : IO Unit := do
  let wasLive := !before.originals.isEmpty
  let isLive := !after.originals.isEmpty
  adjust writer "liveOwners" wasLive isLive
  adjust writer "liveCandidates" before.candidate after.candidate
  if wasLive != isLive then
    for term in after.terms do
      adjust writer (key "frequency" term) wasLive isLive
      writer.put (key (key "posting" term) after.id)
        (if isLive then some (Wire.natural.encode after.id).toByteArray else none)
  writeEntry writer after

def termsFor (writer : PageMap.Writer) (source : PageMap.Snapshot) (owner : Nat) : IO (List Nat) := do
  let originalTerms ← readList source source.get "ownerTerms" owner
  let intern : Intern := ⟨writer,← IO.mkRef {}⟩
  originalTerms.mapM fun term => do intern.term (← readTerm source source.get term)

def attach (writer : PageMap.Writer) (sources : Array PageMap.Snapshot)
    (original : Original) : IO Unit := do
  let source ← sourceAt sources original
  let digest ← nodeHash source original.node
  let snapshot ← writer.snapshot
  let bucket ← readList snapshot writer.get "ownerBucket" digest
  let mut found := none
  for id in bucket do
    let entry ← readEntry snapshot writer.get id
    let representative ← sourceAt sources entry.representative
    -- Digest agreement only nominates this full structural comparison.
    if ← nodesEqual representative entry.representative.node source original.node then
      found := some entry
      break
  let entry ← match found with
    | some entry => pure entry
    | none => do
      let id ← getNat writer.get "allocatedOwners"
      putNat writer "allocatedOwners" (id+1)
      writeList writer "ownerBucket" digest (bucket++[id])
      pure ⟨id,original,[],← termsFor writer source original.node⟩
  unless entry.originals.all (fun old => old.source != original.source || old.node != original.node) do
    throw (IO.userError "owner-view duplicate attachment")
  let after := {entry with originals := (original::entry.originals).mergeSort Original.before}
  replace writer entry after
  putNat writer (alias original.source original.node) entry.id

structure Result where
  mode : String
  publications : Nat
  changedRoots : Nat
  touchedOwners : Nat
  liveOwners : Nat
  liveCandidates : Nat
  deriving ToJson

def capture (sources : Array PageMap.Snapshot) (scope producer : String) : IO Manifest := do
  unless !scope.isEmpty && scope.toUTF8.size ≤ 1024 && producer == implementation do
    throw (IO.userError "owner-view scope and actual producer identity required")
  let mut rows := #[]
  let mut stride := 1
  for source in sources do
    unless rows.all (fun old : Source => old.head.identity != source.head.identity) do
      throw (IO.userError "owner-view source identity appears twice")
    rows := rows.push ⟨source.directory.toString,source.head⟩
    stride := max stride ((← getNat source.get "roots")+1)
  return ⟨scope,producer,rows,stride⟩

/-- Build/recover outside hooks. A missing or divergent publication chain is
unready, not an empty delta or an implicit whole-project rebuild. -/
def prepare (index : PageMap.Snapshot) (sources : Array PageMap.Snapshot)
    (scope producer : String) : IO (PageMap.Head × Result) := do
  let wanted ← capture sources scope producer
  let previous ← readJson (α := Manifest) index index.get "manifest"
  let mut changed : Array (Nat × List Nat) := #[]
  let mut publications := 0
  for slot in [:sources.size] do
    let some source := sources[slot]? | throw (IO.userError "owner-view source disappeared")
    let ids ← match previous with
      | none => do
        let rows ← directory source "outcome"
        unless rows.length == (← getNat source.get "liveOutcomes") do
          throw (IO.userError "owner-view bootstrap omitted a live original")
        pure (rows.map Prod.snd)
      | some previous => do
        unless previous.scope == scope && previous.producer == producer &&
            previous.sources.size == sources.size do
          throw (IO.userError "owner-view scope, producer or complete source inventory changed")
        let some old := previous.sources[slot]? | throw (IO.userError "owner-view prior source disappeared")
        unless old.directory == source.directory.toString && old.head.identity == source.head.identity &&
            old.head.authority == source.head.authority do
          throw (IO.userError "owner-view source order or authority changed")
        let some delta ← SourceDelta.read? source old.head |
          throw (IO.userError "owner-view publication delta unavailable; explicit recovery required")
        publications := publications+delta.records
        pure delta.owners
    changed := changed.push (slot,ids)
  -- Validate even an empty inventory; no loop may bypass the scope binding.
  if let some old := previous then
    unless old.scope == scope && old.producer == producer && old.sources.size == sources.size do
      throw (IO.userError "owner-view inventory changed")
    if old == wanted then
      return (index.head,⟨"unchanged",0,0,0,← getNat index.get "liveOwners",← getNat index.get "liveCandidates"⟩)
  let ((touched,owners,candidates),head,_) ← PageMap.withWriter index fun writer => do
    let mut touched := 0
    for (slot,ids) in changed do
      let some source := sources[slot]? | throw (IO.userError "owner-view source disappeared before commit")
      for id in ids do
        if let some old ← writer.get (alias slot id) then
          let canonical ← IO.ofExcept (payloadSize (some old))
          let before ← readEntry (← writer.snapshot) writer.get canonical
          unless before.originals.any (fun original => original.source == slot && original.node == id) do
            throw (IO.userError "owner-view alias has no live original")
          replace writer before (before.without slot id)
          writer.put (alias slot id) none
          touched := touched+1
        if let some original ← readOriginal? source slot id then
          attach writer sources original
          touched := touched+1
    writeJson writer "manifest" wanted
    pure (touched,← getNat writer.get "liveOwners",← getNat writer.get "liveCandidates")
  return (head,⟨if previous.isSome then "publication-delta" else "bootstrap",
    publications,(changed.map (·.2.length)).foldl (·+·) 0,touched,owners,candidates⟩)

structure Reader where
  index : PageMap.Snapshot
  sources : Array PageMap.Snapshot
  manifest : Manifest

/-- Admission is header-sized per source; it never enumerates Outcomes,
documents, semantic descendants, topology or original bodies. -/
def open? (index : PageMap.Snapshot) (sources : Array PageMap.Snapshot)
    (scope producer : String) : IO (Option Reader) := do
  if producer != implementation then return none
  let some manifest ← readJson (α := Manifest) index index.get "manifest" | return none
  let expected ← capture sources scope producer
  if manifest != expected then return none
  return some ⟨index,sources,manifest⟩

def Reader.owner? (reader : Reader) (slot node : Nat) : IO (Option Entry) := do
  let some bytes ← reader.index.get (alias slot node) | return none
  let id ← IO.ofExcept (payloadSize (some bytes))
  let entry ← readEntry reader.index reader.index.get id
  unless entry.originals.any (fun original => original.source == slot && original.node == node) do
    throw (IO.userError "owner-view point lookup lost its original")
  return some entry

def Reader.frequency (reader : Reader) (unit : String) : IO Nat := do
  let some term ← findTerm? reader.index reader.index.get unit | return 0
  getNat reader.index.get (key "frequency" term.id)

def Reader.postings (reader : Reader) (unit : String) : IO (List Nat) := do
  let some term ← findTerm? reader.index reader.index.get unit | return []
  let rows ← directory reader.index (key "posting" term.id)
  unless rows.length == (← reader.frequency unit) do
    throw (IO.userError "owner-view frequency differs from complete posting")
  return rows.map Prod.snd

def Reader.counts (reader : Reader) : IO (Nat × Nat) := do
  return (← getNat reader.index.get "liveOwners",← getNat reader.index.get "liveCandidates")

end Eggshell.PreparedOwners
