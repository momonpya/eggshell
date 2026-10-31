module
public import Eggshell.CanonicalSourceRecipe
public import tools.research.PreparedSourceView
@[expose] public section

namespace Eggshell.Synapses.CanonicalSource.Cache
open Lean DB Persistence.Store

def implementation : String := Blake3.hex (Blake3.digest "eggshell.canonical-source".toUTF8 [
  (include_str "SourceViewPublication.lean").toUTF8,
  (include_str "PreparedSourceView.lean").toUTF8,
  (include_str "OwnerPalette.lean").toUTF8,
  (include_str "PreparedFileUnits.lean").toUTF8,
  (include_str "PublishedPlanMetadata.lean").toUTF8,
  (include_str "../../Eggshell/CanonicalSource.lean").toUTF8,
  (include_str "../../Eggshell/CanonicalSourceRecipe.lean").toUTF8,
  (include_str "../../Eggshell/CanonicalSourceRecords.lean").toUTF8,
  (include_str "ScopeAlternatives.lean").toUTF8,
  (include_str "ReferenceRequirements.lean").toUTF8])

structure Manifest where
  source : PageMap.Head
  implementation : String
  /-- Identity of the pinned input/producer, not a DB-wide JSON filename. -/
  payload : String
  /-- Owner row bindings; identical payloads may have several real witnesses. -/
  rows : Nat
  statistics : Statistics
  recipes : Option PageMap.Head := none
  bindings : Option PageMap.Head := none
  supplements : Option String := none
  deriving BEq,ToJson,FromJson

/-- The head is supplied by the reader. A header never attempts to contain
its own future PageMap root. Metadata and readiness commit atomically. -/
structure Header where
  source : PageMap.Head
  implementation : String
  payload : String
  rows : Nat
  statistics : Statistics
  bindings : Option PageMap.Head
  supplements : Option String
  deriving ToJson,FromJson

def Header.manifest (header : Header) (root : PageMap.Head) : Manifest :=
  ⟨header.source,header.implementation,header.payload,header.rows,header.statistics,
    some root,header.bindings,header.supplements⟩

def directory (source : PageMap.Snapshot) (storage : Sidecar.Storage) : IO System.FilePath := do
  return (← Sidecar.locate source storage).directory / "canonical-source"

def decode [FromJson α] [ToJson α] (bytes : ByteArray) : IO α := do
  let some text := String.fromUTF8? bytes | throw (IO.userError "invalid canonical view UTF-8")
  let value ← IO.ofExcept (Json.parse text >>= fromJson? (α := α))
  unless (toJson value).compress.toUTF8 == bytes do throw (IO.userError "noncanonical source-view metadata")
  return value

def header? (index : PageMap.Snapshot) : IO (Option Header) := do
  let some descriptor ← index.get "view-header" | return none
  unless (← IO.ofExcept (PageMap.payloadSize (some descriptor))) ≤ 131072 do
    throw (IO.userError "source view header exceeds its bound")
  some <$> (index.readPayload "view-header" >>= decode)

def manifest? (path : System.FilePath) : IO (Option Manifest) := do
  let some index ← PageMap.open? (path / "recipes") | return none
  return (← header? index).map (·.manifest index.head)

def manifestAt? (source : PageMap.Snapshot) (path : System.FilePath) : IO (Option Manifest) := do
  let some index ← PageMap.open? (path / "recipes") | return none
  let some header ← header? index | return none
  if ← Index.sameSources source header.source then return some (header.manifest index.head)
  let some bytes ← index.get (Index.retainedName source.head) | return none
  let metadata ← decode (α := Manifest) bytes
  unless metadata.source == source.head do throw (IO.userError "source view changed its retained input")
  return some metadata

def preparedAt? (source : PageMap.Snapshot) (path : System.FilePath) (metadata : Manifest) :
    IO (Option PageMap.Snapshot) := do
  unless metadata.implementation == implementation && (← Index.sameSources source metadata.source) do return none
  let some root := metadata.recipes | return none
  let some current ← PageMap.open? (path / "recipes") | return none
  let some reader ← PageMap.HistoryReader.make? current root | return none
  let some header ← header? reader.snapshot | return none
  unless header.manifest root == metadata do throw (IO.userError "source view differs from its pinned header")
  return some reader.snapshot

structure Ready where
  metadata : Manifest

