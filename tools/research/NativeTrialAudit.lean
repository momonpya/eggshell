import Eggshell.SynapseBuild
import Eggshell.SynapseUsage
import Eggshell.ContentMetadata
import tools.research.ArtifactHash
import tools.research.RequiredDelivery
import tools.research.AvailableDelivery
import tools.research.OriginalEvidence
import Eggshell.Worker

open Lean Eggshell Eggshell.Synapses

namespace Eggshell.Research.NativeTrialAudit

private abbrev Requirement := OriginalEvidence.Reference

private structure Source where
  source : String
  workspace : String
  prompt : String
  files : Array (String × String)
  required : Array Requirement
  deriving FromJson

private structure Trial where
  source : Source
  database : String
  request : String
  stdout : String
  timing : String
  body : String
  deriving FromJson

private def check (condition : Bool) (message : String) : IO Unit :=
  unless condition do throw (IO.userError message)

private def readJson (path : String) : IO Json := do
  IO.ofExcept (Json.parse (← IO.FS.readFile (.mk path)))

private def originals (source : DB.PageMap.Snapshot) (workspace : System.FilePath) :
    IO (Array Extraction.Document × Array Read) := do
  let reader ← Persistence.Store.NodeReader.new source
  let mut documents := #[]
  let mut rows := #[]
  let mut images : Std.HashMap File OriginalEvidence.Image := {}
  -- Discover original owners from this publication, including newly accumulated
  -- observations. Human reference requirements never choose the source owners.
  for entry in ← Build.entries source do
    let mut doc ← Build.document reader entry.id
    if let some captured ← ContentMetadata.load? source entry.id doc then
      let catalog ← IO.ofExcept (ContentMetadata.catalog source.head.identity doc captured)
      let characters := doc.source.getD "" |>.toList.toArray
      -- The product's saved coordinates are not the oracle. Re-read and hash
      -- the reference image, then compare the actual original slice with its
      -- claimed file line independently of the capture matcher.
      for located in catalog.located do
        let row := located.read
        let some file := row.source.file? | throw (IO.userError "file alias has no file")
        let image ← match images[file]? with
          | some image => pure image
          | none => do
              let image ← OriginalEvidence.load workspace file
              images := images.insert file image
              pure image
        let lines := (image.text.splitOn "\n").toArray
        let some expected := lines[row.source.first-1]? | throw (IO.userError "file alias exceeds reference image")
        let original := String.ofList (characters.extract row.binding.first row.binding.limit).toList
        let decoded := (Json.parse ("\"" ++ original ++ "\"") >>= Json.getStr?).toOption
        check (row.source.first == row.source.last && (original == expected || decoded == some expected))
          "saved file alias differs from independent reference bytes"
        rows := rows.push row
      let files := captured.inputs.filterMap fun input => input.content.map fun content =>
        (⟨input.relative,content.root,content.bytes⟩ : File)
      doc := {doc with files := (hashDistinct (doc.files.toList ++ files.toList)).toArray}
    documents := documents.push doc
    if let .ok found := Extraction.recordedRows source.head.identity doc then rows := rows ++ found
  return (documents,rows)

/-- Freeze every DB-backed obligation before running a hook. This also keeps
partial observations that the historical complete-range metric excludes. -/
def freezeAvailable (value : Json) : IO AvailableDelivery.Frozen := do
  let specification ← IO.ofExcept (fromJson? (α := Source) value)
  for (name,expected) in specification.files do
    check ((← ArtifactHash.hex (.mk specification.source / name)) == expected) "immutable source bytes changed"
  let source ← DB.PageMap.pin (.mk specification.source)
  let (documents,rows) ← originals source (.mk specification.workspace)
  let resolved ← OriginalEvidence.resolve (.mk specification.workspace) source.head.identity
    documents rows specification.required
  IO.ofExcept (AvailableDelivery.freeze (resolved.requirements.map fun item =>
    ⟨item.name,item.alternatives⟩) (resolved.reads.map (·.source)))

/-- Reanalyse retained bytes whose hash was already recorded by an actual
native hook audit. This is not another hook execution or latency sample. -/
def replayAvailable (value : Json) (bodyPath expectedHash : String) : IO Json := do
  let specification ← IO.ofExcept (fromJson? (α := Source) value)
  for (name,expected) in specification.files do
    check ((← ArtifactHash.hex (.mk specification.source / name)) == expected) "immutable source bytes changed"
  let source ← DB.PageMap.pin (.mk specification.source)
  let (documents,rows) ← originals source (.mk specification.workspace)
  let resolved ← OriginalEvidence.resolve (.mk specification.workspace) source.head.identity
    documents rows specification.required
  let requirements := resolved.requirements.map fun item => (⟨item.name,item.alternatives⟩ : RequiredDelivery.Requirement)
  let legacy ← IO.ofExcept (RequiredDelivery.freeze requirements (resolved.reads.map (·.source)))
  let available ← IO.ofExcept (AvailableDelivery.freeze requirements (resolved.reads.map (·.source)))
  let body ← IO.FS.readFile (.mk bodyPath)
  check (Sha256.hex body.toUTF8 == expectedHash) "retained actual body hash changed"
  let shown := Extraction.presented body documents resolved.reads
  return Json.mkObj [("source",toJson source.head),("bodySha256",toJson expectedHash),
    ("frozenEvidence",toJson legacy),("requiredDelivery",toJson (RequiredDelivery.assess legacy shown.ranges)),
    ("availableEvidence",toJson available),("availableDelivery",toJson (AvailableDelivery.assess available shown.ranges)),
    ("retainedActualBody",toJson true),("newHookCalls",toJson (0 : Nat)),("latencySample",toJson false)]

