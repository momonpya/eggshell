import Eggshell.Handoff
open Lean Eggshell Eggshell.Plugin Eggshell.Synapses Eggshell.Synapses.Extraction

#print axioms PacketReceipt.Piece.original_slice
#print axioms PacketReceipt.Shared.same_native_origin
#print axioms PacketReceipt.Shared.original_saved_read
#print axioms PacketReceipt.canonical_read_origin
#print axioms CapturedPacket.exact_returned_body

private def check (condition : Bool) (message : String) : IO Unit :=
  unless condition do throw (IO.userError message)

private def handoff (packet : DeliveryPacket) : Handoff := {
  text := packet.render
  reason := "native-ledger-fixture"
  deliveredGraphs := []
  completed := 0
  advisory := 1
  localUnions := 0
  coveredFragments := []
  blocksCurrent := false
  packet := some packet}

private def fieldCount (receipt : Json) (field : String) : Nat :=
  (receipt.getObjValAs? (Array Json) field).toOption.getD #[] |>.size

def main (args : List String) : IO Unit := do
  let [output] := args | throw (IO.userError "output directory required")
  let root := System.FilePath.mk output
  unless !(← root.pathExists) do throw (IO.userError "preserve prior packet audit")
  IO.FS.createDirAll root
  let raw := (toJson "prefix\n日本語 needle suffix\nlast row\n").compress
  let occurrence : Occurrence := ⟨"session","turn","use"⟩
  let doc : Document := ⟨"owner","work",some "arbitrary MCP tool",some raw,true,#[occurrence],#[]⟩
  let fragment : DeliveryFragment := {first := 1,original := ((raw.drop 1).dropEnd 1).copy,decoded := true}
  let context : ContextDelivery := {
    owner := doc.owner,outcome := "outcome",sourceChars := raw.length,cues := []
    leading := "\nWORK GRAPH owner\n  GROUNDED OUTCOME\n",trailing := "\n  TRACE\n",fragments := [fragment]}
  let part : DeliveryPart := {keys := [],text := context.render,context := some context}
  let packet : DeliveryPacket := {header := "header",footer := "footer",parts := [part]}
  let base := handoff packet
  let plan : Transport.Plan := {documents := #[doc]}
  let receipt := base.deliveryReceipt plan
  check ((receipt.getObjValAs? Bool "packetVerified").toOption == some true &&
    fieldCount receipt "originalPieces" == 1 && fieldCount receipt "unverifiedParts" == 0)
    "an exact selected original was not captured"
  let bodyOnly := Extraction.presented base.text #[doc] #[]
  check (bodyOnly.coversBinding ⟨"database",doc.owner,doc.work,1,raw.length-1⟩)
    "independent presentation parser disagrees with the checked excerpt"
  let broken := {base with text := base.text ++ "changed"}
  let rejected := broken.deliveryReceipt plan
  check ((rejected.getObjValAs? Bool "packetVerified").toOption == some false &&
    fieldCount rejected "originalPieces" == 0) "modified actual body retained planned delivery claims"
  let altered := {context with fragments := [{fragment with original := "wrong"}]}
  let alteredPart : DeliveryPart := {part with context := some altered,text := altered.render}
  let invalid := (handoff {packet with parts := [alteredPart]}).deliveryReceipt plan
  check (fieldCount invalid "originalPieces" == 0 && fieldCount invalid "unverifiedParts" == 1)
    "a rendered caption invented original content"
  let control := "control data"
  let withControl := {base with text := base.text ++ "\n\n" ++ control,controlDeltaChars := control.length+2}
  check (withControl.capturedPacket?.isSome) "control suffix lost the exact captured packet"
  let file : Synapses.File := ⟨"source/file.cc",String.ofList (List.replicate 64 'a'),100⟩
  let numberedRaw := (toJson "7\texact code\n").compress
  let sharedDoc := {doc with source := some numberedRaw,files := #[file]}
  let read : Read := ⟨occurrence,⟨.file file,7,7⟩,⟨"database",doc.owner,doc.work,1,numberedRaw.length-1⟩,#[]⟩
  let row : CanonicalSource.StoredRow := ⟨⟨file,7⟩,"exact code",#[⟨occurrence,read.binding⟩]⟩
  let some shared := CanonicalSource.Delivery.Part.check? #[row] | throw (IO.userError "empty shared fixture")
  let sharedPart : DeliveryPart := {keys := shared.keys,text := shared.render,shared := some shared}
  let sharedHandoff := handoff {packet with parts := [sharedPart]}
  let sharedPlan : Transport.Plan := {documents := #[sharedDoc],rows := #[read]}
  let sharedReceipt := sharedHandoff.deliveryReceipt sharedPlan
  check (fieldCount sharedReceipt "sharedRows" == 1 && fieldCount sharedReceipt "unverifiedParts" == 0)
    "a checked numbered/escaped shared row was not captured"
  let unbound := sharedHandoff.deliveryReceipt {sharedPlan with rows := #[]}
  check (fieldCount unbound "sharedRows" == 0 && fieldCount unbound "unverifiedParts" == 1)
    "a shared spelling invented a saved observation"
  let cached := sharedHandoff.deliveryReceipt {sharedPlan with
    rows := #[],canonical := ({} : Std.HashMap String (Array CanonicalSource.StoredRow)).insert doc.owner #[row]}
  check (fieldCount cached "sharedRows" == 1 && fieldCount cached "unverifiedParts" == 0)
    "an authenticated canonical origin required an unrelated graph nomination"
  let reference := Extraction.presented sharedHandoff.text #[sharedDoc] #[read]
  check (covered read.source reference.ranges) "independent shared-frame parser disagrees"
  let mut timings := #[]
  for count in [32,4096,32768] do
    let subject := ObservationContext.originalSubject doc.work raw
    let hints := (Array.range count).map fun number =>
      (⟨.range (Range.original subject 1 (raw.length-1)),number,s!"evidence-{number}",0,none⟩ : Routing.Store.Hint)
    let large := {plan with results := #[{hints,nodes := count,arcs := count,bytes := count*100}]}
    let started ← IO.monoMsNow
    let actual := base.deliveryReceipt large
    let bytes := actual.compress.toUTF8
    IO.FS.writeBinFile (root / s!"receipt-{count}.json") bytes
    let elapsed := (← IO.monoMsNow)-started
    check (fieldCount actual "originalPieces" == 1 && bytes.size < 4096)
      "unselected candidates entered the query-time delivery ledger"
    timings := timings.push (Json.mkObj [("unselectedOffers",toJson count),("elapsedIncludingWriteMs",toJson elapsed),
      ("receiptBytes",toJson bytes.size),("checkedOriginalPieces",toJson (1 : Nat))])
  IO.FS.writeFile (root / "result.json") (Json.mkObj [("trials",toJson timings),
    ("tamperedBodyRejected",toJson true),("inventedOriginalRejected",toJson true),
    ("unboundSharedRowRejected",toJson true),("independentParserAgreement",toJson true),
    ("warmCalls",toJson (0 : Nat)),("modelCalls",toJson (0 : Nat)),("actualHook",toJson false),
    ("adopted",toJson false)]).pretty
