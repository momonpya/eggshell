import Eggshell.SynapseLive

open Lean Eggshell Eggshell.Synapses
open Eggshell.Persistence.Store

private def check (condition : Bool) (message : String) : IO Unit :=
  unless condition do throw (IO.userError message)

private def shell (root : System.FilePath) (command : String) : IO String := do
  let result ← IO.Process.output {cmd := "/bin/sh", args := #["-c", command], cwd := some root.toString}
  check (result.exitCode == 0) result.stderr
  return result.stdout

private def hook (binary root : System.FilePath) (label : String) (input : Json) : IO Unit := do
  let path := root / (label ++ ".json")
  IO.FS.writeFile path input.compress
  let result ← IO.Process.output {
    cmd := "/bin/sh", args := #["-c", "exec \"$1\" codex-hook < \"$2\"", "hook", binary.toString, path.toString]
    cwd := some root.toString }
  IO.FS.writeFile (root / (label ++ ".stdout")) result.stdout
  IO.FS.writeFile (root / (label ++ ".stderr")) result.stderr
  check (result.exitCode == 0) s!"native {label}: {result.stderr}"
  let _ ← IO.ofExcept (Json.parse result.stdout)

private def awaitOrigins (directory : System.FilePath) (count : Nat) : IO Unit := do
  let deadline := (← IO.monoMsNow)+15000
  repeat
    let source ← DB.PageMap.pin directory
    if (← Provenance.records source).size == count then return
    if (← IO.monoMsNow) ≥ deadline then throw (IO.userError "native worker did not publish portable origins")
    IO.sleep 25

private def awaitConsumed (directory : System.FilePath) : IO (Array Fact) := do
  let deadline := (← IO.monoMsNow)+15000
  repeat
    let source ← DB.PageMap.pin directory
    if let some index ← Index.open? source .database .shared then
      let facts ← Index.allFacts index.index
      if facts.any (fun fact => match fact with
        | .consumed edge => edge.consumer.useId == "native-consumer" && edge.rows.any (·.first == 11)
        | _ => false) then return facts
    if (← IO.monoMsNow) ≥ deadline then throw (IO.userError "native worker did not warm the portable consumption edge")
    IO.sleep 25

def main (args : List String) : IO Unit := do
  let [path, executable] := args | throw (IO.userError "SynapsePortableIntegration NEW-DIRECTORY CANDIDATE")
  let root := System.FilePath.mk path
  let binary := System.FilePath.mk executable
  let some isolated ← IO.getEnv "EGGSHELL_DATA_ROOT" | throw (IO.userError "isolated data root required")
  check (root.isAbsolute && !(← root.pathExists) && binary.isAbsolute &&
    (isolated.splitOn "synaptic-portable-").length > 1) "isolated fixture and executable required"
  IO.FS.createDirAll (root / "src")
  IO.FS.writeFile (root / "src/source.cpp")
    ("\n".intercalate ((List.range 9).map fun i => s!"prefix-{i+1}") ++ "\nalpha\nNEEDED_SYMBOL\nomega\n")
  let source ← DB.PageMap.create (root / "source.egg") (Persistence.valueToJson (.text "fixture")).compress
  let _ ← Build.refresh source .database
  let session := "synaptic-portable-native"
  let files ← Plugin.sessionFiles session
  let pending : Plugin.PendingTurn := {
    sessionId := session, turnId := "native-turn", cwd := root.toString, prompt := "inspect source evidence"
    profile := "work", semanticMatcher := none, read := [source.directory.toString]
    write := some source.directory.toString, handoffChars := 120000, projection := .none }
  Plugin.writeJson files.state ({profile := "work"} : Plugin.ThreadState)
  Plugin.writeJson files.pending pending
  try
    for (useId, command) in [("native-read", "nl -ba src/source.cpp | sed -n '10,12p'"),
        ("native-consumer", "printf NEEDED_SYMBOL")] do
      let input := Json.mkObj [("command", toJson command)]
      let base := Json.mkObj [("session_id", toJson session), ("turn_id", toJson pending.turnId),
        ("tool_name", toJson "shell"), ("tool_use_id", toJson useId), ("tool_input", input)]
      hook binary root (useId ++ "-pre") (base.setObjVal! "hook_event_name" (toJson "PreToolUse"))
      let output ← shell root command
      let response := Json.mkObj [("output", toJson output), ("exitCode", toJson (0 : Nat))]
      let post := (base.setObjVal! "hook_event_name" (toJson "PostToolUse")) |>.setObjVal! "tool_response" response
      hook binary root (useId ++ "-post") post
      awaitOrigins source.directory (if useId == "native-read" then 1 else 2)
    let all ← awaitConsumed source.directory
    let source ← DB.PageMap.pin source.directory
    let origins ← Provenance.records source
    check (origins.all (fun stored => stored.origin.occurrence.session == session && stored.origin.valid))
      "portable origins lost their actual native occurrence"
    let entries ← Journal.turnEntries (← Journal.prepare source) ⟨session, pending.turnId⟩
    check (entries.size == 4) "actual Pre/Post did not record exactly four events"
    -- The reader is a later independent process with a different private root.
    let destination := root / "copied.egg"
    IO.FS.createDirAll destination
    for entry in ← source.directory.readDir do
      if entry.fileName == "head" || entry.fileName.endsWith ".pages" then
        IO.FS.writeBinFile (destination / entry.fileName) (← IO.FS.readBinFile entry.path)
    IO.FS.writeFile (root / "expected.json") (toJson all).compress
    IO.println (Json.mkObj [("nativeEvents", toJson entries.size), ("portableOrigins", toJson origins.size),
      ("actualShellCalls", toJson (2 : Nat)), ("automaticBackground", toJson true),
      ("answeringModelCalls", toJson (0 : Nat))]).compress
  finally
    let _ ← IO.Process.output {cmd := binary.toString, args := #["codex-daemon", "shutdown"]}
    pure ()
