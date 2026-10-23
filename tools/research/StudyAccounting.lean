import Eggshell.Sha256
import Lean.Data.Json

open Lean

namespace Eggshell.Research.StudyAccounting

structure Counters where
  totalTokens : Nat
  inputTokens : Nat
  outputTokens : Nat
  cachedInputTokens : Nat
  reasoningOutputTokens : Nat
  deriving FromJson, ToJson

/-- Cached input and reasoning are components, never additional charges. -/
structure Usage where
  counters : Counters
  exact : counters.totalTokens = counters.inputTokens + counters.outputTokens
  cacheBound : counters.cachedInputTokens ≤ counters.inputTokens
  reasoningBound : counters.reasoningOutputTokens ≤ counters.outputTokens

def Usage.inclusive (usage : Usage) : Nat :=
  usage.counters.inputTokens + usage.counters.outputTokens

theorem Usage.declared_eq_inclusive (usage : Usage) :
    usage.counters.totalTokens = usage.inclusive := usage.exact

def usage (json : Json) : Except String Usage := do
  let counters ← fromJson? (α := Counters) json
  if exact : counters.totalTokens = counters.inputTokens + counters.outputTokens then
    if cacheBound : counters.cachedInputTokens ≤ counters.inputTokens then
      if reasoningBound : counters.reasoningOutputTokens ≤ counters.outputTokens then
        return ⟨counters,exact,cacheBound,reasoningBound⟩
  throw "invalid inclusive token counters"

structure Scope where
  threadId : String
  turnId : String
  expectedBodySha256 : String
  deriving FromJson, ToJson

structure Packet where
  event : String
  sha256 : String
  bytes : Nat
  elapsedMs : Nat
  status : String
  deriving ToJson

structure State where
  lastUsage : Option Usage := none
  usageEvents : Nat := 0
  terminal : Option String := none
  hookIds : Std.HashMap String String := {}
  hookCount : Nat := 0
  hookFailures : Array Json := #[]
  packets : Array Packet := #[]
  answer : Option String := none
  errors : Array Json := #[]
  reroutes : Array Json := #[]
  issues : Array String := #[]

private def sameScope (scope : Scope) (params : Json) : Bool :=
  (params.getObjValAs? String "threadId").toOption == some scope.threadId &&
  (params.getObjValAs? String "turnId").toOption == some scope.turnId

/-- Consume cumulative totals once. A malformed event cannot erase a known
cost; the caller retains it and records an issue instead of substituting zero. -/
def consume (scope : Scope) (state : State) (record : Json) : Except String State := do
  let direction ← record.getObjValAs? String "direction"
  if direction == "client" then return state
  unless direction == "server" do throw "unknown exchange direction"
  let message ← record.getObjVal? "message"
  let some method := (message.getObjValAs? String "method").toOption | return state
  let params ← message.getObjVal? "params"
  if method == "error" then return {state with errors := state.errors.push message}
  if method == "model/rerouted" then return {state with reroutes := state.reroutes.push message}
  if method == "turn/completed" then
    if (params.getObjValAs? String "threadId").toOption != some scope.threadId then return state
    let turn ← params.getObjVal? "turn"
    if (turn.getObjValAs? String "id").toOption != some scope.turnId then return state
    let status ← turn.getObjValAs? String "status"
    unless #["completed","failed","interrupted"].contains status do throw "invalid terminal turn status"
    if state.terminal.isSome then throw "duplicate terminal turn notification"
    return {state with terminal := some status}
  if !sameScope scope params then return state
  if method == "thread/tokenUsage/updated" then
    let current ← usage (← (← params.getObjVal? "tokenUsage").getObjVal? "total")
    if let some previous := state.lastUsage then
      unless previous.counters.inputTokens ≤ current.counters.inputTokens &&
          previous.counters.outputTokens ≤ current.counters.outputTokens do
        throw "cumulative token counters decreased"
    return {state with lastUsage := some current, usageEvents := state.usageEvents + 1}
  if method == "item/completed" then
    let item ← params.getObjVal? "item"
    if (item.getObjValAs? String "type").toOption == some "agentMessage" &&
        (item.getObjValAs? String "phase").toOption == some "final_answer" then
      let text ← item.getObjValAs? String "text"
      if state.answer.isSome then throw "multiple final answers in a single-turn trial"
      return {state with answer := some text}
    return state
  if method != "hook/completed" then return state
  let run ← params.getObjVal? "run"
  let id ← run.getObjValAs? String "id"
  let digest := Sha256.hex run.compress.toUTF8
  if let some previous := state.hookIds[id]? then
    unless previous == digest do throw "conflicting repeated hook result"
    return state
  let event ← run.getObjValAs? String "eventName"
  let status ← run.getObjValAs? String "status"
  let duration ← run.getObjValAs? Nat "durationMs"
  let mut state := {state with hookIds := state.hookIds.insert id digest, hookCount := state.hookCount + 1}
  if status != "completed" || duration ≥ 30000 then
    let failure := Json.mkObj [("event",toJson event),("status",toJson status),("elapsedMs",toJson duration)]
    state := {state with hookFailures := state.hookFailures.push failure}
  for entry in ← run.getObjValAs? (Array Json) "entries" do
    if (entry.getObjValAs? String "kind").toOption != some "context" then continue
    let text ← entry.getObjValAs? String "text"
    let packet := Packet.mk event (Sha256.hex text.toUTF8) text.utf8ByteSize duration status
    state := {state with packets := state.packets.push packet}
  return state

