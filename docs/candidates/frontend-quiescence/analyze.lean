import Lean.Data.Json.FromToJson
import Lean.Data.Json.Parser
open Lean
def read (path : System.FilePath) : IO Json := do IO.ofExcept (Json.parse (← IO.FS.readFile path))
def counts (values : Array String) : Json := Id.run do
  let mut result : List (String × Nat) := []
  for value in values do
    if result.any (·.1 == value) then result := result.map fun (key,n) => (key,n+if key == value then 1 else 0)
    else result := result++[(value,1)]
  return toJson result
def metrics (values : Array Nat) : Json :=
  let ordered := values.toList.mergeSort (· ≤ ·)
  Json.mkObj [("count",toJson values.size),("min",toJson (ordered.headD 0)),
    ("median",toJson (ordered[ordered.length/2]?.getD 0)),("max",toJson (ordered.getLast?.getD 0))]
def datum (folder : System.FilePath) (name : String) : IO Json := do
  let path := folder/(name++".json")
  if !(← path.pathExists) then return Json.null
  return (← read path).getObjValD "data"
def main (args : List String) : IO Unit := do
  let [directory] := args | throw (IO.userError "retained fixture required")
  let root : System.FilePath := .mk directory
  let mut queue := #[]
  let mut work := #[]
  let mut capture := #[]
  let mut dispatch := #[]
  let mut inputStates := #[]
  let mut semantic := #[]
  let mut lexical := #[]
  let mut before := #[]
  let mut delivery := #[]
  let mut validMissing := #[]
  for entry in ← root.readDir do
    if !entry.fileName.startsWith "reader-" || !entry.fileName.endsWith "-measurement.json" then continue
    let measurement ← read entry.path
    let receipt ← IO.ofExcept (measurement.getObjValAs? String "receipt")
    let folder := root/"private/receipts"/receipt
    let inputs ← datum folder "prepared-inputs-turn"
    inputStates := inputStates.push (inputs.getObjValD "status").compress
    let service ← datum folder "operation-service"
    let searched ← datum folder "search"
    let body := (measurement.getObjValAs? String "body").toOption.getD ""
    let head := body.contains "observed-head-case-79-7b319c"
    let tail := body.contains "observed-tail-case-79-d82a04"
    let trace := searched.getObjValD "trace"
    delivery := delivery.push s!"{(trace.getObjValD "route").compress}/{(trace.getObjValD "semantic").compress}/{head}/{tail}"
    if measurement.getObjValD "complete" == toJson true && !(head && tail) then
      let cited := (List.range 80).filter fun i => body.contains s!"mcp://support/case-{i})" || body.contains s!"mcp://support/case-{i}\""
      let rawHeads := (List.range 80).filter fun i => body.contains s!"observed-head-case-{i}-7b319c"
      validMissing := validMissing.push (Json.mkObj [("hook",toJson entry.fileName),
        ("bodyBytes",toJson body.utf8ByteSize),("head",toJson head),("tail",toJson tail),
        ("citedCases",toJson cited),("rawHeadCases",toJson rawHeads),("search",searched)])
    if service != Json.null then
      queue := queue.push ((service.getObjValAs? Nat "queueMs").toOption.getD 0)
      work := work.push ((service.getObjValAs? Nat "workMs").toOption.getD 0)
    else before := before.push (Json.mkObj [("hook",toJson entry.fileName),("inputs",inputs),
      ("dispatch",← datum folder "dispatch"),("search",← datum folder "search")])
    if inputs.getObjValD "status" == toJson "complete" then
      capture := capture.push (["boundaryMs","referenceMs","ownerMs","attachMs"].foldl
        (fun n key => n+(inputs.getObjValAs? Nat key).toOption.getD 0) 0)
    if let .ok ms := (← datum folder "dispatch").getObjValAs? Nat "elapsedMs" then dispatch := dispatch.push ms
    for (name,which) in [("search-phase-semantic",true),("search-phase-lexical",false)] do
      let phase ← datum folder name
      if let .ok ms := phase.getObjValAs? Nat "elapsedMs" then
        if which then semantic := semantic.push ms else lexical := lexical.push ms
  let result ← read (root/"readers-results.json")
  let errors ← IO.ofExcept (result.getObjValAs? (Array Json) "errors")
  let reasons := errors.map fun row =>
    let text := (row.getObjValAs? String "error").toOption.getD ""
    if text.contains "ordinary hook failed" then "hook-incomplete-or-deadline"
    else if text.contains "omitted" then "valid-hook-missing-frozen-fields" else text
  let report := Json.mkObj [("serviceQueueMs",metrics queue),("serviceWorkMs",metrics work),
    ("captureMs",metrics capture),("dispatchMs",metrics dispatch),("inputStates",counts inputStates),
    ("semanticPhaseMs",metrics semantic),("lexicalPhaseMs",metrics lexical),("errorReasons",counts reasons),
    ("deliveryGroups",counts delivery),("validMissing",toJson validMissing),
    ("withoutFinalServiceObservation",toJson before)]
  IO.FS.writeFile (root/"readback-analysis.json") (report.compress++"\n")
  let details := validMissing.map fun row => Json.mkObj
    (["bodyBytes","citedCases","rawHeadCases"].map fun key => (key,row.getObjValD key))
  let compact := report.setObjVal! "withoutFinalServiceObservation" (toJson before.size)
    |>.setObjVal! "validMissing" (toJson details)
  IO.println compact.compress
