module
import all Eggshell.Handoff
public meta import Lean
open Lean Eggshell.Synapses Eggshell.Synapses.CanonicalSource

#print axioms Eggshell.Research.OriginalPayloadBasis.no_inferred_dependencies

run_meta do
  let environment ← getEnv
  let mut pending := [``Eggshell.Plugin.SharedRangeAdapter.plan]
  let mut seen : Std.HashSet Name := {}
  while let name :: tail := pending do
    pending := tail
    if seen.contains name then continue
    seen := seen.insert name
    let some declaration := environment.find? name | throwError "missing selection definition {name}"
    if let some body := declaration.value? then
      for next in body.getUsedConstants do
        if next.toString.startsWith "Eggshell." then pending := next :: pending
  unless seen.contains ``Eggshell.Research.OriginalPayloadBasis.prepare do
    throwError "selector bypasses original cost validation"
  for forbidden in #[``Eggshell.Research.ReferenceRequirements.prepare,
      ``Eggshell.Research.ReferenceRequirements.prepareGraph] do
    if seen.contains forbidden then throwError "heuristic call closure remains mandatory: {forbidden}"

private def check (yes : Bool) (message : String) : IO Unit :=
  unless yes do throw (IO.userError message)

public def main (args : List String) : IO Unit := do
  let file : File := ⟨"input",String.ofList (List.replicate 64 'a'),1000⟩
  let mut count := 0
  for lines in #[#["void root() { leaf(); }","void leaf() { tail(); }","void tail() {}"],
      #["{\"records\":[\"MCP original\"]}","SMB: \\host\\share","é 日本語 한국어"],
      #["if (ready) { run(); }","// unresolved() { }","[2026-10-28] log record"]] do
    let originals := lines.zipIdx.map fun (code,index) =>
      (⟨⟨file,index+1⟩,code,#[]⟩ : StoredRow)
    let frame := Packet.fileFrame file originals
    let fixedText := frame.leading ++ frame.trailing
    let costs := #[(0,0),(fixedText.length,fixedText.utf8ByteSize)] ++ originals.map fun row =>
      let rendered := Packet.rowText row
      (rendered.length,rendered.utf8ByteSize)
    let p : SharedCoverage.Problem := {costs,weights := #[],offers := #[],limit := (120000,128000)}
    let some prepared := Eggshell.Research.OriginalPayloadBasis.prepare 1 originals p |
      throw (IO.userError "original cost validation failed")
    let some reference := Eggshell.Research.ReferenceRequirements.prepare 1 originals p |
      throw (IO.userError "reference cost validation failed")
    check (prepared.sourceRows == reference.sourceRows) "original row/cost/ordering changed"
    check prepared.dependencies.isEmpty "a spelling created a required dependency"
    if count == 0 then check (!reference.dependencies.isEmpty) "fixture did not expose inferred call dependencies"
    check ((prepared.selectedRows [2,3,4]) == originals) "original payload or provenance changed"
    let altered : SharedCoverage.Problem := {
      costs := p.costs.set! 2 (p.costs[2]!.1+1,p.costs[2]!.2)
      weights := p.weights,offers := #[],limit := p.limit}
    check ((Eggshell.Research.OriginalPayloadBasis.prepare 1 originals altered).isNone)
      "mismatched original wire cost was accepted"
    count := count+1
  IO.println (Json.mkObj [("cases",toJson count),("rowCostIdentityEqual",toJson true),
    ("inferredDependenciesAbsent",toJson true),("costMutationRejected",toJson true),
    ("authorityAdded",toJson false),("answeringModelCalls",toJson (0 : Nat))]).compress
  if let [before,after,output] := args then
    let mut reports := #[]
    for path in [before,after] do
      let json ← IO.ofExcept (Json.parse (← IO.FS.readFile (.mk path)))
      let data := json.getObjValD "data"
      let raw ← IO.ofExcept (fromJson? (α := SharedCoverage.Input.RawProblem) (data.getObjValD "selectorInput"))
      let p ← IO.ofExcept raw.decode
      let result ← IO.mkRef (none : Option (SharedCoverage.Selection p))
      let start ← IO.monoMsNow
      result.set (SharedCoverage.choose? p)
      let elapsed := (← IO.monoMsNow)-start
      let some selected ← result.get | throw (IO.userError "recorded problem became infeasible")
      let report := Json.mkObj [("path",toJson path),("selectionMs",toJson elapsed),
        ("nodes",toJson p.costs.size),("cues",toJson p.weights.size),("offers",toJson p.offers.size),
        ("selectedOffers",toJson selected.selected.length),("cost",toJson (SharedCoverage.cost p selected.selected)),
        ("actualPlanKeys",toJson ((data.getObj?).toOption.map (·.toList.map Prod.fst))),
        ("selected",toJson (selected.selected.map Fin.val))]
      reports := reports.push report
      IO.FS.writeFile (.mk output) (toJson reports).pretty
      IO.println (report.setObjVal! "selected" Json.null).compress
