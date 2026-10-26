import tools.ContentCorrespondence
import Lean.Data.Json.FromToJson
open Lean ContentCorrespondence

private def check (condition : Bool) (message : String) : IO Unit :=
  unless condition do throw (IO.userError message)

def main : IO Unit := do
  let inputs := #[#["header","if (条件)","  結果();","}"],#["another","}","끝"]]
  let some index := prepare? inputs | throw (IO.userError "complete content index failed")
  let some anchor := index.unique? "if (条件)" | throw (IO.userError "unique input record was lost")
  check (anchor.position == (0,1)) "unique record acquired another source location"
  check ((index.unique? "}").isNone) "ambiguous repeated content acquired a location"
  check ((index.unique? "unrelated MCP JSON").isNone) "opaque external data acquired a file location"
  check ((checkedIndex? inputs {}).isNone) "an incomplete index permitted negative decisions"
  let output := #["if (条件)","  結果();","}"]
  check ((run? inputs output 0 1 0 3).isSome) "literal adjacent context did not match"
  check ((anchoredRun? index output ⟨0,by decide⟩ anchor 0 3).isSome)
    "a unique anchor did not retain its literal neighboring records"
  check ((anchoredRun? index output ⟨0,by decide⟩ anchor 1 1).isNone)
    "a run not containing its anchor was admitted"
  check ((run? inputs #["if (条件)","fabricated","}"] 0 1 0 3).isNone)
    "a mismatch was filled from neighboring context"
  check ((run? inputs output 1 0 0 3).isNone && (run? inputs output 0 2 0 3).isNone)
    "a foreign or out-of-bounds sequence was admitted"
  let changed := inputs.set! 0 #["header","if (changed)","  結果();","}"]
  let some changedIndex := prepare? changed | throw (IO.userError "changed input index failed")
  check ((changedIndex.unique? "if (条件)").isNone) "changed input retained a stale correspondence"
  let many := #[(Array.range 10000).map fun index => s!"original-{index}"]
  let some large := prepare? many | throw (IO.userError "bounded large input index failed")
  check ((large.unique? "original-9999").map (·.position) == some (0,9999)) "tail input was lost"
  let mut streamed := start #["original-0","original-9999","not-appearing"]
  for row in [:many[0]!.size] do
    streamed := observe streamed (0,row) many[0]![row]!
  check (streamed.size == 3 && streamed["original-9999"]? == some (.one (0,9999)) &&
      streamed["not-appearing"]? == some .absent) "streaming state grew with input or lost its tail"
  let repeated := observe (observe (start #["}"]) (0,3) "}") (0,3) "}"
  check (repeated["}"]? == some (.one (0,3))) "one input replay manufactured ambiguity"
  check ((observe repeated (1,1) "}")["}"]? == some .ambiguous)
    "two input positions were silently merged"
  IO.println (Json.mkObj [("commandInputs",toJson (0 : Nat)),("inputRecords",toJson (10000 : Nat)),
    ("ambiguousNotAssigned",toJson true),("mismatchNotInvented",toJson true),
    ("changedInputRejected",toJson true),("completeIndexRequired",toJson true),
    ("streamStateEntries",toJson streamed.size),("duplicateMergeIdempotent",toJson true),
    ("captureAdapterIntegrated",toJson false),("productionAdoption",toJson false)]).compress
