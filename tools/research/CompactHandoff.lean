module
public import Eggshell.Handoff
public import tools.research.CompactProvenance
@[expose] public section

namespace Eggshell.Research.CompactHandoff
open Lean Plugin Synapses CanonicalSource
open CompactProvenance

def rows (part : DeliveryPart) : Array StoredRow := (part.shared.map (·.rows)).getD #[]

def packetInput (packet : DeliveryPacket) : Input :=
  ⟨(packet.parts.flatMap (fun part => (rows part).toList)).toArray,
    (packet.parts.flatMap (fun part => part.evidence.toList)).toArray⟩

theorem packet_read_member (packet : DeliveryPacket) (part : DeliveryPart) (present : part ∈ packet.parts)
    (read : Read) (member : read ∈ part.evidence) : read ∈ (packetInput packet).reads := by
  change read ∈ (packet.parts.flatMap (fun part => part.evidence.toList)).toArray
  simp only [List.mem_toArray]
  exact List.mem_flatMap.mpr ⟨part,present,by simpa using member⟩

theorem packet_row_member (packet : DeliveryPacket) (part : DeliveryPart) (present : part ∈ packet.parts)
    (row : StoredRow) (member : row ∈ rows part) : row ∈ (packetInput packet).rows := by
  change row ∈ (packet.parts.flatMap (fun part => (rows part).toList)).toArray
  simp only [List.mem_toArray]
  exact List.mem_flatMap.mpr ⟨part,present,by simpa using member⟩

def restoreOption (decode : α → Option β) : Option α → Option (Option β)
  | none => some none
  | some value => (decode value).map some

theorem restoreOption_map (encode : α → β) (decode : β → Option α) (value : Option α)
    (exact : ∀ item ∈ value,decode (encode item) = some item) :
    restoreOption decode (value.map encode) = some value := by
  cases value with
  | none => rfl
  | some item => simp [restoreOption,exact item (by simp)]

structure Shared where
  rows : Array EncodedRow
  plan : String
  deriving ToJson,FromJson

def encodeShared (builder : Builder) (part : Delivery.Part) : Shared :=
  ⟨part.rows.map (encodeRow builder),part.plan⟩

def decodeShared (tables : Tables) (part : Shared) : Option Delivery.Part := do
  let rows ← restoreArray (decodeRow tables) part.rows
  Delivery.Part.check? rows part.plan

theorem shared_roundtrip (builder : Builder) (part : Delivery.Part)
    (exact : ∀ row ∈ part.rows,decodeRow builder.tables (encodeRow builder row) = some row) :
    decodeShared builder.tables (encodeShared builder part) = some part := by
  unfold decodeShared encodeShared
  rw [restoreArray_map _ _ _ exact]
  change Delivery.Part.check? part.rows part.plan = some part
  simp only [Delivery.Part.check?,part.nonempty,↓reduceDIte]

structure Part where
  shell : DeliveryPart
  shared : Option Shared
  evidence : Array EncodedRead
  deriving ToJson,FromJson

def encodePart (builder : Builder) (part : DeliveryPart) : Part :=
  ⟨{part with shared := none,evidence := #[]},part.shared.map (encodeShared builder),part.evidence.map (encodeRead builder)⟩

def decodePart (tables : Tables) (part : Part) : Option DeliveryPart := do
  unless part.shell.shared.isNone && part.shell.evidence.isEmpty do none
  let shared ← restoreOption (decodeShared tables) part.shared
  let evidence ← restoreArray (decodeRead tables) part.evidence
  return {part.shell with shared,evidence}

theorem part_roundtrip (builder : Builder) (part : DeliveryPart)
    (readExact : ∀ read ∈ part.evidence,decodeRead builder.tables (encodeRead builder read) = some read)
    (rowExact : ∀ row ∈ rows part,decodeRow builder.tables (encodeRow builder row) = some row) :
    decodePart builder.tables (encodePart builder part) = some part := by
  have sharedExact : restoreOption (decodeShared builder.tables) (part.shared.map (encodeShared builder)) = some part.shared :=
    restoreOption_map _ _ _ (fun shared member => shared_roundtrip _ _ (fun row present =>
      rowExact row (by
        change part.shared = some shared at member
        simpa [rows,member] using present)))
  unfold decodePart encodePart
  simp only [Option.isNone_none,Array.isEmpty_empty,Bool.and_self,↓reduceIte]
  rw [sharedExact,restoreArray_map _ _ _ readExact]
  cases part
  rfl

structure Packet where
  tables : Tables
  header : String
  footer : String
  frames : List DeliveryFrame
  parts : List Part
  deriving ToJson,FromJson

def encodePacket (packet : DeliveryPacket) : Packet :=
  let builder := (packetInput packet).builder
  ⟨builder.tables,packet.header,packet.footer,packet.frames,packet.parts.map (encodePart builder)⟩

def decodePacket (packet : Packet) : Option DeliveryPacket := do
  let parts ← restoreList (decodePart packet.tables) packet.parts
  return ⟨packet.header,packet.footer,parts,packet.frames⟩

theorem packet_roundtrip (packet : DeliveryPacket) : decodePacket (encodePacket packet) = some packet := by
  have exact : ∀ part ∈ packet.parts,
      decodePart (packetInput packet).builder.tables (encodePart (packetInput packet).builder part) = some part := by
    intro part present
    exact part_roundtrip _ _
      (fun read member => (packetInput packet).restore_read read (packet_read_member packet part present read member))
      (fun row member => (packetInput packet).restore_row row (packet_row_member packet part present row member))
  unfold decodePacket encodePacket
  rw [restoreList_map _ _ _ exact]
  cases packet
  rfl

/-- The shell keeps every non-packet field, including the exact body and
certification metadata. The packet's shared identities are encoded before JSON
allocation; no raw 13MB intermediary is needed by the ordinary sender. -/
structure Encoded where
  shell : Handoff
  packet : Option Packet
  deriving ToJson,FromJson

def encode (handoff : Handoff) : Encoded :=
  ⟨{handoff with packet := none},handoff.packet.map encodePacket⟩

def decode (handoff : Encoded) : Option Handoff := do
  unless handoff.shell.packet.isNone do none
  let packet ← restoreOption decodePacket handoff.packet
  return {handoff.shell with packet}

theorem roundtrip (handoff : Handoff) : decode (encode handoff) = some handoff := by
  have packetExact := restoreOption_map encodePacket decodePacket handoff.packet (fun packet _ => packet_roundtrip packet)
  unfold decode encode
  simp only [Option.isNone_none,↓reduceIte]
  rw [packetExact]
  cases handoff
  rfl

theorem body_unchanged (handoff : Handoff) : (decode (encode handoff)).map (·.text) = some handoff.text := by
  rw [roundtrip]
  rfl

theorem acknowledgment_unchanged (handoff : Handoff) :
    (decode (encode handoff)).map (·.acknowledgmentProjection) = some handoff.acknowledgmentProjection := by
  rw [roundtrip]
  rfl

theorem reconciliation_unchanged (handoff : Handoff) (claims : List String) (chars bytes : Nat) :
    (decode (encode handoff)).bind (fun actual => actual.reconcileDelivery claims chars bytes) =
      handoff.reconcileDelivery claims chars bytes := by
  rw [roundtrip]
  rfl

end Eggshell.Research.CompactHandoff
