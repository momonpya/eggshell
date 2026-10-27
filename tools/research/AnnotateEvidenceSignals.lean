import Lean.Data.Json.Parser
import Lean.Data.Json.FromToJson
import Std.Data.HashMap
open Lean

private def read (path : String) : IO Json :=
  IO.FS.readFile (.mk path) >>= fun text => IO.ofExcept (Json.parse text)

private def array (value : Json) (field : String) : IO (Array Json) :=
  IO.ofExcept (value.getObjValAs? (Array Json) field)

private def nat (value : Json) (field : String) : Nat :=
  (value.getObjValAs? Nat field).toOption.getD 0

private def overlap (row : Json) (first last : Nat) (lastField : String := "limit") : Nat :=
  min last (nat row lastField) - max first (nat row "first")

/-- Frozen labels are opened only after the label-free feature table exists.
This program has no DB/selector/provider access and cannot affect delivery. -/
def main (args : List String) : IO Unit := do
  let [tablePath,frozenPath,auditPath,outputPath] := args |
    throw (IO.userError "completed signal table, frozen requirements, actual audit, new output")
  unless !(← (System.FilePath.mk outputPath).pathExists) do throw (IO.userError "preserve the previous annotation")
  let table ← read tablePath
  unless table.getObjValD "usesFrozenLabels" == toJson false &&
      table.getObjValD "selectorCalls" == toJson (0 : Nat) do
    throw (IO.userError "label-free diagnostic table required")
  let families ← array table "families"
  let frozen ← read frozenPath
  let actual ← read auditPath
  let observed ← array actual "requirements"
  let mut requirements := #[]
  for required in ← array frozen "requirements" do
    let name := (required.getObjValD "reference").getObjValD "name"
    let stored := required.getObjValD "storedOriginal"
    let some audit := observed.find? (fun row => row.getObjValD "name" == name) |
      throw (IO.userError "actual delivery audit lacks a frozen item")
    let mut bindings := #[]
    for original in ← array required "originalRows" do
      let binding := original.getObjValD "binding"
      let owner := binding.getObjValD "owner"
      let first := nat binding "first"
      let last := nat binding "limit"
      let some family := families.find? (fun row => row.getObjValD "owner" == owner) |
        throw (IO.userError "frozen owner was absent from the recorded hydrated domain")
      let atoms := (family.getObjValAs? (Array Json) "atoms").toOption.getD #[]
      let units := (family.getObjValAs? (Array Json) "units").toOption.getD #[]
      let overlapping := atoms.filter (0 < overlap · first last)
      let covering := units.filter fun unit =>
        ((unit.getObjValAs? (Array Json) "ranges").toOption.getD #[]).any fun row =>
          nat row "first" ≤ first && last ≤ nat row "limit"
      let overlappingUnits := units.filter fun unit =>
        ((unit.getObjValAs? (Array Json) "ranges").toOption.getD #[]).any (0 < overlap · first last)
      let dominated := overlapping.foldl (fun n row => n +
        if row.getObjValD "directStrictlyDominated" == toJson true then overlap row first last else 0) 0
      let hints := (← array family "graphHints").filter fun hint =>
        let source := hint.getObjValD "source"
        min last (nat source "last") > max first (nat source "first" - 1)
      let brief := covering.map fun unit => Json.mkObj
        (["id","standaloneCost","actualValue","sameReconstructedValue","selected"].map fun key =>
          (key,unit.getObjValD key))
      bindings := bindings.push (Json.mkObj [
        ("owner",owner),("first",toJson first),("limit",toJson last),
        ("ownerFocusRank",family.getObjValD "ownerFocusRank"),("unitAudit",family.getObjValD "unitAudit"),
        ("selectedOwnerUnits",family.getObjValD "selectedUnits"),
        ("strictlyDominatedDirectCharacters",toJson dominated),("originalCharacters",toJson (last-first)),
        ("overlappingAtoms",toJson overlapping),("completeSingleCandidates",toJson brief),
        ("overlappingCandidates",toJson overlappingUnits.size),("overlappingGraphHints",toJson hints)])
    requirements := requirements.push (Json.mkObj [("name",name),("storedOriginal",stored),
      ("bodyDelivered",audit.getObjValD "bodyDelivered"),("bindings",toJson bindings)])
  let result := Json.mkObj [("source",table.getObjValD "source"),("index",table.getObjValD "index"),
    ("requirements",toJson requirements),("requiredDelivery",actual.getObjValD "requiredDelivery"),
    ("collectionFinishedBeforeLabelsWereOpened",toJson true),("changesSelection",toJson false),
    ("explainsObservedAggregationNotCausalRepair",toJson true),("answeringModelCalls",toJson (0 : Nat))]
  IO.FS.writeFile (.mk outputPath) result.compress
  let summary := requirements.map fun row =>
    let bindings := (row.getObjValAs? (Array Json) "bindings").toOption.getD #[]
    let compact := bindings.map fun binding => Json.mkObj
      (["owner","ownerFocusRank","originalCharacters","strictlyDominatedDirectCharacters",
        "selectedOwnerUnits","unitAudit","completeSingleCandidates"].map fun key => (key,binding.getObjValD key))
    Json.mkObj [("name",row.getObjValD "name"),("bodyDelivered",row.getObjValD "bodyDelivered"),
      ("bindings",toJson compact)]
  IO.println (Json.mkObj [("requiredDelivery",actual.getObjValD "requiredDelivery"),
    ("requirements",toJson summary)]).compress
