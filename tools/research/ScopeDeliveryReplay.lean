import tools.research.StudyRuntime
import tools.research.StudyCommand
import tools.research.StudyHistory
import tools.research.ArtifactHash
open Lean Eggshell.Research

/-- One model-free replay from the sealed pre-answer snapshot. Tracing is
accepted as an explanation only if the actual first model packet is identical. -/
def main : IO Unit := do
  let base : System.FilePath := "/Users/ovm/.codex/experiments/eggshell/scope-token-study-20261028"
  let root := base / "delivery-replay-verified"
  unless !(← root.pathExists) do throw (IO.userError "preserve prior diagnostic")
  let manifest := base / "r0/stage1/history/history.json"
  let _ ← StudyHistory.fork ⟨manifest.toString,← ArtifactHash.hex manifest⟩ root
  let database := root / "work.egg"
  let before ← StudyRuntime.files database
  let prepared := base / "study/seed-2/work.egg/derived"
  let copied ← IO.Process.output {cmd := "/bin/cp",args := #["-cR",prepared.toString,(database / "derived").toString]}
  unless copied.exitCode == 0 do throw (IO.userError copied.stderr)
  let binary := base / "prefix/libexec/eggshell"
  let sealed ← IO.ofExcept (Json.parse (← IO.FS.readFile (base / "r0/stage1/trial/plan.json")))
  let plugin := System.FilePath.mk (← IO.ofExcept (sealed.getObjValAs? String "pluginRoot"))
  let data := root / "data"
  let config := root / "config.toml"
  let workspace := "/Users/ovm/Code/eggshell-benchmarks/aamas-2027/sources/llvm-project"
  IO.FS.writeFile config ("default = \"work\"\nsemantic_matcher = " ++
    (toJson #[binary.toString,"search-provider"]).compress ++ "\n[eggs]\nwork = " ++
    (toJson database.toString).compress ++
    "\n[profiles.work]\nread = [\"work\"]\nwrite = \"work\"\nhandoff_chars = 120000\n")
  let environment := #[
    ("EGGSHELL_PREFIX",some (base / "prefix").toString),("EGGSHELL_DATA_ROOT",some data.toString),
    ("EGGSHELL_CONFIG",some config.toString),("EGGSHELL_PROFILE",some "work"),("PLUGIN_ROOT",some plugin.toString),
    ("EGGSHELL_TRACE_SELECTION_RANGES",some "1"),("EGGSHELL_TRACE_SELECTOR_INPUT",some "1"),
    ("EGGSHELL_HANDOFF_TRACE",some (root / "handoff.trace").toString),
    ("LEAN_NUM_THREADS",some "1"),("OMP_NUM_THREADS",some "1"),("OPENBLAS_NUM_THREADS",some "1"),
    ("MKL_NUM_THREADS",some "1"),("HF_HUB_OFFLINE",some "1"),("TOKENIZERS_PARALLELISM",some "false")]
  let prompt ← IO.FS.readFile (base / "prompts/topic-1.txt")
  let publisher ← StudyRuntime.startPublisher binary data environment
  try
    let session := "scope-topic1-readonly-explanation"
    let managed ← StudyRuntime.startManaged binary plugin session (data / "sessions" / session / "daemon.json") environment
    try
      for event in #["SessionStart","UserPromptSubmit"] do
        let request := Json.mkObj ([("hook_event_name",toJson event),("session_id",toJson session),
          ("turn_id",toJson "first"),("cwd",toJson workspace),("_eggshell_config",toJson config.toString)] ++
          if event == "UserPromptSubmit" then [("prompt",toJson prompt)] else [])
        let result ← StudyCommand.run binary.toString #["codex-hook"] environment workspace
          (request.compress ++ "\n") (root / event) 35000
        if event == "UserPromptSubmit" then
          let response ← IO.ofExcept (Json.parse result.stdout)
          let body ← IO.ofExcept ((response.getObjValD "hookSpecificOutput").getObjValAs? String "additionalContext")
          IO.FS.writeFile (root / "body.txt") body
          let actual ← IO.FS.readFile (base / "r0/stage1/trial/packet-0.txt")
          IO.FS.writeFile (root / "comparison.json") (Json.mkObj [
            ("bodyIdenticalToActualModel",toJson (actual == body)),("elapsedMs",toJson result.elapsedMs),
            ("modelCalls",toJson (0 : Nat)),("sameSourceFiles",toJson ((← StudyRuntime.files database) == before)),
            ("runtimeSha256",toJson (← ArtifactHash.hex binary))]).pretty
    finally StudyRuntime.stopManaged managed (root / "shutdown.json")
  finally StudyRuntime.stopManaged publisher (root / "publisher-shutdown.json")
