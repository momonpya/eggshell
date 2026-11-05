import Lean.Data.Json.FromToJson
import Lean.Data.Json.Parser
open Lean
def base : System.FilePath := "/Users/ovm/.codex/experiments/eggshell/scope-token-study-20261028/fixed-frame-study"
def destination : System.FilePath := "/Users/ovm/.codex/worktrees/hook-deadline-baseline/eggshell/docs/candidates/numerical-ready"
def read (path : System.FilePath) : IO Json := do IO.ofExcept (Json.parse (← IO.FS.readFile path))
def number (value : Json) (key : String) : Nat := (value.getObjValAs? Nat key).toOption.getD 0
def distribution (values : Array Nat) : Json := Id.run do
  let sorted := values.qsort (· < ·)
  return Json.mkObj [("count",toJson sorted.size),("min",toJson sorted[0]?),
    ("median",toJson sorted[sorted.size/2]?),("max",toJson sorted.back?)]
def main : IO Unit := do
  let output := destination/"numerical-metrics.json"
  unless !(← output.pathExists) do throw (IO.userError "metrics already sealed")
  let root := base/"numerical-ready-on80-1-result"
  let prime ← read (root/"prime.json")
  let primeRows ← IO.ofExcept (prime.getObjValAs? (Array Json) "receipts")
  let primeIds := primeRows.map (·.getObjValD "receipt")
  let mut rows := #[]
  for folder in ← (root/"private/receipts").readDir do
    if primeIds.contains (toJson folder.fileName) || !(← (folder.path/"request-pages.json").pathExists) then continue
    for file in ← folder.path.readDir do
      if file.fileName.startsWith "numerical-" && file.fileName.endsWith ".json" then
        rows := rows.push (Json.mkObj [("receipt",toJson folder.fileName),("observation",← read file.path)])
  unless rows.size == 57 do throw (IO.userError "partial scoring metric domain changed")
  let data := rows.map (fun row => (row.getObjValD "observation").getObjValD "data")
  let counters := data.map (·.getObjValD "counters")
  let summaries := ["scoreMs","projectionReadMsWithinScore","scoredWindows","projectionHits","projectionMisses","projectionRetainedBytes"].map
    (fun key => (key,distribution (counters.map (number · key))))
  IO.FS.writeFile output (Json.mkObj [("rows",toJson rows),("scoringQueries",toJson rows.size),
    ("wallAndCompletedReplyCounters",Json.mkObj summaries),
    ("completedReplyKernelScoreUs",distribution (counters.map (fun value => number (value.getObjValD "encoder") "scoreUs"))),
    ("failedRepliesAndIncompleteCurrentRpcNotMeasured",toJson true),
    ("overlappingQueryWallTimesNotAdditive",toJson true),("adopted",toJson false)]).pretty
