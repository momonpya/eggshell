module

public import Eggshell.PluginModel
public import Eggshell.SearchProvider

@[expose] public section

namespace Eggshell.Warm
open Lean

structure Checkpoint where
  database : String
  provider : String
  revision : Nat
  roots : Nat
  candidates : Nat
  deriving BEq, ToJson, FromJson

def checkpoint (target : Plugin.IndexTarget) (snapshot : DB.PageMap.Snapshot) : IO Checkpoint := do
  pure ⟨snapshot.head.identity, Plugin.indexProviderKey target.command, snapshot.head.revision,
    ← Persistence.Store.getNat snapshot.get "roots", ← Persistence.Store.getNat snapshot.get "candidates"⟩

/-- Root ordinals grow on insertion; the live candidate count also detects
deletion. Derived query/matcher memo writes do not change these source counters. -/
def Checkpoint.sameSources (previous current : Checkpoint) : Bool :=
  previous.database == current.database && previous.provider == current.provider &&
    previous.roots == current.roots && previous.candidates == current.candidates

def checkpointPath (target : Plugin.IndexTarget) (snapshot : DB.PageMap.Snapshot) : System.FilePath :=
  target.indexes snapshot / "warm"

/-- A rebuildable scheduling hint only. Every numerical search still validates
its actual cache records; a cold search invalidates this hint. -/
def required (target : Plugin.IndexTarget) (snapshot : DB.PageMap.Snapshot) : IO Bool := do
  let _ :: "search-provider" :: _ := target.command | return false
  try
    let previous ← (Plugin.readBoundedJson (checkpointPath target snapshot) 65536 : IO Checkpoint)
    pure (!(previous.sameSources (← checkpoint target snapshot)))
  catch _ => pure true

def invalidate (target : Plugin.IndexTarget) (snapshot : DB.PageMap.Snapshot) : IO Unit := do
  let path := checkpointPath target snapshot
  if ← path.pathExists then
    IO.FS.removeFile path
    FileSystem.syncPath (path.parent.getD snapshot.directory).toString true

def mark (target : Plugin.IndexTarget) (snapshot : DB.PageMap.Snapshot) : IO Unit := do
  let sidecar ← DB.Sidecar.prepare target.owner
  let directory ← DB.Sidecar.childDirectory sidecar.indexes (Plugin.indexProviderKey target.command)
  let path := directory / "warm"
  let value ← checkpoint target snapshot
  let previous ← try some <$> (Plugin.readBoundedJson path 65536 : IO Checkpoint) catch _ => pure none
  if previous.any (fun old => old.sameSources value ||
      (old.database == value.database && old.provider == value.provider && old.revision > value.revision)) then return
  FileSystem.atomicExistingBytes path (toJson value).compress.toUTF8

structure Window where
  document : Persistence.Store.SearchDocument
  index : Nat
  key : String

structure Coverage where
  database : DB.Sidecar.Owner
  revision : Nat
  model : String
  windows : Nat
  valid : Nat
  missing : Nat
  invalid : Nat
  deriving ToJson

structure Inspection where
  coverage : Coverage
  needed : List Window

/-- Read the configured numerical cache format without starting the provider.
The DB owner overrides a command's process scratch path, as at indexed search. -/
def options (snapshot : DB.PageMap.Snapshot) (command : List String) : IO SearchProvider.Options := do
  let _ :: "search-provider" :: arguments := command |
    throw (IO.userError "cache inspection requires the Eggshell numerical provider")
  let sidecar := DB.Sidecar.ofSnapshot snapshot
  let parsed ← IO.ofExcept (SearchProvider.parse {
    cache := sidecar.semantic, models := (MiniLM.layout (← Paths.installRoot)).models } arguments)
  if parsed.mode == "lexical" then
    throw (IO.userError "lexical-only providers do not maintain numerical window caches")
  pure {parsed with cache := sidecar.semantic, owner := some (DB.Sidecar.Owner.ofSnapshot snapshot)}

/-- Each live window key is counted once per owning DB. Stale cache records
and query vectors do not enter the denominator. No source body is read. -/
def inspect (snapshot : DB.PageMap.Snapshot) (options : SearchProvider.Options) : IO Inspection := do
  let mut seen : Std.HashSet String := {}
  let mut needed := []
  let mut valid := 0
  let mut missing := 0
  let mut invalid := 0
  for document in ← Persistence.Store.searchDocuments snapshot do
    for (key, index) in document.windows.zipIdx do
      if seen.contains key then continue
      seen := seen.insert key
      let path := options.cache / "vectors" /
        (SearchProvider.windowCacheKey options.model key ++ ".json")
      if (← FileSystem.symlinkMetadata? path).isNone then
        missing := missing + 1
        needed := ⟨document, index, key⟩ :: needed
      else
        let usable ← try
          let _ ← SearchProvider.indexedVectors options [key]
          pure true
        catch _ => pure false
        if usable then valid := valid + 1
        else
          invalid := invalid + 1
          needed := ⟨document, index, key⟩ :: needed
  pure {
    coverage := {
      database := DB.Sidecar.Owner.ofSnapshot snapshot, revision := snapshot.head.revision
      model := options.model, windows := seen.size, valid, missing, invalid }
    needed := needed.reverse }

structure Result where
  before : Coverage
  after : Coverage
  requested : Nat
  batches : Nat
  elapsedMs : Nat
  deriving ToJson

/-- Explicit CLI work, never called by a cold search hook. Hydrate only the
missing original windows, in bounded batches, and require exact ACKs. A failed
batch leaves its completed cache writes available to a subsequent invocation. -/
def run (snapshot : DB.PageMap.Snapshot) (command : List String) : IO Result := do
  let started ← IO.monoMsNow
  let settings ← options snapshot command
  let target ← Plugin.registerIndexTarget snapshot command
  let before ← inspect snapshot settings
  if before.needed.isEmpty then
    mark target snapshot
    return ⟨before.coverage, before.coverage, 0, 0, (← IO.monoMsNow) - started⟩
  DB.Sidecar.withIndexClaim (DB.Sidecar.Owner.ofSnapshot snapshot) fun _ => do
    -- Another indexer may have filled the difference before this claim.
    let current ← inspect snapshot settings
    let batches ← if current.needed.isEmpty then pure 0 else
      SemanticMatcher.withIndexProvider command fun running => do
        let mut remaining := current.needed
        let mut batches := 0
        while !remaining.isEmpty do
          let batch := remaining.take 32
          remaining := remaining.drop 32
          let items ← batch.mapM fun window => do
            let text ← Persistence.Store.readSearchWindow snapshot window.document window.index
            pure ({id := window.key, text} : SemanticMatcher.Item)
          let _ ← SemanticMatcher.indexWindows running items (DB.Sidecar.Owner.ofSnapshot snapshot)
          batches := batches + 1
        pure batches
    let after ← inspect snapshot settings
    unless after.needed.isEmpty do throw (IO.userError "provider acknowledged windows without valid DB cache records")
    mark target snapshot
    pure ⟨before.coverage, after.coverage, current.needed.length, batches, (← IO.monoMsNow) - started⟩

end Eggshell.Warm
