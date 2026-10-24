module
public import Eggshell.CandidateDomain
@[expose] public section

namespace Eggshell.WorkPostings
open Lean DB Persistence.Store

/-- In-memory postings from the single checked publication domain. These are
nomination metadata; they never manufacture Outcome or completion authority. -/
abbrev Index := Std.HashMap String (List (Nat × Nat))

def build (rows : List CandidateDomain.Row) : Index := Id.run do
  let mut index : Index := {}
  for row in rows do
    for surface in LogicalText.surfaceNames row.text do
      index := index.insert surface ((row.ordinal,row.owner) :: index.getD surface [])
  return index

/-- Original root order is independent of the query's posting order. Duplicate
surface hits contribute one owner, just as the persisted Work surface index. -/
def lookup (index : Index) (surfaces : List String) : List Nat := Id.run do
  let mut found : Std.TreeMap Nat Nat := {}
  for surface in surfaces do
    for (ordinal,owner) in index.getD surface [] do
      found := found.insert ordinal owner
  return found.toList.map Prod.snd

/-- Effect boundaries keep pure index work inside its measured call rather
than letting the compiler move it past adjacent monotonic-clock reads. -/
@[noinline] def prepare (rows : List CandidateDomain.Row) : IO Index := pure (build rows)
@[noinline] def candidates (index : Index) (surfaces : List String) : IO (List Nat) :=
  pure (lookup index surfaces)

def codec := Wire.list (Wire.text.product (Wire.list (Wire.natural.product Wire.natural)))
def implementation := Sha256.hex ((include_str "WorkPostings.lean").toUTF8 ++
  (include_str "LogicalText.lean").toUTF8)

structure Manifest where
  domain : String
  implementation : String
  digest : String
  bytes : Nat
  deriving ToJson, FromJson

def directory (source : Snapshot) (storage : Sidecar.Storage) : IO System.FilePath := do
  return (← CandidateDomain.directory source storage) / "work-postings"

/-- Verify one bounded prepared index against the exact checked source domain.
No Work spelling compilation, original owner reads or writes happen here. -/
def open? (source : Snapshot) (domain : CandidateDomain.Ready) (storage : Sidecar.Storage) :
    IO (Option Index) := do
  let path ← directory source storage
  let record ← FileSystem.boundedBytes (path / "ready.json") 65536
  let record ← IO.ofExcept (Json.parse (((String.fromUTF8? record).getD "")) >>= fromJson? (α := Manifest))
  unless record.domain == domain.metadata.digest && record.implementation == implementation &&
      record.bytes ≤ CandidateDomain.maxBytes do return none
  let bytes ← FileSystem.boundedBytes (path / "postings") CandidateDomain.maxBytes
  unless bytes.size == record.bytes && Sha256.hex bytes == record.digest do
    throw (IO.userError "prepared Work posting digest disagrees")
  let (rows,tail) ← IO.ofExcept (codec.decode bytes.toList)
  unless tail.isEmpty do throw (IO.userError "trailing prepared Work posting bytes")
  let mut index : Index := {}
  for (surface,entries) in rows do
    unless !index.contains surface do throw (IO.userError "duplicate prepared Work surface")
    for (ordinal,owner) in entries do
      let some row := domain.owners[owner]? | throw (IO.userError "foreign prepared Work owner")
      unless row.ordinal == ordinal do throw (IO.userError "prepared Work ordinal disagrees")
    index := index.insert surface entries
  return some index

def openShared? (source : Snapshot) (domain : CandidateDomain.Ready) : IO (Option Index) := do
  for storage in [.database,.user] do
    try
      if let some index ← open? source domain storage then return some index
    catch _ => pure ()
  return none

/-- Scheduling hint only. Every hook still checks the actual packed payload. -/
def ready (source : Snapshot) : IO Bool := do
  for storage in [.database,.user] do
    try
      let some domain ← CandidateDomain.manifest? source storage | continue
      let bytes ← FileSystem.boundedBytes ((← directory source storage) / "ready.json") 65536
      let record ← IO.ofExcept (Json.parse (((String.fromUTF8? bytes).getD "")) >>= fromJson? (α := Manifest))
      if record.domain == domain.digest && record.implementation == implementation &&
          record.bytes ≤ CandidateDomain.maxBytes then return true
    catch _ => pure ()
  return false

structure Result where
  mode : String
  bytes : Nat
  elapsedMs : Nat
  deriving ToJson

/-- Publication/warm maintenance only. Two atomically replaced files keep
the rebuildable index bounded; graph identity and authority are untouched. -/
def refresh (source : Snapshot) (storage : Sidecar.Storage) : IO Result := do
  let started ← IO.monoMsNow
  let some domain ← CandidateDomain.open? source storage |
    throw (IO.userError "prepare the candidate domain before Work postings")
  if (← try open? source domain storage catch _ => pure none).isSome then
    return ⟨"warm",0,(← IO.monoMsNow)-started⟩
  let index ← prepare domain.data.rows
  let rows := index.toList.mergeSort (fun a b => a.1 ≤ b.1)
  let bytes := (codec.encode rows).toByteArray
  unless bytes.size ≤ CandidateDomain.maxBytes do throw (IO.userError "Work postings exceed byte budget")
  let record : Manifest := ⟨domain.metadata.digest,implementation,Sha256.hex bytes,bytes.size⟩
  Sidecar.withIndexClaim (Sidecar.Owner.ofSnapshot source) (fun _ => do
    unless (← CandidateDomain.stamp (← (Sidecar.Owner.ofSnapshot source).pin)) == domain.metadata.stamp do
      throw (IO.userError "source changed while preparing Work postings")
    let parent ← CandidateDomain.directory source storage
    let path ← Sidecar.childDirectory parent "work-postings"
    FileSystem.atomicExistingBytes (path / "postings") bytes
    FileSystem.atomicExistingBytes (path / "ready.json") (toJson record).compress.toUTF8
    return ⟨"prepared",bytes.size,(← IO.monoMsNow)-started⟩) storage

theorem lookup_empty (index : Index) : lookup index [] = [] := rfl

/-- Work postings use exactly the production spelling function, including
native invocation text. No shell command or MCP tool name is filtered here. -/
theorem row_surfaces (row : CandidateDomain.Row) (owner : OutcomeEdge)
    (same : owner.work = .text row.text) :
    Persistence.Store.ownerWorkSurfaces owner = LogicalText.surfaceNames row.text := by
  simp [Persistence.Store.ownerWorkSurfaces,same,Persistence.Store.text?,Value.text,
    String.fromUTF8?,String.toUTF8_eq_toByteArray,row.text.isValidUTF8,String.fromUTF8]

end Eggshell.WorkPostings
