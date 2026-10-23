import tools.research.StudyAdmission
import tools.research.StudyCommand

open Lean Eggshell Eggshell.Research

private def emit (value : Json) : IO Unit := do
  let output ← IO.getStdout
  output.putStr (value.compress ++ "\n")
  output.flush

private def reply (id result : Json) : IO Unit := emit (Json.mkObj [("id",id),("result",result)])

/-- A native RPC fixture, not an inference provider. Real Eggshell hooks,
daemon, keep and source publication run against an isolated test DB; the
answer and the 110-token usage are explicitly synthetic. No HTTP or auth. -/
def main (_args : List String) : IO UInt32 := do
  let some scenario ← IO.getEnv "EGGSHELL_STUDY_SCENARIO" | return 1
  let plan ← IO.ofExcept (fromJson? (α := StudyAdmission.Plan) (← StudyAdmission.readJson scenario))
  let thread := "synthetic-" ++ plan.label
  let turn := "synthetic-first"
  let notice := fun (method : String) (fields : List (String × Json)) => emit
    (Json.mkObj [("method",toJson method),("params",Json.mkObj
      ([("threadId",toJson thread),("turnId",toJson turn)] ++ fields))])
  let input ← IO.getStdin
  repeat
    let line ← input.getLine
    if line.isEmpty then break
    let value ← IO.ofExcept (Json.parse line)
    let some id := (value.getObjVal? "id").toOption | continue
    let method ← IO.ofExcept (value.getObjValAs? String "method")
    if method == "initialize" then
      reply id (Json.mkObj [("userAgent",toJson "eggshell-native-synthetic")])
    else if method == "model/list" then
      reply id (Json.mkObj [("data",toJson (#[] : Array Json)),("nextCursor",.null)])
    else if method == "hooks/list" then
      let hook := Json.mkObj [("trustStatus",toJson "trusted"),("sourcePath",toJson (plan.pluginRoot ++ "/hooks/hooks.json"))]
      reply id (Json.mkObj [("data",toJson #[Json.mkObj [("errors",toJson (#[] : Array Json)),
        ("warnings",toJson (#[] : Array Json)),("hooks",toJson #[hook])]])])
    else if method == "thread/start" then
      reply id (Json.mkObj [("thread",Json.mkObj [("id",toJson thread)]),("model",toJson plan.model),
        ("modelProvider",toJson "synthetic"),("reasoningEffort",toJson plan.effort),
        ("instructionSources",toJson (#[] : Array Json))])
    else if method == "turn/start" then
      let root := System.FilePath.mk plan.output / "native-hooks"
      IO.FS.createDir root
      let prompt ← IO.FS.readFile (.mk plan.prompt.path)
      let mut body := ""
      let mut duration := 0
      for event in #["SessionStart","UserPromptSubmit","Stop"] do
        let fields := [("hook_event_name",toJson event),("session_id",toJson thread),("turn_id",toJson turn),
          ("cwd",toJson plan.workspace),("_eggshell_config",toJson plan.configuration.path)]
        let extra := if event == "UserPromptSubmit" then [("prompt",toJson prompt)]
          else if event == "Stop" then [("last_assistant_message",toJson "Synthetic fixture answer; not an inference result.")]
          else []
        let request := Json.mkObj (fields ++ extra)
        let result ← StudyCommand.run plan.runtime.path #["codex-hook"] #[] plan.workspace
          (request.compress ++ "\n") (root / event) 35000
        unless result.exitCode == 0 do throw (IO.userError "synthetic fixture's real native hook failed")
        if event == "UserPromptSubmit" then
          duration := result.elapsedMs
          body ← IO.ofExcept (Json.parse result.stdout >>= (·.getObjVal? "hookSpecificOutput") >>=
            (·.getObjValAs? String "additionalContext"))
      notice "hook/completed" [("run",Json.mkObj [("id",toJson "native-fixture-hook"),
        ("eventName",toJson "userPromptSubmit"),("status",toJson "completed"),("durationMs",toJson duration),
        ("entries",toJson #[Json.mkObj [("kind",toJson "context"),("text",toJson body)]])])]
      notice "thread/tokenUsage/updated" [("tokenUsage",Json.mkObj [("total",Json.mkObj [
        ("totalTokens",toJson (110 : Nat)),("inputTokens",toJson (100 : Nat)),("outputTokens",toJson (10 : Nat)),
        ("cachedInputTokens",toJson (80 : Nat)),("reasoningOutputTokens",toJson (4 : Nat))])])]
      notice "item/completed" [("item",Json.mkObj [("type",toJson "agentMessage"),
        ("phase",toJson "final_answer"),("text",toJson "Synthetic fixture answer; not an inference result.")])]
      notice "turn/completed" [("turn",Json.mkObj [("id",toJson turn),("status",toJson "completed")])]
      reply id (Json.mkObj [("turn",Json.mkObj [("id",toJson turn)])])
    else if method == "thread/unsubscribe" then reply id (Json.mkObj [])
    else return 2
  return 0
