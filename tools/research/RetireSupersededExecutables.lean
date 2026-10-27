import Lean.Data.Json.Parser
import Lean.Data.Json.FromToJson
open Lean

private partial def collect (path : System.FilePath) : IO (Array System.FilePath) := do
  let mut found := #[]
  for entry in ← path.readDir do
    let metadata ← entry.path.symlinkMetadata
    if metadata.type == .dir then found := found ++ (← collect entry.path)
    else if metadata.type == .file && ["StudyMain","Probe","product","eggshell"].contains entry.fileName then
      found := found.push entry.path
  return found

private partial def protect (path : System.FilePath) (targets : Array System.FilePath) : IO Unit := do
  for entry in ← path.readDir do
    let metadata ← entry.path.symlinkMetadata
    if metadata.type == .dir then protect entry.path targets
    else if metadata.type == .symlink then
      let actual ← IO.FS.realPath entry.path
      unless !targets.contains actual do throw (IO.userError "retained source or interface refers to executable")

/-- Ended native tools are not dependencies of the retained statically linked
runtime. Preserve every source, object, interface, DB and numerical asset. -/
def main : IO Unit := do
  let base := System.FilePath.mk "/Users/ovm/.codex/experiments/eggshell"
  let baseline := base / "shared-original-structure-20261027"
  let candidate := base / "evidence-cause-contract-20261027"
  let output := System.FilePath.mk "/Users/ovm/.codex/worktrees/hook-deadline-baseline/eggshell/docs/candidates/evidence-cause-contract/retired-executables.json"
  unless !(← output.pathExists) do throw (IO.userError "preserve previous retirement")
  let keep := [baseline,candidate,base / "numerical-owned-20261024"]
  let targets := (← collect base).filter fun path =>
    !(keep.any fun root => path.toString.startsWith (root.toString ++ "/"))
  let processes ← IO.Process.output {cmd := "/bin/ps",args := #["-axo","command="]}
  unless processes.exitCode == 0 do throw (IO.userError "cannot inspect active processes")
  let response ← IO.FS.readFile (baseline / "product-build/runtime.rsp")
  for path in targets do
    unless (processes.stdout.splitOn path.toString).length == 1 &&
      (response.splitOn path.toString).length == 1 do throw (IO.userError "executable still referenced")
  protect (baseline / "checkout") targets
  protect (baseline / "product-build/lib") targets
  protect (candidate / "checkout") targets
  let controller := base / "study-services-20261026/assessed-controller"
  let hashes ← IO.Process.output {cmd := controller.toString,args := #["artifacts"] ++ targets.map (·.toString)}
  unless hashes.exitCode == 0 do throw (IO.userError hashes.stderr)
  let mut sizes := #[]
  let mut bytes := 0
  for path in targets do
    let size := (← path.symlinkMetadata).byteSize.toNat
    sizes := sizes.push (path.toString,size)
    bytes := bytes + size
  IO.FS.createDirAll output.parent.get!
  IO.FS.writeFile output (Json.mkObj [
    ("targets",toJson sizes),("logicalBytes",toJson bytes),
    ("digests",← IO.ofExcept (Json.parse hashes.stdout)),
    ("activeProcessLinkerAndInterfaceReferencesChecked",toJson true),
    ("sourceObjectsInterfacesDatabasesModelsRetained",toJson true),("archiveCreated",toJson false)]).pretty
  for path in targets do IO.FS.removeFile path
  IO.println s!"Deleted {targets.size} ended executables, {bytes} logical bytes; no archives"
