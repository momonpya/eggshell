import Lean.Data.Json.Parser
import Lean.Data.Json.FromToJson
open Lean

private def read (path : System.FilePath) : IO Json :=
  IO.FS.readFile path >>= fun text => IO.ofExcept (Json.parse text)

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
  let records : System.FilePath := "/Users/ovm/.codex/worktrees/hook-deadline-baseline/eggshell/docs/candidates/query-usage-links"
  unless (← records.pathExists) && !(← (records / "retired.json").pathExists) do
    throw (IO.userError "seal query-link evidence before retiring ended trials")
  for name in ["hook.guard.json","fixtures.guard.json","receipt-replay.guard.json","stored-questions.guard.json"] do
    let guard ← read (records / name)
    unless guard.getObjValD "state" == toJson "finished" && guard.getObjValD "exitCode" == toJson (0 : Nat) &&
        guard.getObjValD "ownedPids" == toJson (#[] : Array Nat) do
      throw (IO.userError "query-link guard is not successfully terminal")
  let receipt := root / "query-usage-prepared-hook/data/receipts/9fa231b185cdb220ea915727394e434d1cf5fc1d8dcfa08c270250858ceeedee"
  let mut hashes := #[]
  for name in ["delivery-domain.json","synaptic-delivery.json","selection-plan.json"] do
    let original := receipt / System.FilePath.mk name
    let output ← IO.Process.output {cmd := "/usr/bin/shasum",args := #["-a","256",original.toString]}
    unless output.exitCode == 0 do throw (IO.userError output.stderr)
    hashes := hashes.push (name,output.stdout.trimAscii.toString)
  let targets := #[root / "query-usage-prepared-hook",root / "query-usage-link-fixture",
    root / "query-usage-link-build/StudyMain",root / "query-usage-hook-build/StudyMain",
    root / "stored-question-link-build/StudyMain",root / "query-usage-receipt-build/StudyMain"]
  let processes ← IO.Process.output {cmd := "/bin/ps",args := #["-axo","command="]}
  unless processes.exitCode == 0 && targets.all (fun target =>
      (processes.stdout.splitOn target.toString).length == 1) do
    throw (IO.userError "an ended trial still has a process")
  let objects := fun (build : String) => do
    let mut paths : Array String := #[]
    for line in (← IO.FS.readFile (root / System.FilePath.mk build / "runtime.rsp")).splitOn "\n" do
      unless line.trimAscii.isEmpty do paths := paths.push (← IO.ofExcept (Json.parse line >>= Json.getStr?))
    pure paths
  let baseline ← objects "dependency-checked-runtime-build"
  let candidate ← objects "query-usage-runtime-build"
  let nativeSource := fun (paths : Array String) (name : String) => do
    let some object := paths.find? (·.endsWith ("/Eggshell_" ++ name ++ ".o")) |
      throw (IO.userError "sealed native module source missing")
    let parts ← IO.ofExcept (← read ((System.FilePath.mk object).withExtension "source")).getArr?
    IO.ofExcept parts[0]!.getStr?
  let mut restored : Array (String × String) := #[]
  for name in ["SynapseIndex","SynapseBuild","SynapseRecommend","SynapticTransport","SynapseQueryLinks"] do
    let path := root / "core/Eggshell" / System.FilePath.mk (name ++ ".lean")
    unless (← IO.FS.readFile path) == (← nativeSource candidate name) do
      throw (IO.userError "candidate source changed after its sealed native build")
    if name != "SynapseQueryLinks" then restored := restored.push (path.toString,← nativeSource baseline name)
  for (path,text) in restored do IO.FS.writeFile (.mk path) text
  IO.FS.removeFile (root / "core/Eggshell/SynapseQueryLinks.lean")
  let mut removed := #[]
  for target in targets do
    if ← target.pathExists then removed := removed.push (target.toString,← size target)
  IO.FS.writeFile (records / "retired.json") (Json.mkObj [("targets",toJson removed),
    ("logicalBytes",toJson (removed.foldl (fun total row => total+row.2) 0)),
    ("finalReceiptDigests",toJson hashes),("archiveCreated",toJson false),
    ("originalSeedAndCurrentRuntimeRetained",toJson true),
    ("objectsAndInterfacesRetained",toJson true),
    ("candidateSourceRestoredToCheckedReference",toJson true)]).pretty
  for target in targets do if ← target.pathExists then remove target
  IO.println s!"Deleted {removed.size} ended query-link targets; no archive"
