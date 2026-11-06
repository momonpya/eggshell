import tools.research.StudyRuntime
import tools.research.StudyAdmission
import tools.research.StudyCommand
import tools.research.StudySource
import tools.research.StudyProfile
import tools.research.NativeTrialAudit
import tools.research.StudyWarm
import Eggshell.Install

open Lean Eggshell Eggshell.Research

namespace RealDeliveryProbe

structure Topic where
  topic : Nat
  prompt : StudyAdmission.Artifact
  required : Array OriginalEvidence.Reference
  deriving ToJson,FromJson

structure Input where
  runtime : StudyAdmission.Artifact
  source : String
  workspace : String
  output : String
  pluginRoot : String
  environment : Array (String × Option String)
  handoffChars : Nat
  repetitions : Nat
  topics : Array Topic
  deriving ToJson,FromJson

private def check (ok : Bool) (message : String) : IO Unit :=
  unless ok do throw (IO.userError message)

private def json (path : System.FilePath) : IO Json := do
  IO.ofExcept (Json.parse (← IO.FS.readFile path))
private def save (path : System.FilePath) (value : Json) : IO Unit := IO.FS.writeFile path value.pretty

structure LayoutInput where
  source : String
  sourceFiles : Array (String × String)
  owners : Array String
  reference : OriginalEvidence.Reference
  output : String
  deriving FromJson

/-- Reproduce publication-time units directly from immutable originals.
Reference ranges restrict diagnostics only; they never enter recommendation. -/
private def layout (input : LayoutInput) : IO Unit := do
  let path : System.FilePath := .mk input.source
  check (!(← (System.FilePath.mk input.output).pathExists)) "keep the previous layout diagnostic"
  check ((← StudyRuntime.files path) == input.sourceFiles) "layout source bytes changed"
  let source ← DB.PageMap.pin path
  let reader ← Persistence.Store.NodeReader.new source
  let inReference := fun row : Synapses.CanonicalSource.StoredRow =>
    row.key.file.relative == input.reference.path && input.reference.first ≤ row.key.line &&
      row.key.line ≤ input.reference.last
  let mut owners := #[]
  let mut wanted := input.owners.toList.eraseDups
  -- Public Value identities are not physical node addresses. Resolve them
  -- from this publication's original directory, without trusting an index.
  for entry in ← Synapses.Build.entries source do
    let id := entry.id
    let doc ← Synapses.Build.document reader id
    if !wanted.contains doc.owner then continue
    wanted := wanted.erase doc.owner
    let (registry,statistics) ← Synapses.CanonicalSource.addPublishedDocument source id doc {} {}
    let stored ← IO.ofExcept (Synapses.CanonicalSource.Recipe.compile registry.store)
    let checked ← IO.ofExcept (Synapses.CanonicalSource.Recipe.check stored.rows stored.records)
    let view := Synapses.PreparedSourceView.ownerStored doc.owner stored checked
    let coordinate := fun index : Nat => (stored.rows[index]?).map fun row =>
      (row.key.file.relative,row.key.line)
    let touching := stored.records.filter fun entry =>
      (entry.indices ++ [entry.after]).any fun index => (stored.rows[index]?).any inReference
    let units := checked.catalogue.filter fun unit => unit.any (fun index => inReference stored.rows[index])
    let groups := (view.records.filter fun unit => unit.any fun index =>
      (stored.rows[index]?).any inReference).map (fun unit => unit.map coordinate)
    let neighbors := stored.rows.filter fun row => row.key.file.relative == input.reference.path &&
      input.reference.first-1 ≤ row.key.line && row.key.line ≤ input.reference.last+1
    owners := owners.push (Json.mkObj [("owner",toJson doc.owner),("statistics",toJson statistics),
      ("rows",toJson stored.rows.size),("referenceRows",toJson (stored.rows.filter inReference)),
      ("neighborRows",toJson (neighbors.map fun row => (row.key.line,row.code))),
      ("records",toJson (touching.map fun entry => Json.mkObj [
        ("indices",toJson (entry.indices.map coordinate)),("before",toJson (entry.before.bind coordinate)),
        ("after",toJson (coordinate entry.after))])),
      ("catalogue",toJson (units.map (fun unit => unit.map (coordinate ∘ Fin.val)))),
      ("preparedGroups",toJson groups)])
  check wanted.isEmpty "layout owner is absent from the pinned original directory"
  check ((← StudyRuntime.files path) == input.sourceFiles) "layout diagnostic modified its original source"
  save (.mk input.output) (Json.mkObj [("source",toJson source.head),
    ("reference",toJson input.reference),("owners",toJson owners),
    ("answeringModelCalls",toJson (0 : Nat)),("embeddingCalls",toJson (0 : Nat)),
    ("sourceUnchanged",toJson true),("hookMeasured",toJson false)])

