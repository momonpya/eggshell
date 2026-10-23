import Eggshell.Sha256
import Eggshell.FileSystem

namespace Eggshell.Research.ArtifactHash

private def blocks (state : Array UInt32) (bytes : ByteArray) : Array UInt32 := Id.run do
  let mut state := state
  for index in [:bytes.size/64] do state := Sha256.compress state bytes (index*64)
  return state

private def finish (state : Array UInt32) (tail : ByteArray) (total : Nat) : String := Id.run do
  let mut bytes := tail.push 0x80
  let padding := (64-((bytes.size+8)%64))%64
  for _ in [:padding] do bytes := bytes.push 0
  let bits := total.toUInt64*8
  for index in [:8] do bytes := bytes.push ((bits >>> ((7-index)*8).toUInt64).toUInt8)
  let state := blocks state bytes
  let mut result := ByteArray.empty
  for word in state do
    for index in [:4] do result := result.push ((word >>> ((3-index)*8).toUInt32).toUInt8)
  return Blake3.hex result

/-- The same SHA-256 compression and padding as `Sha256.digest`, with only
one native page and the final padding retained. Reads use the pinned descriptor. -/
def read (handle : FileSystem.ReadHandle) (total : Nat) : IO String := do
  let mut state := Blake3.iv
  let mut offset := 0
  while offset+4096 ≤ total do
    let bytes ← FileSystem.readPage handle offset.toUInt64 ⟨4096,by decide⟩
    unless bytes.size == 4096 do throw (IO.userError "artifact shortened during hashing")
    state := blocks state bytes
    offset := offset+4096
  let count := min 4096 (total-offset)
  let tail ← if count == 0 then pure ByteArray.empty else
    FileSystem.readPage handle offset.toUInt64 ⟨count,Nat.min_le_left _ _⟩
  unless tail.size == count && offset+count == total do
    throw (IO.userError "artifact tail changed during hashing")
  return finish state tail total

/-- Resolve once, read that open file in bounded pages, then recheck both the
descriptor version and current path. A same-size replacement cannot pass. -/
def hex (path : System.FilePath) : IO String := do
  let resolved ← IO.FS.realPath path
  let handle ← FileSystem.openRead resolved.toString
  let before ← FileSystem.readVersion handle
  let digest ← read handle before.bytes
  let after ← FileSystem.readVersion handle
  let current ← FileSystem.readVersion (← FileSystem.openRead resolved.toString)
  unless FileSystem.stableRead before after current before.bytes &&
      (← IO.FS.realPath path) == resolved do
    throw (IO.userError s!"artifact changed while inspecting {path}")
  return digest

end Eggshell.Research.ArtifactHash
