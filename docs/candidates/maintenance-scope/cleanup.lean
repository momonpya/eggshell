import Lean.Data.Json.FromToJson
import Lean.Data.Json.Parser
open Lean
def base : System.FilePath := "/Users/ovm/.codex/experiments/eggshell/scope-token-study-20261028/fixed-frame-study"
def workspace : System.FilePath := "/Users/ovm/.codex/worktrees/hook-deadline-baseline/eggshell"
def read (path : System.FilePath) : IO Json := do IO.ofExcept (Json.parse (← IO.FS.readFile path))
def hash (path : System.FilePath) : IO String := do
  let result ← IO.Process.output {cmd := "/usr/bin/shasum",args := #["-a","256",path.toString]}
  unless result.exitCode == 0 do throw (IO.userError "cannot check retained source")
  return (result.stdout.splitOn " ").headD ""
partial def size (path : System.FilePath) : IO Nat := do
  let metadata ← path.symlinkMetadata
  if metadata.type != .dir then return metadata.byteSize.toNat
  let mut total := 0
  for entry in ← path.readDir do total := total+(← size entry.path)
  return total
def erase (path : System.FilePath) : IO Nat := do
  let bytes ← size path
  if (← path.symlinkMetadata).type == .dir then IO.FS.removeDirAll path else IO.FS.removeFile path
  return bytes
def main : IO Unit := do
  let folder := workspace/"docs/candidates/maintenance-scope"
  for name in ["evidence.json","checks.json","guards.json","attempts.json","identity.json","candidate.patch"] do
    unless ← (folder/name).pathExists do throw (IO.userError "seal results before cleanup")
  let processes ← IO.Process.output {cmd := "/bin/ps",args := #["-axo","command="]}
  unless processes.exitCode == 0 && !(processes.stdout.splitOn "\n").any (·.contains base.toString) do
    throw (IO.userError "related runtime/build process is still live")
  let identity ← read (folder/"identity.json")
  let original := base/"maintenance-scope-baseline-core/Eggshell/PluginHooks.lean"
  let current := base/"interest-traffic-core/Eggshell/PluginHooks.lean"
  unless toJson (← hash original) == identity.getObjValD "parentHooksSha256" &&
      toJson (← hash current) == identity.getObjValD "candidateHooksSha256" do
    throw (IO.userError "candidate or parent source changed before restoration")
  let driver := base/"interest-traffic-core/tools/research/FrontTrafficChecks.lean"
  let driverHash ← hash driver
  unless driverHash == (← hash (base/"maintenance-scope-baseline-core/tools/research/FrontTrafficChecks.lean")) do
    throw (IO.userError "native dispatcher was not restored")
  IO.FS.writeFile current (← IO.FS.readFile original)
  let restored ← hash current
  unless toJson restored == identity.getObjValD "parentHooksSha256" do throw (IO.userError "source restoration failed")
  let reapplies ← IO.Process.output {
    cmd := "/usr/bin/git"
    args := #["apply","--unidiff-zero","--check",(folder/"candidate.patch").toString]
    cwd := (base/"interest-traffic-core").toString}
  unless reapplies.exitCode == 0 do throw (IO.userError "retained isolated patch no longer applies")
  let heads : Array (String × String × String) ← IO.ofExcept (fromJson? (← read (workspace/"docs/candidates/worker-cpu/heads.json")))
  for (path,text,digest) in heads do
    unless (← IO.FS.readFile (.mk path)) == text && (← hash (.mk path)) == digest do
      throw (IO.userError "do not clean up changed original heads")
  let mut deleted := #[]
  for name in ["WorkerCpuProfile.lean","MaintenanceScopeChecks.lean"] do
    let path := base/"interest-traffic-core/tools/research"/name
    if ← path.pathExists then deleted := deleted.push (path.toString,← erase path)
  for entry in ← base.readDir do
    unless entry.fileName.startsWith "worker-cpu-" || entry.fileName.startsWith "maintenance-scope-" do continue
    if entry.fileName == "maintenance-scope-build" then continue
    deleted := deleted.push (entry.path.toString,← erase entry.path)
  IO.FS.writeFile (folder/"restoration.json") (Json.mkObj [("parentHooksSha256",toJson restored),
    ("parentDispatcherSha256",toJson driverHash),
    ("isolatedPatchApplies",toJson true),("currentRuntime",identity.getObjValD "parentRuntimeSha256"),
    ("retainedCandidateIsNotAdopted",toJson true)]).pretty
  IO.FS.writeFile (folder/"cleanup.json") (Json.mkObj [("deleted",toJson deleted),
    ("apparentBytes",toJson (deleted.foldl (fun total row => total+row.2) 0)),
    ("retainedCandidateBuildForNextComparison",toJson true),("originalHeadsUnchanged",toJson true),
    ("noRelatedProcessesBeforeCleanup",toJson true),("archived",toJson false)]).pretty
