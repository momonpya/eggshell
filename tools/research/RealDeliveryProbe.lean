import tools.research.StudyRuntime
import tools.research.StudyAdmission
import tools.research.StudyCommand
import tools.research.StudySource
import tools.research.StudyProfile
import tools.research.NativeTrialAudit

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
    let prepared ← IO.ofExcept (Json.parse warm.stdout >>= (·.getObjValAs? (Array Json) "databases"))
    let some coverage := prepared[0]? | throw (IO.userError "warm returned no database")
    check (prepared.size == 1 && (coverage.getObjValD "after").getObjValD "missing" == toJson (0 : Nat) &&
      (coverage.getObjValD "after").getObjValD "invalid" == toJson (0 : Nat)) "real source numerical preparation incomplete"
    let repeated ← StudyCommand.run input.runtime.path #["egg","warm","work"] environment input.workspace "" (root / "repeat-warm") 240000
    check (repeated.exitCode == 0) "repeat real-source warm failed"
    let repeatedRows ← IO.ofExcept (Json.parse repeated.stdout >>= (·.getObjValAs? (Array Json) "databases"))
    check (repeatedRows.size == 1 && repeatedRows[0]!.getObjValD "requested" == toJson (0 : Nat)) "repeat warm encoded source windows"
    let mut results := #[]
    for topic in input.topics do
      let spec ← json (root / s!"topic-{topic.topic}-source.json")
      let frozen ← json (root / s!"topic-{topic.topic}-frozen.json")
      for repetition in [:input.repetitions] do
        let cell := root / s!"topic-{topic.topic}-chat-{repetition}"
        IO.FS.createDir cell
        let session := s!"real-topic-{topic.topic}-chat-{repetition}"
        let endpoint := root / "data/sessions" / session / "daemon.json"
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
        finally StudyRuntime.stopManaged managed (cell / "shutdown.json")
    check ((← StudyRuntime.files (root / "source.egg")) == (← StudyRuntime.files (root / "work.egg")))
      "readonly diagnostics changed the original database"
    save (root / "result.json") (Json.mkObj [("cells",toJson results),("source",sealed),
      ("answeringModelCalls",toJson (0 : Nat)),("acceptedSeed",toJson false),
      ("firstCycleAndSecondCycleModelTrials",toJson false)])
  finally StudyRuntime.stopManaged publisher (root / "publisher-shutdown.json")

end RealDeliveryProbe

def main (args : List String) : IO Unit := do
  let [operation,path] := args | throw (IO.userError "RealDeliveryProbe freeze|run INPUT")
  let input ← IO.ofExcept (fromJson? (α := RealDeliveryProbe.Input)
    (← IO.ofExcept (Json.parse (← IO.FS.readFile (.mk path)))))
  if operation == "freeze" then RealDeliveryProbe.freeze input (.mk path)
  else if operation == "run" then RealDeliveryProbe.run input (.mk path)
  else throw (IO.userError "unknown real delivery operation")
