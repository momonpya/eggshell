import Lean.Data.Json.Parser
import Lean.Data.Json.FromToJson
open Lean

private def read (path : String) : IO Json :=
  IO.FS.readFile path >>= fun text => IO.ofExcept (Json.parse text)

private def rows (value : Json) (name : String) : IO (Array Json) :=
  IO.ofExcept (value.getObjValAs? (Array Json) name)

/-- Post-run join only: reference labels never reach the selector. -/
def main (args : List String) : IO Unit := do
  let [auditPath,planPath,output] := args |
    throw (IO.userError "ACTUAL-AUDIT TRACE-RECEIPT NEW-OUTPUT")
  unless !(← System.FilePath.pathExists output) do throw (IO.userError "preserve prior diagnosis")
  let audit ← read auditPath
  let plan := (← read planPath).getObjValD "data"
  let bindings ← rows audit "originalOutputBindings"
  let hints ← rows plan "bindingAudit"
  let selected ← IO.ofExcept (plan.getObjValAs? (List Nat) "selected")
  let mut result := #[]
  for requirement in ← rows audit "requirements" do
    if requirement.getObjValD "bodyDelivered" == toJson true then continue
    let name := requirement.getObjValD "name"
    let mut probes := #[]
    for binding in bindings.filter (fun row => row.getObjValD "name" == name) do
      let original := (binding.getObjValD "read").getObjValD "binding"
      let work := original.getObjValD "work"
      let first ← IO.ofExcept (original.getObjValAs? Nat "first")
      let limit ← IO.ofExcept (original.getObjValAs? Nat "limit")
      let lineFirst ← IO.ofExcept (binding.getObjValAs? Nat "referenceFirst")
      let lineLast ← IO.ofExcept (binding.getObjValAs? Nat "referenceLast")
      let mut related := #[]
      for hint in hints do
        let source := hint.getObjValD "source"
        let subject := source.getObjValD "subject"
        let start ← IO.ofExcept (source.getObjValAs? Nat "first")
        let stop ← IO.ofExcept (source.getObjValAs? Nat "last")
        let isOriginal := (((subject.getObjValD "original").getObjValD "original").getObjValD "work") == work
        let isFile := ((subject.getObjValD "file").getObjValD "file") == binding.getObjValD "file"
        let overlap := (isOriginal && start-1 < limit && first < stop) ||
          (isFile && start ≤ lineLast && lineFirst ≤ stop)
        if !overlap then continue
        let alternatives ← IO.ofExcept (hint.getObjValAs? (List (List Nat)) "alternatives")
        related := related.push (hint.setObjVal! "someAlternativeSelected"
          (toJson (alternatives.any fun choice => !choice.isEmpty && choice.all selected.contains)))
      probes := probes.push (Json.mkObj [("owner",original.getObjValD "owner"),
        ("first",toJson first),("limit",toJson limit),("hints",toJson related)])
    result := result.push (Json.mkObj [("name",name),("origins",toJson probes)])
  IO.FS.writeFile output (Json.mkObj [("missing",toJson result),("actualReceipt",toJson planPath),
    ("answeringModelCalls",toJson (0 : Nat)),("adopted",toJson false)]).pretty
  IO.println (toJson result).compress
