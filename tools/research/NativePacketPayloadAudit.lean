import Eggshell.Handoff
open Lean Eggshell Eggshell.Plugin Eggshell.Synapses Eggshell.Synapses.Extraction

private def check (condition : Bool) (message : String) : IO Unit :=
  unless condition do throw (IO.userError message)

/-- Independent reconstruction for auditing a previously emitted payload.
This parser is never called from the product's delivery path. -/
private def part (text : String) (doc : Document) : DeliveryPart := Id.run do
  let raw := (doc.source.getD "").toList.toArray
  let chars := text.toList.toArray
  let mut fragments : List DeliveryFragment := []
  let mut firstCaption : Option Nat := none
  let mut lastLimit := 0
  let mut compact := false
  for line in textLines text do
    let some (first,limit,decoded) := caption line.text | continue
    if limit > raw.size then continue
    let marker := "  DECODED JSON STRING DATA\n"
    let marked := literal chars line.limit (line.limit+marker.length) marker
    let fragment : DeliveryFragment := {
      first,original := String.ofList (raw.extract first limit).toList,decoded := decoded || marked}
    compact := line.text.startsWith "  CHARS ["
    let expected := fragment.render compact
    unless literal chars line.first (line.first+expected.length) expected do continue
    if firstCaption.isNone then firstCaption := some line.first
    lastLimit := line.first+expected.length
    fragments := fragment :: fragments
  let some start := firstCaption | return {keys := [],text}
  let context : ContextDelivery := {
    owner := doc.owner,outcome := "stored-actual-body",sourceChars := raw.size,cues := []
    leading := String.ofList (chars.extract 0 start).toList
    trailing := String.ofList (chars.extract lastLimit chars.size).toList
    fragments := fragments.reverse
    compactCaptions := compact}
  if context.render != text then return {keys := [],text}
  return {keys := [],text,context := some context}

def main (args : List String) : IO Unit := do
  let [output] := args | throw (IO.userError "new output directory required")
  let root := System.FilePath.mk output
  unless !(← root.pathExists) do throw (IO.userError "preserve prior payload audit")
  IO.FS.createDirAll root
  let path := System.FilePath.mk "/Users/ovm/.codex/worktrees/hook-deadline-baseline/eggshell/docs/candidates/prepared-record-delivery/records/checked-hook/body.txt"
  let body ← IO.FS.readFile path
  let source ← DB.PageMap.pin (.mk "/Users/ovm/.codex/experiments/eggshell/study-services-20261026/common-seed-1/source.egg")
  check (source.head.identity == "76352b67a9c35002bff67dc3d3c3a01b7bd194e43e09f5f54714dde75df5a8de" &&
    source.head.revision == 31 && source.head.bytes == 45216846) "wrong fixed original snapshot"
  let entries ← Build.entries source
  let saved : Build.Documents source := ⟨← Persistence.Store.NodeReader.new source,← IO.mkRef {},← IO.mkRef {}⟩
  let mut docs := #[]
  for entry in entries do
    let doc ← saved.get entry.id
    if doc.native then docs := docs.push doc
  let preamble :: blocks := body.splitOn "\nWORK GRAPH " | throw (IO.userError "missing actual WORK GRAPH frame")
  let parts := blocks.map fun block =>
    let text := "WORK GRAPH " ++ block
    let owner := (block.splitOn "\n").head!
    match docs.find? (·.owner == owner) with
    | none => ({keys := [],text} : DeliveryPart)
    | some doc => part text doc
  let packet : DeliveryPacket := {header := preamble,footer := "",parts}
  check (packet.render == body) "reconstruction changed actual delivered bytes"
  let handoff : Handoff := {
    text := body,reason := "actual-old-payload-audit",deliveredGraphs := []
    completed := 0,advisory := 0,localUnions := 0,coveredFragments := [],blocksCurrent := false,packet := some packet}
  let started ← IO.monoMsNow
  let reference := Extraction.presented body docs #[]
  IO.FS.writeFile (root / "independent-original-bindings.json") (toJson reference.bindings).compress
  let referenceMs := (← IO.monoMsNow)-started
  let started ← IO.monoMsNow
  let receipt := handoff.deliveryReceipt {documents := docs}
  IO.FS.writeFile (root / "selected-packet-receipt.json") receipt.pretty
  let elapsed := (← IO.monoMsNow)-started
  let originals ← IO.ofExcept (receipt.getObjValAs? (Array Json) "originalPieces")
  let mut found : Std.HashSet (String × Nat × Nat) := {}
  for piece in originals do
    found := found.insert (← IO.ofExcept (piece.getObjValAs? String "owner"),
      ← IO.ofExcept (piece.getObjValAs? Nat "first"),← IO.ofExcept (piece.getObjValAs? Nat "limit"))
  let expected := reference.bindings.foldl (fun seen binding => seen.insert binding) ({} : Std.HashSet (String × Nat × Nat))
  check (found.size == expected.size && expected.toArray.all found.contains) "actual-payload ledger differs from independent original binding checks"
  check ((← DB.PageMap.pin source.directory).head == source.head) "original DB changed"
  IO.FS.writeFile (root / "result.json") (Json.mkObj [
    ("body",toJson path.toString),("bodySha256",toJson (Sha256.hex body.toUTF8)),
    ("bodyBytes",toJson body.utf8ByteSize),("bodyUnchanged",toJson true),("sourceUnchanged",toJson true),
    ("nativeOwners",toJson docs.size),("packetParts",toJson parts.length),
    ("checkedOriginalBindings",toJson found.size),
    ("independentParserIncludingWriteMs",toJson referenceMs),("ledgerIncludingWriteMs",toJson elapsed),
    ("unverifiedParts",receipt.getObjValD "unverifiedParts"),
    ("warmCalls",toJson (0 : Nat)),("modelCalls",toJson (0 : Nat)),
    ("newActualHook",toJson false),("deliveryRecallMeasured",toJson false),("adopted",toJson false)]).pretty