private def specification (input : Input) (topic : Topic) : IO Json := do
  let common := System.FilePath.mk input.output / "source.egg"
  return Json.mkObj [("source",toJson common.toString),("workspace",toJson input.workspace),
    ("files",toJson (← StudyRuntime.files common)),("prompt",toJson (← IO.FS.readFile (.mk topic.prompt.path))),
    ("required",toJson topic.required)]

private def freeze (input : Input) (inputPath : System.FilePath) : IO Unit := do
  let root : System.FilePath := .mk input.output
  check (root.isAbsolute && !(← root.pathExists) && input.repetitions == 2 && input.topics.size == 3)
    "new diagnostic root, three topics and two independent native chats required"
  StudyAdmission.verifyArtifact input.runtime
  for topic in input.topics do StudyAdmission.verifyArtifact topic.prompt
  IO.FS.createDir root
  let ancestry ← StudySource.verify (.mk input.source)
  let files ← StudyRuntime.checkpoint (.mk input.source) (root / "source.egg")
  StudyRuntime.restore (root / "source.egg") (root / "work.egg")
  let budget ← IO.ofExcept (StudyProfile.checked input.handoffChars)
  IO.FS.writeFile (root / "config.toml") (StudyProfile.render input.runtime.path (root / "work.egg").toString budget false)
  IO.FS.createDir (root / "data")
  IO.FS.createDir (root / "tmp")
  let mut denominators := #[]
  for topic in input.topics do
    let spec ← specification input topic
    let frozen ← NativeTrialAudit.freezeAvailable spec
    save (root / s!"topic-{topic.topic}-source.json") spec
    save (root / s!"topic-{topic.topic}-frozen.json") (toJson frozen)
    denominators := denominators.push (Json.mkObj [("topic",toJson topic.topic),
      ("eligible",toJson frozen.units.size),("absent",toJson frozen.absent),
      ("partial",toJson (frozen.units.flatMap (·.partialNames)))])
  save (root / "sealed.json") (Json.mkObj [("inputSha256",toJson (← ArtifactHash.hex inputPath)),
    ("sourceFiles",toJson files),("ancestry",toJson ancestry),("denominators",toJson denominators),
    ("answeringModelCalls",toJson (0 : Nat)),("acceptedSeed",toJson false),
    ("paidComparison",toJson false),("deliveryBodiesRead",toJson false)])

private def snapshots (root : System.FilePath) : IO (Array String) := do
  if !(← root.pathExists) then return #[]
  return (← root.readDir).map (·.fileName)

private def receipt (root : System.FilePath) (before : Array String) (stdout : String) : IO Json := do
  let mut found := #[]
  for id in ← snapshots root do
    if before.contains id then continue
    let path := root / id
    if !(← (path / "published.json").pathExists) then continue
    let publication := (← json (path / "published.json")).getObjValD "data"
    check (publication.getObjValD "output" == toJson stdout &&
      publication.getObjValD "sha256" == toJson (Sha256.hex stdout.toUTF8)) "actual stdout differs from publication receipt"
    let mut stages := #[]
    for file in ← path.readDir do
      if !file.fileName.endsWith ".json" || file.fileName == "published.json" then continue
      stages := stages.push (Json.mkObj [("name",toJson file.fileName),("record",← json file.path)])
    found := found.push (Json.mkObj [("id",toJson id),("stages",toJson stages),
      ("stdoutSha256",publication.getObjValD "sha256"),("bytes",publication.getObjValD "bytes")])
  check (found.size == 1) "native hook did not yield exactly one publication receipt"
  return found[0]!