def report (scope : Scope) (state : State) : Json := Id.run do
  let finalKnown := state.terminal == some "completed" && state.lastUsage.isSome && state.issues.isEmpty
  let initialMatched := state.packets.any fun packet =>
    packet.event == "userPromptSubmit" && packet.sha256 == scope.expectedBodySha256
  return Json.mkObj [
    ("scope",toJson scope),("total",state.lastUsage.map (toJson ·.counters) |>.getD .null),
    ("observedInclusiveTokens",toJson (state.lastUsage.map Usage.inclusive)),
    ("usageEvents",toJson state.usageEvents),("finalUsageKnown",toJson finalKnown),
    ("unknownFinalUsage",toJson (!finalKnown)),("terminalStatus",toJson state.terminal),
    ("hookCount",toJson state.hookCount),("hookFailures",toJson state.hookFailures),
    ("packets",toJson state.packets),("initialBodyMatched",toJson initialMatched),
    ("answerSha256",toJson (state.answer.map (Sha256.hex ·.toUTF8))),
    ("errors",toJson state.errors),("reroutes",toJson state.reroutes),("issues",toJson state.issues),
    ("protocolPassed",toJson (finalKnown && initialMatched && state.answer.isSome &&
      state.errors.isEmpty && state.reroutes.isEmpty && state.hookFailures.isEmpty))]

def replay (scope : Scope) (path : System.FilePath) : IO State := do
  unless (← path.metadata).byteSize ≤ 256 * 1024 * 1024 do
    throw (IO.userError "exchange exceeds the 256 MiB research trace bound")
  let file ← IO.FS.Handle.mk path .read
  let mut state : State := {}
  let mut lineNumber := 0
  repeat
    let line ← file.getLine
    if line.isEmpty then break
    lineNumber := lineNumber + 1
    let parsed := do
      unless line.utf8ByteSize ≤ 32 * 1024 * 1024 do throw "message exceeds 32 MiB"
      unless line.endsWith "\n" do throw "unfinished exchange record"
      consume scope state (← Json.parse line)
    match parsed with
    | .ok next => state := next
    | .error error => state := {state with issues := state.issues.push s!"line {lineNumber}: {error}"}
  return state

/-- Recover a turn identity even when the turn/start response was lost.
Ambiguous traces stay ambiguous; the trial controller must not guess. -/
def discover (path : System.FilePath) : IO (Array (String × String)) := do
  unless (← path.metadata).byteSize ≤ 256*1024*1024 do
    throw (IO.userError "exchange exceeds the research trace bound")
  let file ← IO.FS.Handle.mk path .read
  let mut result := #[]
  repeat
    let line ← file.getLine
    if line.isEmpty then break
    let .ok row := Json.parse line | continue
    if (row.getObjValAs? String "direction").toOption != some "server" then continue
    let .ok message := row.getObjVal? "message" | continue
    if (message.getObjValAs? String "method").toOption != some "thread/tokenUsage/updated" then continue
    let .ok params := message.getObjVal? "params" | continue
    let .ok thread := params.getObjValAs? String "threadId" | continue
    let .ok turn := params.getObjValAs? String "turnId" | continue
    if !result.contains (thread,turn) then result := result.push (thread,turn)
  return result

def savePackets (scope : Scope) (path directory : System.FilePath) : IO Unit := do
  let file ← IO.FS.Handle.mk path .read
  let mut index := 0
  let mut seen : Std.HashSet String := {}
  repeat
    let line ← file.getLine
    if line.isEmpty then break
    let .ok row := Json.parse line | continue
    if (row.getObjValAs? String "direction").toOption != some "server" then continue
    let .ok message := row.getObjVal? "message" | continue
    if (message.getObjValAs? String "method").toOption != some "hook/completed" then continue
    let .ok params := message.getObjVal? "params" | continue
    if !sameScope scope params then continue
    let .ok run := params.getObjVal? "run" | continue
    let .ok id := run.getObjValAs? String "id" | continue
    if seen.contains id then continue
    seen := seen.insert id
    for entry in (run.getObjValAs? (Array Json) "entries").toOption.getD #[] do
      if (entry.getObjValAs? String "kind").toOption != some "context" then continue
      let text ← IO.ofExcept (entry.getObjValAs? String "text")
      let target := directory / s!"packet-{index}.txt"
      if ← target.pathExists then throw (IO.userError "keep the previous delivered body")
      IO.FS.writeFile target text
      index := index + 1

def cliMain (args : List String) : IO UInt32 := do
  try
    let [specification,exchange,output] := args |
      throw (IO.userError "StudyAccounting SCOPE.json EXCHANGE.jsonl REPORT.json")
    let output := System.FilePath.mk output
    if ← output.pathExists then throw (IO.userError "keep the existing accounting report")
    let scope ← IO.ofExcept (fromJson? (α := Eggshell.Research.StudyAccounting.Scope)
      (← IO.ofExcept (Json.parse (← IO.FS.readFile (.mk specification)))))
    let state ← Eggshell.Research.StudyAccounting.replay scope (.mk exchange)
    let result := Eggshell.Research.StudyAccounting.report scope state
    IO.FS.writeFile output (result.compress ++ "\n")
    return 0
  catch error =>
    IO.eprintln error.toString
    return 1

end Eggshell.Research.StudyAccounting
