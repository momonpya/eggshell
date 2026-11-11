import tools.research.StudyLocal
open Lean StudyLocal
namespace CurrentArtifactCleanup
def records := project/"docs/cleanup/current-artifacts"
def parent := base/"canonical-decoder-runtime"
def controller := base/"current-six/fixed-sequence/controller-build"
def retiredExecutables : Array (String × String) := #[
  ((base/"current-six/stable-source-rows/build/StudyMain").toString,
    "dd53c89bc450b66b58dd57d104ccbc82f32ca6345fa9666125e7feb03017000e"),
  ((base/"current-six/fixed-sequence/preparation-closure-build/StudyMain").toString,
    "f0af9f3bb7c8af9292c6d470c19aff52d6153fd85f4e8731919d5dffb8102d91"),
  ((base/"byte-pages-prefix/libexec/eggshell").toString,
    "534a92d6f93fb253819cfbdcb32eea0643606e70c6e3c52eeae6e78bbdaee552")]

def keepTrees : Array System.FilePath := #[parent,controller,
  base/"current-six/fixed-sequence/controller-source",base/"study-local-lib",base/"parent-facts/source",
  base/"snapshot-scheduling",base/"current-six/fixed-sequence/cohort/account",
  base/"current-six/fixed-sequence/cohort/prompts",base/"current-six/fixed-sequence/cohort/tmp",
  base/"current-six/fixed-sequence/cohort/prefix/share",base/"register-rounds-runtime/prefix/share",
  base/"byte-pages-prefix/share"]

def below (path root : String) : Bool := path == root || path.startsWith (root++"/")

partial def planClosed (path : System.FilePath) (protectedPaths : Array String) (inOldBuild : Bool := false) :
    IO (Array String) := do
  let raw := path.toString
  if keepTrees.any (fun root => below raw root.toString) then return #[]
  let stat ← path.symlinkMetadata
  let cohort := (base/"current-six/fixed-sequence/cohort").toString
  let inOldCohort := below raw cohort
  let actual ← try pure (← IO.FS.realPath path).toString catch _ => pure raw
  let containsProtected := protectedPaths.any (fun kept => below kept raw || below kept actual) ||
    keepTrees.any (fun root => below root.toString raw)
  let name := path.fileName.getD ""
  let oldBuild := inOldBuild || name.endsWith "-build" || name == "build"
  let eligible := oldBuild || name.endsWith "-source" || name == "source" || name.endsWith ".egg" ||
    ["selection-profile-inputs","positive-projection-cells2-result"].contains name || inOldCohort
  if stat.type == .symlink then return #[]
  if eligible && !containsProtected then return #[raw]
  if stat.type != .dir then return #[]
  let mut result := #[]
  for entry in ← path.readDir do result := result ++ (← planClosed entry.path protectedPaths oldBuild)
  return result

def planTrees : IO Unit := do
  idle
  let previous ← read (base/"obsolete-executables-retirement-input.json")
  let checked ← read (base/"obsolete-executables-retirement-plan.json")
  let protectedPaths ← IO.ofExcept (checked.getObjValAs? (Array String) "protectedPaths")
  let mut closed := #[]
  for entry in ← base.readDir do
    if (← entry.path.symlinkMetadata).type == .dir then
      closed := closed ++ (← planClosed entry.path protectedPaths)
  write (records/"trees-plan.json") (Json.mkObj [("closed",toJson closed),
    ("currentKeepTrees",toJson (keepTrees.map System.FilePath.toString)),
    ("preservedResolvedCompilerAndRuntimePaths",toJson protectedPaths.size),
    ("archive",toJson false)])
  let config := previous.setObjVal! "closedDirectories" (toJson closed)
    |>.setObjVal! "libraries" (toJson (#[(parent/"build/lib").toString,(parent/"prefix/share").toString,
      (base/"study-local-lib").toString]++keepTrees.map System.FilePath.toString))
    |>.setObjVal! "plan" (toJson (base/"obsolete-trees-retirement-plan.json").toString)
    |>.setObjVal! "receipt" (toJson (records/"trees-retired.json").toString)
  check (!(← (base/"obsolete-trees-retirement-input.json").pathExists)) "preserve exact cleanup set"
  write (base/"obsolete-trees-retirement-input.json") config

