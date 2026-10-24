import Eggshell.VectorRoute
import Eggshell.SearchProvider
import Eggshell.CandidateDomain

open Lean Eggshell

private def cosine (a b : Array Float) : Except String Float := do
  unless a.size == b.size && !a.isEmpty do throw "score dimensions disagree"
  let mut dot := 0.0
  let mut aa := 0.0
  let mut bb := 0.0
  for i in [:a.size] do
    dot := dot+a[i]!*b[i]!
    aa := aa+a[i]!*a[i]!
    bb := bb+b[i]!*b[i]!
  let norm := Float.sqrt aa*Float.sqrt bb
  unless 0.0 < norm && !norm.isInf && !norm.isNaN do throw "invalid score norm"
  return dot/norm

def main (args : List String) : IO Unit := do
  let [database,matrixRoot,comparison,output] := args |
    throw (IO.userError "RouteScoreGap DB MATRIX-ROOT COMPARISON NEW-OUTPUT")
  unless !(← (System.FilePath.mk output).pathExists) do throw (IO.userError "keep old score diagnostic")
  let report ← IO.ofExcept (Json.parse (← IO.FS.readFile (.mk comparison)))
  let question ← IO.ofExcept (report.getObjValAs? String "question")
  let source ← DB.PageMap.pin (.mk database)
  let some domain ← CandidateDomain.openShared? source | throw (IO.userError "source domain missing")
  let some matrix ← VectorMatrix.open? (.mk matrixRoot) MiniLM.model SearchProvider.encoderContract |
    throw (IO.userError "matrix missing")
  let options : SearchProvider.Options := {cache := (← Paths.dataRoot) / "queries",models := .mk "unused"}
  let queries ← SearchProvider.vectors options question
  let queries ← IO.ofExcept queries.getArr?
  let decoded ← queries.toList.mapM fun q => IO.ofExcept (q.getStr? >>= WindowCentroid.unpack)
  let mut groups := #[]
  for field in ["referenceRelatedRoots","routedRelatedRoots"] do
    let roots ← IO.ofExcept (report.getObjValAs? (List Nat) field)
    let mut rows := #[]
    for root in roots do
      let some owner := domain.owners[root]? | throw (IO.userError "not an original owner")
      let mut best : Option Float := none
      for window in owner.windows do
        let some (_,packed) ← VectorMatrix.read matrix window | throw (IO.userError "original vector missing")
        let vector ← IO.ofExcept (WindowCentroid.unpack packed)
        for query in decoded do
          let score ← IO.ofExcept (cosine query vector)
          best := some (best.map (fun old => if old < score then score else old) |>.getD score)
      rows := rows.push (Json.mkObj [("root",toJson root),("cosine",toJson best)])
    groups := groups.push (Json.mkObj [("set",toJson field),("rows",toJson rows)])
  let result := Json.mkObj [("scope",toJson "independent Lean cosine on original full vectors; diagnostic scores, not a claim of bitwise equality with NumPy, source relevance, answer quality or token savings"),
    ("groups",toJson groups),("newEmbeddingCalls",toJson (0 : Nat)),("adopted",toJson false)]
  IO.FS.writeFile (.mk output) result.pretty
  IO.println result.compress
