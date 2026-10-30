import tools.research.StudyRuntime
import tools.research.StudyCommand
import tools.research.StudyHistory
import tools.research.NativeTrialAudit
import Eggshell.Install
open Lean Eggshell Eggshell.Research Eggshell.Synapses

private def study : System.FilePath := "/Users/ovm/.codex/experiments/eggshell/scope-token-study-20261028"
private def project : System.FilePath := "/Users/ovm/.codex/worktrees/hook-deadline-baseline/eggshell"
private def evidence := project / "docs/candidates/group-cue-coverage"
private def read (p : System.FilePath) : IO Json := IO.FS.readFile p >>= fun s => IO.ofExcept (Json.parse s)
private def check (ok : Bool) (message : String) : IO Unit := unless ok do throw (IO.userError message)

private def install (runtime target : System.FilePath) : IO (System.FilePath × System.FilePath) := do
  let binary := target / "libexec/eggshell"
  IO.FS.createDirAll binary.parent.get!
  let copied ← IO.Process.output {cmd := "/bin/cp",args := #["-c",runtime.toString,binary.toString]}
  check (copied.exitCode == 0) "cannot install isolated group candidate"
  let plugin := target / "share/eggshell/codex-plugin"
  IO.FS.createDirAll (plugin / "bin")
  for name in ["egg","eggshelld"] do
    let path := plugin / "bin" / name
    IO.FS.writeFile path (Install.pluginLauncher target)
    IO.setAccessRights path {
      user := {read := true,write := true,execution := true}
      group := {read := true,execution := true}
      other := {read := true,execution := true}}
  let linked ← IO.Process.output {cmd := "/bin/ln",args := #["-s",(study / "prefix/share/eggshell/minilm").toString,
    (target / "share/eggshell/minilm").toString]}
  check (linked.exitCode == 0) "cannot share unchanged MiniLM numerical runtime"
  return (binary,plugin)

