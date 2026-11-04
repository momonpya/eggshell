import Eggshell.SearchRank
import Lean.Data.Json.FromToJson
open Lean Eggshell
def main : IO Unit := do
  let query := "Return the recorded head and tail facts for support case-79."
  let request := "mcp__fixture__inspect\n{\"case\":\"case-79\",\"uri\":\"mcp://support/case-79\"}"
  let queryTerms := SearchRank.terms query
  let stored := SearchRank.terms request
  let shared := queryTerms.filter stored.contains
  let report := Json.mkObj [("query",toJson query),("queryTerms",toJson queryTerms),
    ("storedToolWork",toJson request),("storedTerms",toJson stored),("shared",toJson shared),
    ("queryWithoutPeriodTerms",toJson (SearchRank.terms (query.dropEnd 1).toString)),
    ("scope",toJson "Pure token-boundary diagnosis, not a ranking/grammar modification or a passed delivery test.")]
  IO.println report.compress
