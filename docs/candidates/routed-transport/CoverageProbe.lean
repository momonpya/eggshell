import Eggshell.Handoff
open Lean Eggshell.Plugin
#print axioms SharedRangeAdapter.UnitPlan.prepared_covers_exact
#eval do
  let path := System.FilePath.mk "/Users/ovm/.codex/experiments/eggshell/literal-support-20261026/required-replay/topic-1/data/receipts/7f4a8714f880982e8929bd13e4faa38c97be87af9c97ed119288dd1d53847fc8/selection-plan.json"
  let parsed ← IO.ofExcept (Json.parse (← IO.FS.readFile path))
  let units ← IO.ofExcept ((parsed.getObjValD "data").getObjValAs? (Array Json) "units")
  let mut original := 0
  let mut normalized := 0
  let mut maxBefore := 0
  let mut maxAfter := 0
  for unit in units do
    let ranges ← IO.ofExcept (unit.getObjValAs? (List (Nat × Nat)) "ranges")
    let index := SharedRangeAdapter.CoverageIndex.prepare ranges
    original := original+ranges.length
    normalized := normalized+index.intervals.length
    maxBefore := max maxBefore ranges.length
    maxAfter := max maxAfter index.intervals.length
  IO.println (Json.mkObj [("units",toJson units.size),("original",toJson original),
    ("normalized",toJson normalized),("maxBefore",toJson maxBefore),("maxAfter",toJson maxAfter)]).compress
