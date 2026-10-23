import tools.research.StudyAccounting

open Lean Eggshell.Research.StudyAccounting

private def check (condition : Bool) (message : String) : IO Unit :=
  unless condition do throw (IO.userError message)

private def record (method : String) (params : Json) : Json :=
  Json.mkObj [("direction",toJson "server"),("message",Json.mkObj
    [("method",toJson method),("params",params)])]

private def scopedParams (fields : List (String × Json)) : Json :=
  Json.mkObj ([("threadId",toJson "thread"),("turnId",toJson "turn")] ++ fields)

private def count (input output : Nat) : Json := toJson (Counters.mk (input+output) input output 80 4)

private def tokenEvent (counters : Json) : Json := record "thread/tokenUsage/updated"
  (scopedParams [("tokenUsage",Json.mkObj [("total",counters)])])

#eval show IO Unit from do
  let scope : Scope := ⟨"thread","turn",Eggshell.Sha256.hex "body".toUTF8⟩
  let first ← IO.ofExcept (consume scope {} (tokenEvent (count 100 10)))
  let duplicate ← IO.ofExcept (consume scope first (tokenEvent (count 100 10)))
  check (duplicate.lastUsage.map Usage.inclusive == some 110) "cumulative totals were double counted"
  check ((usage (toJson (Counters.mk 194 100 10 80 4))).toOption.isNone) "cached/reasoning charges were added twice"
  check ((usage (toJson (Counters.mk 110 100 10 101 4))).toOption.isNone) "cache exceeds input"
  check ((usage (toJson (Counters.mk 110 100 10 80 11))).toOption.isNone) "reasoning exceeds output"
  check ((consume scope first (tokenEvent (count 99 10))).toOption.isNone) "decreasing cumulative usage was admitted"
  let other := record "thread/tokenUsage/updated" (Json.mkObj [("threadId",toJson "other"),
    ("turnId",toJson "turn"),("tokenUsage",Json.mkObj [("total",count 1000 100)])])
  let ignored ← IO.ofExcept (consume scope first other)
  check (ignored.lastUsage.map Usage.inclusive == some 110) "another thread changed trial cost"
  let unfinished := report scope first
  check ((unfinished.getObjValAs? Bool "unknownFinalUsage").toOption == some true)
    "a partial trace was given a known final cost"
  check ((unfinished.getObjValAs? Nat "observedInclusiveTokens").toOption == some 110)
    "partial trace cost was lost"
  let terminal := record "turn/completed" (Json.mkObj [("threadId",toJson "thread"),
    ("turn",Json.mkObj [("id",toJson "turn"),("status",toJson "completed")])])
  let finished ← IO.ofExcept (consume scope first terminal)
  check (((report scope finished).getObjValAs? Bool "finalUsageKnown").toOption == some true)
    "completed usage was not recognized"
  check (((report scope {finished with issues := #["broken JSON"]}).getObjValAs? Bool "unknownFinalUsage").toOption == some true)
    "malformed trace was given a known final cost"
  let hook := record "hook/completed" (scopedParams [("run",Json.mkObj [
    ("id",toJson "one"),("eventName",toJson "userPromptSubmit"),("status",toJson "completed"),
    ("durationMs",toJson (30000 : Nat)),("entries",toJson #[Json.mkObj
      [("kind",toJson "context"),("text",toJson "body")]])])])
  let delivered ← IO.ofExcept (consume scope finished hook)
  let redelivered ← IO.ofExcept (consume scope delivered hook)
  check (redelivered.hookCount == 1 && redelivered.packets.size == 1) "duplicate hook was counted twice"
  check (redelivered.hookFailures.size == 1) "30-second boundary was admitted"
  check (((report scope redelivered).getObjValAs? Bool "initialBodyMatched").toOption == some true)
    "actual initial body hash was not checked"
  let rerouted ← IO.ofExcept (consume scope finished (record "model/rerouted" (scopedParams [])))
  check (rerouted.lastUsage.map Usage.inclusive == some 110 && rerouted.reroutes.size == 1)
    "rerouted cost was discarded"
  IO.println "StudyAccounting checks passed"
