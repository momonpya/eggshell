module

public import Std

@[expose] public section
namespace Eggshell.FileSystem

def privateFile (path : System.FilePath) : IO Unit :=
  IO.setAccessRights path {
    user := { read := true, write := true }, group := {}, other := {} }

def privateDirectory (path : System.FilePath) : IO Unit := do
  IO.FS.createDirAll path
  IO.setAccessRights path {
    user := { read := true, write := true, execution := true }, group := {}, other := {} }

/-- Permission and device failures are not evidence that a file is absent. -/
def symlinkMetadata? (path : System.FilePath) : IO (Option IO.FS.Metadata) := do
  try pure (some (← path.symlinkMetadata))
  catch error => match error with
    | .noFileOrDirectory .. => pure none
    | _ => throw error

def rejectSymlinkAncestors (path : System.FilePath) : IO Unit := do
  let rec visit : Nat → System.FilePath → IO Unit
    | 0, _ => throw (IO.userError s!"authority path is too deep: {path}")
    | fuel + 1, current => do
        if let some metadata ← symlinkMetadata? current then
          if metadata.type == .symlink then
            throw (IO.userError s!"authority path traverses a symbolic link: {current}")
        match current.parent with
        | some parent => if parent == current then pure () else visit fuel parent
        | none => pure ()
  visit (path.toString.length + 1) path.normalize

def regularMetadata? (path : System.FilePath) : IO (Option IO.FS.Metadata) := do
  rejectSymlinkAncestors path
  match ← symlinkMetadata? path with
  | none => pure none
  | some metadata =>
      if metadata.type == .file then pure (some metadata)
      else throw (IO.userError s!"Eggshell authority is not a regular file: {path}")

end Eggshell.FileSystem

namespace Eggshell.FileSystem

/-- OS identity is a validation witness, never a portable memory key. -/
structure ReadVersion where
  stamp : String
  bytes : Nat
  deriving Repr, DecidableEq, BEq

/-- A regular, no-symlink file descriptor. The OS adapter owns its lifetime;
reads use explicit offsets and share neither a cursor nor a global lock. -/
opaque ReadHandle : Type
@[extern "eggshell_read_open"] opaque openRead (path : @& String) : IO ReadHandle
@[extern "eggshell_read_version"] opaque readVersion (handle : @& ReadHandle) : IO ReadVersion
@[extern "eggshell_read_page"] private opaque readPageRaw (handle : @& ReadHandle)
    (offset : UInt64) (count : USize) : IO ByteArray

structure ReadSize where
  bytes : Nat
  bounded : bytes ≤ 4096

/-- The native adapter accepts at most one page. Larger objects must use the
same descriptor in bounded steps; a caller cannot silently exceed this API. -/
opaque readPage (handle : ReadHandle) (offset : UInt64) (count : ReadSize) : IO ByteArray :=
  readPageRaw handle offset count.bytes.toUSize

theorem ReadSize.native_bound (count : ReadSize) : count.bytes ≤ 4096 := count.bounded

/-- An unbuffered, regular-file descriptor for the exclusively owned writer.
The OS adapter checks the expected EOF before writing at explicit offsets.
An IO failure cannot leave a stdio buffer to flush after ownership ends. -/
opaque AppendHandle : Type
@[extern "eggshell_append_open"] opaque openAppend (path : @& String) : IO AppendHandle
@[extern "eggshell_append_write"] opaque appendAt (handle : @& AppendHandle)
    (offset : UInt64) (bytes : @& ByteArray) : IO Unit
@[extern "eggshell_append_sync"] opaque syncAppend (handle : @& AppendHandle) : IO Unit
@[extern "eggshell_append_close"] opaque closeAppend (handle : @& AppendHandle) : IO Unit

/-- Non-waiting advisory reader-cohort guards on securely opened files.
The OS releases these locks on descriptor close, including process death. -/
@[extern "eggshell_read_try_lock"] opaque tryReadLock (handle : @& ReadHandle)
    (exclusive : Bool) : IO Bool
@[extern "eggshell_read_unlock"] opaque unlockRead (handle : @& ReadHandle) : IO Unit

/-- Atomic no-replacement rename of a completed DB directory. Parent
resolution and fsync use held descriptors at the native boundary. -/
@[extern "eggshell_publish_directory"] opaque publishDirectory
    (source target : @& String) : IO Unit

/-- Shrink to the caller's committed boundary iff the descriptor still has the
expected EOF, then fsync. The caller must hold exclusive writer ownership. -/
@[extern "eggshell_append_truncate"] opaque truncateAppend (handle : @& AppendHandle)
    (expectedEnd retainedEnd : UInt64) : IO Unit

