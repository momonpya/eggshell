import Main
import Eggshell.ContractAudit
import tools.research.SharedTrafficChecks
open Lean Eggshell Eggshell.Plugin Eggshell.Research
open Eggshell.Research.SharedProjectLifecycle
namespace LLVMReadPreparation
def prepare (inputPath directory : String) : IO Unit := do
  let input ← IO.ofExcept (fromJson? (α := SharedTrafficChecks.Input) (← StudyAdmission.readJson inputPath))
  let plan := input.installation
  StudyAdmission.verifyArtifact plan.runtime
  for file in plan.pluginFiles do StudyAdmission.verifyArtifact file
  StudySeedChecks.requireNumericalSupport plan
  let original : System.FilePath := .mk input.original
  let root : System.FilePath := .mk directory
  check (root.isAbsolute && !(← root.pathExists)) "fresh LLVM preparation directory required"
  check ((← StudyRuntime.files original) == input.originalFiles) "protected LLVM source changed"
  IO.FS.createDirAll root
  let database := root/"llvm.egg"
  StudyRuntime.restore original database
  let source ← DB.PageMap.pin original
  let copySource ← DB.PageMap.pin database
  check (source.head == copySource.head) "LLVM copy changed its original publication"
  let hints ← DB.Sidecar.locate source .database
  let destination ← DB.Sidecar.locate copySource .database
  check ((← VectorMatrix.open? hints.semantic MiniLM.model SearchProvider.encoderContract).isSome)
    "the protected source has no reusable committed numerical hints"
  IO.FS.createDirAll destination.semantic.parent.get!
  let copied ← IO.Process.output {cmd := "/bin/cp",args := #["-cR",hints.semantic.toString,destination.semantic.toString]}
  check (copied.exitCode == 0) "source-only numerical hint copy failed"
  let mut topics := #[]
  for definition in ← IO.ofExcept input.definitions.getArr? do
    let number ← IO.ofExcept (definition.getObjValAs? Nat "topic")
    let promptPath ← IO.ofExcept ((definition.getObjValD "prompt").getObjValAs? String "path")
    let expected ← IO.ofExcept ((definition.getObjValD "prompt").getObjValAs? String "sha256")
    check ((← ArtifactHash.hex (.mk promptPath)) == expected) "LLVM question changed"
    let prompt ← IO.FS.readFile (.mk promptPath)
    let specification := Json.mkObj [("source",toJson input.original),("files",toJson input.originalFiles),
      ("workspace",toJson input.workspace),("prompt",toJson prompt),("required",definition.getObjValD "referenceRanges")]
    let frozen ← NativeTrialAudit.freezeAvailable specification
    topics := topics.push (Json.mkObj [("topic",toJson number),("source",specification),("frozen",toJson frozen)])
  check (topics.size == 3) "all three LLVM topics required"
  save (root/"frozen-before-delivery.json") (toJson topics)
  let data := root/"data"
  IO.FS.createDir data
  let config := root/"warm.toml"
  IO.FS.writeFile config (SharedTrafficChecks.config plan.runtime.path database true)
  let environment := replaceEnv plan.environment #[("EGGSHELL_DATA_ROOT",some data.toString),
    ("CODEX_THREAD_ID",none),("CODEX_TURN_ID",none)]
  let publisher ← StudyRuntime.startPublisher (.mk plan.runtime.path) data environment
  let frontend ← try
      StudyRuntime.startManaged (.mk plan.runtime.path) (.mk plan.pluginRoot) "llvm-read-preparation"
        (data/"daemon.json") environment
    catch error =>
      StudyRuntime.stopManaged publisher (root/"publisher-startup-stop.json")
      throw error
  let warmed ← try warm plan root data config "warm"
    finally
      try StudyRuntime.stopManaged frontend (root/"frontend-stop.json")
      finally StudyRuntime.stopManaged publisher (root/"publisher-stop.json")
  check ((← StudyRuntime.files original) == input.originalFiles &&
    (← StudyRuntime.files database) == input.originalFiles) "preparation changed an original publication"
  save (root/"prepared.json") (Json.mkObj [("runtime",toJson plan.runtime),("sourceHead",toJson source.head),
    ("originalFiles",toJson input.originalFiles),("warm",warmed),("topicsFrozenBeforeHooks",toJson true),
    ("originalUnchanged",toJson true),("answeringModelCalls",toJson (0 : Nat)),
    ("interruptedSeedIsDiagnosticOnly",toJson true),("adopted",toJson false)])
end LLVMReadPreparation
def main (args : List String) : IO UInt32 := do
  match args with
  | [input,directory] => LLVMReadPreparation.prepare input directory; return 0
  | _ => sourceRouteEngine args
