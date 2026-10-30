import tools.research.StudyRuntime
import tools.research.StudyCommand
import tools.research.StudyHistory
import tools.research.NativeTrialAudit
import Eggshell.Install
open Lean Eggshell Eggshell.Research Eggshell.Synapses

private def study : System.FilePath := "/Users/ovm/.codex/experiments/eggshell/scope-token-study-20261028"
private def project : System.FilePath := "/Users/ovm/.codex/worktrees/hook-deadline-baseline/eggshell"
private def records := project / "docs/candidates/owner-bindings/hooks"
private def read (p : System.FilePath) : IO Json := IO.FS.readFile p >>= fun s => IO.ofExcept (Json.parse s)
private def check (ok : Bool) (message : String) : IO Unit := unless ok do throw (IO.userError message)

private def runtimePath (arm : String) : System.FilePath := study / "shared-snapshot" /
  (if arm == "baseline" then "query-cache-baseline-build" else "owner-bindings-runtime-build") / "StudyMain"
private def helperPath (arm : String) : System.FilePath := study / "shared-snapshot" /
  ("owner-bindings-hook-" ++ arm ++ "-build") / "StudyMain"
private def armPath (arm : String) : System.FilePath := study / "shared-snapshot/owner-bindings-hook-trial" / arm

private def config (binary database : System.FilePath) (write : Bool) : String :=
  "default = \"work\"\nsemantic_matcher = " ++ (toJson #[binary.toString,"search-provider"]).compress ++
  "\n[eggs]\nwork = " ++ (toJson database.toString).compress ++ "\n[profiles.work]\nread = [\"work\"]\n" ++
  (if write then "write = \"work\"\n" else "") ++ "handoff_chars = 120000\n"

private def install (arm : String) : IO Unit := do
  let target := armPath arm / "prefix"
  let binary := target / "libexec/eggshell"
  IO.FS.createDirAll binary.parent.get!
  let copy ← IO.Process.output {cmd := "/bin/cp",args := #["-c",(runtimePath arm).toString,binary.toString]}
  check (copy.exitCode == 0) "cannot install matched arm runtime"
  let plugin := target / "share/eggshell/codex-plugin"
  IO.FS.createDirAll (plugin / "bin")
  for name in ["egg","eggshelld"] do
    let file := plugin / "bin" / name
    IO.FS.writeFile file (Install.pluginLauncher target)
    IO.setAccessRights file {
      user := {read := true,write := true,execution := true}
      group := {read := true,execution := true}
      other := {read := true,execution := true}}
  let linked ← IO.Process.output {cmd := "/bin/ln",args := #["-s",
    (study / "prefix/share/eggshell/minilm").toString,(target / "share/eggshell/minilm").toString]}
  check (linked.exitCode == 0) "cannot share the unchanged MiniLM boundary"
  IO.FS.writeFile (armPath arm / "prepare.toml") (config binary (armPath arm / "work.egg") true)
  IO.FS.writeFile (armPath arm / "readonly.toml") (config binary (armPath arm / "work.egg") false)

private def environment (arm : String) (write : Bool) : Array (String × Option String) :=
  let root := armPath arm
  let installation := root / "prefix"
  #[("CODEX_HOME",some (study / "account").toString),("TMPDIR",some (study / "tmp").toString),
    ("EGGSHELL_PREFIX",some installation.toString),("EGGSHELL_DATA_ROOT",some (root / "data").toString),
    ("EGGSHELL_CONFIG",some (root / (if write then "prepare.toml" else "readonly.toml")).toString),
    ("EGGSHELL_PROFILE",some "work"),("PLUGIN_ROOT",some (installation / "share/eggshell/codex-plugin").toString),
    ("CODEX_THREAD_ID",none),("CODEX_TURN_ID",none),("LEAN_NUM_THREADS",some "1"),
    ("OMP_NUM_THREADS",some "1"),("OPENBLAS_NUM_THREADS",some "1"),("MKL_NUM_THREADS",some "1"),
    ("HF_HUB_OFFLINE",some "1"),("TOKENIZERS_PARALLELISM",some "false"),
    ("EGGSHELL_TRACE_SELECTION_RANGES",none),("EGGSHELL_TRACE_SELECTOR_INPUT",none)]