def planExecutables : IO Unit := do
  idle
  IO.FS.createDirAll records
  let processes ← command "/bin/ps" #["-axo","command="]
  let mut values := #[]
  for (raw,expected) in retiredExecutables do
    let path : System.FilePath := .mk raw
    check (!processes.contains raw && (← path.symlinkMetadata).type == .file && (← hash path) == expected)
      "old executable is live or differs from the recorded historical runtime"
    values := values.push (Json.mkObj [("path",toJson raw),("sha256",toJson expected),
      ("bytes",toJson (← path.metadata).byteSize.toNat)])
  check ((← hash (parent/"build/StudyMain")) ==
    "7cc1432d2d3931a26d60e3e614807545e3f6b522737838bdabc1b1c626e657ab") "current runtime changed"
  check ((← hash (controller/"StudyMain")) ==
    "670aaf8ec8b79cf71ca97daf9ae41bd33a9070196be36ce45a9dd0f8d26cf6c5") "current guard/controller changed"
  let previous ← read (base/"citation-gate-parent-retirement-input.json")
  let protectedFiles ← IO.ofExcept (previous.getObjValAs? (Array String) "protectedFiles")
  let retained := protectedFiles.filter fun path => !retiredExecutables.any (·.1 == path)
  let config := previous.setObjVal! "protectedFiles" (toJson retained)
    |>.setObjVal! "builds" (toJson #[(parent/"build").toString,controller.toString])
    |>.setObjVal! "closedDirectories" (toJson (retiredExecutables.map Prod.fst))
    |>.setObjVal! "plan" (toJson (base/"obsolete-executables-retirement-plan.json").toString)
    |>.setObjVal! "receipt" (toJson (records/"executables-retired.json").toString)
  check (!(← (base/"obsolete-executables-retirement-input.json").pathExists)) "preserve cleanup plan"
  write (base/"obsolete-executables-retirement-input.json") config
  write (records/"executables-plan.json") (Json.mkObj [("retired",toJson values),
    ("currentProductAndGuardRetained",toJson true),("installedUserCliAndModelsRetained",toJson true),
    ("reason",toJson "These three executables belong to completed prior experiments. The active parent-facts plan uses the current native parent and guard."),
    ("archive",toJson false)])

def compactTrees : IO Unit := do
  idle
  let receipt ← read (records/"trees-retired.json")
  let plan ← read (records/"trees-plan.json")
  check (receipt.getObjValD "completed" == toJson true && receipt.getObjValD "compact" == toJson true)
    "only completed, already verified retirement evidence may be condensed"
  let rows : Array (String × Nat × Nat) ← IO.ofExcept (fromJson? (receipt.getObjValD "closedDirectories"))
  let originalHash ← hash (records/"trees-retired.json")
  let planHash ← hash (records/"trees-plan.json")
  write (records/"trees-retired.json") (Json.mkObj [
    ("completed",toJson true),("compact",toJson true),("archive",toJson false),
    ("closedEntries",toJson rows.size),("removedItems",toJson (rows.foldl (fun n row => n+row.2.1) 0)),
    ("logicalBytes",toJson (rows.foldl (fun n row => n+row.2.2) 0)),
    ("preexistingMissingLegacyInputs",receipt.getObjValD "preexistingMissingLegacyInputs"),
    ("protectedHashes",receipt.getObjValD "protectedHashes"),
    ("protectedResolvedFiles",receipt.getObjValD "protectedResolvedFiles"),
    ("beforeFree",receipt.getObjValD "beforeFree"),("afterFree",receipt.getObjValD "afterFree"),
    ("originalReceiptSha256",toJson originalHash),("originalPlanSha256",toJson planHash)])
  write (records/"trees-plan.json") (Json.mkObj [
    ("closedEntries",toJson rows.size),("originalPlanSha256",toJson planHash),
    ("currentKeepTrees",plan.getObjValD "currentKeepTrees"),
    ("preservedResolvedCompilerAndRuntimePaths",plan.getObjValD "preservedResolvedCompilerAndRuntimePaths"),
    ("archive",toJson false),("retirementCompleted",toJson true)])

def planFinished : IO Unit := do
  idle
  let current := base/"practical-runtime"
  let runtime := current/"build/StudyMain"
  let audit ← read (project/"docs/practical-runtime/native.json")
  let sources ← read (project/"docs/practical-runtime/sources.json")
  check (audit.getObjValD "consistent" == toJson true &&
    sources.getObjValD "commonSourcesUnchanged" == toJson true &&
    !(← IO.FS.readFile (current/"build/runtime.rsp")).contains controller.toString)
    "replacement controller still needs the old native inputs"
  let hooks ← read (project/"docs/candidates/parent-facts/hooks.json")
  check (hooks.getObjValD "allActualBodiesAndAcksEqual" == toJson true &&
    hooks.getObjValD "adopted" == toJson false) "collect the finished rejected candidate first"
  let input ← read (base/"obsolete-executables-retirement-input.json")
  let protectedFiles ← IO.ofExcept (input.getObjValAs? (Array String) "protectedFiles")
  let config := input.setObjVal! "builds" (toJson #[(parent/"build").toString,(current/"build").toString])
    |>.setObjVal! "strictBuilds" (toJson #[(parent/"build").toString,(current/"build").toString])
    |>.setObjVal! "protectedFiles" (toJson (protectedFiles.filter (· != (controller/"StudyMain").toString) |>.push runtime.toString))
    |>.setObjVal! "closedDirectories" (toJson #[(base/"parent-facts").toString,controller.toString,
      (base/"current-six/fixed-sequence/controller-source").toString])
    |>.setObjVal! "libraries" (toJson #[(parent/"build/lib").toString,(parent/"prefix/share").toString,
      (parent/"source").toString,(current/"build/lib").toString,(current/"source").toString,(base/"study-local-lib").toString])
    |>.setObjVal! "plan" (toJson (base/"practical-predecessors-retirement-plan.json").toString)
    |>.setObjVal! "receipt" (toJson (records/"finished-candidate-retired.json").toString)
  write (base/"practical-predecessors-retirement-input.json") config

def main (args : List String) : IO Unit := match args with
  | ["plan-executables"] => planExecutables
  | ["plan-trees"] => planTrees
  | ["compact-trees"] => compactTrees
  | ["plan-finished"] => planFinished
  | _ => throw (IO.userError "cleanup action required")
end CurrentArtifactCleanup
def main := CurrentArtifactCleanup.main
