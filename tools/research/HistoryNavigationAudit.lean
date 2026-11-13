import Eggshell.SynapseSource
import Eggshell.Sha256
open Lean Eggshell
namespace HistoryNavigationAudit
def check (valid : Bool) (message : String) : IO Unit := unless valid do throw (IO.userError message)
def read (path : String) : IO Json := IO.FS.readFile path >>= (IO.ofExcept ∘ Json.parse)
def key (work digest : String) (chars : Nat) := (toJson (work,digest,chars)).compress
def merge (ranges : Array (Nat × Nat)) : Array (Nat × Nat) := Id.run do
  let mut result := #[]
  for (first,stop) in ranges.qsort (fun a b => a.1 < b.1) do
    if let some previous := result.back? then
      if first ≤ previous.2 then
        result := result.set! (result.size-1) (previous.1,max previous.2 stop)
        continue
    result := result.push (first,stop)
  return result
def run (originalPath beforePath responsePath output : String) : IO Unit := do
  check (!(← (System.FilePath.mk output).pathExists)) "preserve previous navigation audit"
  let originals ← read originalPath
  let before ← read beforePath
  check (originals.getObjValD "head" == before.getObjValD "originalHead") "audit uses a different original snapshot"
  let documents ← IO.ofExcept (originals.getObjValAs? (Array Json) "documents")
  let mut identities : Std.HashMap String String := {}
  let mut byOwner : Std.HashMap String Json := {}
  for document in documents do
    let raw ← IO.ofExcept (document.getObjValAs? String "source")
    let work ← IO.ofExcept (document.getObjValAs? String "work")
    let owner ← IO.ofExcept (document.getObjValAs? String "owner")
    identities := identities.insert (key work (Sha256.hex raw.toUTF8) raw.length) owner
    byOwner := byOwner.insert owner document
  let responses ← IO.ofExcept ((← read responsePath).getObjValAs? (Array Json) "results")
  let topics ← IO.ofExcept (before.getObjValAs? (Array Json) "topics")
  check (responses.size == 3 && topics.size == 3) "all three frozen questions required"
  let mut reports := #[]
  for index in [:topics.size] do
    let topic := topics[index]!
    let response := responses[index]!
    let mut intervals : Std.HashMap String (Array (Nat × Nat)) := {}
    for item in ← IO.ofExcept (response.getObjValAs? (Array Json) "payload") do
      let owner ← IO.ofExcept (item.getObjValAs? String "owner")
      let some original := byOwner[owner]? | throw (IO.userError "selected owner is absent from the fixed snapshot")
      let raw ← IO.ofExcept (original.getObjValAs? String "source")
      let decoded := Synapses.Extraction.layoutView raw
      let span := item.getObjValD "span"
      let id ← IO.ofExcept (span.getObjValAs? Nat "document")
      check (documents[id]? == some original) "document ID and original owner differ"
      let first ← IO.ofExcept (span.getObjValAs? Nat "first")
      let stop ← IO.ofExcept (span.getObjValAs? Nat "stop")
      check (first < stop && stop < decoded.offsets.size) "selected original slice is out of bounds"
      let expected := String.ofList ((decoded.text.toList.toArray.extract first stop).toList)
      check (item.getObjValD "text" == toJson expected &&
        item.getObjValD "snapshot" == toJson (originals.getObjValD "head").compress &&
        item.getObjValD "originalFirst" == toJson decoded.offsets[first]! &&
        item.getObjValD "originalStop" == toJson decoded.offsets[stop]!) "returned payload differs from its immutable original"
      intervals := intervals.insert owner ((intervals[owner]?.getD #[]).push (decoded.offsets[first]!,decoded.offsets[stop]!))
    intervals := intervals.map (fun _ value => merge value)
    let mut units := #[]
    let mut covered := 0
    for unit in ← IO.ofExcept ((topic.getObjValD "frozen").getObjValAs? (Array Json) "units") do
      let mut complete := false
      let mut originalAlternative := false
      for alternative in ← IO.ofExcept (unit.getObjValAs? (Array Json) "alternatives") do
        let ranges ← IO.ofExcept (alternative.getArr?)
        let mut supported := !ranges.isEmpty
        let mut available := !ranges.isEmpty
        for range in ranges do
          let subject := (range.getObjValD "subject").getObjValD "original"
          if subject == Json.null then
            supported := false
            available := false
            continue
          let source := subject.getObjValD "original"
          let work ← IO.ofExcept (source.getObjValAs? String "work")
          let digest ← IO.ofExcept (source.getObjValAs? String "content")
          let chars ← IO.ofExcept (source.getObjValAs? Nat "chars")
          let some owner := identities[key work digest chars]? | throw (IO.userError "required original identity differs")
          let first ← IO.ofExcept (range.getObjValAs? Nat "first")
          let stop ← IO.ofExcept (range.getObjValAs? Nat "last")
          check (0 < first && first ≤ stop && stop ≤ chars) "required original range is invalid"
          available := available && (intervals[owner]?.getD #[]).any (fun row => row.1 ≤ first-1 && stop ≤ row.2)
        originalAlternative := originalAlternative || supported
        complete := complete || available
      check originalAlternative "unit has no original-only alternative; cannot make this coverage claim"
      if complete then covered := covered+1
      units := units.push (Json.mkObj [("names",unit.getObjValD "names"),("selectedOriginalCovered",toJson complete)])
    reports := reports.push (Json.mkObj [("topic",topic.getObjValD "topic"),("selectedOriginalCovered",toJson covered),
      ("eligible",toJson units.size),("finished",response.getObjValD "finished"),("error",response.getObjValD "error"),
      ("elapsedMs",response.getObjValD "elapsedMs"),("units",toJson units)])
  IO.FS.writeFile output (Json.mkObj [("topics",toJson reports),("allSelectedOriginalsVerified",toJson true),
    ("actualHookDeliveryMeasured",toJson false),("goldenEvidenceWasNavigatorInput",toJson false),
    ("adopted",toJson false)]).compress
end HistoryNavigationAudit
def main : List String → IO Unit
  | [originals,before,response,output] => HistoryNavigationAudit.run originals before response output
  | _ => throw (IO.userError "HistoryNavigationAudit ORIGINALS FROZEN-EVIDENCE NAVIGATOR-RESULT OUTPUT")
