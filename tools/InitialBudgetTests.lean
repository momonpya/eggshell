import Eggshell.Install

open Lean Eggshell Eggshell.Plugin

private def check (accepted : Bool) (message : String) : IO Unit :=
  unless accepted do throw (IO.userError message)

private def provider (slow : Bool) : IO UInt32 := do
  let input ← IO.getStdin
  let output ← IO.getStdout
  repeat
    let line ← input.getLine
    if line.isEmpty then break
    let request ← IO.ofExcept (Json.parse line)
    let documents ← IO.ofExcept (request.getObjValAs? (Array Json) "documents")
    if slow then IO.sleep 5100
    output.putStrLn (Json.mkObj [("related", toJson ([] : List Nat)),
      ("ranked", toJson (List.range documents.size)), ("evidence", toJson ([] : List Json))]).compress
    output.flush
  pure 0

private def scenario (temporary : System.FilePath) : IO UInt32 := do
  let root ← IO.FS.realPath temporary
  let records := (← Paths.dataRoot) / "initial-budget-records"
  let runtime := records / "runtime"
  let binary := (← IO.appPath).withFileName "eggshell"
  let executable ← IO.appPath
  let database := root / "source.egg"
  let config := root / "fixture.toml"
  let pending : PendingTurn := {
    sessionId := "seed", turnId := "seed", cwd := root.toString, prompt := "saved clock observation"
    profile := "probe", semanticMatcher := none, read := [], write := some database.toString
    handoffChars := 120000, projection := .automatic, finalMessage := some "ORIGINAL_CLOCK_BODY" }
  let _ ← promote pending database
  -- This fixture supplies its own numerical responder; the durable lexical
  -- index must still satisfy the same warm precondition as ordinary hooks.
  let _ ← RetrievalResearch.Index.warm (← DB.PageMap.pin database) .database
  let env := #[("EGGSHELL_DATA_ROOT", some runtime.toString), ("PLUGIN_ROOT", none),
    ("CODEX_THREAD_ID", none), ("EGGSHELL_CONFIG", none), ("HF_HUB_OFFLINE", some "1")]
  let mut results := []
  try
    for (turn, mode, initial) in [("first", "slow", true), ("second", "fast", false)] do
      let command := [executable.toString, "provider", mode]
      IO.FS.writeFile config ("default = \"probe\"\nsemantic_matcher = " ++ (toJson command).compress ++
        "\n[eggs]\nsource = " ++ (toJson database.toString).compress ++
        "\n[profiles.probe]\nread = [\"source\"]\nwrite = \"source\"\nhandoff_chars = 120000\n")
      let input := Json.mkObj [("hook_event_name", toJson "UserPromptSubmit"),
        ("session_id", toJson "budget-session"), ("turn_id", toJson turn),
        ("cwd", toJson root.toString), ("prompt", toJson "unrelated request"),
        ("_eggshell_config", toJson config.toString)]
      let started ← IO.monoMsNow
      let result ← IO.Process.output {cmd := binary.toString, args := #["codex-hook"], env}
        (some (input.compress ++ "\n"))
      let elapsed := (← IO.monoMsNow) - started
      writeJson (records / (turn ++ "-output.json")) (Json.mkObj [("input", input),
        ("stdout", toJson result.stdout), ("stderr", toJson result.stderr), ("elapsedMs", toJson elapsed)])
      check (result.exitCode == 0) s!"native hook failed: {result.stderr}"
      let state ← (readBoundedJson (runtime / "sessions/budget-session/state.json") 1048576 : IO ThreadState)
      check state.searchStarted "empty output did not consume the first search budget"
      let mut found := false
      for entry in ← (runtime / "receipts").readDir do
        let path := entry.path / "search.json"
        if !(← path.pathExists) then continue
        let receipt ← (readBoundedJson path 1048576 : IO Json)
        let search := receipt.getObjValD "data"
        if search.getObjValD "turn" != toJson turn then continue
        writeJson (records / (turn ++ "-search.json")) search
        found := true
        check (search.getObjValD "initialSearch" == toJson initial)
          "a later search received the initial allocation"
        let began ← IO.ofExcept (search.getObjValAs? Nat "searchStartedMs")
        let expires ← IO.ofExcept (search.getObjValAs? Nat "semanticDeadlineMs")
        let deadline ← IO.ofExcept (search.getObjValAs? Nat "deadlineMs")
        let allocation := expires - began
        check (expires ≤ deadline && allocation ≤ (deadline - began) / 2)
          "semantic allocation consumed the fallback reserve"
        check (if initial then allocation > 5100 && allocation ≤ 15000 else allocation ≤ 4500)
          "native first/continuation allocation did not match the declared policy"
        check ((search.getObjValD "trace").getObjValD "semantic" == toJson "completed")
          "an empty, completed semantic result was confused with pending"
        if initial then
          check (elapsed ≥ 5100 && elapsed < 30000)
            "first search did not finish its longer semantic request within the native deadline"
        results := results ++ [Json.mkObj [("turn", toJson turn), ("initial", toJson initial),
          ("elapsedMs", toJson elapsed), ("semanticAllocationMs", toJson allocation), ("search", search)]]
      check found "native hook lost its search receipt"
    let state : ThreadState := {profile := "probe", searchStarted := true}
    check (compactState state).searchStarted "compaction reset the initial allocation"
    for now in [0, 1, 100, 100000] do
      for remaining in [0, 1, 2, 9000, 29000, 30000, 60000] do
        for initial in [false, true] do
          let deadline := now + remaining
          let actual := semanticSearchDeadline initial now deadline
          let cap := if initial then 15000 else 4500
          check (actual == now + min cap (remaining / 2)) "deadline policy changed"
      check (semanticSearchDeadline true now (now - 1) ≤ now) "expired upstream deadline was extended"
    IO.println (Json.mkObj [("passed", toJson true), ("nativeEmptyResultSequence", toJson results),
      ("generationModelCalls", toJson (0 : Nat)), ("productionAdoption", toJson false)]).compress
    pure 0
  finally
    let result ← IO.Process.output {cmd := binary.toString, args := #["codex-daemon", "shutdown"], env}
    check (result.exitCode == 0) "test daemon failed to shut down"

def main (arguments : List String) : IO UInt32 := do
  if let ["provider", mode] := arguments then return ← provider (mode == "slow")
  IO.FS.withTempDir scenario
