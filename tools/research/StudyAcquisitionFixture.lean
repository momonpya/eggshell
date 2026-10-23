import tools.research.StudyAcquire

open Lean Eggshell Eggshell.Research

private def emit (value : Json) : IO Unit := do
  let output ← IO.getStdout
  output.putStrLn value.compress
  output.flush

/-- No HTTP/auth/inference provider. The RPC answer and 110-token usage are
synthetic; seed mode really executes native hooks, a source read and saving. -/
def main (_args : List String) : IO UInt32 := do
  let some scenario ← IO.getEnv "EGGSHELL_ACQUISITION_SCENARIO" | return 1
  let plan ← IO.ofExcept (fromJson? (α := StudyAcquire.Plan) (← StudyAdmission.readJson scenario))
  unless plan.provider == "synthetic" do return 1
  let thread := "synthetic-" ++ plan.label
  let turn := "synthetic-first"
  let reply := fun id result => emit (Json.mkObj [("id",id),("result",result)])
  let notice := fun (method : String) (fields : List (String × Json)) => emit (Json.mkObj [("method",toJson method),("params",Json.mkObj
    ([("threadId",toJson thread),("turnId",toJson turn)] ++ fields))])
  let input ← IO.getStdin
  repeat
    let line ← input.getLine
    if line.isEmpty then break
    let request ← IO.ofExcept (Json.parse line)
    let some id := (request.getObjVal? "id").toOption | continue
    let method ← IO.ofExcept (request.getObjValAs? String "method")
    if method == "initialize" then reply id (Json.mkObj [("userAgent",toJson "native-acquisition-synthetic")])
    else if method == "model/list" then reply id (Json.mkObj [("data",toJson (#[] : Array Json)),("nextCursor",.null)])
    else if method == "hooks/list" then
      let hook := Json.mkObj [("enabled",toJson true),("trustStatus",toJson "trusted"),
        ("sourcePath",toJson (plan.pluginRoot ++ "/hooks/hooks.json"))]
      let hooks := if plan.kind == "seed" then Array.replicate 8 hook else #[]
      reply id (Json.mkObj [("data",toJson #[Json.mkObj [("errors",toJson (#[] : Array Json)),
        ("warnings",toJson (#[] : Array Json)),("hooks",toJson hooks)]])])
    else if method == "thread/start" then
      reply id (Json.mkObj [("thread",Json.mkObj [("id",toJson thread)]),("model",toJson plan.model),
        ("modelProvider",toJson "synthetic"),("reasoningEffort",toJson plan.effort),
        ("instructionSources",toJson (#[] : Array Json))])
    else if method == "turn/start" then
      if plan.kind == "seed" then
        let root := System.FilePath.mk plan.output / "native-hooks"
        IO.FS.createDir root
        let some configuration ← IO.getEnv "EGGSHELL_CONFIG" | throw (IO.userError "isolated config required")
        let hook := fun (label event : String) (extra : List (String × Json)) => do
          let nativeEvent := match event with
            | "sessionStart" => "SessionStart"
            | "userPromptSubmit" => "UserPromptSubmit"
            | "preToolUse" => "PreToolUse"
            | "postToolUse" => "PostToolUse"
            | "stop" => "Stop"
            | _ => event
          let fields := [("hook_event_name",toJson nativeEvent),("session_id",toJson thread),("turn_id",toJson turn),
            ("cwd",toJson plan.workspace),("_eggshell_config",toJson configuration)] ++ extra
          let result ← StudyCommand.run plan.runtime.path #["codex-hook"] #[] plan.workspace
            ((Json.mkObj fields).compress ++ "\n") (root / label) 35000
          unless result.exitCode == 0 do throw (IO.userError result.stderr)
          let body := (Json.parse result.stdout >>= (·.getObjVal? "hookSpecificOutput") >>=
            (·.getObjValAs? String "additionalContext")).toOption
          let entries := body.toList.toArray.map fun text => Json.mkObj [("kind",toJson "context"),("text",toJson text)]
          notice "hook/completed" [("run",Json.mkObj [("id",toJson label),("eventName",toJson event),
            ("status",toJson "completed"),("durationMs",toJson result.elapsedMs),("entries",toJson entries)])]
        hook "session" "sessionStart" []
        hook "prompt" "userPromptSubmit" [("prompt",toJson (← IO.FS.readFile (.mk plan.prompt.path)))]
        let command := "nl -ba clang/lib/Driver/Driver.cpp | sed -n '7101,7106p'"
        let tool := [("tool_name",toJson "shell"),("tool_use_id",toJson "fixture-read"),
          ("tool_input",Json.mkObj [("command",toJson command)])]
        hook "pre" "preToolUse" tool
        let actual ← StudyCommand.run "/bin/sh" #["-c",command] #[] plan.workspace "" (root / "actual-read") 5000
        unless actual.exitCode == 0 do throw (IO.userError actual.stderr)
        hook "post" "postToolUse" (tool ++ [("tool_response",Json.mkObj [
          ("output",toJson actual.stdout),("exitCode",toJson actual.exitCode)])])
        hook "stop" "stop" [("last_assistant_message",toJson "Synthetic citation [source](clang/lib/Driver/Driver.cpp:7101-7106).")]
      notice "thread/tokenUsage/updated" [("tokenUsage",Json.mkObj [("total",Json.mkObj [
        ("totalTokens",toJson (110 : Nat)),("inputTokens",toJson (100 : Nat)),("outputTokens",toJson (10 : Nat)),
        ("cachedInputTokens",toJson (80 : Nat)),("reasoningOutputTokens",toJson (4 : Nat))])])]
      notice "item/completed" [("item",Json.mkObj [("type",toJson "agentMessage"),
        ("phase",toJson "final_answer"),("text",toJson "Synthetic acquisition; no inference provider.")])]
      notice "turn/completed" [("turn",Json.mkObj [("id",toJson turn),("status",toJson "completed")])]
      reply id (Json.mkObj [("turn",Json.mkObj [("id",toJson turn)])])
    else if method == "thread/unsubscribe" then reply id (Json.mkObj [])
    else return 2
  return 0
