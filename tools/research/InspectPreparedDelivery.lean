import Eggshell.Handoff
open Lean Eggshell Eggshell.Plugin Eggshell.Synapses
open Eggshell.Persistence.Store

def main (args : List String) : IO Unit := do
  let [output] := args | throw (IO.userError "output required")
  let destination := System.FilePath.mk output
  unless !(← destination.pathExists) do throw (IO.userError "preserve existing diagnostic")
  IO.FS.createDirAll destination
  let trial := System.FilePath.mk "/Users/ovm/.codex/experiments/eggshell/prepared-record-delivery-20261027/fixed-source-hooks"
  let source ← DB.PageMap.pin (trial / "work.egg")
  let some prepared ← Index.openShared? source | throw (IO.userError "missing prepared view")
  let directories ← (trial / "data/receipts").readDir
  let some receipt := directories[0]? | throw (IO.userError "missing actual receipt")
  let domain ← IO.ofExcept (Json.parse (← IO.FS.readFile (receipt.path / "delivery-domain.json")))
  let focus ← IO.ofExcept ((domain.getObjValD "data").getObjValAs? (Array (String × List Nat)) "focusPositions")
  let reader ← NodeReader.new source
  let mut families := []
  let mut rows := #[]
  for (owner,windows) in focus do
    let some id ← Build.ownerId? source owner | throw (IO.userError "missing source owner")
    let edge ← reader.outcome (← reader.locateOutcome id)
    let view ← ObservedRecordView.load? prepared.index source.head.identity owner
    let family : SharedRangeAdapter.Family := {
      owner := edge,windows,originalView := view
      template := {owner := some edge.relation,text := "",keys := [],members := [],visibleKeys := []}}
    let offers := SharedRangeAdapter.directOffers families.length family
    let shell := (family.contextualOutputs.template.context.map fun context =>
      {context with fragments := [],cues := []}.render).getD ""
    rows := rows.push (Json.mkObj [("owner",toJson owner),("native",toJson (Matcher.nativeOutcome edge)),
      ("view",toJson view.isSome),("offers",toJson offers.size),("shellChars",toJson shell.length)])
    families := families ++ [family]
  let started ← IO.monoMsNow
  let cost := fun slices : List TransportSlice => slices.foldl
    (fun total slice => (total.1+slice.text.length+1,total.2+slice.text.utf8ByteSize+1)) (0,0)
  let result := SharedRangeAdapter.directPlan (120000,480000) cost families
  IO.FS.writeFile (destination / "diagnostic.json") (Json.mkObj [("owners",toJson rows),
    ("selection",toJson (result.map (·.receipt))),("selectionMs",toJson ((← IO.monoMsNow)-started)),
    ("originalSourceUnchanged",toJson ((← DB.PageMap.pin (trial / "work.egg")).head == source.head)),
    ("actualHook",toJson false),("modelCalls",toJson (0 : Nat))]).pretty
