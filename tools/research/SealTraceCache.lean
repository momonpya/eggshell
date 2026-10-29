import Lean.Data.Json.Parser
import Lean.Data.Json.FromToJson
open Lean

private def read (path : System.FilePath) : IO Json :=
  IO.FS.readFile path >>= fun text => IO.ofExcept (Json.parse text)

private def objects (path : System.FilePath) : IO (Array String) := do
  let mut result := #[]
  for line in (← IO.FS.readFile (path / "runtime.rsp")).splitOn "\n" do
    unless line.trimAscii.isEmpty do result := result.push (← IO.ofExcept (Json.parse line >>= Json.getStr?))
  return result

private def nativeSource (paths : Array String) (name : String) : IO (String × Array (String × String)) := do
  let some object := paths.find? (·.endsWith ("/Eggshell_" ++ name ++ ".o")) |
    throw (IO.userError "sealed native source missing")
  IO.ofExcept (fromJson? (← read ((System.FilePath.mk object).withExtension "source")))

private def finished (path : System.FilePath) : IO Unit := do
  let guard ← read path
  unless guard.getObjValD "state" == toJson "finished" && guard.getObjValD "exitCode" == toJson (0 : Nat) &&
      guard.getObjValD "guardTriggered" == toJson false && guard.getObjValD "error" == Json.null &&
      guard.getObjValD "ownedPids" == toJson (#[] : Array Nat) do
    throw (IO.userError "required exclusive guard did not finish successfully")

private partial def size (path : System.FilePath) : IO Nat := do
  let metadata ← path.symlinkMetadata
  if metadata.type != .dir then return metadata.byteSize.toNat
  let mut bytes := 0
  for entry in ← path.readDir do bytes := bytes+(← size entry.path)
  return bytes

private partial def remove (path : System.FilePath) : IO Unit := do
  if (← path.symlinkMetadata).type == .dir then
    for entry in ← path.readDir do remove entry.path
    IO.FS.removeDir path
  else IO.FS.removeFile path

def main (args : List String) : IO Unit := do
  let root : System.FilePath := "/Users/ovm/.codex/experiments/eggshell/scope-token-study-20261028/shared-snapshot"
  let output : System.FilePath := "/Users/ovm/.codex/worktrees/hook-deadline-baseline/eggshell/docs/candidates/trace-cache"
  if args == ["retire"] then
    unless (← (output / "decision.json").pathExists) && !(← (output / "retired.json").pathExists) do
      throw (IO.userError "seal evidence before retiring ended trace-cache fixtures")
    finished (output / "fixtures.guard.json")
    let targets := #[root / "trace-cache-fixture",root / "trace-cache-answer-fixture",
      root / "trace-cache-quoted-fixture",root / "trace-cache-verified-fixture",root / "trace-cache-build/StudyMain"]
    let processes ← IO.Process.output {cmd := "/bin/ps",args := #["-axo","command="]}
    unless processes.exitCode == 0 && targets.all (fun target =>
        (processes.stdout.splitOn target.toString).length == 1) do
      throw (IO.userError "trace-cache fixture still owns a process")
    let mut rows := #[]
    for target in targets do
      if ← target.pathExists then rows := rows.push (target.toString,← size target)
    IO.FS.writeFile (output / "retired.json") (Json.mkObj [("targets",toJson rows),
      ("logicalBytes",toJson (rows.foldl (fun total row => total+row.2) 0)),
      ("archiveCreated",toJson false),("isolatedCandidateSourcesAndDependenciesRetained",toJson true),
      ("originalSeedModelAndReferenceRuntimeRetained",toJson true)]).pretty
    for target in targets do if ← target.pathExists then remove target
    IO.println s!"Deleted {rows.size} ended trace-cache targets; kept isolated source and reference"
    return
  unless args.isEmpty && !(← output.pathExists) do throw (IO.userError "preserve prior trace-cache evidence")
  let buildSettings ← read (root / "trace-cache-build.guard-settings.json")
  let buildGuard ← IO.ofExcept (buildSettings.getObjValAs? String "record")
  finished (.mk buildGuard)
  finished (root / "trace-cache-verified-run.guard.json")
  finished (root / "trace-cache-closure.guard.json")
  let report ← read (root / "trace-cache-verified-fixture/result.json")
  for name in ["baseline","delayedOriginal","separateClock","unrelatedSession","retiredProducer"] do
    let value := report.getObjValD name
    unless value.getObjValD "allFactsEqualFullRebuild" == toJson true &&
        value.getObjValD "consumptionEqualFullReplay" == toJson true do
      throw (IO.userError "full reference equality missing")
  let baseline ← objects (root / "dependency-checked-runtime-build")
  let candidate ← objects (root / "trace-cache-build")
  let mut patch := ""
  for name in ["SynapseProvenance","SynapseIndex","SynapseBuild","SynapseTraceCache"] do
    let current := root / "core/Eggshell" / System.FilePath.mk (name ++ ".lean")
    let sealed ← nativeSource candidate name
    unless (← IO.FS.readFile current) == sealed.1 do throw (IO.userError "candidate source changed after native validation")
    for (relative,contents) in sealed.2 do
      unless (← IO.FS.readFile (current.parent.get! / System.FilePath.mk relative)) == contents do
        throw (IO.userError "included candidate input changed after native validation")
    let added := name == "SynapseTraceCache"
    let parent := root / System.FilePath.mk ("trace-cache-parent-" ++ name ++ ".lean")
    if !added then IO.FS.writeFile parent (← nativeSource baseline name).1
    let diff ← IO.Process.output {cmd := "/usr/bin/diff",args := #["-u","--label",
      if added then "/dev/null" else "a/Eggshell/" ++ name ++ ".lean",
      "--label","b/Eggshell/" ++ name ++ ".lean",if added then "/dev/null" else parent.toString,current.toString]}
    unless diff.exitCode == 1 do throw (IO.userError "expected trace-cache difference missing")
    patch := patch ++ diff.stdout
    if !added then IO.FS.removeFile parent
  IO.FS.createDirAll output
  IO.FS.writeFile (output / "candidate.patch") patch
  for (origin,target) in [
      ("trace-cache-verified-fixture/result.json","fixtures.json"),
      ("trace-cache-verified-run.guard.json","fixtures.guard.json"),
      ("trace-cache-fixture/result.json","initial-no-answer-fixture.json"),
      ("trace-cache-run.guard.json","initial-no-answer.guard.json"),
      ("trace-cache-answer-run.guard.json","empty-coquotation.guard.json"),
      ("trace-cache-quoted-run.guard.json","excluded-overlapped-run.guard.json"),
      ("trace-cache-closure.json","native-closure.json"),
      ("trace-cache-closure.guard.json","native-closure.guard.json"),
      ("trace-cache-build/tools_research_TraceCacheAudit-lean.stdout","proofs-and-boundaries.stdout")] do
    IO.FS.writeFile (output / System.FilePath.mk target) (← IO.FS.readFile (root / System.FilePath.mk origin))
  IO.FS.writeFile (output / "build.guard.json") (← IO.FS.readFile (.mk buildGuard))
  let mut guards := #[]
  for entry in ← root.readDir do
    if entry.fileName.startsWith "trace-cache-build-" && entry.fileName.endsWith ".guard.json" then
      guards := guards.push (← read entry.path)
  IO.FS.writeFile (output / "build-guards.json") (toJson guards).pretty
  IO.FS.writeFile (output / "decision.json") (Json.mkObj [("adopted",toJson false),
    ("allObservedFactsEqualFullRebuild",toJson true),("incrementalTraceReplayConnected",toJson true),
    ("otherGlobalWarmScansRemain",toJson true),("answeringModelCalls",toJson (0 : Nat)),
    ("actualHookCalls",toJson (0 : Nat)),("tokenImprovementMeasured",toJson false),
    ("deliveryImprovementMeasured",toJson false),("eightyUserSustainedLoadMeasured",toJson false),
    ("overlappedRunExcluded",toJson true),("goalAchieved",toJson false)]).pretty
  IO.println "Sealed exclusive trace-cache fixture, full-reference checks and candidate source"
