module
public import Eggshell.GraphStore
@[expose] public section

namespace Eggshell.MetadataBytes
open Lean DB Persistence.Store

def limit : Nat := 262144

structure Value where
  bytes : ByteArray
  bounded : bytes.size ≤ limit

def checked (bytes : ByteArray) : Except String Value :=
  if bound : bytes.size ≤ limit then .ok ⟨bytes,bound⟩
  else .error "metadata payload exceeds its byte bound"

theorem Value.chunks_bounded (value : Value) : (value.bytes.size+4095)/4096 ≤ 64 := by
  have := value.bounded
  simp only [limit] at this
  omega

/-- Length framing keeps a logical name distinct from another name ending in
a chunk suffix. Only bounded counters and checked Blob descriptors enter rows. -/
def payloadKey (name : String) : String :=
  "memo:payload:" ++ toString name.utf8ByteSize ++ ":" ++ name

theorem payload_key_is_derived (name : String) : PageMap.derivedKey (payloadKey name) = true := by
  simp [payloadKey,PageMap.derivedKey]

theorem chunk_key_is_derived (name : String) (chunk : Nat) :
    PageMap.derivedKey (PageMap.payloadChunkKey (payloadKey name) chunk) = true := by
  simp [payloadKey,PageMap.payloadChunkKey,PageMap.derivedKey,String.append_assoc]

def checkSize (raw : ByteArray) : IO Unit := do
  let size ← IO.ofExcept (PageMap.payloadSize (some raw))
  unless size ≤ limit do throw (IO.userError "metadata payload exceeds its read bound")

def get? (source : PageMap.Snapshot) (name : String) : IO (Option Value) := do
  let key := payloadKey name
  let some root ← source.get key | return none
  checkSize root
  return some (← IO.ofExcept (checked (← source.readPayload key)))

def pending? (writer : PageMap.Writer) (name : String) : IO (Option Value) := do
  let key := payloadKey name
  let some root ← writer.get key | return none
  checkSize root
  let source ← writer.snapshot
  return some (← IO.ofExcept (checked (← source.readPayloadUsing writer.get key)))

/-- One transaction owns both the count and every body descriptor. Rewriting
a smaller header removes obsolete descriptors; old pinned roots remain valid. -/
def put (writer : PageMap.Writer) (name : String) (value : Value)
    (immutable : Bool := false) : IO Bool := do
  unless PageMap.derivedKey name do throw (IO.userError "metadata cannot replace an authority row")
  let previous ← pending? writer name
  if immutable && previous.any (·.bytes != value.bytes) then
    throw (IO.userError "conflicting immutable metadata payload")
  let mut changed := false
  if !previous.any (·.bytes == value.bytes) then
    putPayload writer (payloadKey name) value.bytes
    changed := true
  return changed

end Eggshell.MetadataBytes
