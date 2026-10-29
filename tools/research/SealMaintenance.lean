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

private def factDelta : IO Unit := do
  let root : System.FilePath := "/Users/ovm/.codex/experiments/eggshell/scope-token-study-20261028/shared-snapshot"
  let project : System.FilePath := "/Users/ovm/.codex/worktrees/hook-deadline-baseline/eggshell"
  let output := project / "docs/candidates/fact-delta"
  unless !(← (output / "decision.json").pathExists) do throw (IO.userError "preserve fact delta evidence")
  for name in ["scoped-fixtures", "native-closure", "seed-replay"] do
    finished (output / System.FilePath.mk (name ++ ".guard.json"))
  let report ← read (root / "fact-delta-scoped-fixture/result.json")
  for name in ["baseline","delayedOriginal","separateClock","unrelatedSession","retiredProducer","unchangedAffectedPublication"] do
    let result := report.getObjValD name
    unless result.getObjValD "allFactsEqualFullRebuild" == toJson true &&
        result.getObjValD "consumptionEqualFullReplay" == toJson true do
      throw (IO.userError "complete oracle comparison failed")
  let micro := report.getObjValD "exactFactDelta"
  unless micro.getObjValD "unchangedAdded" == toJson (0 : Nat) && micro.getObjValD "unchangedRemoved" == toJson (0 : Nat) &&
      micro.getObjValD "allFactPostingBindingAndRoutingRowsEqual" == toJson true &&
      micro.getObjValD "oldPinUnchanged" == toJson true && micro.getObjValD "reverseUpdateEqualsFullReplacement" == toJson true do
    throw (IO.userError "physical delta projection comparison failed")
  let before ← objects (root / "consumed-feedback-runtime-build")
  let after ← objects (root / "fact-delta-build")
  let mut patch := ""
  for name in ["SynapseIndex","SynapseBuild"] do
    let source := root / "core/Eggshell" / System.FilePath.mk (name ++ ".lean")
    let compiled ← nativeSource after name
    unless compiled.1 == (← IO.FS.readFile source) do throw (IO.userError "fact delta source changed after compilation")
    for (relative,contents) in compiled.2 do
      unless (← IO.FS.readFile (source.parent.get! / System.FilePath.mk relative)) == contents do
        throw (IO.userError "fact delta included input changed")
    let parent := root / System.FilePath.mk ("fact-delta-parent-" ++ name ++ ".lean")
    IO.FS.writeFile parent (← nativeSource before name).1
    let difference ← IO.Process.output {cmd := "/usr/bin/diff",args := #["-U0","--label","a/Eggshell/" ++ name ++ ".lean",
      "--label","b/Eggshell/" ++ name ++ ".lean",parent.toString,source.toString]}
    unless difference.exitCode == 1 do throw (IO.userError "fact delta change missing")
    patch := patch ++ difference.stdout
    IO.FS.removeFile parent
  IO.FS.writeFile (output / "candidate.patch") patch
  IO.FS.writeFile (output / "fixtures.json") report.pretty
  for (origin,target) in [("tools_research_FactDeltaChecks-lean.stdout","proofs.stdout"),
      ("tools_research_MaintenanceAudit-lean.stdout","boundaries.stdout")] do
    IO.FS.writeFile (output / System.FilePath.mk target) (← IO.FS.readFile (root / "fact-delta-build" / System.FilePath.mk origin))
  let mut guards := #[]
  for entry in ← root.readDir do
    if entry.fileName.startsWith "fact-delta-build-" && entry.fileName.endsWith ".guard.json" then
      guards := guards.push (← read entry.path)
  IO.FS.writeFile (output / "build-guards.json") (toJson guards).pretty
  let buildRecord ← IO.ofExcept ((← read (root / "fact-delta-build.guard-settings.json")).getObjValAs? String "record")
  finished (.mk buildRecord)
  IO.FS.writeFile (output / "build.guard.json") (← IO.FS.readFile (.mk buildRecord))
  IO.FS.writeFile (output / "decision.json") (Json.mkObj [("adopted",toJson false),
    ("affectedFactSetExact",toJson true),("allFixtureProjectionsEqualFullReplacement",toJson true),
    ("actualHookCalls",toJson (0 : Nat)),("answeringModelCalls",toJson (0 : Nat)),
    ("tokenImprovementMeasured",toJson false),("eightyUserLoadMeasured",toJson false),("goalAchieved",toJson false)]).pretty
  let targets := #[root / "fact-delta-fixture",root / "fact-delta-verified-fixture",root / "fact-delta-final-fixture",
    root / "fact-delta-scoped-fixture",root / "fact-delta-build/StudyMain"]
  let processes ← IO.Process.output {cmd := "/bin/ps",args := #["-axo","command="]}
  unless processes.exitCode == 0 && targets.all (fun path =>
      (processes.stdout.splitOn path.toString).length == 1) do throw (IO.userError "fact delta fixture remains live")
  let mut retired := #[]
  for target in targets do retired := retired.push (target.toString,← size target)
  let cleanup := Json.mkObj [("targets",toJson retired),("archiveCreated",toJson false),
    ("logicalBytes",toJson (retired.foldl (fun total row => total+row.2) 0)),
    ("originalDataModelsComparisonRuntimesSourcesObjectsAndInterfacesRetained",toJson true)]
  IO.FS.writeFile (output / "retired.json") (cleanup.setObjVal! "completed" (toJson false)).pretty
  for target in targets do remove target
  IO.FS.writeFile (output / "retired.json") (cleanup.setObjVal! "completed" (toJson true)).pretty
  IO.println "Sealed exact fact delta and its negative controls; deleted ended fixtures and executable"

private def deferredQuotation : IO Unit := do
  let root : System.FilePath := "/Users/ovm/.codex/experiments/eggshell/scope-token-study-20261028/shared-snapshot"
  let project : System.FilePath := "/Users/ovm/.codex/worktrees/hook-deadline-baseline/eggshell"
  let output := project / "docs/candidates/deferred-quotation"
  unless !(← (output / "decision.json").pathExists) do throw (IO.userError "preserve deferred quotation evidence")
  for name in ["fixtures","seed-replay","native-closure"] do finished (output / System.FilePath.mk (name ++ ".guard.json"))
  let before ← read (project / "docs/candidates/fact-delta/seed-replay.json")
  let after ← read (output / "seed-replay.json")
  for key in ["source","journal","session","starts","finishes","answers","sourceAndJournalUnchanged"] do
    unless before.getObjValD key == after.getObjValD key do throw (IO.userError "replay input or immutable source changed")
  for key in ["usage","consumed","pending","unknown","ambiguousNativeUses","fileRangeReferences","locatorSource","locatorIndex","locatorCache"] do
    unless (before.getObjValD "replay").getObjValD key == (after.getObjValD "replay").getObjValD key do
      throw (IO.userError "deferred quotation changed usage facts or replay evidence")
  let fixture ← read (root / "deferred-quotation-fixture/result.json")
  let cases ← IO.ofExcept ((fixture.getObjValD "cases").getArr?)
  unless cases.size == 5 && cases.all (fun row => row.getObjValD "eagerMappingResultEqual" == toJson true) &&
      fixture.getObjValD "distinctOriginsRetained" == toJson true &&
      fixture.getObjValD "unsupportedProjectionExplicit" == toJson true do
    throw (IO.userError "eager/deferred quote boundary test failed")
  let compiled ← nativeSource (← objects (root / "fact-deferred-runtime-build")) "ObservationContext"
  let source := root / "core/Eggshell/ObservationContext.lean"
  unless compiled.1 == (← IO.FS.readFile source) do throw (IO.userError "quotation source changed after full runtime build")
  for (relative,contents) in compiled.2 do
    unless (← IO.FS.readFile (source.parent.get! / System.FilePath.mk relative)) == contents do
      throw (IO.userError "quotation included input changed")
  let parent := root / "deferred-quotation-parent.lean"
  IO.FS.writeFile parent (← nativeSource (← objects (root / "replay-profile-build")) "ObservationContext").1
  let difference ← IO.Process.output {cmd := "/usr/bin/diff",args := #["-U0","--label","a/Eggshell/ObservationContext.lean",
    "--label","b/Eggshell/ObservationContext.lean",parent.toString,source.toString]}
  unless difference.exitCode == 1 do throw (IO.userError "deferred projection change missing")
  IO.FS.writeFile (output / "candidate.patch") difference.stdout
  IO.FS.removeFile parent
  IO.FS.writeFile (output / "fixtures.json") fixture.pretty
  IO.FS.writeFile (output / "proofs.stdout")
    (← IO.FS.readFile (root / "deferred-quotation-build/tools_research_DeferredQuotationAudit-lean.stdout"))
  let mut guards := #[]
  for label in ["deferred-quotation","replay-deferred","fact-deferred-runtime","fact-deferred-hook"] do
    let settings ← read (root / System.FilePath.mk (label ++ "-build.guard-settings.json"))
    finished (.mk (← IO.ofExcept (settings.getObjValAs? String "record")))
    for entry in ← root.readDir do
      if entry.fileName.startsWith (label ++ "-build-") && entry.fileName.endsWith ".guard.json" then
        guards := guards.push (← read entry.path)
  IO.FS.writeFile (output / "build-guards.json") (toJson guards).pretty
  IO.FS.writeFile (output / "decision.json") (Json.mkObj [("adopted",toJson false),
    ("allUsageFactsAndReplayInputsEqual",toJson true),("eagerProjectionBoundaryCasesEqual",toJson true),
    ("baselineReplayMs",(before.getObjValD "replay").getObjValD "elapsedMs"),
    ("candidateReplayMs",(after.getObjValD "replay").getObjValD "elapsedMs"),
    ("actualHookCalls",toJson (0 : Nat)),("answeringModelCalls",toJson (0 : Nat)),
    ("tokenImprovementMeasured",toJson false),("eightyUserLoadMeasured",toJson false),("goalAchieved",toJson false)]).pretty
  let targets := #[root / "deferred-quotation-fixture",root / "deferred-quotation-build/StudyMain",
    root / "replay-profile-build/StudyMain",root / "replay-deferred-build/StudyMain"]
  let processes ← IO.Process.output {cmd := "/bin/ps",args := #["-axo","command="]}
  unless processes.exitCode == 0 && targets.all (fun path =>
      (processes.stdout.splitOn path.toString).length == 1) do throw (IO.userError "deferred quotation fixture is still live")
  let mut retired := #[]
  for target in targets do retired := retired.push (target.toString,← size target)
  let cleanup := Json.mkObj [("targets",toJson retired),("archiveCreated",toJson false),
    ("logicalBytes",toJson (retired.foldl (fun total row => total+row.2) 0)),
    ("originalDataModelsFullRuntimesSourcesObjectsAndInterfacesRetained",toJson true)]
  IO.FS.writeFile (output / "retired.json") (cleanup.setObjVal! "completed" (toJson false)).pretty
  for target in targets do remove target
  IO.FS.writeFile (output / "retired.json") (cleanup.setObjVal! "completed" (toJson true)).pretty
  IO.println "Sealed identical replay facts and deferred projection; deleted ended helpers and fixture"

def main (args : List String) : IO Unit := do
  if args == ["fact-delta"] then return ← factDelta
  if args == ["deferred-quotation"] then return ← deferredQuotation
  unless args.isEmpty do throw (IO.userError "unknown maintenance evidence target")
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
