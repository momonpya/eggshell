module

public import Eggshell.DB.PageMap
public import Eggshell.Paths

@[expose] public section

namespace Eggshell.DB

inductive Sidecar.Storage where
  | database
  | user
  deriving Repr, BEq, Lean.ToJson, Lean.FromJson

structure Sidecar.Owner where
  directory : String
  database : String
  deriving Repr, BEq, Lean.ToJson, Lean.FromJson

def Sidecar.Owner.ofSnapshot (snapshot : PageMap.Snapshot) : Sidecar.Owner :=
  ⟨snapshot.directory.toString, snapshot.head.identity⟩

def Sidecar.Owner.pin (owner : Sidecar.Owner) : IO PageMap.Snapshot := do
  let path := System.FilePath.mk owner.directory
  unless path.isAbsolute do throw (IO.userError "DB owner must have an absolute directory")
  let snapshot ← PageMap.pin path
  unless snapshot.head.identity == owner.database do
    throw (IO.userError "numerical work belongs to a different DB incarnation")
  pure snapshot

/-- Rebuildable data belongs to the DB incarnation, outside its page map.
Moving/copying the DB retains it; removing the DB removes it with the owner. -/
structure Sidecar where
  database : String
  directory : System.FilePath
  semantic : System.FilePath
  indexes : System.FilePath

def Sidecar.ofSnapshot (snapshot : PageMap.Snapshot) : Sidecar :=
  let directory := snapshot.directory / "derived" / snapshot.head.identity
  { database := snapshot.head.identity, directory,
    semantic := directory / "semantic", indexes := directory / "indexes" }

def Sidecar.locate (snapshot : PageMap.Snapshot) (storage : Sidecar.Storage) : IO Sidecar := do
  if storage == .database then return Sidecar.ofSnapshot snapshot
  let directory := (← Paths.dataRoot) / "read-cache" / snapshot.head.identity
  pure {
    database := snapshot.head.identity, directory
    semantic := directory / "semantic", indexes := directory / "indexes"}

/-- Create one child, never missing ancestors or the DB itself. -/
def Sidecar.childDirectory (parent : System.FilePath) (name : String) : IO System.FilePath := do
  let path := parent / name
  FileSystem.rejectSymlinkAncestors path
  let created ← try IO.FS.createDir path; pure true
    catch error => do
      let metadata ← try path.symlinkMetadata catch _ => throw error
      unless metadata.type == .dir do throw error
      pure false
  if created then
    IO.setAccessRights path {
      user := {read := true, write := true, execution := true}, group := {}, other := {} }
    FileSystem.syncPath path.toString true
    FileSystem.syncPath parent.toString true
  pure path

def Sidecar.Owner.routeKey (owner : Sidecar.Owner) : String :=
  Blake3.hex (Blake3.digest "eggshell.cache-owner".toUTF8 [(Lean.toJson owner).compress.toUTF8])

/-- Registration shares this short claim; retirement takes it exclusively.
The stable installation guard lives outside every reclaimable DB directory. -/
def Sidecar.withCacheClaim (exclusive : Bool) (action : IO α) : IO (Option α) := do
  let root ← Paths.dataRoot
  FileSystem.rejectSymlinkAncestors root
  FileSystem.privateDirectory root
  let path := root / "cache-owners.guard"
  let guard ← try FileSystem.openRead path.toString catch _ => do
    FileSystem.immutableExistingBytes path ByteArray.empty
    FileSystem.openRead path.toString
  let mut claimed ← FileSystem.tryReadLock guard exclusive
  let admissionDeadline := (← IO.monoMsNow) + 25
  while !claimed && !exclusive && (← IO.monoMsNow) < admissionDeadline do
    IO.sleep 1
    claimed ← FileSystem.tryReadLock guard false
  unless claimed do return none
  try some <$> action
  finally FileSystem.unlockRead guard

