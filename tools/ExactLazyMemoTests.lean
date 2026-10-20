import tools.ExactLazyMemo
import Lean.Data.Json

open Lean Eggshell.ExactLazyMemo

private def checkedValue (key : Nat) : Nat :=
  dbg_trace s!"lazy-evaluation {key}"; key * key + 7

private def checkedLarge (key : Nat) : Nat :=
  dbg_trace s!"large-evaluation {key}"; key * key + 7

def main : IO UInt32 := do
  let tree := make checkedValue 10 12
  let addresses := [10, 11, 17, 1023, 3000, 4105]
  let mut comparisons := 0
  for _ in [:3] do
    for key in addresses ++ addresses.reverse do
      unless read checkedValue tree key == key * key + 7 do
        throw (IO.userError "lazy memo changed an in-domain value")
      comparisons := comparisons + 1
  for key in [0, 9, 4106, 10000] do
    unless read checkedValue tree key == key * key + 7 do
      throw (IO.userError "lazy memo aliased an out-of-domain address")
    comparisons := comparisons + 1
  let optionTree := make (fun key => if key % 2 == 0 then some key else none) 0 4
  for key in [:32] do
    unless read (fun key => if key % 2 == 0 then some key else none) optionTree key ==
        (if key % 2 == 0 then some key else none) do
      throw (IO.userError "lazy memo changed an absent value or outside result")
    comparisons := comparisons + 1
  -- Source-coordinate pairs can name a huge domain. Only the visited paths
  -- may be allocated, and a repeated lookup must not rerun its computation.
  let large := make checkedLarge 0 40
  let addresses := [0, 2 ^ 39, 2 ^ 40 - 1]
  for _ in [:3] do
    for key in addresses ++ addresses.reverse do
      unless read checkedLarge large key == key * key + 7 do
        throw (IO.userError "large lazy domain changed a requested value")
      comparisons := comparisons + 1
  let outside := 2 ^ 40 + 3
  unless read checkedLarge large outside == outside * outside + 7 do
    throw (IO.userError "large lazy domain aliased an outside value")
  comparisons := comparisons + 1
  IO.println (Json.mkObj [("passed", toJson true), ("comparisons", toJson comparisons),
    ("expectedEvaluations", toJson (10 : Nat)), ("expectedLargeEvaluations", toJson (4 : Nat)),
    ("virtualDomainEntries", toJson (2 ^ 40 : Nat)), ("generationModelCalls", toJson (0 : Nat)),
    ("productionAdoption", toJson false)]).compress
  pure 0
