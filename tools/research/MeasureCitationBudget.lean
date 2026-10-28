import tools.research.ReferenceRequirements
import tools.SharedCoverageInput
import Lean.Data.Json.Parser
open Lean Eggshell Eggshell.Synapses Eggshell.Synapses.CanonicalSource
open Eggshell.Research

private def read (path : String) : IO Json := IO.FS.readFile path >>= fun s => IO.ofExcept (Json.parse s)

/-- A diagnostic lower bound for the entire seed-citation inventory, using
the exact original payload and frame charges. Labels never enter a selector. -/
def main (args : List String) : IO Unit := do
  let [originalsPath,inventoryPath,receiptPath,output] := args |
    throw (IO.userError "ORIGINALS INVENTORY TRACE-RECEIPT NEW-REPORT")
  unless !(← System.FilePath.pathExists output) do throw (IO.userError "preserve prior budget diagnostic")
  let inventory ← read inventoryPath
  let rawRows : Array StoredRow ← IO.ofExcept ((← read originalsPath).getObjValAs? _ "canonicalRows")
  let rows ← IO.ofExcept (Delivery.merge rawRows)
  let receipt := (← read receiptPath).getObjValD "data"
  let raw : SharedCoverage.Input.RawProblem ← IO.ofExcept (fromJson? (receipt.getObjValD "selectorInput"))
  let problem ← IO.ofExcept raw.decode
  let familyCount : Nat ← IO.ofExcept (receipt.getObjValAs? _ "families")
  let some basis := ReferenceRequirements.prepare familyCount rows problem |
    throw (IO.userError "reference rows do not match the actual original payload cost basis")
  let citations : Array Json ← IO.ofExcept (inventory.getObjValAs? _ "citations")
  let references ← citations.mapM fun value => do
    let citation := value.getObjValD "citation"
    return (← IO.ofExcept (citation.getObjValAs? String "path"),
      ← IO.ofExcept (citation.getObjValAs? Nat "first"),
      ← IO.ofExcept (citation.getObjValAs? Nat "last"))
  let mut frames : Std.HashMap File (Fin problem.costs.size) := {}
  for (row,atom) in basis.sourceRows do
    if !frames.contains row.key.file then
      let frame := Packet.fileFrame row.key.file (rows.filter (·.key.file == row.key.file))
      let index := atom.val-1
      unless problem.costs[index]? == some
          ((frame.leading ++ frame.trailing).length,(frame.leading ++ frame.trailing).utf8ByteSize) do
        throw (IO.userError "file provenance frame charge differs")
      if h : index < problem.costs.size then frames := frames.insert row.key.file ⟨index,h⟩
  let required := basis.sourceRows.filter fun (row,_) => references.any fun (path,first,last) =>
    row.key.file.relative == path && first ≤ row.key.line && row.key.line ≤ last
  let parts ← required.toList.mapM fun (row,atom) => do
    let some frame := frames[row.key.file]? | throw (IO.userError "required row lost its file provenance frame")
    return [frame,atom]
  let direct := hashDistinct parts.flatten
  let expanded := hashDistinct (direct ++ direct.flatMap fun atom => basis.dependencies[atom]?.getD [])
  let charge := fun (nodes : List (Fin problem.costs.size)) => nodes.foldl
    (fun total node => (total.1+problem.costs[node].1,total.2+problem.costs[node].2)) problem.fixed
  let selected := basis.selectedRows (expanded.map (·.val))
  let payloadCharge := required.foldl (fun total (_,atom) =>
    (total.1+problem.costs[atom].1,total.2+problem.costs[atom].2)) (0,0)
  let frameNodes := hashDistinct (parts.filterMap List.head?)
  let frameCharge := frameNodes.foldl (fun total atom =>
    (total.1+problem.costs[atom].1,total.2+problem.costs[atom].2)) (0,0)
  let mut literalRows : Std.HashMap (String × Nat) String := {}
  for value in citations do
    let path : String ← IO.ofExcept ((value.getObjValD "citation").getObjValAs? _ "path")
    let lines : Array Json ← IO.ofExcept (value.getObjValAs? _ "rows")
    for line in lines do
      let number : Nat ← IO.ofExcept (line.getObjValAs? _ "line")
      let code : String ← IO.ofExcept (line.getObjValAs? _ "code")
      if let some previous := literalRows[(path,number)]? then
        unless previous == code do throw (IO.userError "conflicting citation row bytes")
      literalRows := literalRows.insert (path,number) code
  let literalCharge := literalRows.fold (fun total (_,line) code =>
    let text := toString line ++ "\t" ++ code ++ "\n"
    (total.1+text.length,total.2+text.utf8ByteSize)) (0,0)
  let byFile := fun (values : Array StoredRow) =>
    (values.map (·.key.file.relative) |>.toList.eraseDups.toArray).map fun file =>
      (file,(values.filter (fun row => row.key.file.relative == file)).size)
  let result := Json.mkObj [("diagnosticOnly",toJson true),("labelInputToSelector",toJson false),
    ("citations",toJson references.size),("indexedCitationRows",toJson required.size),
    ("directCharge",toJson (charge direct)),("withReferenceDependenciesCharge",toJson (charge expanded)),
    ("payloadCharge",toJson payloadCharge),("provenanceFrameCharge",toJson frameCharge),
    ("allCitedLiteralRowPayloadCharge",toJson literalCharge),("allCitedLiteralRows",toJson literalRows.size),
    ("literalRowsAreOnlyDiagnostic",toJson true),
    ("fixed",toJson problem.fixed),("limit",toJson problem.limit),
    ("directRowsByFile",toJson (byFile (required.map Prod.fst))),
    ("expandedRowsByFile",toJson (byFile selected)),
    ("expandedSourceRows",toJson selected.size),
    ("unindexedNonblankRowsExcludedFromLowerBound",inventory.getObjValD "unindexedNonblankRows"),
    ("provesAll47Fit",toJson false),("answeringModels",toJson (0 : Nat)),("adopted",toJson false)]
  IO.FS.writeFile output result.pretty
  IO.println (Json.mkObj [("direct",toJson (charge direct)),("referenceClosure",toJson (charge expanded)),
    ("rows",toJson required.size),("expandedRows",toJson selected.size)]).compress