def Sidecar.recordOwner (directory : System.FilePath) (owner : Sidecar.Owner) : IO Unit := do
  let routes ← Sidecar.childDirectory directory "owners"
  let path := routes / (owner.routeKey ++ ".json")
  let bytes := (Lean.toJson owner).compress.toUTF8
  unless bytes.size ≤ 65536 do throw (IO.userError "cache owner exceeds metadata bound")
  if let some _ ← FileSystem.symlinkMetadata? path then
    let previous ← FileSystem.boundedBytes path 65536
    if previous == bytes then return
    let parsed : Except String Sidecar.Owner := do
      let some text := String.fromUTF8? previous | throw "invalid cache owner UTF-8"
      Lean.Json.parse text >>= Lean.fromJson?
    if let .ok previous := parsed then
      if previous.database == owner.database && previous.routeKey == owner.routeKey then
        throw (IO.userError "conflicting cache owner digest")
    FileSystem.atomicExistingBytes path bytes
  else FileSystem.immutableExistingBytes path bytes

/-- Reading a shared private overlay registers the currently observed copy.
Only private metadata is written; the shared DB remains read-only. -/
def Sidecar.observe (snapshot : PageMap.Snapshot) : IO Unit := do
  let sidecar ← Sidecar.locate snapshot .user
  if (← FileSystem.symlinkMetadata? sidecar.directory).isNone then return
  let owner := Sidecar.Owner.ofSnapshot snapshot
  let recorded ← Sidecar.withCacheClaim false do
    let _ ← owner.pin
    Sidecar.recordOwner sidecar.directory owner
  unless recorded.isSome do throw (IO.userError "private cache retirement is busy")
  pure ()

def Sidecar.prepare (owner : Sidecar.Owner) (storage : Sidecar.Storage := .database) : IO Sidecar := do
  let snapshot ← owner.pin
  let directory ← if storage == .database then do
      let derived ← Sidecar.childDirectory snapshot.directory "derived"
      Sidecar.childDirectory derived snapshot.head.identity
    else do
      let prepared ← Sidecar.withCacheClaim false do
        let _ ← owner.pin
        let root := (← Paths.dataRoot) / "read-cache"
        FileSystem.rejectSymlinkAncestors root
        FileSystem.privateDirectory root
        let directory ← Sidecar.childDirectory root snapshot.head.identity
        Sidecar.recordOwner directory owner
        pure directory
      let some directory := prepared | throw (IO.userError "private cache retirement is busy")
      pure directory
  let semantic ← Sidecar.childDirectory directory "semantic"
  let _ ← Sidecar.childDirectory semantic "vectors"
  let indexes ← Sidecar.childDirectory directory "indexes"
  pure {database := snapshot.head.identity, directory, semantic, indexes}

/-- A profile grants DB writes explicitly. A filesystem refusal redirects
only rebuildable maintenance to the user's DB-identity-scoped overlay. -/
def Sidecar.destination (owner : Sidecar.Owner) (writable : Bool) :
    IO (Sidecar.Storage × Sidecar) := do
  let _ ← owner.pin
  if !writable then return (.user, ← Sidecar.prepare owner .user)
  try
    let sidecar ← Sidecar.prepare owner
    let probe := sidecar.semantic / "vectors" / (".write-" ++ Blake3.hex (← IO.getRandomBytes 16))
    let handle ← IO.FS.Handle.mk probe .write
    handle.flush
    IO.FS.removeFile probe
    pure (.database, sidecar)
  catch error => match error with
    | .permissionDenied _ _ _ => pure (.user, ← Sidecar.prepare owner .user)
    | _ => throw error

/-- Index and explicit warm share a non-waiting claim; neither takes the DB
writer. An exited owner releases the descriptor lock automatically. -/
def Sidecar.withIndexClaim (owner : Sidecar.Owner) (action : Sidecar → IO α)
    (storage : Sidecar.Storage := .database) : IO α := do
  let sidecar ← Sidecar.prepare owner storage
  let path := sidecar.directory / "index.guard"
  FileSystem.immutableExistingBytes path ByteArray.empty
  let guard ← FileSystem.openRead path.toString
  unless ← FileSystem.tryReadLock guard true do throw (IO.userError "DB indexer is busy")
  try action sidecar
  finally FileSystem.unlockRead guard

end Eggshell.DB
