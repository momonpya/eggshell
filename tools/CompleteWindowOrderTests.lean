import Eggshell.SearchProvider
import Eggshell.Handoff

open Eggshell Eggshell.Plugin

private def require (condition : Bool) (message : String) : IO Unit :=
  unless condition do throw (IO.userError message)

def main : IO Unit := do
  let document : Persistence.Store.SearchDocument :=
    {owner := 1, work := 0, windows := List.replicate 40 "key"}
  let full := (List.range 40).reverse
  require ((SemanticMatcher.CompleteWindowOrder.check? document full).isSome)
    "a complete order was truncated to an IO batch"
  for invalid in [full.take 32, 40 :: full.drop 1, 0 :: full.drop 1] do
    require ((SemanticMatcher.CompleteWindowOrder.check? document invalid).isNone)
      "incomplete, foreign or duplicate window order accepted"
  require ((SemanticMatcher.WindowPull.check? document full).isNone)
    "complete ranking bypassed the source-read batch bound"
  require ((SemanticMatcher.WindowPull.check? document (full.take 32)).isSome)
    "bounded original byte pull was rejected"
  let scores := (List.range 4096).map fun index =>
    (((index * 7919 % 101).toFloat / 100), index)
  let accumulated := scores.foldl (fun state row => SearchProvider.WindowScore.add state row.1 row.2)
    ({} : SearchProvider.WindowScore)
  let expected := scores.foldl (fun prior row =>
    (row :: prior).mergeSort SearchRank.scoreOrder |>.take 16) []
  require (((accumulated.positions.mergeSort SearchRank.scoreOrder).take 16) == expected)
    "complete accumulation changed the strongest numerical prefix"
  require (accumulated.positions.length == scores.length) "a scored window was discarded"
  let windows := (List.range 64).map fun index =>
    if index == 32 then "requested common" else "common"
  let lexical := SearchRank.lexical "requested common" windows
  let old := SearchRank.select 64 16 [] (SearchRank.fused [(List.range 64).take 16, lexical])
  let complete := focusedEvidenceWindows "requested common" windows (List.range 64)
  require (!old.contains 32 && complete.contains 32)
    "rank fusion still treats a truncated numerical tail as absent"
  require (complete.length == 16) "complete rank fusion enlarged the selected cue limit"
  IO.println "complete-window-order: 10 cases passed"