private def workspace := "/Users/ovm/Code/eggshell-benchmarks/aamas-2027/sources/llvm-project"

def main (args : List String) : IO Unit := do
  let mode :: arm :: rest := args | throw (IO.userError "describe/prepare/run baseline/candidate [repetition]")
  check (["baseline","candidate"].contains arm) "unknown matched arm"
  check ((← IO.appPath).normalize == (helperPath arm).normalize) "the wrong arm's producer was invoked"
  IO.FS.createDirAll records
  let descriptor := records / (arm ++ "-runtime.json")
  if mode == "describe" then
    check (rest.isEmpty && !(← descriptor.pathExists)) "preserve frozen arm runtime"
    let runtime : StudyRuntime.PublisherRuntime := {
      binary := (runtimePath arm).toString
      sha256 := ← ArtifactHash.hex (runtimePath arm)
      generation := ← Plugin.Publication.generation}
    IO.FS.writeFile descriptor (Json.mkObj [("arm",toJson arm),("runtime",toJson runtime),
      ("helperSha256",toJson (← ArtifactHash.hex (helperPath arm)))]).pretty
    return
  let described ← read descriptor
  let expected : StudyRuntime.PublisherRuntime ← IO.ofExcept (fromJson? (described.getObjValD "runtime"))
  check (expected.sha256 == (← ArtifactHash.hex (runtimePath arm)) &&
    described.getObjValD "helperSha256" == toJson (← ArtifactHash.hex (helperPath arm)) &&
    expected.generation == (← Plugin.Publication.generation)) "arm producer or runtime changed after sealing"
  let original := study / "r0/stage1/history/source.egg"
  let originalFiles ← StudyRuntime.files original
  let frozenEntries ← IO.ofExcept ((← read (project / "docs/candidates/prepared-bindings/resumed/trial/frozen-before-delivery.json")).getArr?)
  let some frozen := frozenEntries[0]? | throw (IO.userError "missing frozen first question")
  check (frozen.getObjValD "topic" == toJson (1 : Nat) &&
    (frozen.getObjValD "specification").getObjValD "files" == toJson originalFiles) "original source changed"
  let root := armPath arm
  let database := root / "work.egg"
  let binary := root / "prefix/libexec/eggshell"
  let saved := records / arm
  IO.FS.createDirAll saved
  if mode == "prepare" then
    check (rest.isEmpty && !(← root.pathExists)) "fresh isolated source arm required"
    let manifest := study / "r0/stage1/history/history.json"
    let _ ← StudyHistory.fork ⟨manifest.toString,← ArtifactHash.hex manifest⟩ root
    check ((← StudyRuntime.files database) == originalFiles) "fork changed original source bytes"
    let source ← DB.PageMap.pin database
    let numerical := database / "derived" / source.head.identity / "semantic"
    IO.FS.createDirAll numerical.parent.get!
    let copied ← IO.Process.output {cmd := "/bin/cp",args := #["-cR",
      (study / "study/seed-2/work.egg/derived" / source.head.identity / "semantic").toString,numerical.toString]}
    check (copied.exitCode == 0) "cannot reuse unchanged numerical preparation"
    let refinement ← read (study / "shared-snapshot/anchored-capture/seed-refinement.json")
    check (refinement.getObjValD "source" == toJson source.head) "supplements crossed frozen source"
    let entries : Array (Nat × String × ContentCapture.Supplement) ← IO.ofExcept (refinement.getObjValAs? _ "supplements")
    let reader ← Persistence.Store.NodeReader.new source
    let mut supplements := #[]
    for (id,owner,value) in entries do
      check ((← Build.document reader id).owner == owner) "supplement crossed frozen owner"
      if value.sealed then supplements := supplements.push (id,value)
    let prepared ← Build.refresh source .database supplements
    IO.FS.writeFile (saved / "prepared-source.json") ((toJson prepared).setObjVal! "preparerGeneration" (toJson expected.generation)).pretty
    install arm
    check ((← ArtifactHash.hex binary) == expected.sha256) "installed arm runtime changed"
    let publisher ← StudyRuntime.startPublisher binary (root / "data") (environment arm true) (expectedRuntime := some expected)
    try
      let warmed ← StudyCommand.run binary.toString #["egg","warm","work"] (environment arm true) workspace "" (saved / "warm") 240000
      check (warmed.exitCode == 0) "matched arm warm failed"
    finally StudyRuntime.stopManaged publisher (saved / "prepare-shutdown.json")
    check ((← StudyRuntime.files database) == originalFiles && (← StudyRuntime.files original) == originalFiles) "preparation changed original source"
    IO.FS.writeFile (saved / "ready.json") (Json.mkObj [("sourceFiles",toJson originalFiles),
      ("arm",toJson arm),("runtime",toJson expected),("frozen",frozen)]).pretty
    return
  check (mode == "run") "unknown arm action"
  let [repetition] := rest | throw (IO.userError "fixed fresh-session repetition required")
  check (["0","1"].contains repetition) "predeclared two repetitions only"
  let ready ← read (saved / "ready.json")
  check (ready.getObjValD "sourceFiles" == toJson originalFiles && (← StudyRuntime.files database) == originalFiles)
    "actual hook source differs from the ready original"
  let destination := saved / ("rep-" ++ repetition)
  check (!(← destination.pathExists)) "preserve previous actual hook"
  IO.FS.createDirAll destination
  let prompt ← IO.FS.readFile (study / "prompts/topic-1.txt")
  check ((frozen.getObjValD "specification").getObjValD "prompt" == toJson prompt) "fixed question changed"
  let env := environment arm false
  let session := "owner-bindings-" ++ arm ++ "-" ++ repetition
  let publisher ← StudyRuntime.startPublisher binary (root / "data") env (expectedRuntime := some expected)
  try
    let daemon ← StudyRuntime.startManaged binary (root / "prefix/share/eggshell/codex-plugin") session
      (root / "data/sessions" / session / "daemon.json") env
    try
      for event in ["SessionStart","UserPromptSubmit"] do
        let request := Json.mkObj ([("hook_event_name",toJson event),("session_id",toJson session),
          ("turn_id",toJson "owner-bindings-turn"),("cwd",toJson workspace),
          ("_eggshell_config",toJson (root / "readonly.toml").toString)] ++
          if event == "UserPromptSubmit" then [("prompt",toJson prompt)] else [])
        let response ← StudyCommand.run binary.toString #["codex-hook"] env workspace
          (request.compress ++ "\n") (destination / event) 35000
        check (response.exitCode == 0) "actual matched hook failed"
        if event == "UserPromptSubmit" then
          let reply ← IO.ofExcept (Json.parse response.stdout)
          let body ← IO.ofExcept ((reply.getObjValD "hookSpecificOutput").getObjValAs? String "additionalContext")
          IO.FS.writeFile (destination / "body.txt") body
          let sha := Sha256.hex body.toUTF8
          let audit ← NativeTrialAudit.replayAvailable (frozen.getObjValD "specification") (destination / "body.txt").toString sha
          check (audit.getObjValD "availableEvidence" == frozen.getObjValD "available") "actual audit changed frozen denominator"
          IO.FS.writeFile (destination / "audit.json") audit.pretty
          IO.FS.writeFile (destination / "result.json") (Json.mkObj [("arm",toJson arm),
            ("repetition",toJson repetition),("elapsedMs",toJson response.elapsedMs),("bodySha256",toJson sha),
            ("availableDelivery",audit.getObjValD "availableDelivery"),("answeringModelCalls",toJson (0 : Nat)),
            ("adopted",toJson false)]).pretty
    finally StudyRuntime.stopManaged daemon (destination / "shutdown.json")
  finally StudyRuntime.stopManaged publisher (destination / "publisher-shutdown.json")
  check ((← StudyRuntime.files database) == originalFiles && (← StudyRuntime.files original) == originalFiles)
    "actual hooks changed original source bytes"