def atSource? (source : PageMap.Snapshot) (path : System.FilePath) (metadata : Manifest) : IO (Option Ready) := do
  unless digest metadata.payload && metadata.rows ≤ metadata.statistics.originalRows &&
      metadata.statistics.unsupportedOwners ≤ metadata.statistics.nativeOwners do return none
  return (← preparedAt? source path metadata).map fun _ => ⟨metadata⟩

def open? (source : PageMap.Snapshot) (storage : Sidecar.Storage) : IO (Option Ready) := do
  let path ← directory source storage
  let some metadata ← manifestAt? source path | return none
  let prepared ← Index.open? source storage .shared
  unless metadata.supplements == (← prepared.bindM fun prepared => ContentMetadata.supplementStamp prepared.index) do return none
  atSource? source path metadata

def openShared? (source : PageMap.Snapshot) : IO (Option Ready) := do
  if let some ready ← open? source .database then return some ready
  open? source .user

def ready (source : PageMap.Snapshot) : IO Bool := do
  for storage in [.database,.user] do
    try if (← open? source storage).isSome then return true
    catch _ => pure ()
  return false

structure Result where
  mode : String
  metadata : Manifest
  elapsedMs : Nat
  changedOwners : Nat := 0
  hydrated : Nat := 0
  deriving ToJson

structure OwnerState where
  owner : String
  rows : Nat
  statistics : Statistics
  deriving ToJson,FromJson

def stateName (id : Nat) : String := "view-document:" ++ toString id

structure Totals where
  rows : Nat := 0
  statistics : Statistics := {}
  changed : Nat := 0
  hydrated : Nat := 0

def addStatistics (a b : Statistics) : Statistics :=
  ⟨a.nativeOwners+b.nativeOwners,a.originalRows+b.originalRows,
    a.rejectedRows+b.rejectedRows,a.unsupportedOwners+b.unsupportedOwners⟩

/-- One changed observation is the working set. Bootstrap streams the same
operation over the candidate directory; no all-DB registry or payload exists. -/
def projectOwner (source : PageMap.Snapshot) (prepared : Option PageMap.Snapshot)
    (writer : PageMap.Writer) (delta : Bool)
    (totals : Totals) (id : Nat) : IO Totals := do
  -- Flush the preceding owner's bounded edit batch into the unpublished
  -- tree. Only withWriter publishes a head; readers cannot see these roots.
  writer.flush
  let mut totals := {totals with changed := totals.changed+1}
  if delta then
    let current ← writer.snapshot
    if let some descriptor ← current.get (stateName id) then
      unless (← IO.ofExcept (PageMap.payloadSize (some descriptor))) ≤ 131072 do
        throw (IO.userError "source-view owner state exceeds its bound")
      let previous ← current.readPayload (stateName id) >>= decode (α := OwnerState)
      unless previous.rows ≤ totals.rows do throw (IO.userError "source-view row count underflow")
      totals := {totals with
        rows := totals.rows-previous.rows,
        statistics := ← IO.ofExcept (totals.statistics.subtract previous.statistics)}
      writer.put (Recipe.name previous.owner) none
      writer.put (PreparedSourceView.ownerName previous.owner) none
      writer.put (stateName id) none
  unless (← source.get (key "candidate" id)).isSome do return totals
  unless (← getNat source.get (key "candidate" id)) == 1 do
    throw (IO.userError "source-view projection requires a live candidate")
  let reader ← NodeReader.new source
  let document ← Build.document reader id
  if !document.native then return totals
  let (originals,statistics) ← addPublishedDocument source id document {} {} prepared
  let stored ← IO.ofExcept (Recipe.compile originals.store)
  Recipe.write writer document.owner stored
  PreparedSourceView.publishOwner writer document.owner stored
  for file in hashDistinct (stored.rows.toList.map (·.key.file)) do
    PreparedSourceView.publishFile writer file
  let state : OwnerState := ⟨document.owner,stored.rows.size,statistics⟩
  Persistence.Store.putPayload writer (stateName id) (toJson state).compress.toUTF8
  return {totals with
    rows := totals.rows+stored.rows.size,
    statistics := addStatistics totals.statistics statistics,hydrated := totals.hydrated+1}

