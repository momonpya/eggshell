import Lean.Data.Json.FromToJson
import Lean.Data.Json.Parser
open Lean
def read (path : System.FilePath) : IO Json := do IO.ofExcept (Json.parse (← IO.FS.readFile path))
def counts (values : Array String) : Json := Id.run do
  let mut rows : List (String × Nat) := []
  for value in values do
    if rows.any (·.1 == value) then rows := rows.map fun (name,n) => (name,n+if name == value then 1 else 0)
    else rows := rows++[(value,1)]
  return toJson rows
def main (args : List String) : IO Unit := do
  let [directory] := args | throw (IO.userError "retained controlled fixture required")
  let root : System.FilePath := .mk directory
  let mut reports := #[]
  for phase in ["writers","readers"] do
    let result ← read (root/(phase++"-results.json"))
    let rows ← IO.ofExcept (result.getObjValAs? (Array Json) "rows")
    let errors ← IO.ofExcept (result.getObjValAs? (Array Json) "errors")
    let mut statuses := #[]
    let mut routes := #[]
    let mut admissions := #[]
    let mut elapsed : List Nat := []
    for entry in ← root.readDir do
      let selected := if phase == "writers" then entry.fileName.endsWith "-initial-UserPromptSubmit-measurement.json"
        else entry.fileName.endsWith "-readback-UserPromptSubmit-measurement.json"
      if !selected then continue
      let row ← read entry.path
      elapsed := ((row.getObjValAs? Nat "elapsedMs").toOption.getD 0)::elapsed
      let receipt ← IO.ofExcept (row.getObjValAs? String "receipt")
      let folder := root/"private/receipts"/receipt
      let mut admitted := 0
      if ← folder.pathExists then
        for entry in ← folder.readDir do
          if entry.fileName.startsWith "operation-" && entry.fileName.endsWith "-admitted.json" then admitted := admitted+1
      admissions := admissions.push (toString admitted)
      let searched := folder/"search.json"
      if ← searched.pathExists then
        let trace := (← read searched).getObjValD "data" |>.getObjValD "trace"
        statuses := statuses.push (trace.getObjValD "semantic").compress
        routes := routes.push (trace.getObjValD "route").compress
      else statuses := statuses.push "unobserved"
    let ordered := elapsed.mergeSort (· ≤ ·)
    reports := reports.push (Json.mkObj [("phase",toJson phase),("completeClients",toJson rows.size),
      ("errors",toJson errors),("semantic",counts statuses),("route",counts routes),
      ("admissionsPerReceipt",counts admissions),("minMs",toJson (ordered.headD 0)),
      ("maxMs",toJson (ordered.getLast?.getD 0))])
  IO.println (toJson reports).compress
