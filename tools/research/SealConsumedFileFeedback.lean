import Lean.Data.Json.Parser
import Lean.Data.Json.FromToJson
open Lean

private def read (path : System.FilePath) : IO Json :=
  IO.FS.readFile path >>= fun text => IO.ofExcept (Json.parse text)
private def check (condition : Bool) (message : String) : IO Unit :=
  unless condition do throw (IO.userError message)
private def finished (path : System.FilePath) (expected : Nat := 0) : IO Unit := do
  let guard ← read path
  check (guard.getObjValD "state" == toJson "finished" && guard.getObjValD "exitCode" == toJson expected &&
    guard.getObjValD "error" == Json.null && guard.getObjValD "guardTriggered" == toJson false &&
    guard.getObjValD "ownedPids" == toJson (#[] : Array Nat)) "exclusive guard did not finish successfully"
private def digest (path : System.FilePath) : IO String := do
  let result ← IO.Process.output {cmd := "/usr/bin/shasum", args := #["-a", "256", path.toString]}
  check (result.exitCode == 0) "artifact digest failed"
  return (result.stdout.splitOn " ").headD ""
private def nativeSource (directory : System.FilePath) (name : String) : IO (String × Array (String × String)) := do
  for line in (← IO.FS.readFile (directory / "runtime.rsp")).splitOn "\n" do
    if line.trimAscii.isEmpty then continue
    let path ← IO.ofExcept (Json.parse line >>= Json.getStr?)
    if path.endsWith ("/Eggshell_" ++ name ++ ".o") then
      return ← IO.ofExcept (fromJson? (← read ((System.FilePath.mk path).withExtension "source")))
  throw (IO.userError "linked native source missing")
private partial def size (path : System.FilePath) : IO Nat := do
  let metadata ← path.symlinkMetadata
  if metadata.type != .dir then return metadata.byteSize.toNat
  let mut total := 0
  for entry in ← path.readDir do total := total + (← size entry.path)
  return total
private partial def remove (path : System.FilePath) : IO Unit := do
  if (← path.symlinkMetadata).type == .dir then
    for entry in ← path.readDir do remove entry.path
    IO.FS.removeDir path
  else IO.FS.removeFile path

def main (args : List String) : IO Unit := do
  let study : System.FilePath := "/Users/ovm/.codex/experiments/eggshell/scope-token-study-20261028"
  let root := study / "shared-snapshot"
  let project : System.FilePath := "/Users/ovm/.codex/worktrees/hook-deadline-baseline/eggshell"
  let output := project / "docs/candidates/consumed-file-feedback"
  let trial := root / "consumed-feedback-cache-repaired-hook"
  if args == ["retire"] then
    check ((← (output / "decision.json").pathExists) && !(← (output / "retired.json").pathExists))
      "seal evidence before retirement and preserve previous cleanup"
    finished (output / "actual-hook-repaired.guard.json") 1
    let targets := #[trial, root / "consumed-feedback-prepared-hook", root / "consumed-file-feedback-build/StudyMain", root / "consumed-feedback-hook-build/StudyMain", root / "prefix"]
    let processes ← IO.Process.output {cmd := "/bin/ps", args := #["-axo", "command="]}
    check (processes.exitCode == 0 && targets.all (fun target =>
      (processes.stdout.splitOn target.toString).length == 1)) "do not remove a live trial"
    let originalModel := study / "prefix/share/eggshell/minilm"
    let modelLink := root / "prefix/share/eggshell/minilm"
    check ((← modelLink.symlinkMetadata).type == .symlink &&
      (← IO.FS.realPath modelLink) == (← IO.FS.realPath originalModel)) "retain the original numeric runtime"
    let mut rows := #[]
    for target in targets do rows := rows.push (target.toString, ← size target)
    let report := Json.mkObj [("targets", toJson rows), ("archiveCreated", toJson false),
      ("logicalBytes", toJson (rows.foldl (fun total row => total + row.2) 0)),
      ("originalSeedModelsFullRuntimesSourcesObjectsAndInterfacesRetained", toJson true)]
    IO.FS.writeFile (output / "retired.json") (report.setObjVal! "completed" (toJson false)).pretty
    for target in targets do remove target
    check (← originalModel.pathExists) "original numeric runtime was lost"
    IO.FS.writeFile (output / "retired.json") (report.setObjVal! "completed" (toJson true)).pretty
    IO.println "Deleted ended trial DB/cache, two helpers and temporary install; no archive"
    return
  check (args.isEmpty && !(← (output / "decision.json").pathExists)) "preserve previous decision"
  for name in ["coordinates", "replay", "native-closure-repaired"] do
    finished (output / System.FilePath.mk (name ++ ".guard.json"))
  finished (output / "actual-hook-repaired.guard.json") 1
  let before ← read (project / "docs/candidates/feedback-knowledge/candidate-replay.json")
  let after ← read (output / "replay.json")
  for key in ["source", "journal", "session", "starts", "finishes", "answers"] do
    check (before.getObjValD key == after.getObjValD key) "changed feedback input snapshot or session"
  check (after.getObjValD "sourceAndJournalUnchanged" == toJson true) "replay wrote the source or journal"
  let usage ← IO.ofExcept (((after.getObjValD "replay").getObjValD "usage").getArr?)
  let kinds := usage.map fun fact => ((fact.getObjValD "used").getObjValD "usage").getObjValD "kind"
  check (!(← (trial / "UserPromptSubmit").pathExists)) "failure was incorrectly classified as pre-hook"
  let failure ← IO.FS.readFile (trial / "warm/stderr")
  check (failure.contains "native usage deadline") "unexpected preparation failure"
  let lifecycle ← read (trial / "cache-lifecycle.json")
  for key in ["noncanonicalManifestReadRejected", "derivedManifestRebuilt", "originalUnchanged", "pinnedReaderRetained"] do
    check (lifecycle.getObjValD key == toJson true) "cache repair boundary failed"
  let closure ← read (output / "native-closure-repaired.json")
  check ((closure.getObjValD "repairedBuild").getObjValD "consistent" == toJson true &&
    (closure.getObjValD "staleBuild").getObjValD "consistent" == toJson false) "native closure controls failed"
  let mut patch := ""
  for name in ["SynapseUsage", "SynapseJournal", "CanonicalSourceCache"] do
    let source := root / "core/Eggshell" / System.FilePath.mk (name ++ ".lean")
    let actual ← nativeSource (root / "consumed-feedback-runtime-build") name
    check ((← IO.FS.readFile source) == actual.1) "source changed after full runtime build"
    for (relative, contents) in actual.2 do
      check ((← IO.FS.readFile (source.parent.get! / System.FilePath.mk relative)) == contents)
        "included native input changed"
    let parent := root / System.FilePath.mk ("consumed-feedback-parent-" ++ name ++ ".lean")
    let parentBuild := if name == "CanonicalSourceCache" then "prepared-snapshot-build" else "cached-feedback-build"
    IO.FS.writeFile parent (← nativeSource (root / parentBuild) name).1
    let diff ← IO.Process.output {cmd := "/usr/bin/diff", args := #["-U0", "--label", "a/Eggshell/" ++ name ++ ".lean",
      "--label", "b/Eggshell/" ++ name ++ ".lean", parent.toString, source.toString]}
    check (diff.exitCode == 1) "candidate difference missing"
    patch := patch ++ diff.stdout
    IO.FS.removeFile parent
  IO.FS.writeFile (output / "candidate.patch") patch
  let mut buildGuards := #[]
  for label in ["consumed-file-feedback", "consumed-feedback-runtime", "consumed-feedback-hook"] do
    let settings ← read (root / System.FilePath.mk (label ++ "-build.guard-settings.json"))
    finished (.mk (← IO.ofExcept (settings.getObjValAs? String "record")))
    for entry in ← root.readDir do
      if entry.fileName.startsWith (label ++ "-build-") && entry.fileName.endsWith ".guard.json" then
        buildGuards := buildGuards.push (← read entry.path)
  IO.FS.writeFile (output / "build-guards.json") (toJson buildGuards).pretty
  IO.FS.writeFile (output / "proofs.stdout")
    (← IO.FS.readFile (root / "consumed-file-feedback-build/tools_research_ConsumedFileFeedbackFixtures-lean.stdout"))
  let failedManifest := root / "consumed-feedback-prepared-hook/work.egg/derived/d6ff6dad444913158edfc86f2a3bd24212835619ec78e5d4da0e3afe1789a812/canonical-source/manifest.json"
  IO.FS.writeFile (output / "failed-input-manifest.json") (← IO.FS.readFile failedManifest)
  for (origin, target) in [("available-before-delivery.json", "available-before-delivery.json"),
      ("supplement-publication.json", "source-preparation.json"),
      ("warm/record.json", "warm.record.json"), ("warm/stdout", "warm.stdout"),
      ("warm/stderr", "warm.stderr"), ("publisher-shutdown.json", "publisher-shutdown.json"),
      ("cache-lifecycle.json", "cache-lifecycle.json")] do
    IO.FS.writeFile (output / System.FilePath.mk target) (← IO.FS.readFile (trial / System.FilePath.mk origin))
  let decision := Json.mkObj [("adopted", toJson false),
    ("runtimeSha256", toJson (← digest (root / "consumed-feedback-runtime-build/StudyMain"))),
    ("actualPromptSubmitHooks", toJson (0 : Nat)), ("preparationFailure", toJson failure),
    ("cacheManifestReadRejectedAndDerivedRepairPassed", toJson true),
    ("usageFacts", toJson usage.size), ("deliveredThenCited", toJson (kinds.countP (· == toJson "deliveredThenCited"))),
    ("omittedThenConsumed", toJson (kinds.countP (· == toJson "omittedThenConsumed"))),
    ("answeringModelCalls", toJson (0 : Nat)), ("tokenImprovementMeasured", toJson false),
    ("eightyUserLoadMeasured", toJson false), ("goalAchieved", toJson false)]
  IO.FS.writeFile (output / "decision.json") decision.pretty
  IO.println decision.compress
