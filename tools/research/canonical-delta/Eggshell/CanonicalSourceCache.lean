module
public import Eggshell.CanonicalSource
@[expose] public section

namespace Eggshell.Synapses.CanonicalSource.Cache
open Lean DB

def implementation : String := Blake3.hex (Blake3.digest "eggshell.canonical-source".toUTF8 [
  (include_str "CanonicalSource.lean").toUTF8,(include_str "CanonicalSourceCache.lean").toUTF8,
  (include_str "SynapseSource.lean").toUTF8,(include_str "SynapseProvenance.lean").toUTF8,
  (include_str "SynapseBuild.lean").toUTF8])

structure Manifest where
  source : PageMap.Head
  implementation : String
  payload : String
  rows : Nat
  statistics : Statistics
  deriving BEq, ToJson, FromJson

def directory (source : PageMap.Snapshot) (storage : Sidecar.Storage) : IO System.FilePath := do
  return (← Sidecar.locate source storage).directory / "canonical-source"

def decode [FromJson α] [ToJson α] (bytes : ByteArray) : IO α := do
  let some text := String.fromUTF8? bytes | throw (IO.userError "invalid canonical source UTF-8")
  let value ← IO.ofExcept (Json.parse text >>= fromJson? (α := α))
  unless (toJson value).compress.toUTF8 == bytes do throw (IO.userError "noncanonical source cache record")
  return value

def manifest? (path : System.FilePath) : IO (Option Manifest) := do
  let file := path / "manifest.json"
  if !(← file.pathExists) then return none
  some <$> (FileSystem.boundedBytes file 131072 >>= decode)

structure Ready where
  metadata : Manifest
  registry : Registry

/-- Ready data is DB-owned and tied to its original source publication and
implementation. Reading never creates a directory or warms a cold DB. -/
def atSource? (source : PageMap.Snapshot) (path : System.FilePath) (metadata : Manifest) : IO (Option Ready) := do
  unless metadata.implementation == implementation && digest metadata.payload &&
      metadata.rows ≤ metadata.statistics.originalRows &&
      metadata.statistics.unsupportedOwners ≤ metadata.statistics.nativeOwners &&
      (← Index.sameSources source metadata.source) do return none
  let bytes ← FileSystem.boundedBytes (path / (metadata.payload ++ ".json")) (32*1024*1024)
  unless Sha256.hex bytes == metadata.payload do throw (IO.userError "canonical source payload digest mismatch")
  let rows ← decode (α := Array StoredRow) bytes
  unless rows.size == metadata.rows do throw (IO.userError "canonical row directory count mismatch")
  return some ⟨metadata,← IO.ofExcept (load source.head.identity rows)⟩

def open? (source : PageMap.Snapshot) (storage : Sidecar.Storage) : IO (Option Ready) := do
  let path ← directory source storage
  let some metadata ← manifest? path | return none
  atSource? source path metadata

/-- Scheduling reads bounded metadata only. Consumption still authenticates
the payload and each original binding through open?. -/
def ready (source : PageMap.Snapshot) : IO Bool := do
  for storage in [.database,.user] do
    try
      let path ← directory source storage
      let some metadata ← manifest? path | continue
      if metadata.implementation == implementation && digest metadata.payload &&
          metadata.rows ≤ metadata.statistics.originalRows &&
          metadata.statistics.unsupportedOwners ≤ metadata.statistics.nativeOwners &&
          (← Index.sameSources source metadata.source) &&
          (← (path / (metadata.payload ++ ".json")).pathExists) then return true
    catch _ => pure ()
  return false

def openShared? (source : PageMap.Snapshot) : IO (Option Ready) := do
  if let some ready ← open? source .database then return some ready
  open? source .user

structure Result where
  mode : String
  metadata : Manifest
  elapsedMs : Nat
  changedOwners : Nat := 0
  hydrated : Nat := 0
  deriving ToJson

/-- Only explicit/background maintenance builds payloads. Publishing a later
manifest is atomic; an old source cannot replace newer ready data. -/
def refresh (source : PageMap.Snapshot) (storage : Sidecar.Storage) : IO Result := do
  let started ← IO.monoMsNow
  if let some ready ← try open? source storage catch _ => pure none then
    return {mode := "warm",metadata := ready.metadata,elapsedMs := (← IO.monoMsNow)-started}
  let path ← directory source storage
  let previous ← try manifest? path catch _ => pure none
  let rebased ← match previous with
    | none => pure none
    | some metadata => do
      let some history ← PageMap.HistoryReader.make? source metadata.source | pure none
      let old ← try atSource? history.snapshot path metadata catch _ => pure none
      match old with
      | none => pure none
      | some old => rebase source metadata.source old.registry metadata.statistics
  let (registry,statistics,mode,changed,hydrated) ← match rebased with
    | some next => pure (next.registry,next.statistics,"publication-delta",next.owners,next.hydrated)
    | none => do
      let (registry,statistics) ← build source
      pure (registry,statistics,"rebuilt",0,0)
  let rows := registry.store
  let bytes := (toJson rows).compress.toUTF8
  unless bytes.size ≤ 32*1024*1024 do throw (IO.userError "canonical source cache exceeds byte bound")
  let metadata : Manifest := ⟨source.head,implementation,Sha256.hex bytes,rows.size,statistics⟩
  Sidecar.withIndexClaim (Sidecar.Owner.ofSnapshot source) (fun sidecar => do
    let current ← (Sidecar.Owner.ofSnapshot source).pin
    unless ← Index.sameSources current source.head 4096 do
      throw (IO.userError "original source changed during canonical preparation")
    let path ← Sidecar.childDirectory sidecar.directory "canonical-source"
    if let some previous ← try manifest? path catch _ => pure none then
      unless previous.source.identity == source.head.identity && previous.source.authority == source.head.authority do
        throw (IO.userError "foreign canonical source publication")
      if previous.source.revision > source.head.revision then
        throw (IO.userError "older source cannot replace a later canonical publication")
    let payload := path / (metadata.payload ++ ".json")
    let existing ← try some <$> FileSystem.boundedBytes payload (32*1024*1024) catch _ => pure none
    if existing.isSome then
      unless existing == some bytes do FileSystem.atomicExistingBytes payload bytes
    else if ← payload.pathExists then FileSystem.atomicExistingBytes payload bytes
    else FileSystem.immutableExistingBytes payload bytes
    FileSystem.atomicExistingBytes (path / "manifest.json") (toJson metadata).compress.toUTF8) storage
  return ⟨mode,metadata,(← IO.monoMsNow)-started,changed,hydrated⟩

end Eggshell.Synapses.CanonicalSource.Cache