/-- The complete bytes must come from the still-current file object. -/
def stableRead (before after current : ReadVersion) (bytes : Nat) : Bool :=
  decide (before = after) && decide (after = current) && decide (bytes = current.bytes)

theorem stable_read_identity {before after current : ReadVersion} {bytes : Nat}
    (accepted : stableRead before after current bytes = true) :
    before = after ∧ after = current ∧ bytes = current.bytes := by
  simpa [stableRead, and_assoc] using accepted

theorem replaced_read_rejected {before after current : ReadVersion} (bytes : Nat)
    (replaced : after ≠ current) : stableRead before after current bytes = false := by
  simp [stableRead, replaced]

theorem mutated_read_rejected {before after current : ReadVersion} (bytes : Nat)
    (mutated : before ≠ after) : stableRead before after current bytes = false := by
  simp [stableRead, mutated]

/-- Native filesystem primitive: Lean does not expose POSIX fsync. -/
@[extern "eggshell_sync_path"] opaque syncPath (path : @& String)
    (directory : Bool) : IO Unit

def directoryWithin : Nat → System.FilePath → IO Unit
  | 0, _ => throw (IO.userError "directory ancestor traversal did not terminate")
  | fuel + 1, path => do
    FileSystem.rejectSymlinkAncestors path
    let existed ← path.isDir
    if !existed then
      if let some parent := path.parent then
        if parent != path && !(← parent.isDir) then directoryWithin fuel parent
      FileSystem.privateDirectory path
      syncPath path.toString true
      if let some parent := path.parent then syncPath parent.toString true

def durableDirectory (path : System.FilePath) : IO Unit :=
  directoryWithin (path.toString.length + 1) path.normalize

/-- The writers and streaming directory readers share one namespace for
objects which have not reached their atomic publication point. -/
inductive PublicationKind where
  | replace
  | immutable
  deriving BEq, DecidableEq, Repr

def publicationTemporary (kind : PublicationKind) (suffix : String) : String :=
  (match kind with | .replace => ".egg-tmp-" | .immutable => ".egg-object-") ++ suffix

def isPublicationTemporary (name : String) : Bool :=
  name.startsWith ".egg-tmp-" || name.startsWith ".egg-object-"

theorem publication_temporary_recognized (kind : PublicationKind) (suffix : String) :
    isPublicationTemporary (publicationTemporary kind suffix) = true := by
  cases kind <;> simp [publicationTemporary, isPublicationTemporary]

private opaque PublicationHandle : Type
@[extern "eggshell_publication_open"] private opaque openPublication
    (path temporary : @& String) : IO PublicationHandle
@[extern "eggshell_publication_write"] private opaque writePublication
    (handle : @& PublicationHandle) (bytes : @& ByteArray) : IO Unit
@[extern "eggshell_publication_sync_data"] private opaque syncPublicationData
    (handle : @& PublicationHandle) : IO Unit
@[extern "eggshell_publication_install"] private opaque installPublication
    (handle : @& PublicationHandle) (immutable : Bool) : IO Bool
@[extern "eggshell_publication_target"] private opaque readPublicationTarget
    (handle : @& PublicationHandle) : IO ReadHandle
@[extern "eggshell_publication_sync_parent"] private opaque syncPublicationParent
    (handle : @& PublicationHandle) : IO Unit
@[extern "eggshell_publication_close"] private opaque closePublication
    (handle : @& PublicationHandle) : IO Unit

/-- One securely opened parent and one exclusively created temporary file.
The indexed phases make the executed write/sync/install order mandatory. OS
descriptor identity, fsync and namespace atomicity remain native premises. -/
private inductive PublicationPhase where
  | opened | written | synced | installed | durable

inductive PublicationBoundary where
  | written | synced | installed | durable
  deriving BEq, DecidableEq, Repr

/-- Agreement is about the same current file object and exact bytes, never
only a name, hash or matching length. This is the immutable collision gate. -/
def publicationAgreement (before after current : ReadVersion)
    (existing expected : ByteArray) : Bool :=
  stableRead before after current existing.size && decide (existing = expected)

theorem publication_agreement_exact {before after current : ReadVersion}
    {existing expected : ByteArray}
    (accepted : publicationAgreement before after current existing expected = true) :
    before = after ∧ after = current ∧ existing = expected ∧ expected.size = current.bytes := by
  have parts : stableRead before after current existing.size = true ∧ existing = expected := by
    simpa [publicationAgreement] using accepted
  obtain ⟨same, now, sized⟩ := stable_read_identity parts.1
  exact ⟨same, now, parts.2, parts.2 ▸ sized⟩

