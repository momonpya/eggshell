import Lean.Data.Json.Parser
import Lean.Data.Json.FromToJson
open Lean

private def read (path : System.FilePath) : IO Json :=
  IO.FS.readFile path >>= fun text => IO.ofExcept (Json.parse text)

private def check (condition : Bool) (message : String) : IO Unit :=
  unless condition do throw (IO.userError message)

private def finished (path : System.FilePath) : IO Unit := do
  let result ← read path
  check (result.getObjValD "state" == toJson "finished" &&
    result.getObjValD "exitCode" == toJson (0 : Nat) &&
    result.getObjValD "error" == Json.null &&
    result.getObjValD "guardTriggered" == toJson false &&
    result.getObjValD "ownedPids" == toJson (#[] : Array Nat))
    "exclusive guard did not finish successfully"

private def nativeSource (directory : System.FilePath) (name : String) : IO (String × Array (String × String)) := do
  for line in (← IO.FS.readFile (directory / "runtime.rsp")).splitOn "\n" do
    if line.trimAscii.isEmpty then continue
    let path ← IO.ofExcept (Json.parse line >>= Json.getStr?)
    if path.endsWith ("/Eggshell_" ++ name ++ ".o") then
      return ← IO.ofExcept (fromJson? (← read ((System.FilePath.mk path).withExtension "source")))
  throw (IO.userError "actual linked source missing")

private def natural (row : Json) (key : String) : IO Nat :=
  IO.ofExcept (row.getObjValAs? Nat key)

def main (args : List String) : IO Unit := do
  let root : System.FilePath := "/Users/ovm/.codex/experiments/eggshell/scope-token-study-20261028/shared-snapshot"
  let project : System.FilePath := "/Users/ovm/.codex/worktrees/hook-deadline-baseline/eggshell"
  let output := project / "docs/candidates/feedback-knowledge"
  if args == ["retire"] then
    check ((← (output / "decision.json").pathExists) && !(← (output / "retired.json").pathExists))
      "seal evidence before retirement and preserve the existing retirement record"
    for name in ["candidate-coordinates", "candidate-replay", "seal"] do
      finished (output / System.FilePath.mk (name ++ ".guard.json"))
    let targets := #[root / "feedback-knowledge-build/StudyMain", root / "cached-feedback-build/StudyMain"]
    let processes ← IO.Process.output {cmd := "/bin/ps", args := #["-axo", "command="]}
    check (processes.exitCode == 0 && targets.all (fun target =>
      (processes.stdout.splitOn target.toString).length == 1)) "do not retire a live executable"
    let mut retired := #[]
    for target in targets do
      let metadata ← target.symlinkMetadata
      check (metadata.type == .file) "retire only an ended regular helper executable"
      let digest ← IO.Process.output {cmd := "/usr/bin/shasum", args := #["-a", "256", target.toString]}
      check (digest.exitCode == 0) "helper executable digest failed"
      retired := retired.push (Json.mkObj [("path", toJson target.toString),
        ("sha256", toJson ((digest.stdout.splitOn " ").headD "")), ("bytes", toJson metadata.byteSize.toNat)])
    let report := Json.mkObj [("targets", Json.arr retired), ("archiveCreated", toJson false),
      ("databasesModelsComparisonRuntimesSourcesObjectsAndInterfacesRetained", toJson true)]
    IO.FS.writeFile (output / "retired.json") (report.setObjVal! "completed" (toJson false)).pretty
    for target in targets do IO.FS.removeFile target
    IO.FS.writeFile (output / "retired.json") (report.setObjVal! "completed" (toJson true)).pretty
    IO.println "Deleted two ended metadata-audit executables; no DB/cache/archive was created"
    return
  check args.isEmpty "no arguments required"
  check (!(← (output / "decision.json").pathExists)) "preserve previous decision"
  for name in ["native", "replay", "coordinates", "candidate-coordinates", "candidate-replay", "native-closure"] do
    finished (output / System.FilePath.mk (name ++ ".guard.json"))
  let buildSettings ← read (root / "cached-feedback-build.guard-settings.json")
  let buildGuard ← IO.ofExcept (buildSettings.getObjValAs? String "record")
  finished (.mk buildGuard)
  let before ← read (output / "coordinates.json")
  let after ← read (output / "candidate-coordinates.json")
  let replay ← read (output / "replay.json")
  let candidate ← read (output / "candidate-replay.json")
  for report in [before, after, replay, candidate] do
    check (report.getObjValD "sourceAndJournalUnchanged" == toJson true &&
      report.getObjValD "answeringModelCalls" == toJson (0 : Nat) &&
      report.getObjValD "warmCalls" == toJson (0 : Nat)) "audit modified source or ran preparation/model"
    for key in ["source", "journal", "session", "starts", "finishes", "answers"] do
      check (report.getObjValD key == before.getObjValD key) "compared different source, journal or native session"
  let originalRows ← IO.ofExcept ((before.getObjValD "outputCoordinates").getArr?)
  let projectedRows ← IO.ofExcept ((after.getObjValD "outputCoordinates").getArr?)
  check (originalRows.size == projectedRows.size && !originalRows.isEmpty) "missing output comparison"
  let mut saved := 0
  let mut projected := 0
  let mut legacy := 0
  let mut capturedOutputs := 0
  for i in [:originalRows.size] do
    let original := originalRows[i]!
    let mapped := projectedRows[i]!
    for key in ["occurrence", "originalOwnerFound", "originalFiles", "capturedInputs", "capturedAliases",
        "capturedComplete", "legacyLocated", "legacyFileRows"] do
      check (original.getObjValD key == mapped.getObjValD key) "candidate changed original capture metadata"
    check (mapped.getObjValD "originalOwnerFound" == toJson true &&
      mapped.getObjValD "wrongInvocationAndOutputRejected" == toJson true)
      "missing original or invalid invocation/output admitted"
    let aliases ← natural original "capturedAliases"
    let located ← natural mapped "projectedFileRows"
    check (located == aliases && (← natural mapped "requestedFileRows") == (← natural original "legacyFileRows"))
      "cached aliases were lost or returned rows became requested-read feedback"
    saved := saved + aliases
    projected := projected + located
    legacy := legacy + (← natural original "legacyFileRows")
    if aliases > 0 then capturedOutputs := capturedOutputs + 1
  let closure ← read (output / "native-closure.json")
  check ((closure.getObjValD "repairedBuild").getObjValD "consistent" == toJson true &&
    (closure.getObjValD "staleBuild").getObjValD "consistent" == toJson false)
    "native dependency controls failed"
  let mut patch := ""
  for name in ["SynapseExtraction", "ObservationContext", "ContentMetadata", "SynapseProvenance", "SynapseBuild", "SynapseJournal"] do
    let source := root / "core/Eggshell" / System.FilePath.mk (name ++ ".lean")
    let actual ← nativeSource (root / "cached-feedback-build") name
    check ((← IO.FS.readFile source) == actual.1) "candidate changed after native validation"
    for (relative, contents) in actual.2 do
      check ((← IO.FS.readFile (source.parent.get! / System.FilePath.mk relative)) == contents)
        "candidate included source changed after validation"
    let parent := root / System.FilePath.mk ("cached-feedback-parent-" ++ name ++ ".lean")
    IO.FS.writeFile parent (← nativeSource (root / "feedback-knowledge-build") name).1
    let diff ← IO.Process.output {cmd := "/usr/bin/diff", args := #["-u", "--label", "a/Eggshell/" ++ name ++ ".lean",
      "--label", "b/Eggshell/" ++ name ++ ".lean", parent.toString, source.toString]}
    check (diff.exitCode == 1) "expected candidate change missing"
    patch := patch ++ diff.stdout
    IO.FS.removeFile parent
  IO.FS.writeFile (output / "candidate.patch") patch
  IO.FS.writeFile (output / "build.guard.json") (← IO.FS.readFile (.mk buildGuard))
  let mut buildGuards := #[]
  for entry in ← root.readDir do
    if entry.fileName.startsWith "cached-feedback-build-" && entry.fileName.endsWith ".guard.json" then
      buildGuards := buildGuards.push (← read entry.path)
  IO.FS.writeFile (output / "build-guards.json") (toJson buildGuards).pretty
  IO.FS.writeFile (output / "boundaries.stdout")
    (← IO.FS.readFile (root / "cached-feedback-build/tools_research_FeedbackKnowledgeAudit-lean.stdout"))
  let decision := Json.mkObj [("adopted", toJson false), ("outputsCompared", toJson originalRows.size),
    ("outputsWithCapturedCoordinates", toJson capturedOutputs), ("savedAliases", toJson saved),
    ("legacyLocatedFileRows", toJson legacy), ("candidateProjectedFileRows", toJson projected),
    ("baselineFeedback", replay.getObjValD "replay"), ("candidateFeedback", candidate.getObjValD "replay"),
    ("actualHookCalls", toJson (0 : Nat)), ("answeringModelCalls", toJson (0 : Nat)),
    ("tokenImprovementMeasured", toJson false), ("goalAchieved", toJson false)]
  IO.FS.writeFile (output / "decision.json") decision.pretty
  IO.println decision.compress
