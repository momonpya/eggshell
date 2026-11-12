module
public import Init.System.IO
public import Init.Data.ByteArray
@[expose] public section
namespace Eggshell.OwnedSocket

private opaque Native : Type
@[extern "eggshell_socket_connect"] private opaque connectNative (port : UInt16) : IO Native
@[extern "eggshell_socket_poll"] private opaque pollNative (socket : @& Native) (writing : Bool) : IO Bool
@[extern "eggshell_socket_connected"] private opaque connectedNative (socket : @& Native) : IO Unit
@[extern "eggshell_socket_send"] private opaque sendNative (socket : @& Native)
    (bytes : @& ByteArray) (offset : USize) : IO USize
@[extern "eggshell_socket_receive"] private opaque receiveNative (socket : @& Native) (amount : USize) : IO ByteArray
@[extern "eggshell_socket_close"] private opaque closeNative (socket : @& Native) : IO Unit

/-- The callback's sequential task owns close. A canceller signals that task
and joins it; it never closes a descriptor concurrently or signals a reused FD. -/
structure Connection where
  private mk ::
  private native : Native

def maxFrameBytes : Nat := 8*1024*1024
def chunkBytes : Nat := 65536

def validPort (port : Nat) : Bool := decide (0 < port ∧ port ≤ 65535)
theorem valid_port_bounded (port : Nat) (valid : validPort port = true) :
    0 < port ∧ port ≤ 65535 := of_decide_eq_true valid

def sendStep (size offset count : Nat) : Except String Nat :=
  if offset ≤ size && count ≤ min chunkBytes (size-offset) then .ok (offset+count)
  else .error "socket send exceeded its owned extent"

theorem send_step_bounded (size offset count next : Nat)
    (accepted : sendStep size offset count = .ok next) : offset ≤ next ∧ next ≤ size := by
  unfold sendStep at accepted
  split at accepted
  · rename_i valid
    simp only [Bool.and_eq_true,decide_eq_true_eq] at valid
    have step := Nat.le_trans valid.2 (Nat.min_le_right _ _)
    simp only [Except.ok.injEq] at accepted
    omega
  · contradiction

def ensureLive (deadline : Nat) : IO Unit := do
  if ← IO.checkCanceled then throw (IO.userError "owned socket cancelled")
  unless (← IO.monoMsNow) < deadline do throw (IO.userError "owned socket deadline expired")

private def waitReady (socket : Native) (writing : Bool) (deadline : Nat) : IO Unit := do
  repeat
    ensureLive deadline
    if ← pollNative socket writing then
      ensureLive deadline
      return

@[no_expose] def withConnection (port deadline : Nat) (action : Connection → IO α) : IO α := do
  ensureLive deadline
  unless validPort port do throw (IO.userError "invalid owned socket port")
  let socket ← connectNative port.toUInt16
  try
    waitReady socket true deadline
    connectedNative socket
    let result ← action ⟨socket⟩
    ensureLive deadline
    return result
  finally closeNative socket

private def writeAll (connection : Connection) (bytes : ByteArray) (deadline : Nat) : IO Unit := do
  let mut offset := 0
  while offset < bytes.size do
    ensureLive deadline
    let count ← sendNative connection.native bytes offset.toUSize
    let next ← IO.ofExcept (sendStep bytes.size offset count.toNat)
    if next == offset then waitReady connection.native true deadline
    offset := next

private def readExactly (connection : Connection) (amount deadline : Nat) : IO ByteArray := do
  let mut bytes := ByteArray.emptyWithCapacity amount
  while bytes.size < amount do
    ensureLive deadline
    let part ← receiveNative connection.native (min chunkBytes (amount-bytes.size)).toUSize
    unless part.size ≤ min chunkBytes (amount-bytes.size) do
      throw (IO.userError "socket receive exceeded its owned extent")
    if part.isEmpty then waitReady connection.native false deadline
    else bytes := bytes++part
  return bytes

def frameLength (bytes : ByteArray) : ByteArray :=
  let value := bytes.size.toUInt32
  .mk #[(value >>> 24).toUInt8,(value >>> 16).toUInt8,(value >>> 8).toUInt8,value.toUInt8]

def decodeLength (bytes : ByteArray) : Nat :=
  ((bytes.get! 0).toNat <<< 24) ||| ((bytes.get! 1).toNat <<< 16) |||
    ((bytes.get! 2).toNat <<< 8) ||| (bytes.get! 3).toNat

@[no_expose] def Connection.writeFrame (connection : Connection) (bytes : ByteArray) (deadline : Nat) : IO Unit := do
  unless 0 < bytes.size && bytes.size ≤ maxFrameBytes do throw (IO.userError "owned socket frame exceeds its bound")
  writeAll connection (frameLength bytes) deadline
  writeAll connection bytes deadline

@[no_expose] def Connection.readFrame (connection : Connection) (deadline : Nat) : IO ByteArray := do
  let count := decodeLength (← readExactly connection 4 deadline)
  unless 0 < count && count ≤ maxFrameBytes do throw (IO.userError "owned socket frame exceeds its bound")
  readExactly connection count deadline
end Eggshell.OwnedSocket