private def configuration (binary database : System.FilePath) (writable : Bool) : String :=
  "default = \"work\"\nsemantic_matcher = " ++ (toJson #[binary.toString,"search-provider"]).compress ++
  "\n[eggs]\nwork = " ++ (toJson database.toString).compress ++ "\n[profiles.work]\nread = [\"work\"]\n" ++
  (if writable then "write = \"work\"\n" else "") ++ "handoff_chars = 120000\n"

def main (args : List String) : IO Unit := do
  let runtime := study / "shared-snapshot/group-cue-runtime-build/StudyMain"
  let descriptor := evidence / "runtime-descriptor.json"
  if args == ["describe"] then
    check (!(← descriptor.pathExists)) "preserve frozen runtime descriptor"
    let value : StudyRuntime.PublisherRuntime := {
      binary := runtime.toString
      sha256 := ← ArtifactHash.hex runtime
      generation := ← Plugin.Publication.generation}
    IO.FS.writeFile descriptor (toJson value).pretty
    return
  check (args == ["run"]) "describe or run the fixed actual-hook trial"
  let root := study / "shared-snapshot/group-cue-trial"
  let records := evidence / "actual"
  check (!(← root.pathExists) && !(← records.pathExists)) "fresh source fixture and actual-hook records required"
  let expected : StudyRuntime.PublisherRuntime ← IO.ofExcept (fromJson? (← read descriptor))
  check (expected.binary == runtime.toString && expected.sha256 == (← ArtifactHash.hex runtime) &&
    expected.generation == (← Plugin.Publication.generation)) "trial and runtime producer differ"
  let prior := project / "docs/candidates/prepared-bindings/resumed/trial/frozen-before-delivery.json"
  let frozen ← IO.ofExcept ((← read prior).getArr?)
  let original := study / "r0/stage1/history/source.egg"
  let originalFiles ← StudyRuntime.files original
  for row in frozen do
    check ((row.getObjValD "specification").getObjValD "files" == toJson originalFiles) "fixed source files changed"
  IO.FS.createDirAll records
  IO.FS.createDirAll (study / "tmp")
  let manifest := study / "r0/stage1/history/history.json"
  let _ ← StudyHistory.fork ⟨manifest.toString,← ArtifactHash.hex manifest⟩ root
  let database := root / "work.egg"
  check ((← StudyRuntime.files database) == originalFiles) "trial source copy changed original bytes"
  let copied ← IO.Process.output {cmd := "/bin/cp",args := #["-cR",(study / "study/seed-2/work.egg/derived").toString,
    (database / "derived").toString]}
  check (copied.exitCode == 0) "cannot retain immutable numerical preparation"
  let source ← DB.PageMap.pin database
  let refinement ← read (study / "shared-snapshot/anchored-capture/seed-refinement.json")
  check (refinement.getObjValD "source" == toJson source.head) "source supplement crossed snapshot"
  let additions : Array (Nat × String × ContentCapture.Supplement) ← IO.ofExcept (refinement.getObjValAs? _ "supplements")
  let reader ← Persistence.Store.NodeReader.new source
  let mut supplements := #[]
  for (id,owner,supplement) in additions do
    check ((← Build.document reader id).owner == owner) "supplement crossed source owner"
    if supplement.sealed then supplements := supplements.push (id,supplement)
  let prepared ← Build.refresh source .database supplements
  check ((← Plugin.Publication.generation) == expected.generation) "source preparer changed producer"
  IO.FS.writeFile (records / "prepared-source.json") ((toJson prepared).setObjVal! "preparerGeneration" (toJson expected.generation)).pretty
  let installation := root / "prefix"
  let (binary,plugin) ← install runtime installation
  check ((← ArtifactHash.hex binary) == expected.sha256) "installed runtime differs from frozen binary"
  let writeConfig := root / "prepare.toml"
  let config := root / "readonly.toml"
  IO.FS.writeFile writeConfig (configuration binary database true)
  IO.FS.writeFile config (configuration binary database false)
  let env := fun config : System.FilePath => #[
    ("CODEX_HOME",some (study / "account").toString),("TMPDIR",some (study / "tmp").toString),
    ("EGGSHELL_PREFIX",some installation.toString),("EGGSHELL_DATA_ROOT",some (root / "data").toString),
    ("EGGSHELL_CONFIG",some config.toString),("EGGSHELL_PROFILE",some "work"),("PLUGIN_ROOT",some plugin.toString),
    ("CODEX_THREAD_ID",none),("CODEX_TURN_ID",none),("LEAN_NUM_THREADS",some "1"),
    ("OMP_NUM_THREADS",some "1"),("OPENBLAS_NUM_THREADS",some "1"),("MKL_NUM_THREADS",some "1"),
    ("HF_HUB_OFFLINE",some "1"),("TOKENIZERS_PARALLELISM",some "false"),("EGGSHELL_TRACE_SELECTION_RANGES",some "1")]
  let workspace := "/Users/ovm/Code/eggshell-benchmarks/aamas-2027/sources/llvm-project"
  let publisher ← StudyRuntime.startPublisher binary (root / "data") (env writeConfig) (expectedRuntime := some expected)
  try
    let warmed ← StudyCommand.run binary.toString #["egg","warm","work"] (env writeConfig) workspace "" (records / "warm") 240000
    check (warmed.exitCode == 0) "candidate warm failed"
  finally StudyRuntime.stopManaged publisher (records / "prepare-shutdown.json")
  IO.FS.writeFile (records / "frozen-before-delivery.json") (toJson frozen).pretty
  IO.FS.writeFile (records / "protocol.json") (Json.mkObj [("topics",toJson #[1,2,3]),
    ("freshSessions",toJson true),("firstFailureStops",toJson true),("runtime",toJson expected),
    ("answeringModelCalls",toJson (0 : Nat)),("adopted",toJson false)]).pretty
  let service ← StudyRuntime.startPublisher binary (root / "data") (env config) (expectedRuntime := some expected)
  let mut results := #[]
  try
    for topic in [1,2,3] do
      let some entry := frozen.find? (fun row => row.getObjValD "topic" == toJson topic) | throw (IO.userError "missing frozen topic")
      let spec := entry.getObjValD "specification"
      let prompt ← IO.FS.readFile (study / "prompts" / s!"topic-{topic}.txt")
      check (spec.getObjValD "prompt" == toJson prompt) "actual question differs from fixed comparison"
      let session := s!"group-cue-topic-{topic}"
      let out := records / s!"topic-{topic}"
      IO.FS.createDirAll out
      let daemon ← StudyRuntime.startManaged binary plugin session (root / "data/sessions" / session / "daemon.json") (env config)
      let mut accepted := false
      try
        for event in ["SessionStart","UserPromptSubmit"] do
          let request := Json.mkObj ([("hook_event_name",toJson event),("session_id",toJson session),
            ("turn_id",toJson "group-cue-turn"),("cwd",toJson workspace),("_eggshell_config",toJson config.toString)] ++
            if event == "UserPromptSubmit" then [("prompt",toJson prompt)] else [])
          let response ← StudyCommand.run binary.toString #["codex-hook"] (env config) workspace
            (request.compress ++ "\n") (out / event) 35000
          check (response.exitCode == 0) "actual hook process failed"
          if event == "UserPromptSubmit" then
            let reply ← IO.ofExcept (Json.parse response.stdout)
            let body ← IO.ofExcept ((reply.getObjValD "hookSpecificOutput").getObjValAs? String "additionalContext")
            let hash := Sha256.hex body.toUTF8
            IO.FS.writeFile (out / "body.txt") body
            let audit ← NativeTrialAudit.replayAvailable spec (out / "body.txt").toString hash
            check (audit.getObjValD "availableEvidence" == entry.getObjValD "available") "actual audit changed frozen denominator"
            IO.FS.writeFile (out / "audit.json") audit.pretty
            accepted := (audit.getObjValD "availableDelivery").getObjValD "targetMet" == toJson true && response.elapsedMs < 30000
            results := results.push (Json.mkObj [("topic",toJson topic),("elapsedMs",toJson response.elapsedMs),
              ("bodySha256",toJson hash),("actualDelivery",audit.getObjValD "availableDelivery"),
              ("withinDeadlineAndCoverage",toJson accepted)])
            IO.FS.writeFile (records / "progress.json") (toJson results).pretty
      finally StudyRuntime.stopManaged daemon (out / "shutdown.json")
      if !accepted then break
  finally StudyRuntime.stopManaged service (records / "publisher-shutdown.json")
  check ((← StudyRuntime.files database) == originalFiles && (← StudyRuntime.files original) == originalFiles) "actual trial changed source"
  IO.FS.writeFile (records / "result.json") (Json.mkObj [("results",toJson results),
    ("sourceUnchanged",toJson true),("answeringModelCalls",toJson (0 : Nat)),("adopted",toJson false)]).pretty