theorem publication_replacement_rejected {before after current : ReadVersion}
    (existing expected : ByteArray) (replaced : after ≠ current) :
    publicationAgreement before after current existing expected = false := by
  simp [publicationAgreement, replaced_read_rejected existing.size replaced]

private structure Publication (path : System.FilePath) (bytes : ByteArray)
    (phase : PublicationPhase) where
  mk ::
  handle : PublicationHandle

private def Publication.write (publication : Publication path bytes .opened) :
    IO (Publication path bytes .written) := do
  writePublication publication.handle bytes
  pure ⟨publication.handle⟩

private def Publication.syncData (publication : Publication path bytes .written) :
    IO (Publication path bytes .synced) := do
  syncPublicationData publication.handle
  pure ⟨publication.handle⟩

private def Publication.install (publication : Publication path bytes .synced)
    (kind : PublicationKind) : IO (Publication path bytes .installed × Bool) := do
  let created ← installPublication publication.handle (kind == .immutable)
  pure (⟨publication.handle⟩, created)

private def Publication.syncParent (publication : Publication path bytes .installed) :
    IO (Publication path bytes .durable) := do
  syncPublicationParent publication.handle
  pure ⟨publication.handle⟩

private def Publication.agree (publication : Publication path bytes .installed) : IO Unit := do
  let target ← readPublicationTarget publication.handle
  let before ← readVersion target
  unless before.bytes == bytes.size do
    throw (IO.userError "immutable object collision or concurrent replacement")
  let mut existing := ByteArray.empty
  while existing.size < bytes.size do
    let count := min 4096 (bytes.size - existing.size)
    let part ← readPage target existing.size.toUInt64 ⟨count, Nat.min_le_left _ _⟩
    unless part.size == count do
      throw (IO.userError "immutable object collision or concurrent replacement")
    existing := existing ++ part
  let after ← readVersion target
  let current ← readVersion (← readPublicationTarget publication.handle)
  unless publicationAgreement before after current existing bytes do
    throw (IO.userError "immutable object collision or concurrent replacement")

private def publishBytes (kind : PublicationKind) (path : System.FilePath)
    (bytes : ByteArray) (observe : PublicationBoundary → IO Unit) : IO Unit := do
  let parent := path.parent.getD "."
  durableDirectory parent
  let temporary := publicationTemporary kind s!"{← IO.Process.getPID}-{← IO.monoNanosNow}"
  let initial : Publication path bytes .opened := ⟨← openPublication path.toString temporary⟩
  try
    let written ← initial.write
    observe .written
    let synced ← written.syncData
    observe .synced
    let (installed, created) ← synced.install kind
    if kind == .immutable && !created then installed.agree
    observe .installed
    let _ ← installed.syncParent
    observe .durable
    pure ()
  finally closePublication initial.handle

opaque atomicBytesWith (path : System.FilePath) (bytes : ByteArray)
    (observe : PublicationBoundary → IO Unit) : IO Unit :=
  publishBytes .replace path bytes observe

def atomicBytes (path : System.FilePath) (bytes : ByteArray) : IO Unit :=
  atomicBytesWith path bytes (fun _ => pure ())

def boundedBytes (path : System.FilePath) (limit : Nat) : IO ByteArray := do
  let handle ← openRead path.toString
  let before ← readVersion handle
  if before.bytes > limit then throw (IO.userError "storage object exceeds byte budget")
  let mut bytes := ByteArray.empty
  while bytes.size < before.bytes do
    let count := min 4096 (before.bytes - bytes.size)
    let part ← readPage handle bytes.size.toUInt64 ⟨count, Nat.min_le_left _ _⟩
    unless part.size == count do throw (IO.userError "truncated storage object")
    bytes := bytes ++ part
  unless (← readVersion handle) == before do throw (IO.userError "storage object mutated during read")
  pure bytes

/-- Atomic create-if-absent: concurrent publishers can agree on existing bytes,
but cannot overwrite them after a failed existence check. -/
opaque immutableBytesWith (path : System.FilePath) (bytes : ByteArray)
    (observe : PublicationBoundary → IO Unit) : IO Unit :=
  publishBytes .immutable path bytes observe

def immutableBytes (path : System.FilePath) (bytes : ByteArray) : IO Unit :=
  immutableBytesWith path bytes (fun _ => pure ())

end Eggshell.FileSystem
