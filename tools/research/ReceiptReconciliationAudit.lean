import Eggshell.Handoff
import tools.research.CompleteOriginal
import tools.research.StudyRuntime
open Lean Eggshell Eggshell.Plugin Eggshell.Research
private def ensure (ok : Bool) (message : String) : IO Unit := unless ok do throw (IO.userError message)
private def read (path : System.FilePath) : IO Json := IO.FS.readFile path >>= fun text => IO.ofExcept (Json.parse text)

private def context (owner source : String) : IO ContextDelivery := do
  let spans ← IO.ofExcept (CompleteOriginal.prepare source)
  let data := source.toList.toArray
  let fragments := spans.spans.toList.map fun span => ({
    first := span.first,original := String.ofList (data.extract span.first span.limit).toList,
    decoded := span.decoded} : DeliveryFragment)
  return {
    owner,outcome := "original",sourceChars := source.length,cues := [(0,source.length)],
    leading := "WORK GRAPH " ++ owner ++ "\n",trailing := "\nEND WORK GRAPH",fragments}

private def part (context : ContextDelivery) : DeliveryPart :=
  {keys := context.keys,text := context.render,context := some context}

private def samePart (actual : Option DeliveryPart) (expected : DeliveryPart) : Bool :=
  actual.map toJson == some (toJson expected)

private def legacyAccepts (context : ContextDelivery) : Bool :=
  context.fragments.all fun fragment => 0 < fragment.original.length &&
    fragment.original.length ≤ 2048 && fragment.first + fragment.original.length ≤ context.sourceChars