def inspect (input : String) : IO Json := do
  let bytes ← IO.FS.readBinFile (.mk input)
  let some text := String.fromUTF8? bytes | throw (IO.userError "trial input encoding")
  let trial ← IO.ofExcept (Json.parse text >>= fromJson? (α := Trial))
  let specification := trial.source
  for requirement in specification.required do
    check (!requirement.path.isEmpty && 0 < requirement.first && requirement.first ≤ requirement.last)
      "invalid reference source range"
  for (name,expected) in specification.files do
    check ((← ArtifactHash.hex (System.FilePath.mk specification.source / name)) == expected)
      "immutable source bytes changed"
  let before ← DB.PageMap.pin (.mk specification.source)
  let (documents,fileRows) ← originals before (.mk specification.workspace)
  let resolved ← OriginalEvidence.resolve (.mk specification.workspace) before.head.identity
    documents fileRows specification.required
  let rows := resolved.reads
  let alternatives : Array (String × Array Read × Array Range) := resolved.requirements.map fun item =>
    let candidates := rows.filter fun row => item.alternatives.any fun target =>
      target.subject == row.source.subject && row.source.first ≤ target.last && target.first ≤ row.source.last
    (item.name,candidates,item.alternatives)
  -- The denominator is determined from the immutable source before inspecting
  -- delivery bytes. A later failed candidate cannot shrink it.
  let frozen ← IO.ofExcept (RequiredDelivery.freeze (alternatives.map fun (name,_,targets) =>
    ⟨name,targets⟩) (rows.map (·.source)))
  let available ← IO.ofExcept (AvailableDelivery.freeze (alternatives.map fun (name,_,targets) =>
    ⟨name,targets⟩) (rows.map (·.source)))
  let request ← readJson trial.request
  check ((request.getObjValAs? String "hook_event_name").toOption == some "UserPromptSubmit" &&
    (request.getObjValAs? String "prompt").toOption == some specification.prompt &&
    (request.getObjValAs? String "cwd").toOption == some specification.workspace) "wrong preflight question or workspace"
  let stdout ← IO.FS.readFile (.mk trial.stdout)
  let timing ← readJson trial.timing
  check ((timing.getObjValAs? Nat "exitCode").toOption == some 0 &&
    (timing.getObjValAs? Float "elapsedMs").toOption.any (fun ms => 0 < ms && ms < 30000) &&
    (timing.getObjValAs? String "stdoutSha256").toOption == some (Sha256.hex stdout.toUTF8))
    "native preflight failed, expired or has different stdout"
  let reply ← IO.ofExcept (Json.parse stdout)
  check reply.getObj?.isOk "native hook returned a non-object reply"
  let body := (reply.getObjVal? "hookSpecificOutput" >>= (·.getObjValAs? String "additionalContext")).toOption.getD ""
  check (body == (← IO.FS.readFile (.mk trial.body))) "saved body differs from actual stdout"
  let after ← DB.PageMap.pin (.mk trial.database)
  let same ← Index.sameSources after before.head (after.head.revision-before.head.revision+1)
  let original ← IO.FS.readBinFile (DB.PageMap.dataPath before.directory before.head)
  let current ← IO.FS.readBinFile (DB.PageMap.dataPath after.directory after.head)
  let prefixExact := original.extract 0 before.head.bytes == current.extract 0 before.head.bytes
  check (same && prefixExact) "preparation changed original source facts or pages"
  let shown := Extraction.presented body documents rows
  let requirements := alternatives.map fun (name,candidates,targets) =>
    let stored := targets.any (fun target => covered target (candidates.map (fun (row : Read) => row.source)))
    let delivered := targets.any (fun target => covered target shown.ranges)
    Json.mkObj [("name",toJson name),("stored",toJson stored),
      ("storedOwners",toJson ((candidates.map (fun (row : Read) => row.binding.owner)).toList.eraseDups.toArray)),
      ("bodyDelivered",toJson delivered),("unlocated",toJson (!stored))]
  return Json.mkObj [("specSha256",toJson (Sha256.hex bytes)),
    ("sourceGraphFiles",Json.mkObj (specification.files.toList.map fun (name,digest) => (name,toJson digest))),
    ("sameSourceFacts",toJson same),("samePublishedPagePrefix",toJson prefixExact),
    ("originalDocuments",toJson documents.size),("originalRows",toJson fileRows.size),
    ("originalOutputBindings",toJson resolved.bindings),
    ("stdoutSha256",toJson (Sha256.hex stdout.toUTF8)),("bodySha256",toJson (Sha256.hex body.toUTF8)),
    ("frozenEvidence",toJson frozen),("requiredDelivery",toJson (RequiredDelivery.assess frozen shown.ranges)),
    ("availableEvidence",toJson available),("availableDelivery",toJson (AvailableDelivery.assess available shown.ranges)),
    ("requirements",toJson requirements)]

