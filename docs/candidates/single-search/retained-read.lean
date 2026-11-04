import Lean.Data.Json.FromToJson
import Lean.Data.Json.Parser
open Lean
def read (path : System.FilePath) : IO Json := do IO.ofExcept (Json.parse (← IO.FS.readFile path))
def hash (path : System.FilePath) : IO String := do
  let value ← IO.Process.output {cmd := "/usr/bin/shasum",args := #["-a","256",path.toString]}
  unless value.exitCode == 0 do throw (IO.userError "hashing failed")
  return (value.stdout.splitOn " ").head!
def main (args : List String) : IO Unit := do
  let [binary,directory] := args | throw (IO.userError "fixed native runtime and retained fixture required")
  let root : System.FilePath := .mk directory
  let output := root/"retained-read.json"
  unless !(← output.pathExists) do throw (IO.userError "preserve earlier diagnostic")
  let environment := #[("EGGSHELL_DATA_ROOT",some (root/"private").toString),
    ("PLUGIN_ROOT",some (root/"no-plugin-bundle").toString),("LEAN_NUM_THREADS",some "1")]
  let original ← (List.range 16).toArray.mapM fun owner => hash (root/"work.project/owners"/toString owner/"source.egg/head")
  let input := Json.mkObj [("session_id",toJson "retained-solo-reader"),("turn_id",toJson "turn"),
    ("cwd",toJson root.toString),("hook_event_name",toJson "UserPromptSubmit"),
    ("_eggshell_config",toJson (root/"eggshell.toml").toString),
    ("prompt",toJson "Return the recorded head and tail facts for support case-79.")]
  let started ← IO.monoMsNow
  let (text,code) ← try
      let original ← IO.Process.spawn {
        cmd := binary
        args := #["codex-hook"]
        env := environment
        stdin := .piped
        stdout := .piped
        stderr := .inherit }
      let child ← do
        let (writer,child) ← original.takeStdin
        writer.putStr input.compress
        writer.flush
        pure child
      let text ← child.stdout.readToEnd
      let code ← child.wait
      pure (text,code)
    finally
      for command in [#["codex-daemon","shutdown"],#["publication-control","shutdown"]] do
        let stopped ← IO.Process.output {cmd := binary,args := command,env := environment}
        unless stopped.exitCode == 0 do throw (IO.userError "diagnostic service did not exit normally")
  let current ← (List.range 16).toArray.mapM fun owner => hash (root/"work.project/owners"/toString owner/"source.egg/head")
  unless original == current do throw (IO.userError "read-only diagnostic changed an original head")
  let result ← IO.ofExcept (Json.parse text)
  let body := ((result.getObjValD "hookSpecificOutput").getObjValAs? String "additionalContext").toOption.getD ""
  let present := body.contains "observed-head-case-79-7b319c" && body.contains "observed-tail-case-79-d82a04"
  IO.FS.writeFile output ((Json.mkObj [("exitCode",toJson code.toNat),
    ("elapsedIncludingShutdownMs",toJson ((← IO.monoMsNow)-started)),
    ("requiredFieldsDelivered",toJson present),("originalHeadsUnchanged",toJson true),
    ("actualOutput",toJson text),("answeringModelCalls",toJson (0 : Nat))]).compress++"\n")
  IO.println (Json.mkObj [("requiredFieldsDelivered",toJson present),("originalHeadsUnchanged",toJson true)]).compress
