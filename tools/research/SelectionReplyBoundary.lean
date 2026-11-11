module
public import tools.research.CompactSearchWire
@[expose] public section
namespace Eggshell.Research.SelectionReplyBoundary
open Lean Plugin

/-- Selection diagnostics have already gone to the private receipt sink.
They do not belong to the reply frame that carries delivered evidence. -/
def publicHandoff (handoff : Handoff) : Handoff := {handoff with selectionPlan := none}

/-- Reconstructing exactly the private field recovers the entire old value.
Every other field, including future fields, is therefore preserved. -/
theorem only_private_field_changed (handoff : Handoff) :
    {publicHandoff handoff with selectionPlan := handoff.selectionPlan} = handoff := by
  cases handoff
  rfl

theorem body_packet_authority (handoff : Handoff) :
    (publicHandoff handoff).text = handoff.text ∧
    (publicHandoff handoff).packet = handoff.packet ∧
    (publicHandoff handoff).blocksCurrent = handoff.blocksCurrent ∧
    (publicHandoff handoff).completed = handoff.completed ∧
    (publicHandoff handoff).equalitySelection = handoff.equalitySelection ∧
    (publicHandoff handoff).sourceCheckpoints = handoff.sourceCheckpoints := by
  exact ⟨rfl,rfl,rfl,rfl,rfl,rfl⟩

theorem acknowledgment (handoff : Handoff) :
    (publicHandoff handoff).acknowledgmentProjection = handoff.acknowledgmentProjection := by
  cases handoff with
  | mk text reason graphs completed advisory unions fragments blocks records uses checkpoints packet delta search equality complete plan =>
    cases packet with
    | none => rfl
    | some packet =>
      by_cases valid : packet.render = (text.take (text.length-delta)).copy <;>
        simp [publicHandoff,Handoff.acknowledgmentProjection,Handoff.capturedPacket?,valid]

abbrev Reply := {reply : Worker.SearchReply // ∀ handoff ∈ reply.handoff,handoff.selectionPlan = none}

def forDelivery (reply : Worker.SearchReply) : Reply :=
  ⟨{reply with handoff := reply.handoff.map publicHandoff},by
    intro handoff present
    cases found : reply.handoff with
    | none => simp [found] at present
    | some original =>
      have same : publicHandoff original = handoff := by simpa [found] using present
      rw [← same]
      rfl⟩

def encode (reply : Reply) : Json := toJson reply.val

theorem encoding_roundtrip (reply : Reply) : reply.val.pack.restore = some reply.val :=
  reply.val.transport_roundtrip

theorem trace_unchanged (reply : Worker.SearchReply) : (forDelivery reply).val.trace = reply.trace := rfl

theorem sealed_body_unchanged (reply : Worker.SearchReply) :
    (forDelivery reply).val.handoff.map (·.text) = reply.handoff.map (·.text) := by
  simp [forDelivery,publicHandoff,Option.map_map,Function.comp_def]

theorem sealed_acknowledgment_unchanged (reply : Worker.SearchReply) :
    (forDelivery reply).val.handoff.map (·.acknowledgmentProjection) = reply.handoff.map (·.acknowledgmentProjection) := by
  simp [forDelivery,Option.map_map,Function.comp_def,acknowledgment]

#print axioms only_private_field_changed
#print axioms acknowledgment
#print axioms encoding_roundtrip
#print axioms sealed_body_unchanged
#print axioms sealed_acknowledgment_unchanged
end Eggshell.Research.SelectionReplyBoundary
