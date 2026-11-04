import Lean.Data.Json.FromToJson
import Lean.Data.Json.Parser
open Lean
def read (path : System.FilePath) : IO Json := do IO.ofExcept (Json.parse (← IO.FS.readFile path))
def heads (source : System.FilePath) (count : Nat) : IO (Array Json) :=
  (List.range count).toArray.mapM fun i => read (source/"work.project/owners"/toString i/"source.egg/head")
def main (args : List String) : IO Unit := do
  let (runtime,sourceDirectory,outputDirectory,prepare) ← match args with
    | [runtime,sourceDirectory,outputDirectory] => pure (runtime,sourceDirectory,outputDirectory,false)
    | [runtime,sourceDirectory,outputDirectory,"warm"] => pure (runtime,sourceDirectory,outputDirectory,true)
    | _ => throw (IO.userError "fixed runtime, source and fresh output required")
  let source : System.FilePath := .mk sourceDirectory
  let root : System.FilePath := .mk outputDirectory
  unless !(← root.pathExists) do throw (IO.userError "preserve earlier probe")
  IO.FS.createDirAll root
  let identity ← IO.Process.output {cmd := "/usr/bin/shasum",args := #["-a","256",runtime]}
  unless identity.exitCode == 0 do throw (IO.userError "runtime identity unavailable")
  IO.FS.writeFile (root/"runtime.sha256") identity.stdout
  let expected ← IO.ofExcept ((← read (source/"frozen-readback.json")).getObjValAs? (Array Json) "sourceHeads")
  unless (← heads source expected.size) == expected do throw (IO.userError "source no longer matches frozen original cut")
  let config := root/"lexical.toml"
  IO.FS.writeFile config ("default = \"work\"\nsemantic_matcher = false\n[eggs]\nwork = \""++
    (source/"work.project").toString++"\"\n[profiles.work]\nread = [\"work\"]\nwrite = \"work\"\nhandoff_chars = 120000\n")
  let environment := #[("EGGSHELL_DATA_ROOT",some (root/"private").toString),
    ("PLUGIN_ROOT",some (root/"no-plugin-bundle").toString),("EGGSHELL_CONFIG",some config.toString),("LEAN_NUM_THREADS",some "1")]
  let mut rows := #[]
  try
    if prepare then
      let began ← IO.monoMsNow
      let prepared ← IO.Process.output {cmd := runtime,args := #["egg","warm",(source/"work.project").toString],env := environment}
      IO.FS.writeFile (root/"warm-stdout.json") prepared.stdout
      IO.FS.writeFile (root/"warm-stderr.txt") prepared.stderr
      IO.FS.writeFile (root/"warm-result.json") ((Json.mkObj [("exitCode",toJson prepared.exitCode.toNat),
        ("elapsedMs",toJson ((← IO.monoMsNow)-began))]).compress++"\n")
      unless prepared.exitCode == 0 do throw (IO.userError "changed lexical index preparation failed")
      unless (← heads source expected.size) == expected do throw (IO.userError "preparation changed original heads")
    for (name,query) in [("period","Return the recorded head and tail facts for support case-79."),
        ("no-period","Return the recorded head and tail facts for support case-79"),
        ("identifier","case-79"),("uri","mcp://support/case-79")] do
      let input := Json.mkObj [("session_id",toJson ("literal-"++name)),("turn_id",toJson "turn"),
        ("cwd",toJson source.toString),("hook_event_name",toJson "UserPromptSubmit"),
        ("_eggshell_config",toJson config.toString),("prompt",toJson query)]
      let began ← IO.monoMsNow
      let original ← IO.Process.spawn {
        cmd := runtime
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
      let actual ← child.stdout.readToEnd
      let code ← child.wait
      let elapsed := (← IO.monoMsNow)-began
      IO.FS.writeFile (root/(name++"-stdout.json")) actual
      let result ← IO.ofExcept (Json.parse actual)
      let body := ((result.getObjValD "hookSpecificOutput").getObjValAs? String "additionalContext").toOption.getD ""
      let head := body.contains "observed-head-case-79-7b319c"
      let tail := body.contains "observed-tail-case-79-d82a04"
      rows := rows.push (Json.mkObj [("arm",toJson name),("question",toJson query),
        ("exitCode",toJson code.toNat),("hookProcessMs",toJson elapsed),("bodyBytes",toJson body.utf8ByteSize),
        ("head",toJson head),("tail",toJson tail)])
      IO.FS.writeFile (root/"arms.json") ((toJson rows).compress++"\n")
      unless (← heads source expected.size) == expected do throw (IO.userError "query changed original heads")
  finally
    for command in [#["codex-daemon","shutdown"],#["publication-control","shutdown"]] do
      let stopped ← IO.Process.output {cmd := runtime,args := command,env := environment}
      unless stopped.exitCode == 0 do throw (IO.userError "probe service did not exit normally")
  IO.FS.writeFile (root/"report.json") ((Json.mkObj [("arms",toJson rows),
    ("allOriginalHeadsUnchanged",toJson true),("answeringModelCalls",toJson (0 : Nat)),
    ("administrativeWarmCalls",toJson (if prepare then (1 : Nat) else 0)),("adopted",toJson false)]).compress++"\n")
  IO.println (toJson rows).compress
