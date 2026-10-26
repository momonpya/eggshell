import tools.research.StudySeedChecks
import Eggshell.Install
import tools.research.StudyWorkerProbe
open Lean Eggshell Eggshell.Research

private def check (valid : Bool) (message : String) : IO Unit :=
  unless valid do throw (IO.userError message)
private def read (path : System.FilePath) : IO Json := do
  IO.ofExcept (Json.parse (← IO.FS.readFile path))
private def save (path : System.FilePath) (value : Json) : IO Unit := IO.FS.writeFile path value.pretty

/-- Fixed old seed, three original questions, no answering turn. Frozen
requirements are audit-only and never enter the hook's inputs. -/
def main (args : List String) : IO UInt32 := do
  try
    let (candidate,destination,resume,probe,topics) ← match args with
      | [candidate,destination] => pure (candidate,destination,false,false,[1,2,3])
      | [candidate,destination,"resume"] => pure (candidate,destination,true,false,[1,2,3])
      | [candidate,destination,"worker"] => pure (candidate,destination,false,true,[2])
      | [candidate,destination,"topic",number] =>
        let some topic := number.toNat? | throw (IO.userError "numeric topic required")
        unless [1,2,3].contains topic do throw (IO.userError "unknown fixed diagnostic topic")
        pure (candidate,destination,false,false,[topic])
      | _ => throw (IO.userError "SynapticSourceHookAudit CANDIDATE DIRECTORY [resume|worker|topic NUMBER]")
    let root := System.FilePath.mk destination
    check (root.isAbsolute && (← root.pathExists) == resume) "new trial or explicit unfinished-trial resume required"
    if !resume then IO.FS.createDir root
    check (!(← (root / "results.json").pathExists) && !(← (root / "topic-1").pathExists)) "keep existing hook attempts"
    let study := System.FilePath.mk "/Users/ovm/.codex/experiments/eggshell/study-services-20261026"
    let definitionsBytes ← IO.FS.readBinFile (study / "task-definitions.json")
    check (Sha256.hex definitionsBytes == "e2f6b683c2d761734da43793eadf2a8be363f9d356124d3830fd4ab85538c9cf")
      "frozen question definitions changed"
    let oldAudit ← read (study / "seed-1-complete-audit.json")
    check ((oldAudit.getObjValAs? Bool "seedAccepted").toOption == some true) "source seed was not accepted"
    let definitions ← IO.ofExcept (Json.parse (← IO.FS.readFile (study / "task-definitions.json")) >>= Json.getArr?)
    let availability ← IO.ofExcept (oldAudit.getObjValAs? (Array Json) "availability")
    let database := root / "work.egg"
    let sourceFiles ← if resume then StudyRuntime.files database
      else StudyRuntime.checkpoint (study / "common-seed-1/source.egg") database
    check (sourceFiles == (← StudyRuntime.files (study / "common-seed-1/source.egg"))) "source checkpoint bytes changed"
    let original ← DB.PageMap.pin database
    check (original.head.identity == "76352b67a9c35002bff67dc3d3c3a01b7bd194e43e09f5f54714dde75df5a8de" &&
      original.head.revision == 31 && original.head.bytes == 45216846) "wrong original checkpoint"
    if resume then check ((← read (root / "frozen-before-delivery.json")) == toJson availability) "frozen requirements changed"
    else save (root / "frozen-before-delivery.json") (toJson availability)
    let installRoot := root / "prefix"
    let binary := installRoot / "libexec/eggshell"
    if !resume then
      IO.FS.createDirAll binary.parent.get!
      let copied ← IO.Process.output {cmd := "/bin/cp",args := #["-c",candidate ++ "/product-build/StudyMain",binary.toString]}
      check (copied.exitCode == 0) "could not select candidate product"
    let runtimeSha ← ArtifactHash.hex binary
    check (runtimeSha == (← ArtifactHash.hex (.mk (candidate ++ "/product-build/StudyMain")))) "resume product differs"
    let plugin := installRoot / "share/eggshell/codex-plugin"
    let launcher := plugin / "bin/eggshelld"
    if !resume then
      IO.FS.createDirAll launcher.parent.get!
      IO.FS.writeFile launcher (Install.pluginLauncher installRoot)
      IO.setAccessRights launcher {
        user := {read := true,write := true,execution := true}
        group := {read := true,execution := true}
        other := {read := true,execution := true} }
      let link ← IO.Process.output {cmd := "/bin/ln",args := #["-s",
        "/Users/ovm/.codex/experiments/eggshell/numerical-owned-20261024/prefix/share/eggshell/minilm",
        (installRoot / "share/eggshell/minilm").toString]}
      check (link.exitCode == 0) "could not select existing numerical boundary"
    let data := root / "data"
    if !resume then IO.FS.createDir data
    let workspace := "/Users/ovm/Code/eggshell-benchmarks/aamas-2027/sources/llvm-project"
    let configuration := root / "config.toml"
    let expectedConfig := "default = \"work\"\nsemantic_matcher = " ++
      (toJson #[binary.toString,"search-provider"]).compress ++ "\n[eggs]\nwork = " ++
      (toJson database.toString).compress ++ "\n[profiles.work]\nread = [\"work\"]\nhandoff_chars = 120000\n"
    if resume then check ((← IO.FS.readFile configuration) == expectedConfig) "resume config differs"
    else IO.FS.writeFile configuration expectedConfig
    let environment := #[
      ("EGGSHELL_PREFIX",some installRoot.toString),("EGGSHELL_DATA_ROOT",some data.toString),
      ("EGGSHELL_CONFIG",some configuration.toString),("EGGSHELL_PROFILE",some "work"),
      ("PLUGIN_ROOT",some plugin.toString),("CODEX_THREAD_ID",none),("CODEX_TURN_ID",none),
      ("LEAN_NUM_THREADS",some "1"),("OMP_NUM_THREADS",some "1"),("OPENBLAS_NUM_THREADS",some "1"),
      ("MKL_NUM_THREADS",some "1"),("HF_HUB_OFFLINE",some "1"),("TOKENIZERS_PARALLELISM",some "false")]
    -- Static, read-only preparation needs no publisher child. Own the data
    -- service only for actual hooks, after the same frozen source is ready.
    if resume then
      let guard ← read (.mk candidate / "isolated-warm-profile.guard.json")
      check ((guard.getObjValAs? String "state").toOption == some "finished" &&
        (guard.getObjValAs? Nat "exitCode").toOption == some 0 &&
        (guard.getObjValAs? Bool "guardTriggered").toOption == some false &&
        (guard.getObjValAs? (Array Nat) "ownedPids").toOption == some #[]) "isolated warm is not finished successfully"
      let report ← read (.mk candidate / "isolated-warm-profile.stdout")
      let databases ← IO.ofExcept (report.getObjValAs? (Array Json) "databases")
      check (databases.size == 1 && databases.all (fun entry =>
        ((entry.getObjValD "after").getObjValAs? Nat "missing").toOption == some 0 &&
        ((entry.getObjValD "after").getObjValAs? Nat "invalid").toOption == some 0)) "recovered warm is incomplete"
      save (root / "warm-complete.json") (Json.mkObj [("runtimeSha256",toJson runtimeSha),
        ("elapsedMs",guard.getObjValD "elapsedMs"),("recoveredAfterRssStop",toJson true),
        ("warmTimingDiagnosticOnly",toJson true)])
    else
      IO.println "fixed-source warm starting"
      (← IO.getStdout).flush
      let warm ← StudyCommand.run binary.toString #["egg","warm","work"] environment workspace "" (root / "warm") 300000
      check (warm.exitCode == 0) s!"fixed source warm failed: {warm.stderr}"
      save (root / "warm-complete.json") (Json.mkObj [("runtimeSha256",toJson runtimeSha),("elapsedMs",toJson warm.elapsedMs),
        ("publisherStartedAfterWarm",toJson true)])
    let publisher ← StudyRuntime.startPublisher binary data environment resume
    let mut results := #[]
    try
      for topic in topics do
        let some definition := definitions.find? (fun row => (row.getObjValAs? Nat "topic").toOption == some topic) |
          throw (IO.userError "missing question definition")
        let some frozen := availability.find? (fun row => (row.getObjValAs? Nat "topic").toOption == some topic) |
          throw (IO.userError "missing frozen evidence")
        let stage := root / s!"topic-{topic}"
        IO.FS.createDir stage
        let promptPath ← IO.ofExcept ((definition.getObjValD "prompt").getObjValAs? String "path")
        let prompt ← IO.FS.readFile (.mk promptPath)
        let expected ← IO.ofExcept ((definition.getObjValD "prompt").getObjValAs? String "sha256")
        check (Sha256.hex prompt.toUTF8 == expected) "fixed question changed"
        let session := s!"atomic-topology-source-{topic}"
        let managed ← StudyRuntime.startManaged binary plugin session (data / "sessions" / session / "daemon.json") environment
        try
          if probe then
            let output ← StudyWorkerProbe.run binary database data session workspace prompt environment (stage / "worker")
            check (output.exitCode == 0) "diagnostic worker failed"
            let some line := (output.stdout.splitOn "\n" |>.filter (!·.isEmpty)).getLast? |
              throw (IO.userError "diagnostic worker did not return a reply")
            let frame ← IO.ofExcept (Json.parse line >>= fromJson? (α := Plugin.Worker.SearchFrame))
            let .reply _ handoff := frame | throw (IO.userError "diagnostic worker returned progress only")
            let metadata := output.stderr.splitOn "\n" |>.filter (·.startsWith "EGGSHELL_SELECTOR_")
            save (stage / "probe.json") (Json.mkObj [("topic",toJson topic),("elapsedMs",toJson output.elapsedMs),
              ("deadlineMs",toJson (120000 : Nat)),("diagnosticOnly",toJson true),("actualHook",toJson false),
              ("latencyAcceptance",toJson false),("handoffPresent",toJson handoff.isSome),
              ("bodyChars",toJson (handoff.map (·.text.length))),
              ("selectorObservations",toJson metadata),("runtimeSha256",toJson runtimeSha)])
            for observation in metadata do IO.println observation
            results := results.push (← read (stage / "probe.json"))
            continue
          let request := Json.mkObj [("hook_event_name",toJson "UserPromptSubmit"),("session_id",toJson session),
            ("turn_id",toJson "source-turn"),("cwd",toJson workspace),("prompt",toJson prompt),
            ("_eggshell_config",toJson configuration.toString)]
          let hook := stage / "hook"
          let output ← StudyCommand.run binary.toString #["codex-hook"] environment workspace
            (request.compress ++ "\n") hook 35000
          check (output.exitCode == 0 && output.elapsedMs < 30000) s!"topic {topic} hook failed or expired"
          let reply ← IO.ofExcept (Json.parse output.stdout)
          let body := ((reply.getObjValD "hookSpecificOutput").getObjValAs? String "additionalContext").toOption.getD ""
          IO.FS.writeFile (stage / "body.txt") body
          let specification := Json.mkObj [("source",toJson database.toString),("workspace",toJson workspace),
            ("prompt",toJson prompt),("files",toJson sourceFiles),("required",definition.getObjValD "referenceRanges")]
          let input := Json.mkObj [("source",specification),("database",toJson database.toString),
            ("request",toJson (hook / "stdin").toString),("stdout",toJson (hook / "stdout").toString),
            ("timing",toJson (hook / "record.json").toString),("body",toJson (stage / "body.txt").toString)]
          save (stage / "audit-input.json") input
          let audited ← NativeTrialAudit.inspect (stage / "audit-input.json").toString
          check (audited.getObjValD "frozenEvidence" == frozen.getObjValD "frozenEvidence")
            "fixed evidence denominator changed"
          save (stage / "audit.json") audited
          let summary := Json.mkObj [("topic",toJson topic),("elapsedMs",toJson output.elapsedMs),
            ("requiredDelivery",audited.getObjValD "requiredDelivery"),("runtimeSha256",toJson runtimeSha)]
          results := results.push summary
          IO.println summary.compress
          (← IO.getStdout).flush
        finally StudyRuntime.stopManaged managed (stage / "shutdown.json")
    finally StudyRuntime.stopManaged publisher (root / "publisher-shutdown.json")
    check ((← DB.PageMap.pin database).head == original.head && (← StudyRuntime.files database) == sourceFiles)
      "actual hooks or warm changed the original checkpoint"
    save (root / "results.json") (Json.mkObj [("topics",toJson results),("diagnosticOnly",toJson probe),
      ("requestedTopics",toJson topics),("singleTopicDiagnostic",toJson (topics.length == 1 && !probe)),
      ("answeringModelCalls",toJson (0 : Nat)),
      ("answeringStages",toJson (0 : Nat)),("newSeedStudy",toJson false),("productionAdoption",toJson false)])
    return 0
  catch error => IO.eprintln error.toString; return 1
