module

public import Eggshell.SearchRank
public import Eggshell.LogicalText
public import tools.RetrievalGrams

@[expose] public section

open Lean Eggshell

/-- Read-only inspection of the actual compiled lexical and identity lanes. -/
def main (args : List String) : IO UInt32 := do
  for text in args do
    IO.println (Json.mkObj [
      ("text", toJson text), ("retrievalTerms", toJson (SearchRank.terms text)),
      ("identityUnits", toJson ((LogicalText.logical text).units.map (·.text))),
      ("candidate", toJson (RetrievalResearch.terms text))]).compress
  pure 0
