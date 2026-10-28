import tools.research.ReferenceRequirements
import Eggshell.CanonicalSourceCache
import tools.SharedCoverageInput
import tools.VerifiedWinnerCoverage
import Lean.Data.Json.Parser

open Lean Eggshell Eggshell.Synapses Eggshell.Synapses.CanonicalSource
open Eggshell.Research.ReferenceRequirements

private def require (value : Bool) (message : String) : IO Unit := do
  unless value do throw (IO.userError message)

private def read (path : String) : IO Json := IO.FS.readFile path >>= fun text => IO.ofExcept (Json.parse text)

def main (args : List String) : IO Unit := do
  let [database,selectionPath,replayPath,output] := args |
    throw (IO.userError "DATABASE ACTUAL-SELECTION RECORDED-REPLAY NEW-OUTPUT")
  require (!(← System.FilePath.pathExists output)) "preserve earlier native checks"
  let tokenized (text : String) (run : Nat) := lex
    (text.toList.toArray.map fun c => ((c,⟨0,by decide⟩) : Char × Fin 1)) run
  require ((blocks (tokenized "bool root() { /* fake() { } */ return leaf(\"}) (\"); }\nbool leaf() { return 1; }" 0)).map (·.name)
    == #["root","leaf"]) "lexical extraction differs on comments and literals"
  require ((blocks (tokenized "bool root() {" 0 ++ tokenized "}" 1)).isEmpty) "an observation gap completed a block"
  require ((blocks (tokenized "if (ready) { emit(); }" 0)).map (·.name) == #["if"])
    "the extraction hid the declared control-statement limitation"
  let source ← DB.PageMap.pin (.mk database)
  let some ready ← Cache.open? source .database | throw (IO.userError "prepare the changed canonical view off-hook first")
  let actual := (← read selectionPath).getObjValD "data"
  let audit : Array Json ← IO.ofExcept (actual.getObjValAs? (α := Array Json) "rangeAudit")
  let names ← audit.mapM fun row => IO.ofExcept (row.getObjValAs? (α := String) "owner")
  let owners := Std.HashSet.ofArray names
  let rows ← IO.ofExcept (Delivery.merge (ready.registry.store.filterMap fun row =>
    let origins := row.origins.filter (fun origin => owners.contains origin.binding.owner)
    if origins.isEmpty then none else some {row with origins}))
  let raw : SharedCoverage.Input.RawProblem ← IO.ofExcept (fromJson? (actual.getObjValD "selectorInput"))
  let problem ← IO.ofExcept raw.decode
  let some prepared := prepare owners.size rows problem | throw (IO.userError "actual source cost basis differs")
  let conditioned : SharedCoverage.Problem := {problem with offers := prepared.offers problem.offers}
  let some selected := SharedCoverage.choose? conditioned | throw (IO.userError "conditional selection failed")
  let selectedRows := prepared.selectedRows ((SharedCoverage.nodes conditioned selected.selected).map (·.val))
  let replay := (← read replayPath).getObjValD "selectorReplay"
  let expected : Array Key ← IO.ofExcept (replay.getObjValAs? (α := Array Key) "candidateSourceRows")
  let expectedKeys := Std.HashSet.ofArray expected
  let actualKeys := Std.HashSet.ofArray (selectedRows.map (·.key))
  require (expectedKeys.size == actualKeys.size && expectedKeys.toList.all actualKeys.contains)
    "the extracted implementation changed the frozen shadow's selected original rows"
  require (toJson (SharedCoverage.cost conditioned selected.selected) == replay.getObjValD "candidateCost")
    "the extracted implementation changed the frozen shadow's payload cost"
  let report := Json.mkObj [("selectedSourceKeysMatchShadow",toJson true),("costMatchesShadow",toJson true),
    ("source",toJson source.head),("canonical",toJson ready.metadata),("sourceRows",toJson rows.size),
    ("selectedRows",toJson selectedRows.size),("shapeBlocks",toJson prepared.blocks),("callShapes",toJson prepared.calls),
    ("checkedLexicalCases",toJson (3 : Nat)),("cost",toJson (SharedCoverage.cost conditioned selected.selected)),
    ("bindingOrNecessityProved",toJson false),("actualDeliveryAsserted",toJson false),
    ("answeringModelCalls",toJson (0 : Nat)),("warmCalls",toJson (0 : Nat))]
  IO.FS.writeFile output report.pretty
  IO.println report.compress
