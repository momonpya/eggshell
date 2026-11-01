import tools.research.StudyRuntime
import tools.research.StudyCommand
import tools.research.StudyHistory
open Lean Eggshell Eggshell.Research
private def check (ok : Bool) (message : String) : IO Unit := unless ok do throw (IO.userError message)
private def read (path : System.FilePath) : IO Json := IO.FS.readFile path >>= fun text => IO.ofExcept (Json.parse text)

def main : IO Unit := do
  let study : System.FilePath := "/Users/ovm/.codex/experiments/eggshell/scope-token-study-20261028"
  let root := study / "shared-snapshot/selection-frames-trial/candidate"
  let records : System.FilePath := "/Users/ovm/.codex/worktrees/hook-deadline-baseline/eggshell/docs/candidates/transport-profile/resident"
  let prior := records.parent.get! / "hooks/candidate/rep-0/topic-1"
  let specification ← read (records.parent.get! / "hooks/candidate-runtime.json")
  let runtime : StudyRuntime.PublisherRuntime ← IO.ofExcept (specification.getObjValAs? _ "runtime")
  let binary := root / "prefix/libexec/eggshell"
  check ((← ArtifactHash.hex binary) == runtime.sha256 && runtime.generation == (← Plugin.Publication.generation))
    "resident trial changed the frozen runtime"
  let sourceFiles ← StudyRuntime.files (root / "work.egg")
  let source ← read (prior / "before-gold.json")
  check (source.getObjValD "sourceFiles" == toJson sourceFiles) "resident trial changed the frozen source"
  check (!(← records.pathExists)) "preserve resident profile"
  IO.FS.createDirAll records
  let env := #[("CODEX_HOME",some (study / "account").toString),("EGGSHELL_PREFIX",some (root / "prefix").toString),
    ("EGGSHELL_DATA_ROOT",some (root / "data").toString),("EGGSHELL_CONFIG",some (root / "readonly.toml").toString),
    ("EGGSHELL_PROFILE",some "work"),("PLUGIN_ROOT",some (root / "prefix/share/eggshell/codex-plugin").toString),
    ("TMPDIR",some (study / "tmp").toString),("LEAN_NUM_THREADS",some "1"),
    ("OMP_NUM_THREADS",some "1"),("OPENBLAS_NUM_THREADS",some "1"),("MKL_NUM_THREADS",some "1"),
    ("HF_HUB_OFFLINE",some "1"),("TOKENIZERS_PARALLELISM",some "false"),
    ("EGGSHELL_TRACE_SERVICE_PROFILE",some "1"),("EGGSHELL_TRACE_SELECTION_RANGES",none),("EGGSHELL_TRACE_SELECTOR_INPUT",none),
    ("CODEX_THREAD_ID",none),("CODEX_TURN_ID",none)]
  let workspace := "/Users/ovm/Code/eggshell-benchmarks/aamas-2027/sources/llvm-project"
  let prompt ← IO.FS.readFile (study / "prompts/topic-1.txt")
  let reference ← IO.FS.readFile (prior / "body.txt")
  let stages := ["source-plan-profile","source-bindings-profile","server-envelope-profile","client-profile",
    "stream-exchange-profile","stream-receive-profile","render-client-profile","render-automatic-profile"]
  IO.FS.writeFile (records / "before.json") (Json.mkObj [("runtime",toJson runtime),("sourceFiles",toJson sourceFiles),
    ("schedule",toJson "One project publisher, two distinct session daemons/chats, same question in order; stop on mismatch or incomplete hook."),
    ("bodyReference",toJson (prior / "body.txt").toString),("bodySha256",toJson (Sha256.hex reference.toUTF8)),
    ("modelCalls",toJson (0 : Nat)),("sustained80PersonWorkload",toJson false)]).pretty
  let publisher ← StudyRuntime.startPublisher binary (root / "data") env (expectedRuntime := some runtime)
  try
    for chat in [:2] do
      let session := s!"resident-transport-{chat}"
      let destination := records / s!"chat-{chat}"
      IO.FS.createDirAll destination
      let daemon ← StudyRuntime.startManaged binary (root / "prefix/share/eggshell/codex-plugin") session
        (root / "data/sessions" / session / "daemon.json") env
      try
        for event in ["SessionStart","UserPromptSubmit"] do
          let request := Json.mkObj ([("hook_event_name",toJson event),("session_id",toJson session),
            ("turn_id",toJson "resident-transport-turn"),("cwd",toJson workspace),
            ("_eggshell_config",toJson (root / "readonly.toml").toString)] ++
            if event == "UserPromptSubmit" then [("prompt",toJson prompt)] else [])
          let started ← IO.monoMsNow
          let response ← StudyCommand.run binary.toString #["codex-hook"] env workspace
            (request.compress ++ "\n") (destination / event) 35000
          check (response.exitCode == 0) "resident hook failed"
          if event == "UserPromptSubmit" then
            let output ← IO.ofExcept (Json.parse response.stdout)
            let body ← IO.ofExcept ((output.getObjValD "hookSpecificOutput").getObjValAs? String "additionalContext")
            check (body == reference) "resident cache changed the actual delivered body"
            let mut profiles := #[]
            for receipt in ← (root / "data/receipts").readDir do
              for stage in stages do
                let path := receipt.path / (stage ++ ".json")
                if !(← path.pathExists) then continue
                let row ← read path
                if ((row.getObjValAs? Nat "observedMs").toOption.getD 0) ≥ started then profiles := profiles.push row
            IO.FS.writeFile (destination / "result.json") (Json.mkObj [("chat",toJson chat),
              ("elapsedMs",toJson response.elapsedMs),("bodySha256",toJson (Sha256.hex body.toUTF8)),
              ("sameParentBody",toJson true),("publisherPid",toJson (StudyRuntime.pid publisher)),
              ("sessionPid",toJson (StudyRuntime.pid daemon)),("serviceProfiles",toJson profiles),
              ("sameQuestionAndSource",toJson true),("modelCalls",toJson (0 : Nat)),("adopted",toJson false)]).pretty
      finally StudyRuntime.stopManaged daemon (destination / "shutdown.json")
  finally StudyRuntime.stopManaged publisher (records / "publisher-shutdown.json")
  check ((← StudyRuntime.files (root / "work.egg")) == sourceFiles) "resident hooks changed their original source"
