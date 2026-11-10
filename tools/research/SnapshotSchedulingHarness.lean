import tools.research.MemoryCapacity
import tools.research.StudyHistory
import tools.research.StudyReadiness
import tools.research.NativeTrialAudit

open Lean Eggshell Eggshell.Plugin
namespace Eggshell.Research.SnapshotSchedulingHarness

structure Input where
  workload : MemoryCapacity.Input
  history : StudyAdmission.Artifact
  definitions : StudyAdmission.Artifact
  deriving FromJson

private def check (value : Bool) (message : String) : IO Unit :=
  unless value do throw (IO.userError message)

private def read (path : System.FilePath) : IO Json := StudyAdmission.readJson path.toString
private def save (path : System.FilePath) (value : Json) : IO Unit := IO.FS.writeFile path value.compress

private def profiles (data : System.FilePath) : IO (Array Json) := do
  let mut rows := #[]
  for entry in ← (data/"receipts").readDir do
    for stage in #["source-plan-profile","source-bindings-profile","source-views-profile","server-envelope-profile"] do
      let file := entry.path/(stage++".json")
      if ← file.pathExists then rows := rows.push (← read file)
  return rows

/-- Capture normal product output before defining the performance reference.
The separately frozen originals enter only the post-delivery auditor. -/
def run (path digest : String) : IO Unit := do
  StudyAdmission.verifyArtifact ⟨path,digest⟩
  let input ← IO.ofExcept (fromJson? (α := Input) (← read (.mk path)))
  let work := input.workload
  let root : System.FilePath := .mk work.output
  check (!(← root.pathExists) && work.topics.map (·.topic) == #[1,2,3] &&
    work.counts == #[4] && work.diagnostic && work.handoffChars == 500000)
    "one fresh three-topic/four-client diagnosis required"
  check (work.config == (root/"config.toml").toString &&
    work.project == (root.parent.get!/"work/work.egg").toString &&
    work.data == (root.parent.get!/"work/data").toString) "owned workload paths changed"
  check ((← MemoryCapacity.hash (.mk work.runtime)) == work.runtimeSha256 &&
    (← IO.getEnv "EGGSHELL_DATA_ROOT") == some work.data &&
    (← IO.getEnv "LEAN_NUM_THREADS").isNone) "runtime, private root or scheduler profile changed"
  StudyAdmission.verifyArtifact input.definitions
  let definitions ← IO.ofExcept (fromJson? (α := Array Json) (← read (.mk input.definitions.path)))
  check (definitions.map (fun row => row.getObjValD "topic") == (#[1,2,3] : Array Nat).map toJson)
    "three frozen task definitions required"
  let snapshot ← StudyHistory.fork input.history (System.FilePath.mk work.project).parent.get!
  check (snapshot.sourceFiles == work.sourceFiles) "fork changed the original publication"
  IO.FS.createDir root
  IO.FS.writeFile (.mk work.config) (StudyProfile.render work.runtime work.project
    (← IO.ofExcept (StudyProfile.checked work.handoffChars)) false)
  let replayPublisher ← StudyRuntime.startPublisher (.mk work.runtime) (.mk work.data) work.environment
  try
    discard <| StudyReadiness.finishJournal work.runtime (.mk work.project) work.environment work.workspace (root/"replay")
  finally StudyRuntime.stopManaged replayPublisher (root/"replay-publisher-shutdown.json")
  let publisher ← StudyRuntime.startPublisher (.mk work.runtime) (.mk work.data) work.environment
  try
    let warm ← StudyCommand.run work.runtime #["egg","warm","work"] work.environment work.workspace "" (root/"warm") 240000
    check (warm.exitCode == 0) "explicit source warm failed"
    discard <| StudyReadiness.warm warm (.mk work.project)
    check ((← StudyRuntime.files (.mk work.project)) == work.sourceFiles) "warm changed the source publication"
    let mut sources := #[]
    let mut frozen := #[]
    for position in [:3] do
      let definition := definitions[position]!
      let some topic := work.topics[position]? | throw (IO.userError "declared topic absent")
      let prompt : StudyAdmission.Artifact ← IO.ofExcept (definition.getObjVal? "prompt" >>= fromJson?)
      StudyAdmission.verifyArtifact prompt
      check ((← IO.FS.readFile (.mk prompt.path)) == topic.prompt) "question changed"
      let source := Json.mkObj [("source",toJson work.project),("workspace",toJson work.workspace),
        ("prompt",toJson topic.prompt),("files",toJson work.sourceFiles),
        ("required",definition.getObjValD "referenceRanges")]
      sources := sources.push source
      frozen := frozen.push (← NativeTrialAudit.freezeAvailable source)
    save (root/"frozen-available.json") (toJson frozen)
    let managed ← StudyRuntime.startManaged (.mk work.runtime) (.mk work.plugin) "snapshot-scheduling"
      (System.FilePath.mk work.data/"daemon.json") work.environment
    try
      let mut topics := #[]
      let mut confirmations := #[]
      for position in [:3] do
        let some topic := work.topics[position]? | throw (IO.userError "declared topic absent")
        let some frozenTopic := frozen[position]? | throw (IO.userError "frozen availability absent")
        let call := root/s!"topic-{topic.topic}"
        IO.FS.createDir call
        let session := "scheduling-baseline-"++Sha256.hex s!"{root}:{topic.topic}".toUTF8
        let mut body := ""
        for event in #["SessionStart","UserPromptSubmit"] do
          let request := MemoryCapacity.request work session event topic.prompt
          let result ← StudyCommand.run work.runtime #["codex-hook"] work.environment work.workspace
            (request.compress++"\n") (call/event) 35000
          check (result.exitCode == 0 && result.elapsedMs < 30000) "baseline product hook failed or expired"
          if event == "UserPromptSubmit" then
            let value ← IO.ofExcept (Json.parse result.stdout)
            body ← IO.ofExcept ((value.getObjValD "hookSpecificOutput").getObjValAs? String "additionalContext")
        let bodyPath := call/"body.txt"
        IO.FS.writeFile bodyPath body
        let hook := call/"UserPromptSubmit"
        let spec := Json.mkObj [("source",sources[position]!),("database",toJson work.project),
          ("request",toJson (hook/"stdin").toString),("stdout",toJson (hook/"stdout").toString),
          ("timing",toJson (hook/"record.json").toString),("body",toJson bodyPath.toString)]
        save (call/"audit-input.json") spec
        let audit ← NativeTrialAudit.inspect (call/"audit-input.json").toString
        check (audit.getObjValD "availableEvidence" == toJson frozenTopic &&
          (audit.getObjValD "availableDelivery").getObjValD "targetMet" == toJson true)
          "baseline lost frozen DB-present originals"
        save (call/"audit.json") audit
        let available ← IO.ofExcept ((audit.getObjValD "availableDelivery").getObjValAs? Nat "delivered")
        let reference := {topic with body := bodyPath.toString,sha256 := Sha256.hex body.toUTF8,available}
        topics := topics.push (⟨reference,body⟩ : MemoryCapacity.Expected)
        let confirmRoot := root/"confirm"
        IO.FS.createDirAll confirmRoot
        let confirm ← MemoryCapacity.client work ⟨reference,body⟩ confirmRoot 0 position
        let summary ← MemoryCapacity.receiptSummary work confirm
        check (confirm.getObjValD "success" == toJson true &&
          ((summary.getObjValD "search").getObjValD "trace").getObjValD "semantic" == toJson "completed" &&
          (summary.getObjValD "synapse").getObjValD "complete" == toJson true)
          "independent chat changed the actual semantic/synaptic body or ACK"
        confirmations := confirmations.push (Json.mkObj [("client",confirm),("receiptSummary",summary)])
        save (root/"confirmations.json") (toJson confirmations)
      let started ← IO.monoMsNow
      let sampleCommand : IO.Process.SpawnArgs := {
        cmd := "/usr/bin/sample"
        args := #[toString (StudyRuntime.pid publisher),"3","5","-file",(root/"publisher.sample.txt").toString] }
      let sampler ← IO.asTask (IO.Process.output sampleCommand) .dedicated
      let phase ← try MemoryCapacity.phase work topics 4 finally
        let sample ← IO.ofExcept (← IO.wait sampler)
        save (root/"sampling.json") (Json.mkObj [("pid",toJson (StudyRuntime.pid publisher)),
          ("exitCode",toJson sample.exitCode.toNat),("stdout",toJson sample.stdout),("stderr",toJson sample.stderr),
          ("diagnosticInterferencePossible",toJson true),("wholeHookCpuPercentages",toJson false)])
        check (sample.exitCode == 0) "owned publisher sampling failed"
      let finished ← IO.monoMsNow
      save (root/"phase-window.json") (Json.mkObj [("startedMs",toJson started),("finishedMs",toJson finished)])
      let service ← profiles (.mk work.data)
      save (root/"service-profiles.json") (toJson service)
      let clients ← IO.ofExcept (phase.getObjValAs? (Array Json) "rows")
      let mut stages := #[]
      for client in clients do
        let id ← IO.ofExcept (client.getObjValAs? String "receipt")
        let record ← read (System.FilePath.mk work.data/"receipts"/id/"request-pages.json")
        stages := stages.push (Json.mkObj [("client",client.getObjValD "client"),("receipt",toJson id),
          ("stages",record.getObjValD "data")])
      save (root/"actor-stages.json") (toJson stages)
      check (phase.getObjValD "passed" == toJson true &&
        (← StudyRuntime.files (.mk work.project)) == work.sourceFiles) "diagnostic changed bodies, search, synapses, ACK or source"
      save (root/"report.json") (Json.mkObj [("runtimeSha256",toJson work.runtimeSha256),
        ("diagnosticOnly",toJson true),("phase",phase),("referenceTopics",toJson (topics.map (·.topic.topic))),
        ("answeringModelCalls",toJson (0 : Nat)),("sourcePublicationUnchanged",toJson true),
        ("serviceProfileCount",toJson service.size),("concurrentServiceRequestAttribution",toJson false),
        ("sixteenClientTargetEstablished",toJson false),("adopted",toJson false)])
    finally StudyRuntime.stopManaged managed (root/"frontend-shutdown.json")
  finally StudyRuntime.stopManaged publisher (root/"publisher-shutdown.json")

end Eggshell.Research.SnapshotSchedulingHarness
