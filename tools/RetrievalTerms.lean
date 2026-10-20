module

public import Eggshell.SearchRank
public import Eggshell.LogicalText
public import tools.RetrievalGrams

@[expose] public section

open Lean Eggshell

/-- Full-corpus diagnostic for gold-source rank and document-length analysis.
This runs outside the measured hook and does not populate a query cache. -/
def rankAudit : IO Unit := do
  let request ← IO.ofExcept (Json.parse (← (← IO.getStdin).getLine))
  let query ← IO.ofExcept (request.getObjValAs? String "query")
  let documents ← IO.ofExcept (request.getObjValAs? (List String) "documents")
  let wanted := RetrievalResearch.terms query
  let parsed := documents.map RetrievalResearch.terms
  let ranking : List Nat := RetrievalResearch.rank wanted parsed
  let positions : List (Nat × Nat) := ranking.zipIdx
  let rows := (documents.zip parsed).zipIdx.map fun ((text, terms), index) =>
    Json.mkObj [
      ("ordinal", toJson index), ("characters", toJson text.length),
      ("bytes", toJson text.utf8ByteSize),
      ("primaryTerms", toJson terms.primary.length), ("auxiliaryTerms", toJson terms.auxiliary.length),
      ("primaryMatches", toJson (wanted.primary.filter terms.primary.contains).length),
      ("auxiliaryMatches", toJson (wanted.auxiliary.filter terms.auxiliary.contains).length),
      ("rank", toJson ((positions.find? (fun (row : Nat × Nat) => row.1 == index)).map Prod.snd))]
  IO.println (Json.mkObj [("query", toJson query), ("queryTerms", toJson wanted),
    ("ranking", toJson ranking), ("documents", toJson rows),
    ("purpose", toJson "offline-full-corpus-lexical-rank-audit")]).compress

/-- Read-only inspection of the actual compiled lexical and identity lanes. -/
def main (args : List String) : IO UInt32 := do
  if args == ["--rank"] then
    rankAudit
    return 0
  for text in args do
    IO.println (Json.mkObj [
      ("text", toJson text), ("retrievalTerms", toJson (SearchRank.terms text)),
      ("identityUnits", toJson ((LogicalText.logical text).units.map (·.text))),
      ("candidate", toJson (RetrievalResearch.terms text))]).compress
  pure 0
