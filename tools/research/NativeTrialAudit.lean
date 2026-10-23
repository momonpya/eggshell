import Eggshell.SynapseBuild
import Eggshell.SynapseUsage
import tools.research.ArtifactHash

open Lean Eggshell Eggshell.Synapses

namespace Eggshell.Research.NativeTrialAudit

private structure Requirement where
  name : String
  path : String
  first : Nat
  last : Nat
  deriving FromJson

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

private def originals (source : DB.PageMap.Snapshot) :
    IO (Array Extraction.Document × Array Read) := do
  let reader ← Persistence.Store.NodeReader.new source
  let mut documents := #[]
  let mut rows := #[]
  -- Discover original owners from this publication, including newly accumulated
  -- observations. Human reference requirements never choose the source owners.
  for entry in ← Build.entries source do
    let doc ← Build.document reader entry.id
    documents := documents.push doc
    if let .ok found := Extraction.recordedRows source.head.identity doc then rows := rows ++ found
  return (documents,rows)

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
  let body ← IO.ofExcept (reply.getObjVal? "hookSpecificOutput" >>= (·.getObjValAs? String "additionalContext"))
  check (body == (← IO.FS.readFile (.mk trial.body))) "saved body differs from actual stdout"
  let before ← DB.PageMap.pin (.mk specification.source)
  let after ← DB.PageMap.pin (.mk trial.database)
  let same ← Index.sameSources after before.head (after.head.revision-before.head.revision+1)
  let original ← IO.FS.readBinFile (DB.PageMap.dataPath before.directory before.head)
  let current ← IO.FS.readBinFile (DB.PageMap.dataPath after.directory after.head)
  let prefixExact := original.extract 0 before.head.bytes == current.extract 0 before.head.bytes
  check (same && prefixExact) "preparation changed original source facts or pages"
  let (documents,rows) ← originals before
  let shown := Extraction.presented body documents rows
  let requirements := specification.required.map fun requirement =>
    let candidates := rows.filter fun row => row.source.file.relative == requirement.path &&
      row.source.first ≤ requirement.last && requirement.first ≤ row.source.last
    let files := candidates.foldl (fun found row => found.insert row.source.file) ({} : Std.HashSet File)
    let stored := files.toArray.any fun file => covered ⟨file,requirement.first,requirement.last⟩
      (candidates.map (·.source))
    let delivered := files.toArray.any fun file => covered ⟨file,requirement.first,requirement.last⟩ shown.ranges
    Json.mkObj [("name",toJson requirement.name),("stored",toJson stored),
      ("storedOwners",toJson ((candidates.map (·.binding.owner)).toList.eraseDups.toArray)),
      ("bodyDelivered",toJson delivered),("unlocated",toJson (!stored))]
  return Json.mkObj [("specSha256",toJson (Sha256.hex bytes)),
    ("sourceGraphFiles",Json.mkObj (specification.files.toList.map fun (name,digest) => (name,toJson digest))),
    ("sameSourceFacts",toJson same),("samePublishedPagePrefix",toJson prefixExact),
    ("originalDocuments",toJson documents.size),("originalRows",toJson rows.size),
    ("stdoutSha256",toJson (Sha256.hex stdout.toUTF8)),("bodySha256",toJson (Sha256.hex body.toUTF8)),
    ("requirements",toJson requirements)]

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
