module

public import Eggshell.DB.Sidecar

@[expose] public section
namespace Eggshell.DB
open Lean

def Sidecar.retiredName (name : String) : Bool :=
  match name.splitOn "-" with
  | [".retired", database, nonce] =>
      PageMap.validIdentity database && nonce.length == 32 &&
        nonce.toList.all (fun c => ('0' ≤ c && c ≤ '9') || ('a' ≤ c && c ≤ 'f'))
  | _ => false

/-- Missing, replaced owners are dead. An unreadable DB or incomplete ownership
record cannot establish death, and retains the entire rebuildable overlay. -/
def Sidecar.cacheOwners (directory : System.FilePath) : IO (List IO.FS.DirEntry) := do
  let owners := directory / "owners"
  if (← FileSystem.symlinkMetadata? owners).isNone then return []
  FileSystem.rejectSymlinkAncestors owners
  pure (((← owners.readDir).toList.filter (·.fileName.endsWith ".json")).mergeSort
    (fun a b => a.fileName ≤ b.fileName))

def Sidecar.ownerLive (entry : IO.FS.DirEntry) (database : String) : IO Bool := do
  let bytes ← FileSystem.boundedBytes entry.path 65536
  let some text := String.fromUTF8? bytes | throw (IO.userError "invalid cache owner encoding")
  let owner ← IO.ofExcept (Json.parse text >>= (fromJson? : Json → Except String Sidecar.Owner))
  unless owner.database == database && entry.fileName == owner.routeKey ++ ".json" &&
      (System.FilePath.mk owner.directory).isAbsolute do
    throw (IO.userError "cache owner disagrees with its DB directory")
  if let some snapshot ← PageMap.open? (.mk owner.directory) then
    return snapshot.head.identity == database
  pure false

/-- Incrementally retire dead routes while holding the registry exclusively.
Keep a last checked route until the whole directory is atomically retired. -/
def Sidecar.ownersGone (directory : System.FilePath) (database : String) (deadline : Nat) : IO Bool := do
  let entries ← Sidecar.cacheOwners directory
  if entries.isEmpty then return false
  let mut remaining := entries.length
  for (entry, index) in entries.zipIdx do
    if index ≥ 64 || (← IO.monoMsNow) ≥ deadline then return false
    if ← Sidecar.ownerLive entry database then return false
    if remaining > 1 then
      IO.FS.removeFile entry.path
      remaining := remaining - 1
  pure true

/-- The registry claim fences new copy registrations. An existing index lease
also fences retirement, without waiting for or cancelling background work. -/
def Sidecar.retireCache (directory : System.FilePath) (database : String) (deadline : Nat) :
    IO (Option System.FilePath) := do
  -- Most live roots need no exclusive claim. An inconclusive probe is
  -- rechecked under the claim, which also makes progress on old dead routes.
  let entries ← Sidecar.cacheOwners directory
  if entries.isEmpty then return none
  for entry in entries.take 4 do
    if (← IO.monoMsNow) ≥ deadline then return none
    if ← Sidecar.ownerLive entry database then return none
  let result ← Sidecar.withCacheClaim true do
    if (← FileSystem.symlinkMetadata? directory).isNone then return none
    let path := directory / "index.guard"
    let lease ← if (← FileSystem.symlinkMetadata? path).isSome then
        some <$> FileSystem.openRead path.toString
      else pure none
    if let some lease := lease then
      unless ← FileSystem.tryReadLock lease true do return none
    try
      unless ← Sidecar.ownersGone directory database deadline do return none
      if (← IO.monoMsNow) ≥ deadline then return none
      let nonce := Blake3.hex (← IO.getRandomBytes 16)
      let retired := directory.withFileName s!".retired-{database}-{nonce}"
      FileSystem.publishDirectory directory.toString retired.toString
      pure (some retired)
    finally
      if let some lease := lease then FileSystem.unlockRead lease
  pure result.join

/-- Only DB-identity directories in the user's derived namespace are considered.
Retired trees take at most 128 entries per step and resume after interruption. -/
def Sidecar.collect (deadline : Nat) : IO Nat := do
  let root := (← Paths.dataRoot) / "read-cache"
  if (← FileSystem.symlinkMetadata? root).isNone then return 0
  FileSystem.rejectSymlinkAncestors root
  let mut removed := 0
  for entry in ((← root.readDir).toList.mergeSort (fun a b => a.fileName ≤ b.fileName)) do
    if (← IO.monoMsNow) ≥ deadline then break
    try
      if (← entry.path.symlinkMetadata).type != .dir then continue
      let target ← if Sidecar.retiredName entry.fileName then pure (some entry.path)
        else if PageMap.validIdentity entry.fileName then
          Sidecar.retireCache entry.path entry.fileName deadline
        else pure none
      if let some target := target then
        if ← FileSystem.pruneDirectory target.toString ⟨128, by decide⟩ then
          removed := removed + 1
    catch error => IO.eprintln s!"Eggshell retained private cache: {error}"
  pure removed

end Eggshell.DB
