import Lean.Data.Json.Parser
import Lean.Data.Json.FromToJson
open Lean

private def read (path : System.FilePath) : IO Json :=
  IO.FS.readFile path >>= fun text => IO.ofExcept (Json.parse text)
private partial def bytes (path : System.FilePath) : IO Nat := do
  let metadata ← path.symlinkMetadata
  if metadata.type != .dir then return if metadata.type == .file then metadata.byteSize.toNat else 0
  let mut total := 0
  for entry in ← path.readDir do total := total+(← bytes entry.path)
  return total
private partial def remove (path : System.FilePath) : IO Unit := do
  if (← path.symlinkMetadata).type == .dir then
    for entry in ← path.readDir do remove entry.path
    IO.FS.removeDir path
  else IO.FS.removeFile path
private partial def protect (path : System.FilePath) (targets : Array System.FilePath) : IO Unit := do
  for entry in ← path.readDir do
    let metadata ← entry.path.symlinkMetadata
    if metadata.type == .dir then protect entry.path targets
    else if metadata.type == .symlink then
      let actual ← IO.FS.realPath entry.path
      unless targets.all (fun target => actual != target && !actual.toString.startsWith (target.toString ++ "/")) do
        throw (IO.userError "active source/interface depends on a retirement target")

/-- Delete only ended experiment copies and old executables. Original seed,
one current prepared checkpoint, numerical boundary, object/source/interface
dependencies and the assessed resource controller are retained. No archive. -/
def main (args : List String) : IO Unit := do
  let probes := args == ["probes"]
  unless args.isEmpty || probes do throw (IO.userError "probes | no arguments")
  let base := System.FilePath.mk "/Users/ovm/.codex/experiments/eggshell"
  let study := base / "study-services-20261026"
  let active := base / "shared-original-structure-20261027"
  let project := System.FilePath.mk "/Users/ovm/.codex/worktrees/hook-deadline-baseline/eggshell"
  if probes then
    let report := project / "docs/candidates/shared-original-structure/retired-probe-executables.json"
    unless !(← report.pathExists) do throw (IO.userError "preserve probe retirement")
    let targets := #[base / "literal-support-20261026/probe-tools_research_SynapticReplayProfile/Probe",
      base / "literal-support-20261026/probe-tools_research_SynapticReplayProfile-facts/Probe",
      base / "shared-prepared-service-20261026/audit-build/StudyMain"]
    let processes ← IO.Process.output {cmd := "/bin/ps",args := #["-axo","command="]}
    unless processes.exitCode == 0 do throw (IO.userError "cannot inspect probe ownership")
    let response ← IO.FS.readFile (active / "product-build/runtime.rsp")
    for target in targets do
      unless (processes.stdout.splitOn target.toString).length == 1 &&
          (response.splitOn target.toString).length == 1 do throw (IO.userError "old probe is still used")
    for directory in [active / "product-build/lib",active / "checkout"] do protect directory targets
    let artifacts ← IO.Process.output {
      cmd := (study / "assessed-controller").toString
      args := #["artifacts"] ++ targets.map (·.toString)}
    unless artifacts.exitCode == 0 do throw (IO.userError artifacts.stderr)
    let digests ← IO.ofExcept (Json.parse artifacts.stdout)
    IO.FS.writeFile report (Json.mkObj [("targets",toJson (targets.map (·.toString))),
      ("digests",digests),("sourceObjectsAndInterfacesRetained",toJson true),("archiveCreated",toJson false)]).pretty
    for target in targets do remove target
    IO.println "Deleted three ended probe executables without archives"
    return
  let report := project / "docs/candidates/shared-original-structure/retired-study-copies.json"
  unless !(← report.pathExists) do throw (IO.userError "preserve retirement evidence")
  let original ← read (study / "common-seed-1/source.egg/head")
  let databasePaths := #[study / "study/seed-1/work.egg",study / "study/seed-1/output.egg",
    study / "study/seed-1-ready/ready.egg",study / "pilot-stage-1/work.egg"]
  for database in databasePaths do
    unless (← read (database / "head")) == original do
      throw (IO.userError "ended DB copy differs from the retained original source head")
  let mut guards := #[]
  for path in [study / "seed-1.guard.json",study / "seed-1-ready.guard.json",
      study / "pilot-stage-1/preparation.guard.json",active / "compile-all-texts.guard.json"] do
    let value ← read path
    unless value.getObjValD "state" == toJson "finished" &&
        value.getObjValD "ownedPids" == toJson (#[] : Array Nat) do
      throw (IO.userError "ended study still owns a process")
    guards := guards.push (path.toString,value)
  let mut targets := databasePaths ++ #[study / "study/seed-1/data",study / "pilot-stage-1/data"]
  let mut executables := #[]
  for name in ["streamed-incidence-20261027","captured-correspondence-20261026","routed-transport-20261026",
      "bound-span-preparation-20261027","owner-unit-postings-20261026","shared-prepared-service-20261026",
      "selector-preparation-20261026","shared-bundle-projection-20261026"] do
    let path := base / name / "product-build/StudyMain"
    if ← path.pathExists then executables := executables.push path
  for path in [study / "controller",study / "product",study / "prefix/libexec/eggshell"] do
    if ← path.pathExists then executables := executables.push path
  targets := targets ++ executables
  let processes ← IO.Process.output {cmd := "/bin/ps",args := #["-axo","command="]}
  unless processes.exitCode == 0 do throw (IO.userError "cannot inspect live ownership")
  for target in targets do
    unless (processes.stdout.splitOn target.toString).length == 1 do
      throw (IO.userError "retirement target is referenced by a live process")
  for directory in [active / "product-build/lib",active / "checkout"] do protect directory targets
  let response ← IO.FS.readFile (active / "product-build/runtime.rsp")
  for target in targets do
    unless (response.splitOn target.toString).length == 1 do
      throw (IO.userError "active linker still depends on retirement target")
  let artifacts ← IO.Process.output {
    cmd := (study / "assessed-controller").toString
    args := #["artifacts"] ++ executables.map (·.toString)}
  unless artifacts.exitCode == 0 do throw (IO.userError artifacts.stderr)
  let executableDigests ← IO.ofExcept (Json.parse artifacts.stdout)
  let mut sizes := #[]
  for target in targets do sizes := sizes.push (target.toString,← bytes target)
  IO.FS.createDirAll report.parent.get!
  IO.FS.writeFile report (Json.mkObj [
    ("targets",toJson sizes),("executableDigests",executableDigests),("terminalGuards",toJson guards),
    ("sameRetainedSourceHead",original),("archiveCreated",toJson false),
    ("originalSeedOnePreparedCheckpointAndLiveCodeDependenciesRetained",toJson true)]).pretty
  for target in targets do remove target
  IO.println s!"Deleted {targets.size} ended study copies/executables without archives"
