import Lean.Data.Json.Parser
import Lean.Data.Json.FromToJson
open Lean

private def check (ok : Bool) (message : String) : IO Unit := unless ok do throw (IO.userError message)
private def read (p : System.FilePath) : IO Json := IO.FS.readFile p >>= fun s => IO.ofExcept (Json.parse s)
private def array (value : Json) (field : String) : IO (Array Json) := IO.ofExcept (value.getObjValAs? _ field)
private def nat (value : Json) (field : String) : IO Nat := IO.ofExcept (value.getObjValAs? _ field)
private def covers (spans : Array (Nat × Nat)) (first limit : Nat) : Bool :=
  let sorted := spans.qsort fun a b => if a.1 == b.1 then a.2 < b.2 else a.1 < b.1
  limit ≤ sorted.foldl (fun cursor (a,b) => if a ≤ cursor then max cursor b else cursor) first
private def ownerMatches (family binding : Json) : Bool :=
  family.getObjValD "owner" == binding.getObjValD "owner" && family.getObjValD "work" == binding.getObjValD "work"
private def intervals (family : Json) (field : String) : IO (Array (Nat × Nat)) :=
  IO.ofExcept (family.getObjValAs? _ field)

/- Read an already completed product plan. Reference probes never enter
nomination, binding, ranking or selection. Planned positions are kept distinct
from the actual body's independently measured delivery. -/
private def partCoverage (part : Json) (reads canonical families : Array Json) (field : String) : IO (Bool × Bool) := do
  let first ← nat part "first"
  let last ← nat part "last"
  check (0 < first && first ≤ last) "invalid frozen range"
  let subject := part.getObjValD "subject"
  if subject.getObjValD "original" != Json.null then
    let mut mapped := #[]
    let mut found := #[]
    for row in reads do
      let source := row.getObjValD "source"
      if source.getObjValD "subject" != subject then continue
      let a ← nat source "first"
      let b ← nat source "last"
      let binding := row.getObjValD "binding"
      let start ← nat binding "first"
      let stop ← nat binding "limit"
      check (a ≤ b && stop-start == b-a+1) "original range is not a character-exact binding"
      mapped := mapped.push (a-1,b)
      for family in families do
        unless ownerMatches family binding do continue
        if field == "domain" then found := found.push (a-1,b)
        else
          for (lo,hi) in ← intervals family field do
            let lo := max start lo
            let hi := min stop hi
            if lo < hi then found := found.push (a-1+lo-start,a-1+hi-start)
    return (covers mapped (first-1) last,covers found (first-1) last)
  let file := (subject.getObjValD "file").getObjValD "file"
  check (file != Json.null) "unsupported frozen source subject"
  let mut mapped := true
  let mut covered := true
  for line in [first:last+1] do
    let rows := canonical.filter fun row => (row.getObjValD "key").getObjValD "file" == file &&
      (row.getObjValD "key").getObjValD "line" == toJson line
    mapped := mapped && !rows.isEmpty
    let mut present := false
    for row in rows do
      for origin in ← array row "origins" do
        let binding := origin.getObjValD "binding"
        let lo ← nat binding "first"
        let hi ← nat binding "limit"
        for family in families do
          unless ownerMatches family binding do continue
          if field == "domain" then present := true
          else if covers (← intervals family field) lo hi then present := true
    covered := covered && present
  return (mapped,covered)

