import Lean.Data.Json.Parser
import Lean.Data.Json.FromToJson
open Lean

private def read (path : System.FilePath) : IO Json :=
  IO.FS.readFile path >>= fun text => IO.ofExcept (Json.parse text)

private def finished (path : System.FilePath) : IO Unit := do
  let result ← read path
  unless result.getObjValD "state" == toJson "finished" && result.getObjValD "exitCode" == toJson (0 : Nat) &&
      result.getObjValD "error" == Json.null && result.getObjValD "guardTriggered" == toJson false &&
      result.getObjValD "ownedPids" == toJson (#[] : Array Nat) do
    throw (IO.userError "exclusive guard did not finish successfully")

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

private def nativeSource (directory : System.FilePath) (name : String) : IO (String × Array (String × String)) := do
  for line in (← IO.FS.readFile (directory / "runtime.rsp")).splitOn "\n" do
    if line.trimAscii.isEmpty then continue
    let path ← IO.ofExcept (Json.parse line >>= Json.getStr?)
    if path.endsWith ("/Eggshell_" ++ name ++ ".o") then
      return ← IO.ofExcept (fromJson? (← read ((System.FilePath.mk path).withExtension "source")))
  throw (IO.userError "actual native source missing")

def main (args : List String) : IO Unit := do
  let root : System.FilePath := "/Users/ovm/.codex/experiments/eggshell/scope-token-study-20261028/shared-snapshot"
  let output : System.FilePath := "/Users/ovm/.codex/worktrees/hook-deadline-baseline/eggshell/docs/candidates/prepared-snapshot"
  if args == ["retire"] then
    unless (← (output / "decision.json").pathExists) && !(← (output / "retired.json").pathExists) do
      throw (IO.userError "seal fixture evidence before retirement")
    finished (output / "fixtures.guard.json")
    let targets := #[root / "prepared-snapshot-fixture", root / "prepared-snapshot-build/StudyMain"]
    let processes ← IO.Process.output {cmd := "/bin/ps", args := #["-axo", "command="]}
    unless processes.exitCode == 0 && targets.all (fun target =>
        (processes.stdout.splitOn target.toString).length == 1) do
      throw (IO.userError "prepared snapshot fixture is still running")
    let mut rows := #[]
    for target in targets do if ← target.pathExists then rows := rows.push (target.toString, ← size target)
    let report := Json.mkObj [("targets", toJson rows),
      ("logicalBytes", toJson (rows.foldl (fun total row => total + row.2) 0)),
      ("archiveCreated", toJson false), ("originalSeedModelsRuntimesObjectsAndInterfacesRetained", toJson true)]
    IO.FS.writeFile (output / "retired.json") (report.setObjVal! "completed" (toJson false)).pretty
    for target in targets do if ← target.pathExists then remove target
    IO.FS.writeFile (output / "retired.json") (report.setObjVal! "completed" (toJson true)).pretty
    IO.println "Deleted ended prepared snapshot fixture DB, caches and executable; no archive"
    return
  unless args.isEmpty && !(← output.pathExists) do throw (IO.userError "preserve previous fixture evidence")
  finished (root / "prepared-snapshot-run.guard.json")
  finished (root / "prepared-snapshot-closure.guard.json")
  let buildSettings ← read (root / "prepared-snapshot-build.guard-settings.json")
  let buildGuard ← IO.ofExcept (buildSettings.getObjValAs? String "record")
  finished (.mk buildGuard)
  let report ← read (root / "prepared-snapshot-fixture/result.json")
  for name in ["latestOnlyControlRejectedOldSource", "oldFactsAndBytesPreserved", "unpreparedNewSourceRejected",
      "readsAndOldWarmDoNotWrite", "foreignRootAndWrongSourcesRejected", "toolStartCapturedOldPreparedIndex"] do
    unless report.getObjValD name == toJson true do throw (IO.userError "required snapshot boundary failed")
  let mut patch := ""
  for name in ["SynapseIndex", "CanonicalSourceCache", "PublicationService"] do
    let source := root / "core/Eggshell" / System.FilePath.mk (name ++ ".lean")
    let actual ← nativeSource (root / "prepared-snapshot-build") name
    unless (← IO.FS.readFile source) == actual.1 do throw (IO.userError "source changed after native validation")
    for (relative, contents) in actual.2 do
      unless (← IO.FS.readFile (source.parent.get! / System.FilePath.mk relative)) == contents do
        throw (IO.userError "included source changed after native validation")
    let parent := root / System.FilePath.mk ("prepared-snapshot-parent-" ++ name ++ ".lean")
    IO.FS.writeFile parent (← nativeSource (root / "maintenance-runtime-build") name).1
    let diff ← IO.Process.output {cmd := "/usr/bin/diff", args := #["-u", "--label", "a/Eggshell/" ++ name ++ ".lean",
      "--label", "b/Eggshell/" ++ name ++ ".lean", parent.toString, source.toString]}
    unless diff.exitCode == 1 do throw (IO.userError "expected candidate difference missing")
    patch := patch ++ diff.stdout
    IO.FS.removeFile parent
  IO.FS.createDirAll output
  IO.FS.writeFile (output / "candidate.patch") patch
  for (origin, target) in [("prepared-snapshot-fixture/result.json", "fixtures.json"),
      ("prepared-snapshot-run.guard.json", "fixtures.guard.json"),
      ("prepared-snapshot-closure.json", "native-closure.json"),
      ("prepared-snapshot-closure.guard.json", "native-closure.guard.json"),
      ("prepared-snapshot-build/tools_research_PreparedSnapshotAudit-lean.stdout", "boundaries.stdout")] do
    IO.FS.writeFile (output / System.FilePath.mk target) (← IO.FS.readFile (root / System.FilePath.mk origin))
  IO.FS.writeFile (output / "build.guard.json") (← IO.FS.readFile (.mk buildGuard))
  let mut guards := #[]
  for entry in ← root.readDir do
    if entry.fileName.startsWith "prepared-snapshot-build-" && entry.fileName.endsWith ".guard.json" then
      guards := guards.push (← read entry.path)
  IO.FS.writeFile (output / "build-guards.json") (toJson guards).pretty
  IO.FS.writeFile (output / "decision.json") (Json.mkObj [("adopted", toJson false),
    ("preparedOldSnapshotRaceFixedInNativeServiceApi", toJson true),
    ("unpreparedSourceTailHandled", toJson false), ("actualHookCalls", toJson (0 : Nat)),
    ("answeringModelCalls", toJson (0 : Nat)), ("tokenImprovementMeasured", toJson false),
    ("eightyUserSustainedLoadMeasured", toJson false), ("goalAchieved", toJson false)]).pretty
  IO.println "Sealed native source, old/new snapshot race and actual service API boundary checks"
