import Lean.Data.Json.FromToJson
import Lean.Data.Json.Parser
import Std.Data.HashMap

open Lean

namespace HookLatencyAudit

private structure Run where
  key : String
  thread : String
  turn : String
  event : String
  status : String
  ms : Nat
  deriving ToJson

private def percentile (values : Array Nat) (percent : Nat) : Nat :=
  let sorted := values.qsort (· < ·)
  sorted[((percent * sorted.size + 99) / 100) - 1]?.getD 0

private def stats (runs : Array Run) : Json :=
  let values := runs.map (·.ms)
  Json.mkObj [
    ("count", toJson runs.size), ("sumMs", toJson (values.foldl (· + ·) 0)),
    ("p50Ms", toJson (percentile values 50)), ("p95Ms", toJson (percentile values 95)),
    ("sampleP99Ms", toJson (percentile values 99)),
    ("maxMs", toJson (values.foldl max 0)),
    ("failedOrIncomplete", toJson (runs.filter (·.status != "completed")).size),
    ("atLeast30Seconds", toJson (values.filter (· ≥ 30000)).size)]

/-- Stream saved caller notifications, pair starts/terminals by full scope, and
retain every terminal status. Summed durations are handler cost, not elapsed
turn wall time: callers can overlap executions. No search or model is run. -/
def audit (path : System.FilePath) : IO Json := do
  unless (← path.metadata).byteSize ≤ 256 * 1024 * 1024 do
    throw (IO.userError "latency trace exceeds bound")
  let input ← IO.FS.Handle.mk path .read
  let mut starts : Std.HashMap String String := {}
  let mut finishes : Std.HashMap String String := {}
  let mut runs : Array Run := #[]
  repeat
    let line ← input.getLine
    if line.isEmpty then break
    let row ← IO.ofExcept (Json.parse line)
    if (row.getObjValAs? String "direction").toOption != some "server" then continue
    let .ok message := row.getObjVal? "message" | continue
    let method := (message.getObjValAs? String "method").toOption
    if method != some "hook/started" && method != some "hook/completed" then continue
    let params ← IO.ofExcept (message.getObjVal? "params")
    let thread ← IO.ofExcept (params.getObjValAs? String "threadId")
    let turn := (params.getObjValAs? String "turnId").toOption.getD ""
    let run ← IO.ofExcept (params.getObjVal? "run")
    let id ← IO.ofExcept (run.getObjValAs? String "id")
    let event ← IO.ofExcept (run.getObjValAs? String "eventName")
    let key := (toJson [thread, turn, id]).compress
    if method == some "hook/started" then
      if starts.contains key then throw (IO.userError "duplicate hook start")
      starts := starts.insert key event
    else
      if finishes.contains key then throw (IO.userError "duplicate hook terminal")
      finishes := finishes.insert key event
      let status ← IO.ofExcept (run.getObjValAs? String "status")
      let ms ← IO.ofExcept (run.getObjValAs? Nat "durationMs")
      runs := runs.push {key, thread, turn, event, status, ms}
  let missing := starts.toArray.filter fun (key, _) => !finishes.contains key
  let unmatched := finishes.toArray.filter fun (key, event) => starts[key]? != some event
  let mut events : Array String := #[]
  let mut turns : Array (String × String) := #[]
  for run in runs do
    if !events.contains run.event then events := events.push run.event
    if !turns.contains (run.thread, run.turn) then turns := turns.push (run.thread, run.turn)
  let toolRuns := runs.filter fun run => ["preToolUse", "postToolUse"].contains run.event
  return Json.mkObj [
    ("scope", toJson "saved App Server handler durations; no new hook or answering model"),
    ("input", toJson path.toString), ("completeStartTerminalPairs", toJson (missing.isEmpty && unmatched.isEmpty)),
    ("missingTerminals", toJson missing), ("unmatchedTerminals", toJson unmatched),
    ("events", toJson (events.map fun event =>
      (stats (runs.filter (·.event == event))).setObjVal! "event" (toJson event))),
    ("prePostCombined", stats toolRuns),
    ("turns", toJson (turns.map fun (thread, turn) =>
      let cost := stats (toolRuns.filter fun run => run.thread == thread && run.turn == turn)
      (cost.setObjVal! "threadId" (toJson thread)).setObjVal! "turnId" (toJson turn))),
    ("runs", toJson runs), ("largeWarmDbQualified", toJson false),
    ("predefinedP99Cohort", toJson false), ("answeringModelCalls", toJson (0 : Nat))]

end HookLatencyAudit

def main (args : List String) : IO Unit := do
  let [input, output] := args | throw (IO.userError "HookLatencyAudit EXCHANGE.jsonl NEW-REPORT.json")
  let output := System.FilePath.mk output
  if ← output.pathExists then throw (IO.userError "keep existing latency report")
  IO.FS.writeFile output ((← HookLatencyAudit.audit (.mk input)).pretty ++ "\n")
