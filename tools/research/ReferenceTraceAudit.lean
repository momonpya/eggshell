import Eggshell.CanonicalSourceCache
import Lean.Data.Json.Parser

open Lean Eggshell Eggshell.Synapses Eggshell.Synapses.CanonicalSource

private def read (path : System.FilePath) : IO Json :=
  IO.FS.readFile path >>= fun text => IO.ofExcept (Json.parse text)

private def field [FromJson α] (value : Json) (name : String) : IO α :=
  IO.ofExcept (value.getObjValAs? α name)

private def covers (ranges : List (Nat × Nat)) (first last : Nat) : Bool :=
  last ≤ ((ranges.mergeSort fun a b => a.1 ≤ b.1).foldl
    (fun frontier (a,b) => if a ≤ frontier then max frontier b else frontier) first)

private structure Owner where
  name : String
  work : String
  candidate : List (Nat × Nat)
  selected : List (Nat × Nat)

private def rowCovered (owners : Array Owner) (chosen : Bool) (row : StoredRow) : Bool :=
  row.origins.any fun origin => owners.any fun owner => owner.name == origin.binding.owner &&
    covers (if chosen then owner.selected else owner.candidate) origin.binding.first origin.binding.limit

private def coverage (rows : Array StoredRow) (owners : Array Owner) (chosen : Bool) (range : Range) : Bool :=
  match range.subject with
  | .file file =>
    (List.range (range.last+1-range.first)).all fun offset => rows.any fun row =>
      row.key.file == file && row.key.line == range.first+offset && rowCovered owners chosen row
  | .original original => owners.any fun owner => owner.work == original.work &&
      covers (if chosen then owner.selected else owner.candidate) range.first range.last

def main (args : List String) : IO Unit := do
  let [database,ordinaryPath,tracePath,output] := args |
    throw (IO.userError "DATABASE ORDINARY-THREE-TOPICS TRACE-THREE-TOPICS NEW-REPORT")
  unless !(← System.FilePath.pathExists output) do throw (IO.userError "preserve prior trace audit")
  let ordinary := System.FilePath.mk ordinaryPath
  let trace := System.FilePath.mk tracePath
  let source ← DB.PageMap.pin (.mk database)
  let some ready ← Cache.open? source .database | throw (IO.userError "prepared original view unavailable")
  let receipts := (System.FilePath.mk database).parent.get! / "data/receipts"
  let mut results := #[]
  for topic in [1:4] do
    let current := trace / s!"topic-{topic}"
    let same := (← IO.FS.readBinFile (ordinary / s!"topic-{topic}/body.txt")) ==
      (← IO.FS.readBinFile (current / "body.txt"))
    unless same do throw (IO.userError "trace changed the actual body; do not explain the ordinary run with it")
    let stdin ← IO.ofExcept (Json.parse (← IO.FS.readFile (current / "UserPromptSubmit/stdin")))
    let session : String ← field stdin "session_id"
    let mut matching := #[]
    for directory in ← receipts.readDir do
      if !(← (directory.path / "request.json").pathExists) then continue
      let header := (← read (directory.path / "request.json")).getObjValD "data"
      if header.getObjValD "session" == toJson session && header.getObjValD "event" == toJson "UserPromptSubmit" then
        matching := matching.push directory.path
    let [receipt] := matching.toList | throw (IO.userError "one actual hook receipt required")
    let plan := (← read (receipt / "selection-plan.json")).getObjValD "data"
    let audit : Array Json ← field plan "rangeAudit"
    let owners ← audit.mapM fun row => do
      let shared : List (Nat × Nat) ← field row "candidateSharedRanges"
      let original : List (Nat × Nat) ← field row "candidateOriginalRanges"
      let selectedShared : List (Nat × Nat) ← field row "selectedSharedRanges"
      let selectedOriginal : List (Nat × Nat) ← field row "selectedOriginalRanges"
      let name ← field row "owner"
      let work ← field row "work"
      return ({
        name := name
        work := work
        candidate := shared ++ original
        selected := selectedShared ++ selectedOriginal
      } : Owner)
    let report ← read (current / "audit-report.json")
    let units : Array Json ← field (report.getObjValD "frozenEvidence") "units"
    let delivered : Array Json ← field report "requirements"
    let mut requirements := #[]
    for unit in units do
      let names : Array String ← field unit "names"
      let alternatives : Array Range ← field unit "alternatives"
      let candidate := alternatives.any (coverage ready.registry.store owners false)
      let selected := alternatives.any (coverage ready.registry.store owners true)
      let body := names.all fun name => delivered.any fun row => row.getObjValD "name" == toJson name &&
        row.getObjValD "bodyDelivered" == toJson true
      let ranges := alternatives.filterMap fun range => match range.subject with
        | .original _ => none
        | .file file => some (file,range)
      let fileRows := ranges.map fun (file,range) =>
        let expected := (List.range (range.last+1-range.first)).map (range.first+·)
        let chosen := expected.filter fun line => ready.registry.store.any fun row =>
          row.key.file == file && row.key.line == line && rowCovered owners true row
        Json.mkObj [("range",toJson range),("selectedLines",toJson chosen),
          ("missingSelectedLines",toJson (expected.filter (!chosen.contains ·)))]
      requirements := requirements.push (Json.mkObj [("names",toJson names),("candidate",toJson candidate),
        ("selected",toJson selected),("bodyDelivered",toJson body),("fileRows",toJson fileRows)])
    results := results.push (Json.mkObj [("topic",toJson topic),("receipt",toJson receipt.toString),
      ("bodyBytesIdentical",toJson same),("requirements",toJson requirements)])
  IO.FS.writeFile output (Json.mkObj [("source",toJson source.head),("canonical",toJson ready.metadata),
    ("topics",toJson results),("exactLeanJson",toJson true),("readOnly",toJson true),
    ("answeringModelCalls",toJson (0 : Nat)),("warmCalls",toJson (0 : Nat)),("productionAdoption",toJson false)]).pretty
  IO.println "All trace bodies match ordinary bodies; classified candidate/selection/delivery from actual original bindings"
