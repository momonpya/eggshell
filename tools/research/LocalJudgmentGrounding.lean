import Eggshell.SynapseSource
import Lean.Data.Json.Parser

open Lean Eggshell.Synapses
namespace LocalJudgmentGrounding
private def check (condition : Bool) (message : String) : IO Unit :=
  unless condition do throw (IO.userError message)
private def read (path : String) : IO Json := IO.FS.readFile path >>= (IO.ofExcept ∘ Json.parse)
private def array (value : Json) : IO (Array Json) := IO.ofExcept value.getArr?
private def nat (value : Json) : IO Nat := IO.ofExcept (fromJson? value)
private def ranks (scores : Json) (topic : Nat) (ids : Array Nat) : IO Json := do
  let measurements ← array (scores.getObjValD "measurements")
  let some measurement := measurements.find? (·.getObjValD "name" == toJson s!"topic-{topic}") |
    throw (IO.userError "topic scores missing")
  let mut found := #[]
  let rows ← array ((measurement.getObjValD "response").getObjValD "results")
  for number in [:rows.size] do
    let index ← nat (rows[number]!.getObjValD "index")
    if ids.contains index then found := found.push (Json.mkObj [
      ("claim",toJson index),("rank",toJson (number+1)),
      ("score",rows[number]!.getObjValD "relevance_score")])
  return toJson found
def run (claimsPath controlPath onlyPath beforePath capturePath output : String) : IO Unit := do
  check (!(← System.FilePath.pathExists output)) "preserve prior citation grounding audit"
  let captured ← read claimsPath
  let before ← read beforePath
  check (captured.getObjValD "sourceHead" == before.getObjValD "originalHead") "claims and evidence use different snapshots"
  let claims ← array (captured.getObjValD "claims")
  let control ← read controlPath
  let only ← read onlyPath
  let selection ← read capturePath
  let mut files : Array File := #[]
  for entry in ← array ((selection.getObjValD "selectionWitness").getObjValD "sourceNodes") do
    let row ← array entry
    check (row.size == 2) "canonical source key is malformed"
    let file ← IO.ofExcept (fromJson? (α := File) (row[1]!.getObjValD "file"))
    unless files.contains file do files := files.push file
  let mut parsed : Array (Nat × Array Range) := #[]
  for claim in claims do
    let index ← nat (claim.getObjValD "index")
    let paragraph ← IO.ofExcept (claim.getObjValAs? String "paragraph")
    parsed := parsed.push (index,Extraction.paragraphCitations paragraph files)
  let mut result := #[]
  for topic in ← array (before.getObjValD "topics") do
    let number ← nat (topic.getObjValD "topic")
    let frozen ← array ((topic.getObjValD "frozen").getObjValD "units")
    let mut names : Array String := #[]
    for unit in frozen do names := names++(← IO.ofExcept (unit.getObjValAs? (Array String) "names"))
    let mut requirements := #[]
    for required in ← array ((topic.getObjValD "specification").getObjValD "required") do
      let name ← IO.ofExcept (required.getObjValAs? String "name")
      if !(names.contains name) then continue
      let relative ← IO.ofExcept (required.getObjValAs? String "path")
      let matchingFiles := files.filter (·.relative == relative)
      check (matchingFiles.size == 1) "required path has no unique immutable file identity"
      let first ← nat (required.getObjValD "first")
      let last ← nat (required.getObjValD "last")
      check (0 < first && first ≤ last && last-first ≤ 1000000) "required source range invalid"
      let footprint : Range := ⟨.file matchingFiles[0]!,first,last⟩
      let complete := parsed.filterMap fun (id,citations) =>
        if (List.range (last-first+1)).all (fun offset =>
          citations.any (·.contains ⟨footprint.subject,first+offset,first+offset⟩)) then some id else none
      let unionCovered := (List.range (last-first+1)).all fun offset =>
        parsed.any fun (_,citations) => citations.any (·.contains ⟨footprint.subject,first+offset,first+offset⟩)
      requirements := requirements.push (Json.mkObj [("name",toJson name),("range",toJson footprint),
        ("citationUnionCovers",toJson unionCovered),("completeSupportingClaims",toJson complete),
        ("workAndClaimRanks",← ranks control number complete),("claimOnlyRanks",← ranks only number complete)])
    result := result.push (Json.mkObj [("topic",toJson number),("requirements",toJson requirements)])
  IO.FS.writeFile output (Json.mkObj [("topics",toJson result),("claimCount",toJson claims.size),
    ("scope",toJson "literal citation coverage and numerical rank only; not graph reachability, selection feasibility or actual delivery"),
    ("answeringModelCalls",toJson (0 : Nat)),("productChanged",toJson false)]).compress
end LocalJudgmentGrounding
def main : List String → IO Unit
  | [claims,control,only,before,capture,output] => LocalJudgmentGrounding.run claims control only before capture output
  | _ => throw (IO.userError "LocalJudgmentGrounding CLAIMS CONTROL CLAIM-ONLY FROZEN CAPTURE OUTPUT")
