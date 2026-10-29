import Lean.Data.Json.Parser
import Lean.Data.Json.FromToJson
open Lean

private def read (path : System.FilePath) : IO Json :=
  IO.FS.readFile path >>= fun text => IO.ofExcept (Json.parse text)

private def finished (path : System.FilePath) : IO Unit := do
  let guard ← read path
  unless guard.getObjValD "state" == toJson "finished" && guard.getObjValD "exitCode" == toJson (0 : Nat) &&
      guard.getObjValD "error" == Json.null && guard.getObjValD "guardTriggered" == toJson false &&
      guard.getObjValD "ownedPids" == toJson (#[] : Array Nat) do
    throw (IO.userError "wait for successful exclusive guard completion")

private def objects (directory : System.FilePath) : IO (Array String) := do
  let mut result := #[]
  for line in (← IO.FS.readFile (directory / "runtime.rsp")).splitOn "\n" do
    unless line.trimAscii.isEmpty do result := result.push (← IO.ofExcept (Json.parse line >>= Json.getStr?))
  return result

private def nativeSource (paths : Array String) (name : String) : IO (String × Array (String × String)) := do
  let some path := paths.find? (·.endsWith ("/Eggshell_" ++ name ++ ".o")) |
    throw (IO.userError "sealed native source missing")
  IO.ofExcept (fromJson? (← read ((System.FilePath.mk path).withExtension "source")))

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

def main : IO Unit := do
  let root : System.FilePath := "/Users/ovm/.codex/experiments/eggshell/scope-token-study-20261028/shared-snapshot"
  let project : System.FilePath := "/Users/ovm/.codex/worktrees/hook-deadline-baseline/eggshell"
  let output := project / "docs/candidates/maintenance-delta"
  unless !(← output.pathExists) do throw (IO.userError "preserve prior maintenance evidence")
  let buildRecord ← IO.ofExcept ((← read (root / "maintenance-build.guard-settings.json")).getObjValAs? String "record")
  finished (.mk buildRecord)
  finished (root / "maintenance-run.guard.json")
  finished (root / "maintenance-closure.guard.json")
  let report ← read (root / "maintenance-fixture/result.json")
  for name in ["baseline","delayedOriginal","separateClock","unrelatedSession","retiredProducer"] do
    let result := report.getObjValD name
    unless result.getObjValD "allFactsEqualFullRebuild" == toJson true &&
        result.getObjValD "consumptionEqualFullReplay" == toJson true do
      throw (IO.userError "complete reference equality missing")
  let baseline ← objects (root / "trace-cache-build")
  let candidate ← objects (root / "maintenance-build")
  let old := (← nativeSource baseline "SynapseBuild").1
  let oracle := old.replace "namespace Eggshell.Synapses.Build" "namespace Eggshell.Synapses.BuildOracle"
    |>.replace "end Eggshell.Synapses.Build" "end Eggshell.Synapses.BuildOracle"
  unless (← IO.FS.readFile (project / "tools/research/SynapseBuildOracle.lean")) == oracle do
    throw (IO.userError "independent oracle differs from the sealed preceding implementation")
  let mut patch := ""
  for name in ["SynapticTopology","SynapseIndex","SynapseBuild","SynapseMaintenance"] do
    let source := root / "core/Eggshell" / System.FilePath.mk (name ++ ".lean")
    let compiled ← nativeSource candidate name
    unless (← IO.FS.readFile source) == compiled.1 do throw (IO.userError "candidate differs from native source")
    for (path,text) in compiled.2 do
      unless (← IO.FS.readFile (source.parent.get! / System.FilePath.mk path)) == text do
        throw (IO.userError "included source differs from native evidence")
    let added := name == "SynapseMaintenance"
    let parent := root / System.FilePath.mk ("maintenance-parent-" ++ name ++ ".lean")
    if !added then IO.FS.writeFile parent (← nativeSource baseline name).1
    let diff ← IO.Process.output {cmd := "/usr/bin/diff",args := #["-u","--label",
      if added then "/dev/null" else "a/Eggshell/" ++ name ++ ".lean",
      "--label","b/Eggshell/" ++ name ++ ".lean",if added then "/dev/null" else parent.toString,source.toString]}
    unless diff.exitCode == 1 do throw (IO.userError "expected candidate difference missing")
    patch := patch ++ diff.stdout
    if !added then IO.FS.removeFile parent
  IO.FS.createDirAll output
  IO.FS.writeFile (output / "candidate.patch") patch
  for (origin,target) in [
      ("maintenance-fixture/result.json","fixtures.json"),("maintenance-run.guard.json","fixtures.guard.json"),
      ("maintenance-closure.json","native-closure.json"),("maintenance-closure.guard.json","native-closure.guard.json"),
      ("maintenance-executable-retired.json","executable-retired.json"),
      ("maintenance-build/tools_research_MaintenanceAudit-lean.stdout","proofs-and-boundaries.stdout")] do
    IO.FS.writeFile (output / System.FilePath.mk target) (← IO.FS.readFile (root / System.FilePath.mk origin))
  IO.FS.writeFile (output / "build.guard.json") (← IO.FS.readFile (.mk buildRecord))
  let mut guards := #[]
  for entry in ← root.readDir do
    if entry.fileName.startsWith "maintenance-build-" && entry.fileName.endsWith ".guard.json" then
      guards := guards.push (← read entry.path)
  IO.FS.writeFile (output / "build-guards.json") (toJson guards).pretty
  IO.FS.writeFile (output / "decision.json") (Json.mkObj [
    ("adopted",toJson false),("answeringModelCalls",toJson (0 : Nat)),("actualHookCalls",toJson (0 : Nat)),
    ("frozenPrecedingImplementationIsOracle",toJson true),("allFixtureFactsMatchFullOracle",toJson true),
    ("forwardAndReverseSourceClosuresCompared",toJson true),("maintenanceKeysHaveNoRoute",toJson true),
    ("tokenImprovementMeasured",toJson false),("deliveryImprovementMeasured",toJson false),
    ("eightyUserSustainedLoadMeasured",toJson false),("goalAchieved",toJson false)]).pretty
  let target := root / "maintenance-fixture"
  let processes ← IO.Process.output {cmd := "/bin/ps",args := #["-axo","command="]}
  unless processes.exitCode == 0 && (processes.stdout.splitOn target.toString).length == 1 do
    throw (IO.userError "ended fixture still has a process")
  let count ← size target
  IO.FS.writeFile (output / "retired.json") (Json.mkObj [("target",toJson target.toString),
    ("logicalBytes",toJson count),("archiveCreated",toJson false),
    ("originalSeedModelsCheckedReferenceAndIsolatedSourcesRetained",toJson true)]).pretty
  remove target
  IO.println "Sealed maintenance delta, verified frozen oracle and deleted ended fixture DB/cache"