def main (args : List String) : IO Unit := do
  let [trialPath,signalsPath,originalsPath,destination] := args |
    throw (IO.userError "completed trial, frozen signal audit, canonical inventory and fresh output")
  let trial := System.FilePath.mk trialPath
  let output := System.FilePath.mk destination
  check (!(← output.pathExists)) "preserve previous range disposition"
  let result ← read (trial / "result.json")
  check (result.getObjValD "originalSourcesUnchanged" == toJson true) "trial did not verify original source"
  let frozen ← IO.ofExcept ((← read (trial / "frozen-before-delivery.json")).getArr?)
  let signals ← read signalsPath
  let originals ← read originalsPath
  let protocol ← read (trial / "protocol.json")
  check (signals.getObjValD "source" == originals.getObjValD "sourceHead" &&
    signals.getObjValD "source" == protocol.getObjValD "source") "probe inputs cross source snapshots"
  let canonical ← array originals "canonicalRows"
  let mut rows := #[]
  for measurement in ← array result "results" do
    let arm ← IO.ofExcept (measurement.getObjValAs? String "arm")
    let repetition ← nat measurement "repetition"
    let topic ← nat measurement "topic"
    let session := s!"keys-{arm}-{repetition}-{topic}"
    let mut plans := #[]
    for receipt in ← (trial / arm / "receipts").readDir do
      let request := (← read (receipt.path / "request.json")).getObjValD "data"
      unless request.getObjValD "session" == toJson session &&
          request.getObjValD "event" == toJson "UserPromptSubmit" do continue
      plans := plans.push ((← read (receipt.path / "selection-plan.json")).getObjValD "data")
    check (plans.size == 1) "missing or ambiguous completed range plan"
    let plan := plans[0]!
    check (plan.getObjValD "rangeAuditKind" == toJson "planned-original-positions" &&
      plan.getObjValD "assertsActualDelivery" == toJson false) "range capture was not explicitly enabled"
    let families ← array plan "rangeAudit"
    let selected : Array Nat ← IO.ofExcept (plan.getObjValAs? _ "selected")
    let some fixed := frozen.find? (fun row => row.getObjValD "topic" == toJson topic) |
      throw (IO.userError "frozen topic missing")
    check ((fixed.getObjValD "specification").getObjValD "files" ==
      ((frozen[0]!.getObjValD "specification").getObjValD "files")) "frozen source files differ"
    let mut requirements := #[]
    for unit in ← array signals "rows" do
      unless unit.getObjValD "topic" == toJson topic && unit.getObjValD "missing" == toJson true do continue
      let some requirement := (← array (fixed.getObjValD "available") "units").find?
        (fun row => row.getObjValD "names" == unit.getObjValD "names") |
        throw (IO.userError "original missing unit differs from current frozen obligation")
      let reads ← array unit "reads"
      let alternatives ← array requirement "alternatives"
      let mut stages := #[]
      for field in ["domain","candidateRanges","selectedRanges"] do
        let mut parts := #[]
        for alternative in alternatives do
          let values ← IO.ofExcept alternative.getArr?
          let coverage ← values.mapM fun part => partCoverage part reads canonical families field
          parts := parts.push (coverage.all (·.1),coverage.all (·.2))
        stages := stages.push (field,parts.any (·.1),parts.any (·.2))
      let hints := (← array plan "bindingAudit").filter fun hint => alternatives.any fun alternative =>
        (alternative.getArr?.toOption.getD #[]).any fun part => Id.run do
          let offered := hint.getObjValD "source"
          if offered.getObjValD "subject" != part.getObjValD "subject" then return false
          let get := fun object field => (object.getObjValAs? Nat field).toOption.getD 0
          return get offered "first" ≤ get part "last" && get part "first" ≤ get offered "last"
      let delivery := measurement.getObjValD "availableDelivery"
      let missing : Array (Array String) ← IO.ofExcept (delivery.getObjValAs? _ "missing")
      let names : Array String ← IO.ofExcept (unit.getObjValAs? _ "names")
      let delivered := !missing.contains names
      let lookup := fun field => (stages.find? (·.1 == field)).map (·.2.2) |>.getD false
      let known := stages.any (·.2.1)
      let stage := if delivered then "delivered" else if !known then "unmapped-diagnostic"
        else if !lookup "domain" then "domain" else if !lookup "candidateRanges" then "candidate-ranges"
        else if !lookup "selectedRanges" then "selection" else "render-or-body-verification"
      requirements := requirements.push (Json.mkObj [("names",toJson names),("stage",toJson stage),
        ("actualBodyDelivered",toJson delivered),("plannedCoverage",toJson stages),
        ("overlappingProjectedMembers",toJson hints.size),
        ("projectedMemberHasSelectedAlternative",toJson (hints.any fun hint =>
          ((hint.getObjValAs? (Array (Array Nat)) "alternatives").toOption.getD #[]).any
            (fun option => !option.isEmpty && option.all selected.contains)))])
    rows := rows.push (Json.mkObj [("arm",toJson arm),("repetition",toJson repetition),("topic",toJson topic),
      ("actualBodySha256",measurement.getObjValD "bodySha256"),("requirements",toJson requirements)])
  IO.FS.writeFile output (Json.mkObj [("rows",toJson rows),("selectorRerun",toJson false),
    ("labelsEnteredProduct",toJson false),("plannedPositionsAreActualDelivery",toJson false),
    ("answeringModelCalls",toJson (0 : Nat)),("adopted",toJson false)]).pretty
  IO.println s!"Explained original missing ranges in {rows.size} completed actual-hook plans"
