import tools.research.StudyRuntime
open Lean Eggshell Eggshell.Research

private def check (ok : Bool) (message : String) : IO Unit :=
  unless ok do throw (IO.userError message)

private def invoke (binary workspace output : System.FilePath) (event : Json) : IO Json := do
  IO.FS.createDir output
  let input := output / "input.json"
  IO.FS.writeFile input event.compress
  let receiptRoot := (← Paths.dataRoot) / "receipts"
  let before ← if ← receiptRoot.pathExists then
      pure ((← receiptRoot.readDir).map (·.fileName)) else pure #[]
  let started ← IO.monoMsNow
  let result ← IO.Process.output {
    cmd := "/bin/sh"
    args := #["-c","exec \"$1\" codex-hook < \"$2\"","hook",binary.toString,input.toString]
    cwd := some workspace.toString}
  let ms := (← IO.monoMsNow)-started
  IO.FS.writeFile (output / "stdout.json") result.stdout
  IO.FS.writeFile (output / "stderr.txt") result.stderr
  check (result.exitCode == 0 && ms < 30000) "native hook failed or exceeded deadline"
  let reply ← IO.ofExcept (Json.parse result.stdout)
  let mut publications := 0
  let mut ackRequired := false
  let mut offerAccepted : Option Bool := none
  let memoryOfferExpected := reply.compress.contains "SOURCE_ORIGINAL_MARKER" ||
    ((reply.getObjValD "hookSpecificOutput").getObjValAs? String "permissionDecision").toOption == some "deny"
  if ← receiptRoot.pathExists then
    for entry in ← receiptRoot.readDir do
      if before.contains entry.fileName then continue
      let path := entry.path / "published.json"
      if !(← path.pathExists) then continue
      let raw ← IO.ofExcept (Json.parse (← IO.FS.readFile path))
      let data := raw.getObjValD "data"
      if (data.getObjValAs? String "output").toOption == some result.stdout then
        check ((data.getObjValAs? Nat "bytes").toOption == some result.stdout.utf8ByteSize &&
          (data.getObjValAs? String "sha256").toOption == some (Sha256.hex result.stdout.toUTF8))
          "native publication differs from stdout"
        let complete := (data.getObjValAs? Bool "replyComplete").toOption == some true
        if complete && reply != Json.mkObj [] then
          ackRequired := true
          let ackPath := entry.path / "ack.json"
          check (← ackPath.pathExists) "nonempty publication has no ACK"
          let ack ← IO.ofExcept (Json.parse (← IO.FS.readFile ackPath))
          check (((ack.getObjValD "data").getObjValAs? Bool "rpcCompleted").toOption == some true)
            "ACK RPC did not complete"
          offerAccepted := ((ack.getObjValD "data").getObjValAs? Bool "offerAccepted").toOption
          if memoryOfferExpected then
            check (offerAccepted == some true) "manager did not accept memory delivery ACK"
        if (event.getObjValAs? String "hook_event_name").toOption == some "PreToolUse" then
          check (← (entry.path / "work-class-root.json").pathExists)
            "native PreToolUse did not enter the class-root producer"
        publications := publications + 1
  check (publications == 1) "native stdout does not have exactly one new publication receipt"
  let record := Json.mkObj [("elapsedMs",toJson ms),("reply",reply),
    ("publishedExactly",toJson true),("ackRequired",toJson ackRequired),
    ("memoryOfferExpected",toJson memoryOfferExpected),("offerAccepted",toJson offerAccepted),
    ("stdoutSha256",toJson (Sha256.hex result.stdout.toUTF8))]
  IO.FS.writeFile (output / "result.json") record.pretty
  return record

private def run (binary plugin database workspace output : System.FilePath) (mode : String := "plain") : IO Unit := do
  check (!(← output.pathExists)) "preserve native trial"
  FileSystem.privateDirectory output
  let config := output / "config.toml"
  let provider := if mode == "provider" then "[\"/does-not-exist/structural-provider-must-not-run\"]" else "false"
  IO.FS.writeFile config ("default = \"readonly\"\nsemantic_matcher = " ++ provider ++ "\n[eggs]\nsource = " ++
    (toJson database.toString).compress ++ "\n[profiles.readonly]\nread = [\"source\"]\nhandoff_chars = 24000\n")
  let original ← IO.FS.readFile (workspace / "source.txt")
  let sourceHead := (← DB.PageMap.pin database).head
  let mut records := []
  try
    for label in ["fresh","changed"] do
      if label == "changed" then IO.FS.writeFile (workspace / "source.txt") "NATIVE_CHANGED_SOURCE\n"
      let suffix := ((← Eggshell.Receipt.fresh).take 12).copy
      let session := "structural-" ++ label ++ "-" ++ suffix
      let endpoint ← Plugin.Daemon.endpointPath session
      let managed ← StudyRuntime.startManaged binary plugin session endpoint #[
        ("EGGSHELL_CONFIG",some config.toString)]
      try
        let common := [("session_id",toJson session),("turn_id",toJson "native-turn"),
          ("cwd",toJson workspace.toString),("_eggshell_config",toJson config.toString)]
        let nativeInput := Json.mkObj [("command",toJson "sed -n '1,2p' source.txt")]
        let tool : Eggshell.Plugin.ToolEvent := {
          name := "Bash", useId := "native-read", input := nativeInput.compress, response := ""}
        let question := if mode == "known" then Eggshell.Plugin.canonicalToolWork tool else "zzzzzz"
        let prompt ← invoke binary workspace (output / (label++"-prompt"))
          (Json.mkObj (common ++ [("hook_event_name",toJson "UserPromptSubmit"),("prompt",toJson question)]))
        let pre ← invoke binary workspace (output / (label++"-pre"))
          (Json.mkObj (common ++ [("hook_event_name",toJson "PreToolUse"),
            ("tool_use_id",toJson "native-read"),("tool_name",toJson "Bash"),
            ("tool_input",nativeInput)]))
        let decision := ((pre.getObjValD "reply").getObjValD "hookSpecificOutput").getObjValD "permissionDecision"
        check ((decision == toJson "deny") == (label == "fresh")) "native control ignored freshness"
        if label == "fresh" then
          check ((if mode == "known" then prompt else pre).compress.contains "SOURCE_ORIGINAL_MARKER")
            "native session lacks the confirmed original body"
        records := Json.mkObj [("case",toJson label),("prompt",prompt),("preToolUse",pre)] :: records
      finally
        StudyRuntime.stopManaged managed (output / (label++"-manager-stop.json"))
  finally IO.FS.writeFile (workspace / "source.txt") original
  check ((← DB.PageMap.pin database).head == sourceHead) "native query changed original source head"
  IO.FS.writeFile (output / "result.json") (Json.mkObj [
    ("runtimeSha256",toJson (← ArtifactHash.hex binary)),("cases",toJson records.reverse),
    ("mode",toJson mode),
    ("sourceHeadUnchanged",toJson true),("answeringModelCalls",toJson (0 : Nat)),
    ("adopted",toJson false)]).pretty

def main (args : List String) : IO Unit := do
  match args with
  | [binary,plugin,database,workspace,output] => run (.mk binary) (.mk plugin) (.mk database) (.mk workspace) (.mk output)
  | [binary,plugin,database,workspace,output,mode] => run (.mk binary) (.mk plugin) (.mk database) (.mk workspace) (.mk output) mode
  | _ => throw (IO.userError "StructuralHookAudit BINARY PLUGIN DB WORKSPACE NEW-OUTPUT")
