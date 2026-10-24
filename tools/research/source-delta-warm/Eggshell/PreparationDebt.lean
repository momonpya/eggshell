module
public import Eggshell.DB.Sidecar
public import Eggshell.Receipt

@[expose] public section
namespace Eggshell.PreparationDebt
open Lean DB

/-- Actual cache observations only; a search deadline is not repair debt. -/
inductive Reason where
  | unavailableInput
  deriving BEq, ToJson, FromJson

structure Event where
  database : String
  model : String
  encoder : String
  reason : Reason
  windows : Nat
  deriving ToJson, FromJson

def directory (owner : Sidecar.Owner) (model encoder : String) : IO System.FilePath := do
  unless Receipt.validId owner.database do throw (IO.userError "invalid repair owner")
  return (← Paths.dataRoot) / "repair" / owner.database /
    Sha256.hex (toJson [model,encoder]).compress.toUTF8

/-- Each immutable event has a unique id. Acknowledge only captured ids, so
an event arriving during repair cannot be erased with the old requests.
No query, tool arguments, output text or original path is persisted here. -/
def record (owner : Sidecar.Owner) (model encoder : String) (reason : Reason)
    (windows : Nat) : IO Unit := do
  if windows == 0 then return
  let path ← directory owner model encoder
  FileSystem.privateDirectory path
  let event : Event := ⟨owner.database,model,encoder,reason,windows⟩
  FileSystem.immutableExistingBytes (path / (← Receipt.fresh)) (toJson event).compress.toUTF8

def pending (owner : Sidecar.Owner) (model encoder : String) : IO Bool := do
  let path ← directory owner model encoder
  FileSystem.rejectSymlinkAncestors path
  if (← FileSystem.symlinkMetadata? path).isNone then return false
  return !(← path.readDir).isEmpty

def capture (owner : Sidecar.Owner) (model encoder : String) : IO (List String) := do
  let path ← directory owner model encoder
  FileSystem.rejectSymlinkAncestors path
  if (← FileSystem.symlinkMetadata? path).isNone then return []
  let entries ← path.readDir
  let mut ids := []
  for entry in entries.toList.take 4096 do
    unless Receipt.validId entry.fileName do throw (IO.userError "invalid repair event identity")
    let bytes ← FileSystem.boundedBytes entry.path 2048
    let some text := String.fromUTF8? bytes | throw (IO.userError "invalid repair event encoding")
    let event : Event ← IO.ofExcept (Json.parse text >>= fromJson?)
    unless event.database == owner.database && event.model == model && event.encoder == encoder &&
        event.windows > 0 do throw (IO.userError "foreign or empty repair event")
    ids := entry.fileName :: ids
  return ids

def acknowledge (owner : Sidecar.Owner) (model encoder : String) (ids : List String) : IO Unit := do
  let path ← directory owner model encoder
  for id in ids do
    unless Receipt.validId id do throw (IO.userError "invalid acknowledged repair event")
    let file := path / id
    FileSystem.rejectSymlinkAncestors file
    if (← FileSystem.symlinkMetadata? file).isSome then IO.FS.removeFile file
  if !ids.isEmpty then FileSystem.syncPath path.toString true

theorem different_event_not_acknowledged (captured : List String) (newEvent : String)
    (fresh : newEvent ∉ captured) : captured.contains newEvent = false := by
  apply Bool.eq_false_iff.mpr
  intro present
  exact fresh (List.contains_iff_mem.mp present)

end Eggshell.PreparationDebt