private def run (input : Input) (inputPath : System.FilePath) : IO Unit := do
  let root : System.FilePath := .mk input.output
  let sealed ← json (root / "sealed.json")
  check (sealed.getObjValD "inputSha256" == toJson (← ArtifactHash.hex inputPath)) "sealed diagnostic input changed"
  StudyAdmission.verifyArtifact input.runtime
  check (!(← (root / "warm").pathExists)) "this diagnostic was already started; keep its result"
  let environment := input.environment.filter (fun row =>
    !["EGGSHELL_CONFIG","EGGSHELL_PROFILE","EGGSHELL_DATA_ROOT","TMPDIR","CODEX_THREAD_ID","CODEX_TURN_ID"].contains row.1) ++
    #[("EGGSHELL_CONFIG",some (root / "config.toml").toString),("EGGSHELL_PROFILE",some "work"),
      ("EGGSHELL_DATA_ROOT",some (root / "data").toString),("TMPDIR",some (root / "tmp").toString),
      ("CODEX_THREAD_ID",none),("CODEX_TURN_ID",none)]
  let publisher ← StudyRuntime.startPublisher (.mk input.runtime.path) (root / "data") environment
  try
    let warm ← StudyCommand.run input.runtime.path #["egg","warm","work"] environment input.workspace "" (root / "warm") 240000
    check (warm.exitCode == 0) s!"explicit real-source warm failed: {warm.stderr}"
    let current ← DB.PageMap.pin (root/"work.egg")
    let prepared ← IO.ofExcept (StudyWarm.decode warm.stdout #[(root/"work.egg").toString] #[current.head]
      MiniLM.model SearchProvider.encoderContract)
    save (root/"warm-admission.json") (toJson prepared.frame)
    let repeated ← StudyCommand.run input.runtime.path #["egg","warm","work"] environment input.workspace "" (root / "repeat-warm") 240000
    check (repeated.exitCode == 0) "repeat real-source warm failed"
    let repeatedRows ← IO.ofExcept (StudyWarm.decode repeated.stdout #[(root/"work.egg").toString] #[current.head]
      MiniLM.model SearchProvider.encoderContract true)
    check (toJson prepared.frame.inputs == toJson repeatedRows.frame.inputs)
      "unchanged repeat warm changed its prepared public inputs"
    let mut results := #[]
    for topic in input.topics do
      let spec ← json (root / s!"topic-{topic.topic}-source.json")
      let frozen ← json (root / s!"topic-{topic.topic}-frozen.json")
      for repetition in [:input.repetitions] do
        let cell := root / s!"topic-{topic.topic}-chat-{repetition}"
        IO.FS.createDir cell
        let session := s!"real-topic-{topic.topic}-chat-{repetition}"
        let endpoint := root / "data/daemon.json"
        let managed ← StudyRuntime.startManaged (.mk input.runtime.path) (.mk input.pluginRoot) session endpoint environment
        try
          let fields := [("session_id",toJson session),("turn_id",toJson "first"),
            ("cwd",toJson input.workspace),("_eggshell_config",toJson (root / "config.toml").toString)]
          let start := Json.mkObj (fields ++ [("hook_event_name",toJson "SessionStart")])
          let started ← StudyCommand.run input.runtime.path #["codex-hook"] environment input.workspace
            (start.compress ++ "\n") (cell / "SessionStart") 35000
          check (started.exitCode == 0) "native SessionStart failed"
          let receiptRoot := root / "data/receipts"
          let before ← snapshots receiptRoot
          let request := Json.mkObj (fields ++ [("hook_event_name",toJson "UserPromptSubmit"),
            ("prompt",spec.getObjValD "prompt")])
          let hook ← StudyCommand.run input.runtime.path #["codex-hook"] environment input.workspace
            (request.compress ++ "\n") (cell / "hook") 35000
          let reply ← IO.ofExcept (Json.parse hook.stdout)
          let body := (reply.getObjVal? "hookSpecificOutput" >>= (·.getObjValAs? String "additionalContext")).toOption.getD ""
          IO.FS.writeFile (cell / "body.txt") body
          save (cell / "receipt.json") (← receipt receiptRoot before hook.stdout)
          let auditInput := Json.mkObj [("source",spec),("database",toJson (root / "work.egg").toString),
            ("request",toJson (cell / "hook/stdin").toString),("stdout",toJson (cell / "hook/stdout").toString),
            ("timing",toJson (cell / "hook/record.json").toString),("body",toJson (cell / "body.txt").toString)]
          save (cell / "audit-input.json") auditInput
          let report ← NativeTrialAudit.inspect (cell / "audit-input.json").toString
          check (report.getObjValD "availableEvidence" == frozen) "delivery changed the frozen denominator"
          save (cell / "audit.json") report
          results := results.push (Json.mkObj [("topic",toJson topic.topic),("repetition",toJson repetition),
            ("elapsedMs",toJson hook.elapsedMs),("bodyCharacters",toJson body.length),
            ("bodySha256",toJson (Sha256.hex body.toUTF8)),
            ("requiredDelivery",report.getObjValD "requiredDelivery"),
            ("availableDelivery",report.getObjValD "availableDelivery")])
          save (root / "progress.json") (toJson results)
          check ((report.getObjValD "availableDelivery").getObjValD "targetMet" == toJson true)
            "frozen real-source delivery missed the target; stop before another topic"
        finally StudyRuntime.stopManaged managed (cell / "shutdown.json")
    check ((← StudyRuntime.files (root / "source.egg")) == (← StudyRuntime.files (root / "work.egg")))
      "readonly diagnostics changed the original database"
    save (root / "result.json") (Json.mkObj [("cells",toJson results),("source",sealed),
      ("answeringModelCalls",toJson (0 : Nat)),("acceptedSeed",toJson false),
      ("firstCycleAndSecondCycleModelTrials",toJson false)])
  finally
    StudyRuntime.stopManaged publisher (root / "publisher-shutdown.json")