/-- Body coverage from an explicitly unbounded worker diagnostic is distinct
from timely hook delivery. It cannot satisfy the native preflight gate. -/
def inspectWorker (input : String) : IO Json := do
  let bytes ← IO.FS.readBinFile (.mk input)
  let some text := String.fromUTF8? bytes | throw (IO.userError "worker audit encoding")
  let trial ← IO.ofExcept (Json.parse text >>= fromJson? (α := Trial))
  let specification := trial.source
  for (name,expected) in specification.files do
    check ((← ArtifactHash.hex (.mk specification.source / name)) == expected) "worker source bytes changed"
  let before ← DB.PageMap.pin (.mk specification.source)
  let request ← IO.ofExcept ((← readJson trial.request) |> fromJson? (α := Plugin.Worker.Search))
  check (request.pending.prompt == specification.prompt && request.work == specification.prompt &&
    request.pending.cwd == specification.workspace && !request.enforce && request.evidence.isNone)
    "worker diagnostic differs from the frozen question"
  let stdout ← IO.FS.readFile (.mk trial.stdout)
  let timing ← readJson trial.timing
  check ((timing.getObjValAs? Nat "exitCode").toOption == some 0 &&
    (timing.getObjValAs? String "stdoutSha256").toOption == some (Sha256.hex stdout.toUTF8)) "worker reply differs"
  let some last := (stdout.splitOn "\n" |>.filter (!·.isEmpty)).getLast? |
    throw (IO.userError "worker diagnostic has no frame")
  let frame ← IO.ofExcept (Json.parse last >>= fromJson? (α := Plugin.Worker.SearchFrame))
  let .reply identity handoff := frame | throw (IO.userError "worker diagnostic has only progress")
  check (identity == request.identity) "worker reply identity differs"
  let (documents,fileRows) ← originals before (.mk specification.workspace)
  let resolved ← OriginalEvidence.resolve (.mk specification.workspace) before.head.identity
    documents fileRows specification.required
  let frozen ← IO.ofExcept (RequiredDelivery.freeze (resolved.requirements.map fun item =>
    ⟨item.name,item.alternatives⟩) (resolved.reads.map (·.source)))
  let available ← IO.ofExcept (AvailableDelivery.freeze (resolved.requirements.map fun item =>
    ⟨item.name,item.alternatives⟩) (resolved.reads.map (·.source)))
  let after ← DB.PageMap.pin (.mk trial.database)
  check (after.head == before.head) "worker diagnostic changed the source publication"
  let body := handoff.map (·.text) |>.getD ""
  let shown := Extraction.presented body documents resolved.reads
  return Json.mkObj [("diagnosticOnly",toJson true),("actualHook",toJson false),
    ("latencyAcceptance",toJson false),("productionAdoption",toJson false),
    ("specSha256",toJson (Sha256.hex bytes)),("stdoutSha256",toJson (Sha256.hex stdout.toUTF8)),
    ("bodySha256",toJson (Sha256.hex body.toUTF8)),("bodyChars",toJson body.length),
    ("elapsedMs",timing.getObjValD "elapsedMs"),("frozenEvidence",toJson frozen),
    ("coverageWithoutDeadline",toJson (RequiredDelivery.assess frozen shown.ranges)),
    ("availableEvidence",toJson available),
    ("availableCoverageWithoutDeadline",toJson (AvailableDelivery.assess available shown.ranges))]

/-- Source extraction and literal code/fingerprint comparison stay in Lean.
The orchestrator can seal the report, then replay it without trusting labels. -/
def cliMain (args : List String) : IO Unit := do
  let [mode,input,output] := args | throw (IO.userError "NativeTrialAudit emit|check INPUT REPORT")
  let report ← inspect input
  if mode == "emit" then
    check (!(← (System.FilePath.mk output).pathExists)) "keep the existing native audit"
    IO.FS.writeFile (.mk output) (report.compress ++ "\n")
  else if mode == "check" then
    check (report == (← readJson output)) "sealed native evidence report differs from replay"
  else throw (IO.userError "expected emit or check")
  IO.println s!"native evidence audit {mode} completed"

end Eggshell.Research.NativeTrialAudit
