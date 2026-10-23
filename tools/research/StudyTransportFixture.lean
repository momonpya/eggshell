import Lean.Data.Json

open Lean

private def emit (json : Json) : IO Unit := do
  let output ← IO.getStdout
  output.putStr (json.compress ++ "\n")
  output.flush

private def reply (id : Json) (result : Json) : IO Unit :=
  emit (Json.mkObj [("id",id),("result",result)])

private def notice (method : String) (fields : List (String × Json)) : IO Unit :=
  emit (Json.mkObj [("method",toJson method),("params",Json.mkObj
    ([("threadId",toJson "fixture-thread"),("turnId",toJson "fixture-turn")] ++ fields))])

/-- Synthetic stdio peer. It has no provider, HTTP client or credential reader.
The detached mode spawns only its bounded helper. Counters are fixture data. -/
def main (args : List String) : IO UInt32 := do
  let [mode] := args | return 1
  if mode == "scratch" || mode == "scratch-check" then
    IO.FS.withTempDir fun directory => do
      unless ← directory.isDir do throw (IO.userError "temporary directory was not created")
      if mode == "scratch-check" then emit (Json.mkObj [("temporaryDirectoryCreated",toJson true)])
    if mode == "scratch-check" then return 0
  if mode == "helper" then
    IO.sleep 20000
    return 0
  if mode == "no-read" then
    IO.sleep 20000
    return 0
  let input ← IO.getStdin
  repeat
    let line ← input.getLine
    if line.isEmpty then break
    let message ← IO.ofExcept (Json.parse line)
    let some id := (message.getObjVal? "id").toOption | continue
    let method ← IO.ofExcept (message.getObjValAs? String "method")
    if method == "initialize" then
      if mode == "detached" then
        let _ ← IO.Process.spawn {
          cmd := (← IO.appPath).toString,args := #["helper"],setsid := true
          stdin := .null,stdout := .null,stderr := .null}
        pure ()
      if mode == "timeout" then
        IO.sleep 500
        return 0
      if mode == "malformed" || mode == "truncated" then
        let output ← IO.getStdout
        output.putStr (if mode == "malformed" then "{\n" else "{\"id\":")
        output.flush
        return 0
      if mode == "wrong-id" then
        reply (toJson (999 : Nat)) (Json.mkObj [])
        continue
      if mode == "server-request" then
        emit (Json.mkObj [("id",toJson (999 : Nat)),("method",toJson "item/permissions/requestApproval"),
          ("params",Json.mkObj [])])
        continue
      if mode == "generation-during-inspection" then
        notice "turn/started" []
        continue
      if mode == "oversized" then
        reply id (toJson (String.ofList (List.replicate 4096 'x')))
        continue
      if mode == "flood" then
        for i in [0:300] do notice "fixture/delta" [("index",toJson i)]
      if mode == "trace-limit" then
        for i in [0:10] do notice "fixture/delta" [("index",toJson i)]
      reply id (Json.mkObj [("userAgent",toJson "fixture")])
    else if method == "model/list" || method == "hooks/list" then
      if mode == "large" then
        reply id (Json.mkObj [("payload",toJson (String.ofList (List.replicate (2*1024*1024) 'x')))])
      else reply id (Json.mkObj [("data",toJson (#[] : Array Json)),("nextCursor",.null)])
    else if method == "thread/start" then
      reply id (Json.mkObj [("thread",Json.mkObj [("id",toJson "fixture-thread")]),
        ("model",toJson "fixture"),("reasoningEffort",toJson "xhigh"),("instructionSources",toJson (#[] : Array Json))])
    else if method == "turn/start" then
      notice "hook/completed" [("run",Json.mkObj [("id",toJson "fixture-hook"),
        ("eventName",toJson "userPromptSubmit"),("status",toJson "completed"),("durationMs",toJson (12 : Nat)),
        ("entries",toJson #[Json.mkObj [("kind",toJson "context"),("text",toJson "fixture body")]])])]
      notice "thread/tokenUsage/updated" [("tokenUsage",Json.mkObj [("total",Json.mkObj [
        ("totalTokens",toJson (110 : Nat)),("inputTokens",toJson (100 : Nat)),("outputTokens",toJson (10 : Nat)),
        ("cachedInputTokens",toJson (80 : Nat)),("reasoningOutputTokens",toJson (4 : Nat))])])]
      notice "item/completed" [("item",Json.mkObj [("type",toJson "agentMessage"),
        ("phase",toJson "final_answer"),("text",toJson "fixture answer")])]
      notice "turn/completed" [("turn",Json.mkObj [("id",toJson "fixture-turn"),("status",toJson "completed")])]
      reply id (Json.mkObj [("turn",Json.mkObj [("id",toJson "fixture-turn")])])
    else if method == "thread/unsubscribe" then reply id (Json.mkObj [])
    else return 2
  return 0
