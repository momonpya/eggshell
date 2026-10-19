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

def Sidecar.prepare (owner : Sidecar.Owner) (storage : Sidecar.Storage := .database) : IO Sidecar := do
  let snapshot ← owner.pin
  let directory ← if storage == .database then do
      let derived ← Sidecar.childDirectory snapshot.directory "derived"
      Sidecar.childDirectory derived snapshot.head.identity
    else do
      let root := (← Paths.dataRoot) / "read-cache"
      FileSystem.rejectSymlinkAncestors root
      FileSystem.privateDirectory root
      Sidecar.childDirectory root snapshot.head.identity
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