structure Probe where
  originalInput : StudyAdmission.Artifact
  runtime : StudyAdmission.Artifact
  pluginRoot : String
  topic : Nat
  destination : String
  deriving FromJson

/-- One instrumented transport diagnosis, sharing only the already prepared
project source. It is not a retry of the six-cell acceptance study. -/
private def diagnose (probe : Probe) : IO Unit := do
  StudyAdmission.verifyArtifact probe.originalInput
  StudyAdmission.verifyArtifact probe.runtime
  let input ← IO.ofExcept (fromJson? (← json (.mk probe.originalInput.path)) : Except String Input)
  let root : System.FilePath := .mk input.output
  let sealed ← json (root/"sealed.json")
  check (sealed.getObjValD "inputSha256" == toJson probe.originalInput.sha256)
    "diagnosis changed the original frozen input"
  let some topic := input.topics.find? (·.topic == probe.topic) | throw (IO.userError "unknown diagnostic topic")
  let cell : System.FilePath := .mk probe.destination
  check (cell.isAbsolute && !(← cell.pathExists)) "fresh diagnostic destination required"
  IO.FS.createDirAll cell
  let config := cell/"config.toml"
  IO.FS.writeFile config (StudyProfile.render probe.runtime.path (root/"work.egg").toString
    (← IO.ofExcept (StudyProfile.checked input.handoffChars)) false)
  let environment := input.environment.filter (fun row => !["EGGSHELL_CONFIG","EGGSHELL_PROFILE",
      "EGGSHELL_DATA_ROOT","TMPDIR","CODEX_THREAD_ID","CODEX_TURN_ID","EGGSHELL_PREFIX","PLUGIN_ROOT",
      "EGGSHELL_RESEARCH_REPLY_FOOTPRINT"].contains row.1) ++ #[
    ("EGGSHELL_CONFIG",some config.toString),("EGGSHELL_PROFILE",some "work"),
    ("EGGSHELL_DATA_ROOT",some (root/"data").toString),("TMPDIR",some (root/"tmp").toString),
    ("CODEX_THREAD_ID",none),("CODEX_TURN_ID",none),
    ("EGGSHELL_PREFIX",some (System.FilePath.mk probe.runtime.path).parent.get!.parent.get!.toString),
    ("PLUGIN_ROOT",some probe.pluginRoot),("EGGSHELL_RESEARCH_REPLY_FOOTPRINT",some "1")]
  let sourceFiles ← StudyRuntime.files (root/"work.egg")
  check (toJson sourceFiles == sealed.getObjValD "sourceFiles") "diagnostic original changed before admission"
  let publisher ← StudyRuntime.startPublisher (.mk probe.runtime.path) (root/"data") environment
  try
    let warmed ← StudyCommand.run probe.runtime.path #["egg","warm","work"] environment input.workspace "" (cell/"warm") 240000
    check (warmed.exitCode == 0) "diagnostic cache validation failed"
    let current ← DB.PageMap.pin (root/"work.egg")
    discard <| IO.ofExcept (StudyWarm.decode warmed.stdout #[(root/"work.egg").toString] #[current.head]
      MiniLM.model SearchProvider.encoderContract true)
    let session := s!"reply-footprint-topic-{probe.topic}"
    let managed ← StudyRuntime.startManaged (.mk probe.runtime.path) (.mk probe.pluginRoot) session
      (root/"data/daemon.json") environment
    try
      let fields := [("session_id",toJson session),("turn_id",toJson "first"),
        ("cwd",toJson input.workspace),("_eggshell_config",toJson config.toString)]
      let started ← StudyCommand.run probe.runtime.path #["codex-hook"] environment input.workspace
        ((Json.mkObj (fields++[("hook_event_name",toJson "SessionStart")])).compress++"\n") (cell/"SessionStart") 35000
      check (started.exitCode == 0) "diagnostic SessionStart failed"
      let receiptRoot := root/"data/receipts"
      let before ← snapshots receiptRoot
      let witnessRoot := root/"data/reply-witnesses"
      let witnessesBefore ← snapshots witnessRoot
      let spec ← json (root/s!"topic-{topic.topic}-source.json")
      let request := Json.mkObj (fields++[("hook_event_name",toJson "UserPromptSubmit"),("prompt",spec.getObjValD "prompt")])
      let hook ← StudyCommand.run probe.runtime.path #["codex-hook"] environment input.workspace
        (request.compress++"\n") (cell/"hook") 35000
      let reply ← IO.ofExcept (Json.parse hook.stdout)
      let body := (reply.getObjVal? "hookSpecificOutput" >>= (·.getObjValAs? String "additionalContext")).toOption.getD ""
      IO.FS.writeFile (cell/"body.txt") body
      save (cell/"receipt.json") (← receipt receiptRoot before hook.stdout)
      save (cell/"audit-input.json") (Json.mkObj [("source",spec),("database",toJson (root/"work.egg").toString),
        ("request",toJson (cell/"hook/stdin").toString),("stdout",toJson (cell/"hook/stdout").toString),
        ("timing",toJson (cell/"hook/record.json").toString),("body",toJson (cell/"body.txt").toString)])
      let audit ← NativeTrialAudit.inspect (cell/"audit-input.json").toString
      check (audit.getObjValD "availableEvidence" == (← json (root/s!"topic-{topic.topic}-frozen.json")))
        "diagnostic changed frozen necessary evidence"
      save (cell/"audit.json") audit
      let mut witnesses := #[]
      for name in ← snapshots witnessRoot do
        if witnessesBefore.contains name then continue
        let path := witnessRoot/name
        witnesses := witnesses.push (Json.mkObj [("path",toJson path.toString),("sha256",toJson (← ArtifactHash.hex path))])
      check (witnesses.size == 1) "diagnostic did not capture one actual actor reply"
      save (cell/"result.json") (Json.mkObj [("diagnosticOnly",toJson true),("topic",toJson topic.topic),
        ("runtime",toJson probe.runtime),("sourceFiles",toJson sourceFiles),("hookMs",toJson hook.elapsedMs),
        ("availableDelivery",audit.getObjValD "availableDelivery"),("witnesses",toJson witnesses),
        ("answeringModelCalls",toJson (0 : Nat)),("adopted",toJson false)])
    finally StudyRuntime.stopManaged managed (cell/"shutdown.json")
  finally StudyRuntime.stopManaged publisher (cell/"publisher-shutdown.json")
  check ((← StudyRuntime.files (root/"work.egg")) == sourceFiles) "diagnostic modified the original DB"

