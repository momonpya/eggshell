import Lean.Data.Json.Parser
import Lean.Data.Json.FromToJson
open Lean

private def read (path : System.FilePath) : IO Json :=
  IO.FS.readFile path >>= fun text => IO.ofExcept (Json.parse text)

private def objects (directory : System.FilePath) : IO (Array String) := do
  let mut paths := #[]
  for line in (← IO.FS.readFile (directory / "runtime.rsp")).splitOn "\n" do
    unless line.trimAscii.isEmpty do paths := paths.push (← IO.ofExcept (Json.parse line >>= Json.getStr?))
  return paths

private def nativeSource (paths : Array String) (name : String) : IO String := do
  let some object := paths.find? (·.endsWith ("/Eggshell_" ++ name ++ ".o")) |
    throw (IO.userError "sealed native source missing")
  let parts ← IO.ofExcept (← read ((System.FilePath.mk object).withExtension "source")).getArr?
  IO.ofExcept parts[0]!.getStr?

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

private def retire (root output : System.FilePath) : IO Unit := do
  unless (← (output / "decision.json").pathExists) && !(← (output / "retired.json").pathExists) do
    throw (IO.userError "seal evidence once before retiring this candidate")
  let success ← read (output / "fixtures.guard.json")
  unless success.getObjValD "exitCode" == toJson (0 : Nat) &&
      success.getObjValD "ownedPids" == toJson (#[] : Array Nat) do
    throw (IO.userError "candidate fixture is not successfully terminal")
  let targets := #[root / "index-readiness-fixture",root / "index-readiness-fixture2",
    root / "index-readiness-build/StudyMain",root / "query-usage-runtime-build/StudyMain",root / "prefix"]
  let processes ← IO.Process.output {cmd := "/bin/ps",args := #["-axo","command="]}
  unless processes.exitCode == 0 && targets.all (fun target =>
      (processes.stdout.splitOn target.toString).length == 1) do
    throw (IO.userError "an ended candidate still owns a process")
  let baseline ← objects (root / "dependency-checked-runtime-build")
  let candidate ← objects (root / "index-readiness-build")
  let mut restore : Array (System.FilePath × String) := #[]
  for name in ["SynapseIndex","SynapseJournal"] do
    let path := root / "core/Eggshell" / System.FilePath.mk (name ++ ".lean")
    unless (← IO.FS.readFile path) == (← nativeSource candidate name) do
      throw (IO.userError "unsealed source edits must not be reverted")
    restore := restore.push (path,← nativeSource baseline name)
  for (path,text) in restore do IO.FS.writeFile path text
  let mut removed := #[]
  for target in targets do
    if ← target.pathExists then removed := removed.push (target.toString,← size target)
  let bytes := removed.foldl (fun total row => total+row.2) 0
  IO.FS.writeFile (output / "retired.json") (Json.mkObj [("targets",toJson removed),
    ("logicalBytes",toJson bytes),("archiveCreated",toJson false),
    ("candidateSourcesRestoredToCheckedReference",toJson true),
    ("originalSeedModelAndReferenceRuntimeRetained",toJson true),
    ("objectsAndInterfacesRetained",toJson true)]).pretty
  for target in targets do if ← target.pathExists then remove target
  IO.println s!"Restored checked reference; deleted {removed.size} ended targets, {bytes} logical bytes"

def main (args : List String) : IO Unit := do
  let root : System.FilePath := "/Users/ovm/.codex/experiments/eggshell/scope-token-study-20261028/shared-snapshot"
  let output : System.FilePath := "/Users/ovm/.codex/worktrees/hook-deadline-baseline/eggshell/docs/candidates/index-readiness"
  if args == ["retire"] then return ← retire root output
  unless args.isEmpty do throw (IO.userError "expected no argument or retire")
  unless !(← output.pathExists) do throw (IO.userError "preserve prior readiness evidence")
  for name in ["index-readiness-run2.guard.json","index-readiness-closure.guard.json"] do
    let guard ← read (root / System.FilePath.mk name)
    unless guard.getObjValD "state" == toJson "finished" && guard.getObjValD "exitCode" == toJson (0 : Nat) &&
        guard.getObjValD "ownedPids" == toJson (#[] : Array Nat) do
      throw (IO.userError "readiness checks are not successfully terminal")
  let baseline ← objects (root / "dependency-checked-runtime-build")
  let candidate ← objects (root / "index-readiness-build")
  let mut patch := ""
  for name in ["SynapseIndex","SynapseJournal"] do
    let current := root / "core/Eggshell" / System.FilePath.mk (name ++ ".lean")
    unless (← IO.FS.readFile current) == (← nativeSource candidate name) do
      throw (IO.userError "current source differs from the checked native candidate")
    let parent := root / System.FilePath.mk ("index-readiness-parent-" ++ name ++ ".lean")
    IO.FS.writeFile parent (← nativeSource baseline name)
    let diff ← IO.Process.output {cmd := "/usr/bin/diff",args := #["-u","--label","a/Eggshell/" ++ name ++ ".lean",
      "--label","b/Eggshell/" ++ name ++ ".lean",parent.toString,current.toString]}
    unless diff.exitCode == 1 do throw (IO.userError "expected readiness change missing")
    patch := patch ++ diff.stdout
    IO.FS.removeFile parent
  let report ← read (root / "index-readiness-fixture2/result.json")
  unless report.getObjValD "historicalEntriesCanonicallyReadable" == toJson (75 : Nat) &&
      report.getObjValD "historicalReasonsInvented" == toJson (0 : Nat) do
    throw (IO.userError "historical raw journal boundary was not checked")
  IO.FS.createDirAll output
  IO.FS.writeFile (output / "candidate.patch") patch
  for (origin,target) in [
      ("index-readiness-fixture2/result.json","fixtures.json"),
      ("index-readiness-run2.guard.json","fixtures.guard.json"),
      ("index-readiness-run.guard.json","failed-historical-reader.guard.json"),
      ("index-readiness-closure.json","native-closure.json"),
      ("index-readiness-closure.guard.json","native-closure.guard.json"),
      ("index-readiness-build/tools_research_IndexReadinessAudit-lean.stdout","proofs-and-boundaries.stdout")] do
    IO.FS.writeFile (output / System.FilePath.mk target) (← IO.FS.readFile (root / System.FilePath.mk origin))
  let mut builds := #[]
  for entry in ← root.readDir do
    let name := entry.fileName
    if name.startsWith "index-readiness-build-" && name.endsWith ".guard.json" then
      builds := builds.push (← read entry.path)
  IO.FS.writeFile (output / "build-guards.json") (toJson builds).pretty
  IO.FS.writeFile (output / "decision.json") (Json.mkObj [
    ("adopted",toJson false),("answeringModelCalls",toJson (0 : Nat)),
    ("actualHookCalls",toJson (0 : Nat)),("tokenImprovementMeasured",toJson false),
    ("deliveryImprovementMeasured",toJson false),("goalAchieved",toJson false),
    ("historical32CausesKnown",toJson false),
    ("futureCaptureReasonsDurableInCandidate",toJson true),
    ("sourceFrontierGapReproduced",toJson true)]).pretty
  IO.println "Sealed isolated readiness diagnostics and observed source frontier gap"
