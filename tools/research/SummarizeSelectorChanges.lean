import Lean.Data.Json.Parser
import Lean.Data.Json.FromToJson
open Lean
private def read (path : System.FilePath) : IO Json :=
  IO.FS.readFile path >>= fun text => IO.ofExcept (Json.parse text)

def main : IO Unit := do
  let root := System.FilePath.mk "/Users/ovm/.codex/experiments/eggshell/selector-input-20261027"
  let measured ← read (root / "measured-selector-changes/result.json")
  let input ← read (root / "selector-input.json")
  let rounds ← IO.ofExcept (measured.getObjValAs? (Array Json) "iterations")
  let values ← rounds.mapM fun row => IO.ofExcept (row.getObjValAs? Nat "unselectedTouched")
  let sorted := values.qsort (· < ·)
  let total := fun key => rounds.foldl (fun sum row => sum+(row.getObjValAs? Nat key).toOption.getD 0) 0
  let costs ← IO.ofExcept (input.getObjValAs? (Array (Nat × Nat)) "costs")
  let fixed ← IO.ofExcept (input.getObjValAs? (Nat × Nat) "fixed")
  let limit ← IO.ofExcept (input.getObjValAs? (Nat × Nat) "limit")
  let output := Json.mkObj [
    ("offers",measured.getObjValD "offers"),("rounds",measured.getObjValD "rounds"),
    ("visitedCandidates",measured.getObjValD "visitedCandidates"),("scoreComparisons",measured.getObjValD "scoreComparisons"),
    ("totalUnselectedTouched",measured.getObjValD "totalUnselectedTouched"),
    ("totalScalarChanges",toJson (total "scalarChanges")),("newlyFeasibleEvents",toJson (total "newlyFeasible")),
    ("zeroTouchedRounds",toJson (values.filter (· == 0)).size),
    ("medianTouched",toJson sorted[sorted.size/2]?),
    ("p95Touched",toJson sorted[sorted.size*95/100]?),
    ("maximumTouched",toJson sorted.back?),
    ("bytesDominatedByFourChars",toJson (costs.all fun (chars,bytes) => bytes ≤ 4*chars)),
    ("fixedBytesDominatedByFourChars",toJson (decide (fixed.2 ≤ 4*fixed.1))),
    ("byteLimitAtLeastFourCharLimit",toJson (decide (4*limit.1 ≤ limit.2))),
    ("sameNativeReferenceSequence",measured.getObjValD "sameNativeReferenceSequence"),
    ("instrumentedReplayMs",measured.getObjValD "instrumentedReplayMs"),
    ("productionLatencyClaim",toJson false),("answeringModelCalls",toJson (0 : Nat)),("adopted",toJson false)]
  IO.FS.writeFile (root / "measured-selector-changes/summary.json") output.pretty
  IO.println output.pretty
