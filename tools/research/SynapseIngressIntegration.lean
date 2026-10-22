import Eggshell.SynapseLive

open Lean Eggshell Eggshell.Synapses Eggshell.Synapses.Extraction
open Eggshell.Persistence.Store

private def check (condition : Bool) (message : String) : IO Unit :=
  unless condition do throw (IO.userError message)

private def shell (root : System.FilePath) (command : String) : IO String := do
  let result ← IO.Process.output {cmd := "/bin/sh", args := #["-c", command], cwd := some root.toString}
  check (result.exitCode == 0) result.stderr
  return result.stdout

private def hook (binary root : System.FilePath) (name : String) (input : Json) : IO Unit := do
  let path := root / (name ++ ".json")
  IO.FS.writeFile path input.compress
  let result ← IO.Process.output {
    cmd := "/bin/sh", args := #["-c", "exec \"$1\" codex-hook < \"$2\"", "hook", binary.toString, path.toString]
    cwd := some root.toString }
  IO.FS.writeFile (root / (name ++ ".stdout")) result.stdout
  IO.FS.writeFile (root / (name ++ ".stderr")) result.stderr
  check (result.exitCode == 0) s!"native {name}: {result.stderr}"
  let _ ← IO.ofExcept (Json.parse result.stdout)

private def awaitSaves (files : Plugin.SessionFiles) : IO Unit := do
  let deadline := (← IO.monoMsNow)+10000
  repeat
    let path := files.directory / "checkpoints"
    let queued ← if ← path.pathExists then pure ((← path.readDir).any (·.fileName.endsWith ".json")) else pure false
    if !queued then return
    if (← IO.monoMsNow) ≥ deadline then throw (IO.userError "native save worker did not drain its durable checkpoints")
    IO.sleep 25

private def awaitFeedback (directory : System.FilePath) (kind : UsageKind) : IO Unit := do
  let deadline := (← IO.monoMsNow)+15000
  repeat
    let source ← DB.PageMap.pin directory
    if let some reader ← Index.open? source .user .usage then
      let facts ← Index.allFacts reader.index
      if facts.any (fun fact => match fact with | .used usage => usage.kind == kind | _ => false) then return
    if (← IO.monoMsNow) ≥ deadline then throw (IO.userError "native background worker did not publish feedback")
    IO.sleep 25

def main (args : List String) : IO Unit := do
  let [path, executable] := args | throw (IO.userError "SynapseIngressIntegration NEW-DIRECTORY CANDIDATE-BINARY")
  let root := System.FilePath.mk path
  let binary := System.FilePath.mk executable
  unless root.isAbsolute && !(← root.pathExists) && binary.isAbsolute do
    throw (IO.userError "new absolute directory and isolated candidate executable required")
  let some isolated ← IO.getEnv "EGGSHELL_DATA_ROOT" | throw (IO.userError "isolated data root required")
  check ((System.FilePath.mk isolated).isAbsolute && (isolated.splitOn "synaptic-ingress-").length > 1) "refuse installation data root"
  IO.FS.createDirAll (root / "src")
  IO.FS.writeFile (root / "src/source.cpp")
    ("\n".intercalate ((List.range 9).map fun i => s!"prefix-{i+1}") ++ "\nalpha\nNEEDED_SYMBOL\nomega\n")
  let command := "nl -ba src/source.cpp | sed -n '10,12p'"
  let output ← shell root command
  let toolInput := Json.mkObj [("command", toJson command)]
  let response := Json.mkObj [("output", toJson output), ("exitCode", toJson (0 : Nat))]
  let seed : Plugin.ToolEvent := ⟨"shell", "seed", toolInput.compress, response.compress, none⟩
  let relation := (Plugin.compileOperationOutcomes (.text "seed") (.text "seed") seed).2
  let some (fingerprint, _) ← SourceEvidence.fingerprint (root / "src/source.cpp") ((← IO.monoMsNow)+3000) |
    throw (IO.userError "could not capture actual fixture fingerprint")
  let certificate := SourceEvidence.receipt (.text "seed") (.text "seed") (.text "seed") relation {
    workspace := root.toString, complete := true, files := [⟨"src/source.cpp", some fingerprint⟩] }
  let source ← DB.PageMap.create (root / "source.egg") (Persistence.valueToJson (.text "fixture")).compress
  let _ ← DB.PageMap.withWriter source fun writer => do
    let intern : Intern := ⟨writer, ← IO.mkRef {}⟩
    let ids ← [relation, certificate].mapM intern.root
    writeChange writer ⟨ids, [], false⟩
  let source ← DB.PageMap.pin source.directory
  let _ ← Build.refresh source .database
  let originalHead ← IO.FS.readBinFile (source.directory / "head")
  let originalPages ← IO.FS.readBinFile (DB.PageMap.dataPath source.directory source.head)
  let archive ← DB.PageMap.create (root / "private-work.egg") (Persistence.valueToJson (.text "private-work")).compress
  let session := "synaptic-native-ingress"
  let files ← Plugin.sessionFiles session
  let pending : Plugin.PendingTurn := {
    sessionId := session, turnId := "turn", cwd := root.toString, prompt := "inspect source evidence"
    profile := "work", semanticMatcher := none, read := [source.directory.toString, archive.directory.toString]
    write := some archive.directory.toString, handoffChars := 120000, projection := .none }
  Plugin.writeJson files.state ({profile := "work"} : Plugin.ThreadState)
  Plugin.writeJson files.pending pending
  let base := Json.mkObj [("session_id", toJson session), ("turn_id", toJson pending.turnId),
    ("tool_name", toJson "shell"), ("tool_use_id", toJson "native-read"), ("tool_input", toolInput)]
  try
    hook binary root "pre" (base.setObjVal! "hook_event_name" (toJson "PreToolUse"))
    let actual ← shell root command
    check (actual == output) "source changed during native read"
    let post := (base.setObjVal! "hook_event_name" (toJson "PostToolUse")) |>.setObjVal! "tool_response" response
    hook binary root "post" post
    awaitSaves files
    let saved ← DB.PageMap.pin archive.directory
    let native : Plugin.ToolEvent := {seed with useId := "native-read"}
    let expected := (Plugin.compileOperationOutcomes (.text session) (.text pending.turnId) native).2
    let some _ ← findNode? saved expected | throw (IO.userError "native Post was not published by the actual save worker")
    awaitFeedback source.directory .omittedThenRead
    let some usage ← Index.open? source .user .usage | throw (IO.userError "actual ingress produced no private feedback")
    let values ← Index.allFacts usage.index
    check (values.any fun fact => match fact with
      | .used used => used.event.occurrence.useId == "native-read" && used.kind == .omittedThenRead
      | _ => false) "actual native Pre/Post did not record the stored but omitted read"
    let stop := Json.mkObj [("session_id", toJson session), ("turn_id", toJson pending.turnId),
      ("hook_event_name", toJson "Stop"), ("last_assistant_message", toJson "[source.cpp:11](src/source.cpp:11)")]
    hook binary root "stop" stop
    awaitSaves files
    awaitFeedback source.directory .deliveredThenCited
    let source ← DB.PageMap.pin source.directory
    let some journal ← Journal.open? source | throw (IO.userError "no native journal")
    let entries ← Journal.turnEntries journal ⟨session, pending.turnId⟩
    let some first := entries[0]? | throw (IO.userError "no native ingress events")
    check (entries.size == 3 && entries.all (·.clock.domain == first.clock.domain))
      "actual native ingress lost an event or manager clock binding"
    check ((← IO.FS.readBinFile (source.directory / "head")) == originalHead &&
      (← IO.FS.readBinFile (DB.PageMap.dataPath source.directory source.head)) == originalPages)
      "read-only source DB changed during native private-work feedback"
    check ((← findNode? source expected).isNone) "private tool output leaked into the shared source graph"
    IO.println (Json.mkObj [("nativeEvents", toJson entries.size), ("automaticBackground", toJson true),
      ("actualShellRead", toJson true), ("readOnlySourceUnchanged", toJson true),
      ("privateWorkPublished", toJson true), ("answeringModelCalls", toJson (0 : Nat))]).compress
  finally
    let _ ← IO.Process.output {cmd := binary.toString, args := #["codex-daemon", "shutdown"]}
    pure ()
