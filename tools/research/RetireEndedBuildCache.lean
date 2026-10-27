import Lean.Data.Json.Parser
import Lean.Data.Json.FromToJson
open Lean

private partial def collect (path : System.FilePath) : IO (Array System.FilePath) := do
  let mut found := #[]
  for entry in ← path.readDir do
    let metadata ← entry.path.symlinkMetadata
    if metadata.type == .dir then found := found ++ (← collect entry.path)
    else if metadata.type == .file && entry.fileName.endsWith ".dependencies" then
      found := found.push entry.path
  return found

private partial def protect (path : System.FilePath) (targets : Array System.FilePath) : IO Unit := do
  for entry in ← path.readDir do
    let metadata ← entry.path.symlinkMetadata
    if metadata.type == .dir then protect entry.path targets
    else if metadata.type == .symlink then
      let actual ← IO.FS.realPath entry.path
      unless !targets.contains actual do throw (IO.userError "active dependency selected for retirement")

/-- Remove ended executables and recomputable dependency-cache copies, never
source stamps, objects, interfaces, DBs, numerical models or the live runtime.
The inherited native linker uses .o and .source, not .dependencies. -/
def main : IO Unit := do
  let base := System.FilePath.mk "/Users/ovm/.codex/experiments/eggshell"
  let active := base / "shared-original-structure-20261027"
  let report := System.FilePath.mk "/Users/ovm/.codex/worktrees/hook-deadline-baseline/eggshell/docs/candidates/rendered-marginal-cost/retired-build-cache.json"
  unless !(← report.pathExists) do throw (IO.userError "preserve prior retirement evidence")
  let names := #[
    "complete-focus-20261026/probe-tools_research_CompleteFocusChecks/Probe",
    "record-focus-20261026/probe-tools_research_OriginalDomainChecks/Probe",
    "feedback-context-20261026/build/StudyMain",
    "feedback-context-20261026/routing-build/StudyMain",
    "feedback-context-20261026/required-replay/prefix/libexec/eggshell",
    "lean-study-20261025/controller/StudyMain",
    "study-services-20261026/build/StudyMain",
    "synaptic-routing-store-20261026/build/StudyMain",
    "publication-service-20261026/prefix/libexec/eggshell",
    "publication-service-20261026/product",
    "source-authority-20261026/prefix/libexec/eggshell",
    "source-authority-20261026/product"]
  let executables := names.map fun name => base / System.FilePath.mk name
  for path in executables do
    unless (← path.symlinkMetadata).type == .file do throw (IO.userError "retirement target changed")
  let caches := (← collect base).filter fun path => !path.toString.startsWith (active.toString ++ "/")
  let targets := executables ++ caches
  let processes ← IO.Process.output {cmd := "/bin/ps",args := #["-axo","command="]}
  unless processes.exitCode == 0 do throw (IO.userError "cannot inspect live ownership")
  let response ← IO.FS.readFile (active / "product-build/runtime.rsp")
  for path in targets do
    unless (processes.stdout.splitOn path.toString).length == 1 &&
      (response.splitOn path.toString).length == 1 do throw (IO.userError "retirement target is still referenced")
  protect (active / "product-build/lib") targets
  protect (active / "checkout") targets
  let controller := base / "study-services-20261026/assessed-controller"
  let digests ← IO.Process.output {cmd := controller.toString,args := #["artifacts"] ++ executables.map (·.toString)}
  unless digests.exitCode == 0 do throw (IO.userError digests.stderr)
  let mut sizes := #[]
  let mut total := 0
  for path in targets do
    let size := (← path.symlinkMetadata).byteSize.toNat
    total := total+size
    sizes := sizes.push (path.toString,size)
  IO.FS.createDirAll report.parent.get!
  IO.FS.writeFile report (Json.mkObj [
    ("targets",toJson sizes),("logicalBytes",toJson total),
    ("executableDigests",← IO.ofExcept (Json.parse digests.stdout)),
    ("activeLinkerAndInterfacesChecked",toJson true),("archiveCreated",toJson false),
    ("originalsPreparedDatabaseSourceObjectsInterfacesAndModelsRetained",toJson true)]).pretty
  for path in targets do IO.FS.removeFile path
  IO.println s!"Deleted {executables.size} ended executables and {caches.size} dependency caches ({total} logical bytes)"
