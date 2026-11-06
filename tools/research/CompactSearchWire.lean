module
public import Eggshell.OperationWire
public import tools.research.CompactHandoff
@[expose] public section

namespace Eggshell.Plugin.Worker
open Lean
open Research.CompactHandoff (Encoded encode decode restoreOption restoreOption_map roundtrip)

structure SearchReply where
  handoff : Option Handoff
  trace : SearchTrace

structure ReplyPayload where
  handoff : Option Encoded
  trace : SearchTrace
  deriving ToJson,FromJson

def SearchReply.pack (reply : SearchReply) : ReplyPayload := ⟨reply.handoff.map encode,reply.trace⟩

def ReplyPayload.restore (reply : ReplyPayload) : Option SearchReply := do
  let handoff ← restoreOption decode reply.handoff
  return ⟨handoff,reply.trace⟩

theorem SearchReply.transport_roundtrip (reply : SearchReply) : reply.pack.restore = some reply := by
  unfold SearchReply.pack ReplyPayload.restore
  rw [restoreOption_map encode decode reply.handoff (fun handoff _ => roundtrip handoff)]
  cases reply
  rfl

instance : ToJson SearchReply := ⟨fun reply => toJson reply.pack⟩
instance : FromJson SearchReply where
  fromJson? value := do
    let payload ← fromJson? (α := ReplyPayload) value
    let some reply := payload.restore | throw "invalid compact search reply"
    return reply

def SearchReply.decode (response : Option Json) : Option SearchReply :=
  response.bind fun value => (fromJson? value : Except String SearchReply).toOption

theorem absent_transport_is_not_reply : SearchReply.decode none = none := rfl

abbrev SearchIdentity := OperationWire.Identity

inductive SearchFrame where
  | ready (identity : SearchIdentity)
  | reply (identity : SearchIdentity) (handoff : Option Handoff)

inductive FramePayload where
  | ready (identity : SearchIdentity)
  | reply (identity : SearchIdentity) (handoff : Option Encoded)
  deriving ToJson,FromJson

def SearchFrame.pack : SearchFrame → FramePayload
  | .ready identity => .ready identity
  | .reply identity handoff => .reply identity (handoff.map encode)

def FramePayload.restore : FramePayload → Option SearchFrame
  | .ready identity => some (.ready identity)
  | .reply identity encoded => (restoreOption decode encoded).map (.reply identity)

theorem SearchFrame.transport_roundtrip (frame : SearchFrame) : frame.pack.restore = some frame := by
  cases frame with
  | ready identity => rfl
  | reply identity handoff =>
    change (restoreOption decode (handoff.map encode)).map (SearchFrame.reply identity) = some (.reply identity handoff)
    rw [restoreOption_map encode decode handoff (fun handoff _ => roundtrip handoff)]
    rfl

instance : ToJson SearchFrame := ⟨fun frame => toJson frame.pack⟩
instance : FromJson SearchFrame where
  fromJson? value := do
    let payload ← fromJson? (α := FramePayload) value
    let some frame := payload.restore | throw "invalid compact search frame"
    return frame

end Eggshell.Plugin.Worker