end RealDeliveryProbe

def main (args : List String) : IO Unit := do
  let [operation,path] := args | throw (IO.userError "RealDeliveryProbe freeze|run INPUT")
  if operation == "probe" then
    RealDeliveryProbe.diagnose (← IO.ofExcept (fromJson? (← IO.ofExcept (Json.parse (← IO.FS.readFile (.mk path))))))
    return
  if operation == "install-prefix" then
    let value ← IO.ofExcept (Json.parse (← IO.FS.readFile (.mk path)))
    let root := System.FilePath.mk (← IO.ofExcept (value.getObjValAs? String "root"))
    let runtime ← IO.ofExcept (fromJson? (value.getObjValD "runtime") : Except String StudyAdmission.Artifact)
    let models := System.FilePath.mk (← IO.ofExcept (value.getObjValAs? String "models"))
    unless root.isAbsolute && !(← root.pathExists) && (← models.isDir) do
      throw (IO.userError "fresh isolated prefix and existing model directory required")
    StudyAdmission.verifyArtifact runtime
    IO.FS.createDirAll (root/"libexec")
    let copied ← IO.Process.output {cmd := "/bin/cp",args := #["-c",runtime.path,(root/"libexec/eggshell").toString]}
    unless copied.exitCode == 0 do throw (IO.userError "cannot stage the pinned runtime")
    let plugin := root/"share/eggshell/codex-plugin"
    IO.FS.createDirAll (plugin/"bin")
    for name in ["egg","eggshelld"] do
      let target := plugin/"bin"/name
      IO.FS.writeFile target (Eggshell.Install.pluginLauncher root)
      IO.setAccessRights target {
        user := {read := true,write := true,execution := true}
        group := {read := true,execution := true}
        other := {read := true,execution := true}}
    let linked ← IO.Process.output {cmd := "/bin/ln",args := #["-s",models.toString,(root/"share/eggshell/minilm").toString]}
    unless linked.exitCode == 0 do throw (IO.userError "cannot share unchanged MiniLM assets")
    unless (← ArtifactHash.hex (root/"libexec/eggshell")) == runtime.sha256 do
      throw (IO.userError "staged executable differs from the pinned runtime")
    return
  if operation == "layout" then
    let input ← IO.ofExcept (fromJson? (α := RealDeliveryProbe.LayoutInput)
      (← IO.ofExcept (Json.parse (← IO.FS.readFile (.mk path)))))
    RealDeliveryProbe.layout input
    return
  let input ← IO.ofExcept (fromJson? (α := RealDeliveryProbe.Input)
    (← IO.ofExcept (Json.parse (← IO.FS.readFile (.mk path)))))
  if operation == "freeze" then RealDeliveryProbe.freeze input (.mk path)
  else if operation == "run" then RealDeliveryProbe.run input (.mk path)
  else throw (IO.userError "unknown real delivery operation")
