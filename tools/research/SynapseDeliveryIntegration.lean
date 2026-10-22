import Eggshell.Worker
import Eggshell.SynapseTransport

open Lean Eggshell Eggshell.Synapses
open Eggshell.Persistence.Store

private def check (value : Bool) (message : String) : IO Unit :=
  unless value do throw (IO.userError message)

private def shell (root : System.FilePath) (command : String) : IO String := do
  let result ← IO.Process.output {cmd := "/bin/sh", args := #["-c", command], cwd := some root.toString}
  check (result.exitCode == 0) result.stderr
  return result.stdout

private def hook (binary root : System.FilePath) (label : String) (input : Json) : IO Unit := do
  let path := root / (label ++ ".json")
  IO.FS.writeFile path input.compress
  let result ← IO.Process.output {
    cmd := "/bin/sh", args := #["-c", "exec \"$1\" codex-hook < \"$2\"", "hook", binary.toString, path.toString]
    cwd := some root.toString}
  IO.FS.writeFile (root / (label ++ ".stdout")) result.stdout
  IO.FS.writeFile (root / (label ++ ".stderr")) result.stderr
  check (result.exitCode == 0) s!"native {label}: {result.stderr}"
  let _ ← IO.ofExcept (Json.parse result.stdout)

private def awaitState (directory : System.FilePath) (count : Nat) (answer := false) : IO Unit := do
  let deadline := (← IO.monoMsNow)+15000
  repeat
    let source ← DB.PageMap.pin directory
    if (← Provenance.records source).size == count then
      if let some index ← Index.open? source .database .shared then
        let all ← Index.allFacts index.index
        if !answer || all.any (fun fact => match fact with | .supports _ => true | _ => false) then return
    if (← IO.monoMsNow) ≥ deadline then throw (IO.userError "native publication and background index did not become ready")
    IO.sleep 25

def main (args : List String) : IO Unit := do
  let [path, executable] := args | throw (IO.userError "SynapseDeliveryIntegration NEW-DIRECTORY CANDIDATE")
  let root := System.FilePath.mk path
  let binary := System.FilePath.mk executable
  let some isolated ← IO.getEnv "EGGSHELL_DATA_ROOT" | throw (IO.userError "isolated data root required")
  check (root.isAbsolute && !(← root.pathExists) && binary.isAbsolute &&
    (isolated.splitOn "synaptic-delivery-").length > 1) "isolated fixture and executable required"
  IO.FS.createDirAll (root / "src")
  for (name, line, text) in [("a", 11, "next source: src/b.cpp"),
      ("b", 21, "paired_value"), ("c", 31, "coquoted_value")] do
    IO.FS.writeFile (root / s!"src/{name}.cpp")
      ("\n".intercalate ((List.range (line-1)).map fun _ => "prefix") ++ "\n" ++ text ++ "\n")
  let source ← DB.PageMap.create (root / "source.egg") (Persistence.valueToJson (.text "fixture")).compress
  let _ ← Build.refresh source .database
  let question := "Inspect the source dependency and its paired observation."
  let session := "synaptic-delivery-native"
  let files ← Plugin.sessionFiles session
  let pending : Plugin.PendingTurn := {
    sessionId := session, turnId := "native-turn", cwd := root.toString, prompt := question
    profile := "work", semanticMatcher := none, read := [source.directory.toString]
    write := some source.directory.toString, handoffChars := 120000, projection := .none}
  Plugin.writeJson files.state ({profile := "work"} : Plugin.ThreadState)
  Plugin.writeJson files.pending pending
  try
    for (index, (name, line)) in [("a",11), ("b",21), ("c",31)].zipIdx.map (fun (x,i) => (i,x)) do
      let useId := s!"native-{index}"
      let command := s!"nl -ba src/{name}.cpp | sed -n '{line},{line}p'"
      let input := Json.mkObj [("command", toJson command)]
      let base := Json.mkObj [("session_id", toJson session), ("turn_id", toJson pending.turnId),
        ("tool_name", toJson "shell"), ("tool_use_id", toJson useId), ("tool_input", input)]
      hook binary root (useId ++ "-pre") (base.setObjVal! "hook_event_name" (toJson "PreToolUse"))
      let output ← shell root command
      let response := Json.mkObj [("output", toJson output), ("exitCode", toJson (0 : Nat))]
      let post := (base.setObjVal! "hook_event_name" (toJson "PostToolUse")) |>.setObjVal! "tool_response" response
      hook binary root (useId ++ "-post") post
      awaitState source.directory (index+1)
    let finalText := "Inspect [b.cpp:21](src/b.cpp:21) together with [c.cpp:31](src/c.cpp:31)."
    hook binary root "stop" (Json.mkObj [("session_id", toJson session), ("turn_id", toJson pending.turnId),
      ("hook_event_name", toJson "Stop"), ("last_assistant_message", toJson finalText)])
    awaitState source.directory 3 true
    -- A read already seen in this chat is a reread, not an omission. Use a
    -- genuinely new chat whose acknowledged history is empty for feedback.
    let feedbackSession := "synaptic-delivery-feedback"
    let feedbackFiles ← Plugin.sessionFiles feedbackSession
    let feedback := {pending with sessionId := feedbackSession, turnId := "feedback-turn"}
    Plugin.writeJson feedbackFiles.state ({profile := "work"} : Plugin.ThreadState)
    Plugin.writeJson feedbackFiles.pending feedback
    let command := "nl -ba src/b.cpp | sed -n '21,21p'"
    let input := Json.mkObj [("command", toJson command)]
    let base := Json.mkObj [("session_id", toJson feedbackSession), ("turn_id", toJson feedback.turnId),
      ("tool_name", toJson "shell"), ("tool_use_id", toJson "missing-read"), ("tool_input", input)]
    hook binary root "feedback-pre" (base.setObjVal! "hook_event_name" (toJson "PreToolUse"))
    let output ← shell root command
    let response := Json.mkObj [("output", toJson output), ("exitCode", toJson (0 : Nat))]
    hook binary root "feedback-post" ((base.setObjVal! "hook_event_name" (toJson "PostToolUse"))
      |>.setObjVal! "tool_response" response)
    awaitState source.directory 4 true
    let _ ← IO.Process.output {cmd := binary.toString, args := #["codex-daemon", "shutdown"]}
    let source ← DB.PageMap.pin source.directory
    let command := [binary.toString, "search-provider", "--mode", "semantic", "--threshold", "-1"]
    let _ ← RetrievalResearch.Index.warm source .user
    let target : Plugin.IndexTarget := ⟨DB.Sidecar.Owner.ofSnapshot source, command, .user⟩
    let warmed ← Warm.runTarget source target
    IO.FS.writeFile (root / "warm.json") (toJson warmed).compress
    let source ← DB.PageMap.pin source.directory
    let originalHead ← IO.FS.readBinFile (source.directory / "head")
    let originalPages ← IO.FS.readBinFile (DB.PageMap.dataPath source.directory source.head)
    let selection : Config.Selection := {
      label := "native-synaptic-test", semanticMatcher := some command
      read := [⟨"test", source.directory⟩], write := none, handoffChars := 120000}
    let receipt ← Receipt.fresh
    let context : Plugin.SourceContext := {
      workspace := root, deadline := (← IO.monoMsNow)+30000, question, receipt := some receipt}
    let some baseline ← Plugin.computeAutomaticHandoff selection [some source] question [] false
        (refreshSources := true) (meaningQuery := some question) |
      throw (IO.userError "baseline handoff returned no context")
    let baseline ← baseline.checkSources context
    IO.FS.writeFile (root / "baseline.json") (toJson baseline).compress
    let some result ← Plugin.automaticHandoff selection question [] false (sourceContext := some context) (publishMemo := false) |
      throw (IO.userError "actual handoff returned no original context")
    IO.FS.writeFile (root / "handoff.json") (toJson result).compress
    IO.FS.writeFile (root / "body.txt") result.text
    let stage := (System.FilePath.mk isolated) / "receipts" / receipt / "synaptic-delivery.json"
    let json ← IO.ofExcept (Json.parse (← IO.FS.readFile stage))
    IO.FS.writeFile (root / "synaptic-delivery.json") json.compress
    let data ← IO.ofExcept (json.getObjVal? "data")
    let offers ← IO.ofExcept (data.getObjValAs? (Array Json) "offers")
    for kind in ["support", "consumption", "coquotation", "omitted_then_read"] do
      let actual := offers.any fun offer =>
        ((offer.getObjVal? "offer" >>= (·.getObjValAs? String "kind")).toOption == some kind) &&
          (offer.getObjValAs? Bool "bodyDelivered").toOption == some true
      check actual s!"actual packet did not deliver an original row reached by {kind}"
    check (result.completed == baseline.completed && result.localUnions == baseline.localUnions &&
      result.blocksCurrent == baseline.blocksCurrent && !result.blocksCurrent && result.synapticComplete)
      "synaptic recommendation changed the existing completion/control result or left unfinished planning"
    let config := root / "fixture.toml"
    IO.FS.writeFile config ("default = \"readonly\"\nsemantic_matcher = " ++ (toJson command).compress ++
      "\n[eggs]\nshared = " ++ (toJson source.directory.toString).compress ++
      "\n[profiles.readonly]\nread = [\"shared\"]\nhandoff_chars = 120000\n")
    let receiptRoot := (System.FilePath.mk isolated) / "receipts"
    let before := (← receiptRoot.readDir).map (·.fileName)
    hook binary root "new-chat-prompt" (Json.mkObj [
      ("session_id", toJson "synaptic-delivery-new-chat"), ("turn_id", toJson "new-chat-turn"),
      ("cwd", toJson root.toString), ("prompt", toJson question),
      ("_eggshell_config", toJson config.toString), ("hook_event_name", toJson "UserPromptSubmit")])
    let stdout ← IO.ofExcept (Json.parse (← IO.FS.readFile (root / "new-chat-prompt.stdout")))
    let text ← IO.ofExcept (stdout.getObjVal? "hookSpecificOutput" >>= (·.getObjValAs? String "additionalContext"))
    IO.FS.writeFile (root / "new-chat-body.txt") text
    for original in ["next source: src/b.cpp", "paired_value", "coquoted_value"] do
      check ((text.splitOn original).length > 1) "actual new-chat stdout omitted an original source row"
    let mut deliveredKinds : Std.HashSet String := {}
    for directory in ← receiptRoot.readDir do
      if before.contains directory.fileName then continue
      let path := directory.path / "synaptic-delivery.json"
      if !(← path.pathExists) then continue
      let value ← IO.ofExcept (Json.parse (← IO.FS.readFile path))
      let offers ← IO.ofExcept (value.getObjVal? "data" >>= (·.getObjValAs? (Array Json) "offers"))
      for offer in offers do
        if (offer.getObjValAs? Bool "bodyDelivered").toOption == some true then
          if let .ok kind := offer.getObjVal? "offer" >>= (·.getObjValAs? String "kind") then
            deliveredKinds := deliveredKinds.insert kind
    check (["support", "consumption", "coquotation", "omitted_then_read"].all deliveredKinds.contains)
      "actual stdout receipt did not account for all three relation types"
    let optional ← Index.prepare source .user .shared
    let facts ← Index.allFacts optional
    let some damaged := facts.find? (fun fact => match fact with | .supports _ => true | _ => false) |
      throw (IO.userError "no optional support to damage")
    let _ ← DB.PageMap.withWriter optional fun writer => writer.put (Index.factName damaged) none
    let fallbackReceipt ← Receipt.fresh
    let some fallback ← Plugin.automaticHandoff selection question [] false
        (sourceContext := some {context with receipt := some fallbackReceipt}) (publishMemo := false) |
      throw (IO.userError "failed optional index discarded the original packet")
    IO.FS.writeFile (root / "fallback.json") (toJson fallback).compress
    check (fallback.text == baseline.text && fallback.completed == baseline.completed &&
      fallback.blocksCurrent == baseline.blocksCurrent && !fallback.synapticComplete)
      "failed optional index changed the original packet or completion/control result"
    check ((← IO.FS.readBinFile (source.directory / "head")) == originalHead &&
      (← IO.FS.readBinFile (DB.PageMap.dataPath source.directory source.head)) == originalPages)
      "read-only planning changed the source DB"
    IO.println (Json.mkObj [("actualShellCalls", toJson (4 : Nat)), ("actualStop", toJson true),
      ("deliveredSignalKinds", toJson ["support", "consumption", "coquotation", "omitted_then_read"]),
      ("completed", toJson result.completed), ("baselineCompleted", toJson baseline.completed),
      ("actualUserPromptStdout", toJson true), ("blocksCurrent", toJson result.blocksCurrent),
      ("corruptOptionalIndexKeepsBaselineBytes", toJson true),
      ("answeringModelCalls", toJson (0 : Nat))]).compress
  finally
    let _ ← IO.Process.output {cmd := binary.toString, args := #["codex-daemon", "shutdown"]}
    pure ()