def refresh (source : PageMap.Snapshot) (storage : Sidecar.Storage) : IO Result := do
  let started ← IO.monoMsNow
  if let some ready ← open? source storage then
    return {mode := "warm",metadata := ready.metadata,elapsedMs := (← IO.monoMsNow)-started}
  let bindings ← Index.open? source storage .shared
  let prepared := bindings.map (·.index)
  let stamp ← bindings.bindM fun found => ContentMetadata.supplementStamp found.index
  -- The global sidecar claim only creates/opens this projection. Streaming
  -- work owns its PageMap writer and does not block unrelated index workers.
  let (path,index) ← Sidecar.withIndexClaim (Sidecar.Owner.ofSnapshot source) (fun sidecar => do
    let path ← Sidecar.childDirectory sidecar.directory "canonical-source"
    let index ← match ← PageMap.open? (path / "recipes") with
      | some index => pure index
      | none => PageMap.create (path / "recipes") ("canonical-layout:" ++ source.head.identity)
    return (path,index)) storage
  let previous ← (← header? index).mapM fun header => pure (header.manifest index.head)
  if let some previous := previous then
    unless previous.source.identity == source.head.identity && previous.source.authority == source.head.authority &&
        previous.source.revision ≤ source.head.revision do throw (IO.userError "source-view publication would move backwards")
  let changed ← match previous with
    | some previous =>
      if previous.implementation == implementation && previous.supplements == stamp then
        if (← SourceDelta.read? source previous.source).isSome then Build.changes source previous.source else pure none
      else pure none
    | none => pure none
  let delta := changed.isSome
  let initial : Totals := match previous with
    | some previous => if delta then ⟨previous.rows,previous.statistics,0,0⟩ else {}
    | none => {}
  let payload := Sha256.hex (toJson (source.head,implementation,bindings.map (·.index.head),stamp)).compress.toUTF8
  let (totals,root,_) ← PageMap.withWriter index fun writer => do
    if let some previous := previous then
      if previous.source != source.head then
        writer.put (Index.retainedName previous.source) (some (← Index.checkedBytes previous))
    if !delta then
      -- A producer change/bootstrap cannot leave deleted owners from an old
      -- projection visible. Stream retirements in this same atomic commit;
      -- old immutable pins retain their own roots and payloads.
      let _ ← index.foldRange ⟨"view-document:","view-document;"⟩ (fun (count : Nat) row => do
        if row.2.isNone then return count
        let some id := (row.1.drop "view-document:".length).toString.toNat? | return count
        unless row.1 == stateName id do throw (IO.userError "noncanonical owner-state key")
        let previous ← index.readPayload row.1 >>= decode (α := OwnerState)
        writer.put (Recipe.name previous.owner) none
        writer.put (PreparedSourceView.ownerName previous.owner) none
        writer.put row.1 none
        if count % 256 == 255 then writer.flush
        return count+1) 0
      writer.flush
    let totals ← match changed with
      | some changed => changed.owners.toList.foldlM (projectOwner source prepared writer true) initial
      | none => source.foldRange ⟨"searchCandidate:","searchCandidate;"⟩ (fun totals row => do
          if row.2.isNone then return totals
          let some ordinal := (row.1.drop "searchCandidate:".length).toString.toNat? |
            throw (IO.userError "invalid canonical candidate ordinal")
          unless row.1 == key "searchCandidate" ordinal do
            throw (IO.userError "noncanonical source-view candidate key")
          let id ← getNat (fun _ => pure row.2) row.1
          unless (← getNat source.get (key "member" id)) == ordinal do
            throw (IO.userError "source-view candidate changed its membership")
          projectOwner source prepared writer false totals id) initial
    let header : Header := ⟨source.head,implementation,payload,totals.rows,totals.statistics,
      bindings.map (·.index.head),stamp⟩
    Persistence.Store.putPayload writer "view-header" (toJson header).compress.toUTF8
    return totals
  let metadata : Manifest := ⟨source.head,implementation,payload,totals.rows,totals.statistics,
    some root,bindings.map (·.index.head),stamp⟩
  -- A newer raw source does not invalidate a completed older snapshot.
  -- The next publication consumes its remaining exact change feed.
  let _ := path
  return ⟨if delta then "owner-delta" else "owner-stream",metadata,
    (← IO.monoMsNow)-started,totals.changed,totals.hydrated⟩

end Eggshell.Synapses.CanonicalSource.Cache
