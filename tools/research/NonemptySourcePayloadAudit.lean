import Eggshell.Handoff
open Lean Eggshell Eggshell.Plugin Eggshell.Synapses

#print axioms CanonicalSource.Delivery.empty_part_rejected
#print axioms CanonicalSource.Delivery.checked_part_nonempty
#print axioms SharedRangeAdapter.output_context_preserves_control

private def check (valid : Bool) (message : String) : IO Unit :=
  unless valid do throw (IO.userError message)

private def scenario (raw : String) : IO Json := do
  let work := Value.text "arbitrary_provider\n{}"
  let outcome := Value.text raw
  let event := Value.applyList .occurrence [Ref.semantic outcome,Ref.semantic work,
    Ref.exact (.text "session"),Ref.exact (.text "turn"),Ref.exact (.text "call")]
  let owner := OutcomeEdge.make work outcome [event] (by simp) (by simp [maxOutcomeObservations])
  let family : SharedRangeAdapter.Family := {
    owner,template := {owner := some owner.relation,keys := [],text := "",members := [],visibleKeys := []},windows := [0]}
  check (family.outputEnvelope?.isSome) "uncached native output lost its original envelope"
  let prepared := family.contextualOutputs
  let (units,_) := SharedRangeAdapter.prepare 0 prepared
  check (!units.isEmpty && units.all (fun unit => !unit.slice.text.isEmpty && unit.slice.shared.isNone &&
    unit.slice.members.isEmpty && unit.slice.visibleKeys.isEmpty)) "original data became empty or acquired control"
  check (SharedRangeAdapter.covers (units.flatMap (·.ranges)) 0 raw.length)
    "generic original records do not cover the stored output"
  let some problem := SharedRangeAdapter.problem [prepared] units [] (0,0) (100000,400000) |
    throw (IO.userError "original payload has no cost model")
  check ((List.finRange problem.offers.size).all fun index =>
    let charge := SharedCoverage.cost problem [index]
    0 < charge.1 && 0 < charge.2) "an original data unit claimed free full-output coverage"
  return Json.mkObj [("sourceChars",toJson raw.length),("units",toJson units.length),
    ("completeOriginalDomain",toJson true),("positivePayloadCosts",toJson true),("nativeControl",toJson false)]

def main (args : List String) : IO UInt32 := do
  try
    let [destination] := args | throw (IO.userError "NonemptySourcePayloadAudit NEW-DIRECTORY")
    let root := System.FilePath.mk destination
    check (root.isAbsolute && !(← root.pathExists)) "new regression directory required"
    IO.FS.createDir root
    check ((CanonicalSource.Delivery.Part.check? #[]).isNone) "empty native constructor accepted"
    for value in #[Json.mkObj [("rows",toJson (#[] : Array Json)),("plan",toJson "same-plan")],
        Json.mkObj [("rows",Json.null)],Json.mkObj [("plan",toJson "missing-rows")]] do
      check (!(fromJson? (α := CanonicalSource.Delivery.Part) value).isOk) "empty or malformed wire payload accepted"
    let mut records := #[]
    for raw in #["condition\n  FIRST();\n  SECOND();\n",
        (toJson "JSON scalar\n日本語の原文\nlast line\n").compress,
        (Json.mkObj [("resource",toJson "mcp://arbitrary/document"),
          ("output",toJson "arbitrary output\ncontains needed evidence\n"),
          ("structured",Json.mkObj [("identifier",toJson "LAST_FIELD")])]).compress] do
      records := records.push (← scenario raw)
    IO.FS.writeFile (root / "results.json") (Json.mkObj [("scenarios",toJson records),
      ("emptyConstructorsRejected",toJson true),("emptyWireRejected",toJson true),
      ("answeringModelCalls",toJson (0 : Nat)),("productionAdoption",toJson false)]).pretty
    IO.println (toJson records).compress
    return 0
  catch error => IO.eprintln error.toString; return 1
