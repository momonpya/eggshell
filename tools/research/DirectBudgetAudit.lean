import Eggshell.Handoff
open Lean Eggshell Eggshell.Plugin Eggshell.Synapses

#print axioms SharedRangeAdapter.direct_keeps_control

def main (args : List String) : IO Unit := do
  let [output] := args | throw (IO.userError "output required")
  let root := System.FilePath.mk output
  unless !(← root.pathExists) do throw (IO.userError "keep prior audit")
  IO.FS.createDirAll root
  let raw := "".intercalate (List.replicate 600 "MCP arbitrary output data\n")
  let work := Value.text "mcp/arbitrary\n{}"
  let outcome := Value.text raw
  let occurrence : Occurrence := ⟨"record-budget-fixture","turn","read"⟩
  let event := Value.applyList .occurrence [Ref.semantic outcome,Ref.semantic work,
    Ref.exact (.text occurrence.session),Ref.exact (.text occurrence.turn),Ref.exact (.text occurrence.useId)]
  let edge := OutcomeEdge.make work outcome [event] (by simp) (by simp [maxOutcomeObservations])
  let document ← IO.ofExcept (Transport.Owner.document ⟨"database",edge,[]⟩)
  let view ← IO.ofExcept (ObservedRecordView.make "database" document)
  let family : SharedRangeAdapter.Family := {
    owner := edge
    windows := List.range ((raw.length+100)/384+2)
    originalView := some view
    template := {owner := some edge.relation,text := "",keys := [],members := [],visibleKeys := []}}
  let mandatory : TransportSlice := {owner := none,text := "CONTROL",keys := ["control"],members := [],visibleKeys := []}
  let ranked := {family with windows := 13 :: ((List.range 40).filter (· != 13))}
  let prioritized := SharedRangeAdapter.directOffers 0 ranked
  unless prioritized[0]?.any (fun offer => offer.priority == 0 && offer.fragment.first > 4000) do
    throw (IO.userError "overlapping windows promoted an unrelated source prefix over the first focus")
  let mut records := #[]
  for extra in [0,1000,2000,6000] do
    let cost := fun slices : List TransportSlice =>
      let data := slices.foldl (fun total slice =>
        (total.1+slice.text.length+1,total.2+slice.text.utf8ByteSize+1)) (0,0)
      let frame := if slices.any (fun slice => slice.context.any (fun context => !context.fragments.isEmpty)) then extra else 0
      (data.1+frame,data.2+frame)
    let started ← IO.monoMsNow
    let some plan := SharedRangeAdapter.directPlan (10000,40000) cost [family] [mandatory] |
      throw (IO.userError "lost mandatory control")
    unless plan.selected > 0 && plan.result.val.head?.map (·.text) == some "CONTROL" do
      throw (IO.userError "a framing change erased feasible evidence or mandatory control")
    records := records.push (plan.receipt.setObjVal! "extraVariableFrame" (toJson extra)
      |>.setObjVal! "elapsedMs" (toJson ((← IO.monoMsNow)-started)))
  IO.FS.writeFile (root / "result.json") (Json.mkObj [("cases",toJson records),
    ("modelCalls",toJson (0 : Nat)),("actualHook",toJson false),("adopted",toJson false)]).pretty
