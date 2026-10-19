module

public import Eggshell.DB.PageMap

@[expose] public section

namespace Eggshell.DB

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

/-- Create one child, never missing ancestors or the DB itself. -/
def Sidecar.childDirectory (parent : System.FilePath) (name : String) : IO System.FilePath := do
  let path := parent / name
  FileSystem.rejectSymlinkAncestors path
  let created ← try IO.FS.createDir path; pure true
    catch error => do
      let metadata ← path.symlinkMetadata
      unless metadata.type == .dir do throw error
      pure false
  if created then
    IO.setAccessRights path {
      user := {read := true, write := true, execution := true}, group := {}, other := {} }
    FileSystem.syncPath path.toString true
    FileSystem.syncPath parent.toString true
  pure path

def Sidecar.prepare (owner : Sidecar.Owner) : IO Sidecar := do
  let snapshot ← owner.pin
  let derived ← Sidecar.childDirectory snapshot.directory "derived"
  let directory ← Sidecar.childDirectory derived snapshot.head.identity
  let semantic ← Sidecar.childDirectory directory "semantic"
  let _ ← Sidecar.childDirectory semantic "vectors"
  let indexes ← Sidecar.childDirectory directory "indexes"
  pure {database := snapshot.head.identity, directory, semantic, indexes}

end Eggshell.DB