private def fixtures : IO Json := do
  let long := String.ofList (List.replicate 5000 'x')
  let samples := #[long,(toJson long).compress,
    (toJson ("日本語\n한글\tκώδικας 🙂" ++ long)).compress,
    (Json.mkObj [("uri",toJson "mcp://resource/item"),("result",toJson #["alpha",long])]).compress]
  for source in samples do
    let value ← context "fixture" source
    ensure (!legacyAccepts value) "large regression case did not exercise the rejected fragment"
    ensure (samePart ((part value).remaining []) (part value)) "fresh receipt deleted or changed original context"
    ensure ((part value).remaining value.keys).isNone "acknowledged original was redelivered"
  let value ← context "overlap" long
  let receipt := ["e:overlap:original:1000:4000"]
  let some remaining := (part value).remaining receipt | throw (IO.userError "partial long receipt removed original")
  let some pending := remaining.context | throw (IO.userError "lost original context")
  ensure (pending.fragments.map (fun f => (f.first,f.original.length)) == [(0,1000),(4000,1000)])
    "large receipt overlap was not subtracted exactly"
  ensure (samePart ((part value).remaining ["e:other:original:0:5000"]) (part value)) "another owner erased original"
  ensure (samePart ((part value).remaining ["e:overlap:other:0:5000"]) (part value)) "another outcome erased original"
  ensure (samePart ((part value).remaining ["e:overlap:original:0:5001"]) (part value)) "out-of-source receipt erased original"
  let invalid := {value with sourceChars := 4999}
  ensure ((part invalid).remaining []).isNone "source bounds were disabled"
  let badText := {(part value) with
    text := "changed"}
  ensure (badText.remaining []).isNone "changed presentation was accepted"
  let packet : DeliveryPacket := {header := "",footer := "",parts := [part value]}
  let handoff : Handoff := {
    text := packet.render,reason := "receipt fixture",deliveredGraphs := value.keys,
    completed := 0,advisory := 1,localUnions := 0,coveredFragments := [],blocksCurrent := false,packet := some packet}
  ensure ((handoff.reconcileDelivery [] 10000 10000).map (·.handoff.text) == some handoff.text)
    "packet reconciliation dropped a fitted long original"
  ensure ((handoff.reconcileDelivery [] 1000 1000).isNone) "packet limit was disabled"
  return Json.mkObj [("largeOriginalCases",toJson samples.size),("exactOverlap",toJson true),
    ("receiptOwnerAndOutcomeScope",toJson true),("sourceAndPacketBounds",toJson true),
    ("originalPresentationChecked",toJson true)]

def main : IO Unit := do
  let study : System.FilePath := "/Users/ovm/.codex/experiments/eggshell/scope-token-study-20261028"
  let project : System.FilePath := "/Users/ovm/.codex/worktrees/hook-deadline-baseline/eggshell"
  let records := project / "docs/candidates/receipt-reconciliation"
  ensure (!(← (records / "result.json").pathExists)) "preserve receipt audit result"
  let fixtureResult ← fixtures
  let initialFiles ← StudyRuntime.files (study / "r0/stage1/history/source.egg")
  let inventory ← read (study / "seed-originals.json")
  let documents : Array Json ← IO.ofExcept (inventory.getObjValAs? _ "documents")
  let previous ← IO.FS.readFile (project / "docs/candidates/complete-work/hooks/candidate/rep-0/topic-1/body.txt")
  let mut rejected := #[]
  let mut survivors := #[]
  let mut totalSource := 0
  let mut allParts := []
  for document in documents do
    let owner ← IO.ofExcept (document.getObjValAs? String "owner")
    let source ← IO.ofExcept (document.getObjValAs? String "source")
    let value ← context owner source
    if legacyAccepts value then survivors := survivors.push owner else rejected := rejected.push owner
    ensure (((previous.splitOn ("WORK GRAPH " ++ owner ++ "\n")).length == 2) == legacyAccepts value)
      "old cap does not explain the exact actual-owner survivor set"
    let some actual := (part value).remaining [] | throw (IO.userError "selected source owner disappeared")
    ensure (toJson actual == toJson (part value)) "fresh receipt changed original bytes or coordinates"
    ensure ("".intercalate (value.fragments.map (·.original)) == source) "source layout lost original characters"
    allParts := allParts ++ [actual]
    totalSource := totalSource+source.length
  ensure (documents.size == 38 && survivors.size == 6 && rejected.size == 32) "sealed owner population changed"
  let packet : DeliveryPacket := {header := "",footer := "",parts := allParts}
  let handoff : Handoff := {
    text := packet.render,reason := "actual source receipt audit",deliveredGraphs := allParts.flatMap (·.keys),
    completed := 0,advisory := allParts.length,localUnions := 0,coveredFragments := [],blocksCurrent := false,packet := some packet}
  let some accepted := handoff.reconcileDelivery [] (1024*1024) (1024*1024) |
    throw (IO.userError "actual source packet did not survive original reconciliation")
  ensure (accepted.handoff.text == handoff.text) "receipt reconciliation silently changed selected source packet"
  ensure ((accepted.handoff.packet.map (·.parts.length)) == some 38) "actual source packet lost an owner"
  ensure ((← StudyRuntime.files (study / "r0/stage1/history/source.egg")) == initialFiles) "receipt audit changed source"
  IO.FS.writeFile (records / "result.json") (Json.mkObj [
    ("source",inventory.getObjValD "sourceHead"),("sourceFiles",toJson initialFiles),("sourceUnchanged",toJson true),
    ("fixtures",fixtureResult),("legacySurvivors",toJson survivors),("legacyRejected",toJson rejected),
    ("sameActualLegacySurvivors",toJson true),("selectedOriginalOwners",toJson documents.size),
    ("reconciledOriginalOwners",toJson allParts.length),("originalCharacters",toJson totalSource),
    ("acceptedPacketCharacters",toJson accepted.handoff.text.length),
    ("actualHookCalls",toJson (0 : Nat)),("answeringModelCalls",toJson (0 : Nat)),("adopted",toJson false)]).pretty
  IO.println "Exact legacy owner loss reproduced: 38 to 6; corrected receipt boundary preserves all 38 originals"
