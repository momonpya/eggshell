import tools.research.StudyRuntime
import tools.research.StudyCommand
import tools.research.StudyHistory
import tools.research.NativeTrialAudit
import Eggshell.Install
import tools.research.CheckedOriginalFixtures
import tools.research.FrozenCanonicalBasis
open Lean Eggshell Eggshell.Research Eggshell.Synapses

private def study : System.FilePath := "/Users/ovm/.codex/experiments/eggshell/scope-token-study-20261028"
private def project : System.FilePath := "/Users/ovm/.codex/worktrees/hook-deadline-baseline/eggshell"
private def records := project / "docs/candidates/source-plan/hooks"
private def read (p : System.FilePath) : IO Json := IO.FS.readFile p >>= fun s => IO.ofExcept (Json.parse s)
private def check (ok : Bool) (message : String) : IO Unit := unless ok do throw (IO.userError message)

private def runtimePath (arm : String) : System.FilePath := study / "shared-snapshot" /
  (if arm == "baseline" then "owner-palette-runtime-build" else "source-plan-runtime-build") / "StudyMain"
private def helperPath (arm : String) : System.FilePath := study / "shared-snapshot" /
  ("source-plan-hook-" ++ arm ++ "-build") / "StudyMain"
private def armPath (arm : String) : System.FilePath := study / "shared-snapshot/source-plan-trial" / arm

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

private def sourcePlanSuite : IO Unit := do
  let evidence := project / "docs/candidates/source-plan"
  check (!(← (evidence / "result.json").pathExists)) "preserve source-plan suite results"
  let original := study / "r0/stage1/history/source.egg"
  let before ← StudyRuntime.files original
  let mut stages := #[]
  let run (arm stage : String) (args : Array String) : IO Unit := do
    let result ← IO.Process.output {
      cmd := (helperPath arm).toString
      args := args
      env := #[("LEAN_NUM_THREADS",some "1")]}
    IO.FS.writeFile (evidence / (stage ++ "-exit.json")) (Json.mkObj [
      ("exitCode",toJson result.exitCode.toNat),("stdout",toJson result.stdout),
      ("stderr",toJson result.stderr)]).pretty
    check (result.exitCode == 0) (stage ++ " failed: " ++ result.stderr)
  for arm in ["baseline","candidate"] do
    for (kind,directory) in [("runtime",(runtimePath arm).parent.get!),
        ("helper",(helperPath arm).parent.get!)] do
      let checked ← IO.Process.output {
        cmd := "/Users/ovm/.elan/toolchains/leanprover--lean4---v4.33.0/bin/lean"
        args := #["-M3072","--run",(project / "tools/research/StudyBuildClosureAudit.lean").toString,
          "inspect",directory.toString,(evidence / (arm ++ "-" ++ kind ++ "-native-closure.json")).toString]}
      check (checked.exitCode == 0) "source-plan native closure mismatch"
    let helperDeps ← read ((helperPath arm).parent.get! / "tools_research_SourcePlanHook.dependencies")
    let runtimeDeps ← read ((runtimePath arm).parent.get! / "Main.dependencies")
    let actual : Array (String × String) ← IO.ofExcept (fromJson? helperDeps)
    let expected : Array (String × String) ← IO.ofExcept (fromJson? runtimeDeps)
    let expected := Std.HashMap.ofArray expected
    for (name,stamp) in actual do
      if let some wanted := expected[name]? then check (stamp == wanted) ("helper/runtime mismatch: " ++ name)
    run arm (arm ++ "-describe") #["describe",arm]
    run arm (arm ++ "-prepare") #["prepare",arm]
  run "candidate" "candidate-independent-audit" #["audit","candidate","0","1"]
  let receipts := armPath "candidate" / "data/receipts"
  let mut exactAudits := #[]
  for entry in ← receipts.readDir do
    let path := entry.path / "selection-plan.json"
    if !(← path.pathExists) then continue
    let audit := ((← read path).getObjValD "data").getObjValD "jointBindings" |>.getObjValD "sourceDomainAudit"
    if audit == Json.null then continue
    check (["problemExact","rowsExact","scopesExact"].all (fun key => audit.getObjValD key == toJson true))
      "source-plan differs from the independent reference construction"
    exactAudits := exactAudits.push audit
  check (!exactAudits.isEmpty) "source-plan exact audit was vacuous"
  IO.FS.writeFile (evidence / "exact-construction.json") (toJson exactAudits).pretty
  for topic in [1,2,3] do
    for repetition in [0,1] do
      for arm in ["baseline","candidate"] do
        run arm s!"{arm}-topic-{topic}-rep-{repetition}" #["run",arm,toString repetition,toString topic]
      let location := fun arm => records / arm / s!"rep-{repetition}" / s!"topic-{topic}"
      let baseline ← read (location "baseline" / "result.json")
      let candidate ← read (location "candidate" / "result.json")
      let same := (← IO.FS.readFile (location "baseline" / "body.txt")) ==
        (← IO.FS.readFile (location "candidate" / "body.txt"))
      let sameEvidence := baseline.getObjValD "availableDelivery" == candidate.getObjValD "availableDelivery"
      let baselineMs ← IO.ofExcept (baseline.getObjValAs? Nat "elapsedMs")
      let candidateMs ← IO.ofExcept (candidate.getObjValAs? Nat "elapsedMs")
      stages := stages.push (Json.mkObj [("topic",toJson topic),("repetition",toJson repetition),
        ("baselineMs",toJson baselineMs),("candidateMs",toJson candidateMs),
        ("sameBody",toJson same),("sameFrozenEvidence",toJson sameEvidence),
        ("availableDelivery",candidate.getObjValD "availableDelivery")])
      IO.FS.writeFile (evidence / "progress.json") (toJson stages).pretty
      check (same && sameEvidence) "source-plan changed actual body or frozen evidence"
      check (baselineMs < 30000 && candidateMs < 30000) "source-plan hook deadline exceeded"
      IO.println (stages.back!).compress
  check ((← StudyRuntime.files original) == before) "source-plan study changed source snapshot"
  IO.FS.writeFile (evidence / "result.json") (Json.mkObj [
    ("pairs",toJson stages),("exactConstructionAudits",toJson exactAudits),
    ("ordinaryActualHooks",toJson (12 : Nat)),("independentAuditHooks",toJson (1 : Nat)),
    ("answeringModelCalls",toJson (0 : Nat)),("newSeeds",toJson (0 : Nat)),
    ("sourceUnchanged",toJson true),("adopted",toJson false),
    ("fullOriginalTransferStillPresent",toJson true),("sharedStaticPlanConnected",toJson false),
    ("sustained80PersonWorkloadVerified",toJson false)]).pretty


