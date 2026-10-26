import Eggshell.Handoff
open Lean Eggshell Eggshell.Plugin

private def check (condition : Bool) (message : String) : IO Unit :=
  unless condition do throw (IO.userError message)

private def family (source : String) : SharedRangeAdapter.Family := Id.run do
  let work := Value.text "mcp__records__read\n{}"
  let output := Value.text source
  let occurrence := Value.applyList .occurrence [Ref.semantic output,Ref.semantic work,
    Ref.exact (.text "test"),Ref.exact (.text "turn"),Ref.exact (.text "use")]
  let owner := OutcomeEdge.make work output [occurrence] (by simp) (by simp [maxOutcomeObservations])
  return {owner,template := {owner := some owner.relation,keys := [],text := "",members := [],visibleKeys := []},windows := []}

def main : IO Unit := do
  let text := "αβ: \"quoted\"\\tail\n  条件と結果\n끝\n"
  let json := Json.mkObj [("content",toJson (String.ofList (List.replicate 6000 'x') ++ "TAIL")),
    ("other",toJson text)]
  let cases := #["",text,(toJson text).compress,"\"\\u0061\"",json.compress,
    String.ofList (List.replicate 5000 '界') ++ "END"]
  let mut totalUnits := 0
  for source in cases do
    let contextual := (family source).contextualOutputs
    check contextual.template.context.isSome "generic native output did not obtain its original envelope"
    let prepared := SharedRangeAdapter.prepare 0 contextual
    let ranges := prepared.1.flatMap (·.ranges)
    if !source.isEmpty then
      check (SharedRangeAdapter.covers ranges 0 source.length)
        "the query-independent original domain omitted a header, tail, escape or Unicode character"
    for unit in prepared.1 do
      check unit.slice.members.isEmpty "a source record acquired control authority"
      let some context := unit.slice.context | throw (IO.userError "original record lost its envelope")
      for fragment in context.fragments do
        check (fragment.original == ((source.drop fragment.first).take fragment.original.length).copy)
          "an original payload changed at its character coordinates"
        check (fragment.original.length ≤ 2048) "a bounded source record exceeded its actual limit"
        let presented := fragment.presentation
        if presented.2 then
          check (encodedTextBody presented.1 == fragment.original)
            "optional display decoding did not round-trip to the original bytes"
    if source == "\"\\u0061\"" then
      check (prepared.1.all fun unit => unit.slice.context.all fun context =>
        context.fragments.all (!·.decoded)) "noncanonical scalar received inferred decoding coordinates"
    totalUnits := totalUnits+prepared.1.length
  IO.println (Json.mkObj [("cases",toJson cases.size),("originalUnits",toJson totalUnits),
    ("noQueryHintsRequired",toJson true),("completeOriginalCharacterDomain",toJson true),
    ("unicodeAndEscapesExact",toJson true),("decodedDisplayRoundTrips",toJson true),
    ("noncanonicalNotInferred",toJson true),("noControlAuthority",toJson true),
    ("answeringModelCalls",toJson (0 : Nat)),("productionAdoption",toJson false)]).compress
