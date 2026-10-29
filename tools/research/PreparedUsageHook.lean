import tools.research.StudyRuntime
import tools.research.StudyCommand
import tools.research.NativeTrialAudit
import Eggshell.Install
open Lean Eggshell Eggshell.Research

private def read (path : System.FilePath) : IO Json :=
  IO.FS.readFile path >>= fun text => IO.ofExcept (Json.parse text)

def main (args : List String) : IO Unit := do
  let [runtime,prepared,newOutput] := args | throw (IO.userError "runtime, prepared trial and new output required")
  let root := System.FilePath.mk newOutput
  unless !(← root.pathExists) do throw (IO.userError "preserve actual hook evidence")
  let trial := System.FilePath.mk prepared
  let database := trial / "work.egg"
  let source ← DB.PageMap.pin database
  let study : System.FilePath := "/Users/ovm/.codex/experiments/eggshell/scope-token-study-20261028"
  let frozen ← DB.PageMap.pin (study / "r0/stage1/history/source.egg")
  unless source.head == frozen.head do throw (IO.userError "prepared source differs from the frozen snapshot")
  let original ← StudyRuntime.files database
  IO.FS.createDir root
  let prefixRoot := root / "prefix"
  let binary := prefixRoot / "libexec/eggshell"
  IO.FS.createDirAll binary.parent.get!
  let copied ← IO.Process.output {cmd := "/bin/cp",args := #["-c",runtime,binary.toString]}
  unless copied.exitCode == 0 do throw (IO.userError copied.stderr)
  let plugin := prefixRoot / "share/eggshell/plugin"
  IO.FS.createDirAll (plugin / "bin")
  IO.FS.writeFile (plugin / "bin/eggshelld") (Install.pluginLauncher prefixRoot)
  let model := prefixRoot / "share/eggshell/minilm"
  let linked ← IO.Process.output {cmd := "/bin/ln",args := #["-s",
    (study / "prefix/share/eggshell/minilm").toString,model.toString]}
  unless linked.exitCode == 0 do throw (IO.userError linked.stderr)
  let config := root / "config.toml"
  IO.FS.writeFile config ("default = \"work\"\nsemantic_matcher = " ++
    (toJson #[binary.toString,"search-provider"]).compress ++ "\n[eggs]\nwork = " ++
    (toJson database.toString).compress ++ "\n[profiles.work]\nread = [\"work\"]\nwrite = \"work\"\nhandoff_chars = 120000\n")
  let data := trial / "data"
  let environment := #[
    ("EGGSHELL_PREFIX",some prefixRoot.toString),("EGGSHELL_DATA_ROOT",some data.toString),
    ("EGGSHELL_CONFIG",some config.toString),("EGGSHELL_PROFILE",some "work"),
    ("PLUGIN_ROOT",some plugin.toString),("LEAN_NUM_THREADS",some "1"),
    ("EGGSHELL_HANDOFF_TRACE",some (root / "handoff.trace").toString),
    ("EGGSHELL_TRACE_SELECTION_RANGES",some "1"),("EGGSHELL_TRACE_SELECTOR_INPUT",some "1"),
    ("OMP_NUM_THREADS",some "1"),("OPENBLAS_NUM_THREADS",some "1"),("MKL_NUM_THREADS",some "1"),
    ("HF_HUB_OFFLINE",some "1"),("TOKENIZERS_PARALLELISM",some "false")]
  let workspace := "/Users/ovm/Code/eggshell-benchmarks/aamas-2027/sources/llvm-project"
  let publisher ← StudyRuntime.startPublisher binary data environment
  try
    let warm ← StudyCommand.run binary.toString #["egg","warm","work"] environment workspace "" (root / "warm") 240000
    unless warm.exitCode == 0 do throw (IO.userError "prepared runtime warm did not complete")
    let session := "prepared-usage-native-hook"
    let managed ← StudyRuntime.startManaged binary plugin session (data / "sessions" / session / "daemon.json") environment
    try
      for event in #["SessionStart","UserPromptSubmit"] do
        let prompt ← IO.FS.readFile (study / "prompts/topic-1.txt")
        let request := Json.mkObj ([("hook_event_name",toJson event),("session_id",toJson session),
          ("turn_id",toJson "first"),("cwd",toJson workspace),("_eggshell_config",toJson config.toString)] ++
          if event == "UserPromptSubmit" then [("prompt",toJson prompt)] else [])
        let result ← StudyCommand.run binary.toString #["codex-hook"] environment workspace
          (request.compress ++ "\n") (root / event) 35000
        unless result.exitCode == 0 do throw (IO.userError "actual hook failed")
        if event == "UserPromptSubmit" then
          let reply ← IO.ofExcept (Json.parse result.stdout)
          let body ← IO.ofExcept ((reply.getObjValD "hookSpecificOutput").getObjValAs? String "additionalContext")
          IO.FS.writeFile (root / "body.txt") body
          let previous ← read (study / "all-citations-audit-input.json")
          let input := Json.mkObj [("source",previous.getObjValD "source"),("database",toJson database.toString),
            ("request",toJson (root / event / "stdin").toString),("stdout",toJson (root / event / "stdout").toString),
            ("timing",toJson (root / event / "record.json").toString),("body",toJson (root / "body.txt").toString)]
          IO.FS.writeFile (root / "audit-input.json") input.pretty
          let audit ← NativeTrialAudit.inspect (root / "audit-input.json").toString
          IO.FS.writeFile (root / "audit.json") audit.pretty
          IO.println (Json.mkObj [("delivery",audit.getObjValD "requiredDelivery"),
            ("elapsedMs",toJson result.elapsedMs),("answeringModelCalls",toJson (0 : Nat))]).compress
    finally StudyRuntime.stopManaged managed (root / "shutdown.json")
  finally StudyRuntime.stopManaged publisher (root / "publisher-shutdown.json")
  unless (← StudyRuntime.files database) == original do throw (IO.userError "actual hook changed the original source")