def main (args : List String) : IO Unit := do
  if args == ["suite"] then
    sourcePlanSuite
    return
  let mode :: arm :: rest := args | throw (IO.userError "describe/prepare/run baseline/candidate [repetition]")
  let audit := mode == "audit"
  let mode := if audit then "run" else mode
  check (["baseline","candidate"].contains arm) "unknown matched arm"
  check ((← IO.appPath).normalize == (helperPath arm).normalize) "the wrong arm's producer was invoked"
  IO.FS.createDirAll records
  let descriptor := records / (arm ++ "-runtime.json")
  if mode == "describe" then
    CheckedOriginalFixtures.verify
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
  let topic ← if mode == "run" then do
    let [_,value] := rest | throw (IO.userError "repetition and topic required")
    let some topic := value.toNat? | throw (IO.userError "invalid topic")
    check ([1,2,3].contains topic) "outside the declared three topics"
    pure topic
  else pure 1
  let some frozen := frozenEntries[topic-1]? | throw (IO.userError "missing frozen first question")
  check (frozen.getObjValD "topic" == toJson topic &&
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
  let [repetition,_topicText] := rest | throw (IO.userError "fixed fresh-session repetition required")
  check (["0","1"].contains repetition) "predeclared two repetitions only"
  let ready ← read (saved / "ready.json")
  check (ready.getObjValD "sourceFiles" == toJson originalFiles && (← StudyRuntime.files database) == originalFiles)
    "actual hook source differs from the ready original"
  let destination := saved / (if audit then "audit" else "rep-" ++ repetition) / s!"topic-{topic}"
  check (!(← destination.pathExists)) "preserve previous actual hook"
  IO.FS.createDirAll destination
  let prompt ← IO.FS.readFile (study / s!"prompts/topic-{topic}.txt")
  check ((frozen.getObjValD "specification").getObjValD "prompt" == toJson prompt) "fixed question changed"
  let env := (environment arm false).map fun (name,value) =>
    (name,if audit && name == "EGGSHELL_TRACE_SELECTOR_INPUT" then some "1" else value)
  let session := "source-plan-" ++ arm ++ (if audit then "-audit-" else "-") ++ repetition ++ "-" ++ toString topic
  let publisher ← StudyRuntime.startPublisher binary (root / "data") env (expectedRuntime := some expected)
  try
    let daemon ← StudyRuntime.startManaged binary (root / "prefix/share/eggshell/codex-plugin") session
      (root / "data/sessions" / session / "daemon.json") env
    try
      for event in ["SessionStart","UserPromptSubmit"] do
        let request := Json.mkObj ([("hook_event_name",toJson event),("session_id",toJson session),
          ("turn_id",toJson "source-plan-turn"),("cwd",toJson workspace),
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
          let (pinned,originalRows) ← FrozenCanonicalBasis.load study (study / "shared-snapshot")
          let nodeReader ← Persistence.Store.NodeReader.new pinned
          let documents ← (← Build.entries pinned).mapM fun entry => Build.document nodeReader entry.id
          let aliases : Array Read := originalRows.flatMap fun row => row.origins.map fun origin =>
            ⟨origin.occurrence,⟨row.key.file,row.key.line,row.key.line⟩,origin.binding,#[]⟩
          let originals := documents.flatMap fun doc => (Extraction.recordedRows pinned.head.identity doc).toOption.getD #[]
          let shown := Extraction.presented body documents (aliases ++ originals)
          let ranges := (Extraction.compactRanges shown.ranges).qsort fun a b => (toJson a).compress < (toJson b).compress
          let bindings := shown.bindings.toList.eraseDups.toArray.qsort fun a b => (toJson a).compress < (toJson b).compress
          IO.FS.writeFile (destination / "original-presentation.json") (Json.mkObj [
            ("ranges",toJson ranges),("bindings",toJson bindings)]).compress
          IO.FS.writeFile (destination / "result.json") (Json.mkObj [("arm",toJson arm),
            ("repetition",toJson repetition),("elapsedMs",toJson response.elapsedMs),("bodySha256",toJson sha),
            ("availableDelivery",audit.getObjValD "availableDelivery"),("answeringModelCalls",toJson (0 : Nat)),
            ("adopted",toJson false),("sourceAuditRequested",toJson audit)]).pretty
    finally StudyRuntime.stopManaged daemon (destination / "shutdown.json")
  finally StudyRuntime.stopManaged publisher (destination / "publisher-shutdown.json")
  check ((← StudyRuntime.files database) == originalFiles && (← StudyRuntime.files original) == originalFiles)
    "actual hooks changed original source bytes"
