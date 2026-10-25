import tools.research.NativeTrialAudit
import Eggshell.ObservationContext

open Lean Eggshell Eggshell.Synapses Eggshell.Research
open Eggshell.Research.RequiredDelivery

private def check (condition : Bool) (message : String) : IO Unit :=
  unless condition do throw (IO.userError message)

private def identities : IO Unit := do
  let file : File := ⟨"src/driver.c",Sha256.hex "original file".toUTF8,10000⟩
  let response : Original := ⟨"remote/resource",Sha256.hex "original response".toUTF8,10000⟩
  let ranges : Array Range := (Array.range 20).map fun index =>
    ⟨if index < 10 then .file file else .original response,index*10+1,index*10+4⟩
  let required := ranges.zipIdx |>.map fun (source,index) => ({name := toString index,alternatives := #[source]} : Requirement)
  let frozen ← IO.ofExcept (freeze required ranges)
  check (frozen.units.size == 20 && frozen.initiallyUnavailable.isEmpty) "mixed required evidence was not frozen"
  check ((assess frozen (ranges.extract 0 19)).targetMet &&
    !(assess frozen (ranges.extract 0 18)).targetMet) "95 percent boundary was rounded or treated as 90 percent"
  let duplicated ← IO.ofExcept (freeze (required.push ⟨"alias",#[ranges[0]!]⟩) ranges)
  check (duplicated.units.size == 20) "duplicate evidence inflated the denominator"
  let overlap := {ranges[0]! with first := 2}
  check (!(freeze (required.push ⟨"overlap",#[overlap]⟩) ranges).isOk)
    "overlapping distinct evidence silently changed the counting unit"
  let wrong := ranges.map fun range => match range.subject with
    | .file value => {range with subject := .file {value with fingerprint := Sha256.hex "different version".toUTF8}}
    | .original value => {range with subject := .original {value with content := Sha256.hex "different response".toUTF8}}
  check ((assess frozen wrong).delivered == 0) "a path, tool or coordinate match hid changed original bytes"
  let truncated := ranges.map fun range => {range with last := range.last-1}
  check ((assess frozen truncated).delivered == 0) "partial evidence was counted as a complete required item"
  let missing := assess frozen #[]
  check (missing.eligible == 20 && missing.missing.size == 20 && !missing.targetMet)
    "a retrieval miss shrank the frozen denominator"
  let absent ← IO.ofExcept (freeze required #[])
  check (absent.initiallyUnavailable.size == 20 && !(assess absent #[]).targetMet)
    "an empty eligible denominator passed the delivery target"

private def actualBytes : IO Unit := do
  let raw := (Json.mkObj ((List.range 20).map fun index => (s!"field_{index}",toJson s!"VALUE_{index}"))).compress
  let doc : Extraction.Document := {
    owner := "fixture-original",work := "fixture-work",workText := some "mcp__records__read\n{}"
    source := some raw,native := true,occurrences := #[⟨"fixture","turn","call"⟩],files := #[] }
  let some catalog := ObservationContext.recorded (Sha256.hex "fixture database".toUTF8) doc |
    throw (IO.userError "generic JSON source did not expose its original coordinates")
  let reads := catalog.reads
  check (reads.size == 20) "JSON fixture did not contain twenty disjoint evidence items"
  let frozen ← IO.ofExcept (freeze (reads.zipIdx |>.map fun (read,index) => ⟨toString index,#[read.source]⟩)
    (reads.map (·.source)))
  let body := s!"EGGSHELL\nWORK GRAPH {doc.owner}\n  GROUNDED OUTCOME\n{raw}\n  TRACE\nEND EGGSHELL"
  let shown := Extraction.presented body #[doc] reads
  check ((assess frozen shown.ranges).delivered == 20 && (assess frozen shown.ranges).targetMet)
    "actual complete original bytes were not counted"
  for fake in #[raw,s!"WORK GRAPH {doc.owner}\nlocation: remote/resource\n",body.replace "VALUE_0" "FORGED_0"] do
    let shown := Extraction.presented fake #[doc] reads
    check ((assess frozen shown.ranges).delivered == 0 && !(assess frozen shown.ranges).targetMet)
      "unattributed prose, a locator or altered bytes passed original delivery verification"

def main : IO UInt32 := do
  try
    identities
    actualBytes
    IO.println (Json.mkObj [("arithmeticBoundary",toJson true),("mixedImmutableSubjects",toJson true),
      ("duplicateAndOverlapProtection",toJson true),("frozenDenominator",toJson true),
      ("actualJsonEvidenceItems",toJson (20 : Nat)),("unattributedOrAlteredDeliveryRejected",toJson true),
      ("answeringModelCalls",toJson (0 : Nat)),("productionRecallMeasured",toJson false)]).compress
    return 0
  catch error => IO.eprintln error.toString; return 1
