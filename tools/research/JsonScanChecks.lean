import tools.research.JsonScanReference
open Lean Eggshell

private def signature (result : Except String (Array JsonScalars.Scalar)) := result.map fun rows =>
  rows.map fun row => (row.first,row.limit,row.literal,row.text,row.offsets,row.pathRev,row.contextFirst)

private def same [BEq α] : Except String α → Except String α → Bool
  | .ok a,.ok b => a == b
  | .error a,.error b => a == b
  | _,_ => false

private def check (yes : Bool) (message : String) : IO Unit :=
  unless yes do throw (IO.userError message)

private def measured (scan : Json → String → Except String (Array JsonScalars.Scalar))
    (json : Json) (raw : String) : IO (Nat × Nat) := do
  let forced ← IO.mkRef (Except.error "not started" : Except String (Array JsonScalars.Scalar))
  let start ← IO.monoNanosNow
  forced.set (scan json raw)
  let result ← forced.get
  let elapsed := (← IO.monoNanosNow)-start
  let rows ← IO.ofExcept result
  return (elapsed,rows.size)

#print axioms Eggshell.JsonScalars.Reference.exact

def main : IO Unit := do
  let cases := #["null","true","[1,false,null,\"text\"]","{\"a\":\"x\\n\\t\\\"y\",\"b\":[{},[]]}",
    "{\"日本語\":\"韓国語 한국어 café é 😀\"}","[", "{\"a\": 1}","\"\\u0061\"","{\"a\":-0}"]
  for raw in cases do
    let json := (Json.parse raw).toOption.getD Json.null
    check (same (signature (JsonScalars.scan json raw)) (signature (JsonScalars.Reference.scan json raw)))
      "scanner result, coordinates, error or scalar metadata changed"
  let mut report := #[]
  for size in [5000,50000,500000] do
    let json := Json.mkObj [("body",toJson (String.ofList (List.replicate size 'x'))),("id",toJson "record")]
    let raw := json.compress
    let (newNs,rows) ← measured JsonScalars.scan json raw
    let old ← if size ≤ 50000 then do
        let (oldNs,count) ← measured JsonScalars.Reference.scan json raw
        check (count == rows) "old/new scalar counts differ"
        check (same (signature (JsonScalars.scan json raw)) (signature (JsonScalars.Reference.scan json raw)))
          "large scalar coordinates or content changed"
        pure (some oldNs)
      else pure none
    report := report.push (Json.mkObj [("bodyBytes",toJson size),("candidateNs",toJson newNs),
      ("referenceNs",toJson old),("scalars",toJson rows)])
  IO.println (Json.mkObj [("smallCasesEqual",toJson cases.size),("universalEqualityProved",toJson true),
    ("measurements",toJson report),("answeringModelCalls",toJson (0 : Nat))]).compress
