module
public import Eggshell.Handoff
@[expose] public section
namespace Eggshell.Research.PacketInspection
open Lean Plugin

/-- A bounded metadata view of the actual typed reply. No original bodies,
origin arrays or query text are copied into the diagnostic record. -/
def inspect (handoff : Option Handoff) : Json :=
  match handoff with
  | none => Json.mkObj [("handoff",toJson false)]
  | some handoff =>
    let projection := handoff.acknowledgmentProjection
    let captured := handoff.capturedPacket?
    let parts : List DeliveryPart := match captured with
      | none => []
      | some packet => packet.packet.parts
    let totalParts := parts.length
    let parts := (parts.take 64).zipIdx.map fun (entry : DeliveryPart × Nat) =>
      let part := entry.1
      let index := entry.2
      let kinds := ((part.keys.take 16).map (fun (key : String) => ((key.splitOn ":").headD "").take 16 |>.copy)
        |>.eraseDups).take 8
      Json.mkObj [("index",toJson index),("projected",toJson part.projected),
        ("projectionComplete",toJson part.projectionComplete),
        ("context",toJson part.context.isSome),("shared",toJson part.shared.isSome),
        ("textChars",toJson part.text.length),("textBytes",toJson part.text.utf8ByteSize),
        ("keys",toJson part.keys.length),("keyKindsSample",toJson kinds),
        ("evidence",toJson part.evidence.size),("acknowledgedReads",toJson part.acknowledgedReads.size),
        ("nativeOwners",toJson part.nativeOwners.size),
        ("sharedRows",toJson ((part.shared.map (fun (shared : Synapses.CanonicalSource.Delivery.Part) => shared.rows.size)).getD 0))]
    Json.mkObj [("handoff",toJson true),("packetCaptured",toJson captured.isSome),
      ("bodyBytes",toJson handoff.text.utf8ByteSize),("parts",toJson parts),
      ("totalParts",toJson totalParts),("partsTruncated",toJson (decide (totalParts > 64))),
      ("sampleLimits",toJson (#[(64 : Nat),16,8])),
      ("projectionRows",toJson projection.rows.size),("projectionBindings",toJson projection.bindings.size),
      ("projectionComplete",toJson projection.complete),
      ("completed",toJson handoff.completed),("blocksCurrent",toJson handoff.blocksCurrent)]

def record (receipt : Option String) (handoff : Option Handoff) : IO Unit := do
  unless (← IO.getEnv "EGGSHELL_PACKET_INSPECTION") == some "1" do return
  unless receipt.isSome do throw (IO.userError "packet observation needs its actual receipt")
  Receipt.observe receipt "packet-inspection" (inspect handoff)

end Eggshell.Research.PacketInspection
