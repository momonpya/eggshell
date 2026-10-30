import tools.research.StudyRuntime
import tools.research.StudyCommand
import tools.research.StudyHistory
import tools.research.NativeTrialAudit
import Eggshell.Install
import Eggshell.SynapseJournal
open Lean Eggshell Eggshell.Research Eggshell.Synapses

private def check (condition : Bool) (message : String) : IO Unit :=
  unless condition do throw (IO.userError message)
private def read (path : System.FilePath) : IO Json :=
  IO.FS.readFile path >>= fun text => IO.ofExcept (Json.parse text)

private def install (runtime target models : System.FilePath) : IO (System.FilePath × System.FilePath) := do
  let binary := target / "libexec/eggshell"
  IO.FS.createDirAll binary.parent.get!
  let copied ← IO.Process.output {cmd := "/bin/cp",args := #["-c",runtime.toString,binary.toString]}
  check (copied.exitCode == 0) "cannot install selected measured runtime"
  let plugin := target / "share/eggshell/codex-plugin"
  IO.FS.createDirAll (plugin / "bin")
  for name in ["egg","eggshelld"] do
    let path := plugin / "bin" / name
    IO.FS.writeFile path (Install.pluginLauncher target)
    IO.setAccessRights path {
      user := {read := true,write := true,execution := true}
      group := {read := true,execution := true}
      other := {read := true,execution := true}}
  let linked ← IO.Process.output {cmd := "/bin/ln",args := #["-s",models.toString,(target / "share/eggshell/minilm").toString]}
  check (linked.exitCode == 0) "cannot share the existing numerical boundary"
  return (binary,plugin)

private def configuration (binary database : System.FilePath) (writable : Bool) : String :=
  "default = \"work\"\nsemantic_matcher = " ++ (toJson #[binary.toString,"search-provider"]).compress ++
  "\n[eggs]\nwork = " ++ (toJson database.toString).compress ++
  "\n[profiles.work]\nread = [\"work\"]\n" ++ (if writable then "write = \"work\"\n" else "") ++
  "handoff_chars = 120000\n"

private def profileReuse : IO Unit := do
  let study : System.FilePath := "/Users/ovm/.codex/experiments/eggshell/scope-token-study-20261028"
  let arm := study / "shared-snapshot/source-service-profile/baseline"
  let saved : System.FilePath := "/Users/ovm/.codex/worktrees/hook-deadline-baseline/eggshell/docs/candidates/source-service-profile/reuse"
  check ((← (arm / "readonly.toml").pathExists) && !(← saved.pathExists)) "reuse only the prepared measured source fixture"
  IO.FS.createDirAll saved
  let binary := arm / "prefix/libexec/eggshell"
  check ((← ArtifactHash.hex binary) == "d11c80efad039aeb6669c87b914e42f129aded1e40bef46881e75adec078ff53")
    "cache reuse diagnosis must retain the identical runtime"
  let plugin := arm / "prefix/share/eggshell/codex-plugin"
  let config := arm / "readonly.toml"
  let data := arm / "data"
  let env := #[("CODEX_HOME",some (study / "account").toString),("TMPDIR",some (study / "tmp").toString),
    ("EGGSHELL_PREFIX",some (arm / "prefix").toString),("EGGSHELL_DATA_ROOT",some data.toString),
    ("EGGSHELL_CONFIG",some config.toString),("EGGSHELL_PROFILE",some "work"),("PLUGIN_ROOT",some plugin.toString),
    ("CODEX_THREAD_ID",none),("CODEX_TURN_ID",none),("LEAN_NUM_THREADS",some "1"),
    ("OMP_NUM_THREADS",some "1"),("OPENBLAS_NUM_THREADS",some "1"),("MKL_NUM_THREADS",some "1"),
    ("HF_HUB_OFFLINE",some "1"),("TOKENIZERS_PARALLELISM",some "false")]
  let before ← StudyRuntime.files (arm / "work.egg")
  let workspace := "/Users/ovm/Code/eggshell-benchmarks/aamas-2027/sources/llvm-project"
  let prompt ← IO.FS.readFile (study / "prompts/topic-2.txt")
  let expected ← IO.FS.readFile (saved.parent.get! / "trial/baseline/rep-0/topic-2/body.txt")
  let publisher ← StudyRuntime.startPublisher binary data env
  let mut results := #[]
  try
    let endpoint ← IO.ofExcept (fromJson? (α := Plugin.Daemon.Endpoint) (← read (data / "publisher/endpoint.json")))
    let stats := do IO.ofExcept (Json.parse (← Plugin.Daemon.exchange endpoint "stats" (budget := 1000)))
    IO.FS.writeFile (saved / "service-before.json") (← stats).pretty
    for repetition in [0:2] do
      let session := s!"source-cache-reuse-{repetition}"
      let out := saved / s!"rep-{repetition}"
      IO.FS.createDir out
      let managed ← StudyRuntime.startManaged binary plugin session (data / "sessions" / session / "daemon.json") env
      try
        for event in ["SessionStart","UserPromptSubmit"] do
          let request := Json.mkObj ([("hook_event_name",toJson event),("session_id",toJson session),
            ("turn_id",toJson "reuse-turn"),("cwd",toJson workspace),("_eggshell_config",toJson config.toString)] ++
            if event == "UserPromptSubmit" then [("prompt",toJson prompt)] else [])
          let response ← StudyCommand.run binary.toString #["codex-hook"] env workspace (request.compress ++ "\n") (out / event) 35000
          check (response.exitCode == 0) "cache reuse actual hook failed"
          if event == "UserPromptSubmit" then
            let value ← IO.ofExcept (Json.parse response.stdout)
            let body ← IO.ofExcept ((value.getObjValD "hookSpecificOutput").getObjValAs? String "additionalContext")
            IO.FS.writeFile (out / "body.txt") body
            check (body == expected) "cache reuse changed the actual delivered body"
            let measured ← stats
            IO.FS.writeFile (out / "service-after.json") measured.pretty
            results := results.push (Json.mkObj [("repetition",toJson repetition),("elapsedMs",toJson response.elapsedMs),
              ("bodyUnchanged",toJson true),("bodySha256",toJson (Sha256.hex body.toUTF8)),("service",measured)])
      finally StudyRuntime.stopManaged managed (out / "shutdown.json")
  finally StudyRuntime.stopManaged publisher (saved / "publisher-shutdown.json")
  check ((← StudyRuntime.files (arm / "work.egg")) == before) "cache reuse changed the source"
  let receipts := saved / "receipts"
  IO.FS.createDir receipts
  for receipt in ← (data / "receipts").readDir do
    let request := (← read (receipt.path / "request.json")).getObjValD "data"
    unless ((request.getObjValAs? String "session").toOption.getD "").startsWith "source-cache-reuse-" do continue
    IO.FS.createDir (receipts / receipt.fileName)
    for entry in ← receipt.path.readDir do
      if entry.fileName.endsWith ".json" then IO.FS.writeFile (receipts / receipt.fileName / entry.fileName) (← IO.FS.readFile entry.path)
  IO.FS.writeFile (saved / "result.json") (Json.mkObj [("results",Json.arr results),
    ("originalSourceUnchanged",toJson true),("answeringModelCalls",toJson (0 : Nat)),
    ("warmCalls",toJson (0 : Nat)),("adopted",toJson false)]).pretty

def main (args : List String) : IO Unit := do
  if args == ["reuse-service"] then return ← profileReuse
  let profileService := args == ["profile-service"]
  let bindingsCache := args == ["bindings-cache"]
  let blockCache := args == ["block-cache"] || bindingsCache
  check (args.isEmpty || profileService || blockCache) "explicit paired cache trial or unchanged-service profile required"
  let study : System.FilePath := "/Users/ovm/.codex/experiments/eggshell/scope-token-study-20261028"
  let label := if bindingsCache then "prepared-bindings-trial" else
    if blockCache then "service-block-cache-trial" else if profileService then "source-service-profile" else "prepared-original-keys-trial"
  let root := study / "shared-snapshot" / label
  let candidates : System.FilePath := "/Users/ovm/.codex/worktrees/hook-deadline-baseline/eggshell/docs/candidates"
  let records := candidates / (if bindingsCache then "prepared-bindings" else
    if blockCache then "service-block-cache" else if profileService then "source-service-profile" else "prepared-original-keys") / "trial"
  check (!(← root.pathExists) && !(← records.pathExists)) "fresh paired key-reuse trial required"
  IO.FS.createDirAll root
  IO.FS.createDirAll records
  let manifest := study / "r0/stage1/history/history.json"
  let manifestHash ← ArtifactHash.hex manifest
  let common := study / "r0/stage1/history/source.egg"
  let original ← StudyRuntime.files common
  let pinned ← DB.PageMap.pin common
  let workspace : System.FilePath := "/Users/ovm/Code/eggshell-benchmarks/aamas-2027/sources/llvm-project"
  let definitions ← IO.ofExcept ((← read (study / "task-definitions.json")).getArr?)
  let previous : Array Json ← IO.ofExcept ((← read (records.parent.get!.parent.get! / "query-cache-llvm/records/frozen-before-delivery.json")).getArr?)
  let mut questions : Array (Nat × String × Json × AvailableDelivery.Frozen) := #[]
  for topic in (if profileService then [2] else [1,2,3]) do
    let some definition := definitions.find? (fun row => (row.getObjValAs? Nat "topic").toOption == some topic) |
      throw (IO.userError "fixed topic definition missing")
    let prompt ← IO.FS.readFile (study / "prompts" / s!"topic-{topic}.txt")
    check ((definition.getObjValD "prompt").getObjValD "sha256" == toJson (Sha256.hex prompt.toUTF8)) "fixed prompt changed"
    let spec := Json.mkObj [("source",toJson common.toString),("workspace",toJson workspace.toString),
      ("prompt",toJson prompt),("files",toJson original),("required",definition.getObjValD "referenceRanges")]
    let frozen ← NativeTrialAudit.freezeAvailable spec
    let some old := previous.find? (fun row => row.getObjValD "topic" == toJson topic) |
      throw (IO.userError "prior frozen obligation missing")
    check (old.getObjValD "available" == toJson frozen) "frozen DB-present obligations drifted"
    questions := questions.push (topic,prompt,spec,frozen)
  IO.FS.writeFile (records / "frozen-before-delivery.json") (toJson (questions.map fun (topic,_,spec,available) =>
    Json.mkObj [("topic",toJson topic),("specification",spec),("available",toJson available)])).pretty
  let sourcePreparers ← if bindingsCache then read (records.parent.get! / "source-preparers.json") else pure Json.null
  IO.FS.writeFile (records / "protocol.json") (Json.mkObj [
    ("repetitions",toJson (if profileService then 1 else (2 : Nat))),
    ("topics",toJson (questions.map fun (topic,_,_,_) => topic)),("allFreshSessions",toJson true),
    ("armOrder",toJson (if profileService then #[#["baseline"]] else #[#["baseline","candidate"],#["candidate","baseline"]])),
    ("diagnosticServiceProfile",toJson profileService),
    ("sameHistoryManifestSha256",toJson manifestHash),("source",toJson pinned.head),
    ("sourcePreparers",sourcePreparers),
    ("answeringModelCalls",toJson (0 : Nat)),("tokenComparison",toJson false),("adopted",toJson false)]).pretty
  let derivation ← read (study / "shared-snapshot/anchored-capture/seed-refinement.json")
  check (derivation.getObjValD "source" == toJson pinned.head) "coordinate supplement changed source"
  let additions : Array (Nat × String × ContentCapture.Supplement) ← IO.ofExcept (derivation.getObjValAs? _ "supplements")
  let environment := fun (arm installation plugin config : System.FilePath) => #[
    ("CODEX_HOME",some (study / "account").toString),("TMPDIR",some (study / "tmp").toString),
    ("EGGSHELL_PREFIX",some installation.toString),("EGGSHELL_DATA_ROOT",some (arm / "data").toString),
    ("EGGSHELL_CONFIG",some config.toString),("EGGSHELL_PROFILE",some "work"),("PLUGIN_ROOT",some plugin.toString),
    ("CODEX_THREAD_ID",none),("CODEX_TURN_ID",none),("LEAN_NUM_THREADS",some "1"),
    ("OMP_NUM_THREADS",some "1"),("OPENBLAS_NUM_THREADS",some "1"),("MKL_NUM_THREADS",some "1"),
    ("HF_HUB_OFFLINE",some "1"),("TOKENIZERS_PARALLELISM",some "false")] ++
    if profileService then #[("EGGSHELL_HANDOFF_TRACE",some (records / "handoff.trace").toString)] else #[]
  let mut arms := #[]
  let definitions := [("baseline","query-cache-baseline-build"),
    ("candidate",if bindingsCache then "prepared-bindings-build" else
      if blockCache then "service-block-cache-build" else "prepared-original-keys-build")]
  for (name,runtime) in (if profileService then definitions.take 1 else definitions) do
    let arm := root / name
    let _ ← StudyHistory.fork ⟨manifest.toString,manifestHash⟩ arm
    let database := arm / "work.egg"
    check ((← StudyRuntime.files database) == original) "arm fork changed source bytes"
    let runtimeDescriptor ←
      if blockCache then do
        let descriptors ← IO.ofExcept ((← read (records.parent.get! / "runtime-descriptors.json")).getArr?)
        let some record := descriptors.find? (fun row => row.getObjValD "arm" == toJson name) |
          throw (IO.userError "frozen publisher runtime descriptor missing")
        let declared ← IO.ofExcept (fromJson? (α := StudyRuntime.PublisherRuntime) (record.getObjValD "runtime"))
        check (declared.binary == (study / "shared-snapshot" / runtime / "StudyMain").toString) "runtime descriptor crossed its arm"
        pure (some declared)
      else pure none
    let preparedSource := if blockCache && !bindingsCache then study / "shared-snapshot/source-service-profile/baseline/work.egg/derived"
      else study / "study/seed-2/work.egg/derived"
    let copied ← IO.Process.output {cmd := "/bin/cp",args := #["-cR",preparedSource.toString,
      (database / "derived").toString]}
    check (copied.exitCode == 0) "cannot retain existing immutable vector preparation"
    let destination := records / name
    IO.FS.createDirAll destination
    if bindingsCache then
      let rows ← IO.ofExcept ((← read (records.parent.get! / "source-preparers.json")).getArr?)
      let some row := rows.find? (fun row => row.getObjValD "arm" == toJson name) |
        throw (IO.userError "source preparer for this arm was not frozen")
      let descriptor := row.getObjValD "preparer"
      let program ← IO.ofExcept (descriptor.getObjValAs? String "binary")
      check (program == (study / "shared-snapshot" / ("source-prepare-" ++ name ++ "-build/StudyMain")).toString &&
        descriptor.getObjValD "sha256" == toJson (← ArtifactHash.hex (.mk program))) "source preparer crossed its audited arm"
      let output := destination / "prepared-source.json"
      let response ← StudyCommand.run program #[database.toString,
        (study / "shared-snapshot/anchored-capture/seed-refinement.json").toString,output.toString]
        #[("EGGSHELL_DATA_ROOT",some (arm / "data").toString),("LEAN_NUM_THREADS",some "1")]
        workspace.toString "" (destination / "prepare") 240000
      check (response.exitCode == 0) "the arm's own source preparer failed"
      let some expected := runtimeDescriptor | throw (IO.userError "source preparer has no frozen runtime contract")
      check ((← read output).getObjValD "preparerGeneration" == toJson expected.generation)
        "source preparation and runtime used different producer implementations"
    else
      let source ← DB.PageMap.pin database
      let reader ← Persistence.Store.NodeReader.new source
      let mut supplements := #[]
      for (id,owner,supplement) in additions do
        check ((← Build.document reader id).owner == owner) "supplement crossed source owners"
        if supplement.sealed then supplements := supplements.push (id,supplement)
      let prepared ← Build.refresh source .database supplements
      IO.FS.writeFile (destination / "prepared-source.json") (toJson prepared).pretty
    let installation := arm / "prefix"
    let (binary,plugin) ← install (study / "shared-snapshot" / runtime / "StudyMain") installation (study / "prefix/share/eggshell/minilm")
    let writeConfig := arm / "prepare.toml"
    let config := arm / "readonly.toml"
    IO.FS.writeFile writeConfig (configuration binary database true)
    IO.FS.writeFile config (configuration binary database false)
    let env := environment arm installation plugin writeConfig
    let publisher ← StudyRuntime.startPublisher binary (arm / "data") env (expectedRuntime := runtimeDescriptor)
    try
      let warmed ← StudyCommand.run binary.toString #["egg","warm","work"] env workspace.toString "" (destination / "warm") 240000
      check (warmed.exitCode == 0) "paired arm preparation failed"
    finally StudyRuntime.stopManaged publisher (destination / "prepare-shutdown.json")
    arms := arms.push (name,arm,binary,plugin,installation,config,runtimeDescriptor)
  let mut results := #[]
  let mut bodies : Std.HashMap Nat String := {}
  if profileService then
    bodies := bodies.insert 2 (← IO.FS.readFile (candidates / "prepared-original-keys/trial/baseline/rep-0/topic-2/body.txt"))
  for repetition in [0:(if profileService then 1 else 2)] do
    let order := if repetition == 0 then arms else arms.reverse
    for (name,arm,binary,plugin,installation,config,runtimeDescriptor) in order do
      let env := environment arm installation plugin config
      let publisher ← StudyRuntime.startPublisher binary (arm / "data") env (expectedRuntime := runtimeDescriptor)
      let destination := records / name / s!"rep-{repetition}"
      IO.FS.createDirAll destination
      try
        if blockCache then
          let endpoint ← IO.ofExcept (fromJson? (α := Plugin.Daemon.Endpoint) (← read (arm / "data/publisher/endpoint.json")))
          IO.FS.writeFile (destination / "service-before.json")
            (← IO.ofExcept (Json.parse (← Plugin.Daemon.exchange endpoint "stats" (budget := 1000)))).pretty
        for (topic,prompt,spec,frozen) in questions do
          let out := destination / s!"topic-{topic}"
          IO.FS.createDir out
          let session := s!"keys-{name}-{repetition}-{topic}"
          let managed ← StudyRuntime.startManaged binary plugin session (arm / "data/sessions" / session / "daemon.json") env
          try
            for event in ["SessionStart","UserPromptSubmit"] do
              let request := Json.mkObj ([("hook_event_name",toJson event),("session_id",toJson session),
                ("turn_id",toJson "paired-turn"),("cwd",toJson workspace.toString),("_eggshell_config",toJson config.toString)] ++
                if event == "UserPromptSubmit" then [("prompt",toJson prompt)] else [])
              let run := StudyCommand.run binary.toString #["codex-hook"] env workspace.toString (request.compress ++ "\n") (out / event) 35000
              let response ← if profileService && event == "UserPromptSubmit" then do
                  IO.FS.writeFile (records / "handoff.trace") ""
                  let pending ← IO.asTask run .dedicated
                  let limit := (← IO.monoMsNow)+20000
                  repeat
                    let trace ← try IO.FS.readFile (records / "handoff.trace") catch _ => pure ""
                    if trace.contains "source focus" then break
                    check (!(← IO.hasFinished pending) && (← IO.monoMsNow) < limit) "hook did not reach the post-focus boundary"
                    IO.sleep 25
                  let endpoint ← IO.ofExcept (fromJson? (α := Plugin.Daemon.Endpoint) (← read (arm / "data/publisher/endpoint.json")))
                  check (endpoint.session == "publisher" && (← Numerical.alive endpoint.pid)) "owned source service is not live"
                  for phase in ["bindings","projection"] do
                    let sample ← IO.Process.output {cmd := "/usr/bin/sample",args := #[toString endpoint.pid,"3","2",
                      "-file",(records / (phase ++ ".sample.txt")).toString]}
                    IO.FS.writeFile (records / (phase ++ "-sample.json")) (Json.mkObj [
                      ("pid",toJson endpoint.pid),("exitCode",toJson sample.exitCode.toNat),
                      ("stdout",toJson sample.stdout),("stderr",toJson sample.stderr)]).pretty
                    check (sample.exitCode == 0) "source-service CPU sampling failed"
                  IO.ofExcept pending.get
                else run
              check (response.exitCode == 0) "paired actual hook failed"
              if event == "UserPromptSubmit" then
                let reply ← IO.ofExcept (Json.parse response.stdout)
                let body := ((reply.getObjValD "hookSpecificOutput").getObjValAs? String "additionalContext").toOption.getD ""
                IO.FS.writeFile (out / "body.txt") body
                if blockCache then
                  let endpoint ← IO.ofExcept (fromJson? (α := Plugin.Daemon.Endpoint) (← read (arm / "data/publisher/endpoint.json")))
                  IO.FS.writeFile (out / "service-after.json")
                    (← IO.ofExcept (Json.parse (← Plugin.Daemon.exchange endpoint "stats" (budget := 1000)))).pretty
                let same := (bodies[topic]?).all (· == body)
                if !bodies.contains topic then bodies := bodies.insert topic body
                let input := Json.mkObj [("source",spec),("database",toJson (arm / "work.egg").toString),
                  ("request",toJson (out / event / "stdin").toString),("stdout",toJson (out / event / "stdout").toString),
                  ("timing",toJson (out / event / "record.json").toString),("body",toJson (out / "body.txt").toString)]
                IO.FS.writeFile (out / "audit-input.json") input.pretty
                let audit ← NativeTrialAudit.inspect (out / "audit-input.json").toString
                check (audit.getObjValD "availableEvidence" == toJson frozen) "paired delivery changed frozen denominator"
                IO.FS.writeFile (out / "audit.json") audit.pretty
                results := results.push (Json.mkObj [("arm",toJson name),("repetition",toJson repetition),
                  ("topic",toJson topic),("runtimeSha256",toJson (← ArtifactHash.hex binary)),
                  ("elapsedMs",toJson response.elapsedMs),("bodyUnchanged",toJson same),
                  ("bodySha256",toJson (Sha256.hex body.toUTF8)),("availableDelivery",audit.getObjValD "availableDelivery")])
                IO.FS.writeFile (records / "progress.json") (Json.arr results).pretty
          finally StudyRuntime.stopManaged managed (out / "shutdown.json")
      finally StudyRuntime.stopManaged publisher (destination / "publisher-shutdown.json")
  for (_,arm,_,_,_,_,_) in arms do
    check ((← StudyRuntime.files (arm / "work.egg")) == original) "paired source changed during actual hooks"
    let saved := records / arm.fileName.get! / "receipts"
    IO.FS.createDir saved
    for receipt in ← (arm / "data/receipts").readDir do
      IO.FS.createDir (saved / receipt.fileName)
      for entry in ← receipt.path.readDir do
        if entry.fileName.endsWith ".json" then IO.FS.writeFile (saved / receipt.fileName / entry.fileName) (← IO.FS.readFile entry.path)
  check ((← StudyRuntime.files common) == original) "common immutable source changed"
  IO.FS.writeFile (records / "result.json") (Json.mkObj [("results",Json.arr results),
    ("diagnosticServiceProfile",toJson profileService),
    ("originalSourcesUnchanged",toJson true),("allBodiesUnchanged",toJson (results.all fun row => row.getObjValD "bodyUnchanged" == toJson true)),
    ("answeringModelCalls",toJson (0 : Nat)),("tokenImprovementMeasured",toJson false),("adopted",toJson false)]).pretty
